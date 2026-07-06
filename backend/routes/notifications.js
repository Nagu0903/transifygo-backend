const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const Notification = require('../models/Notification');
const User = require('../models/User');
const admin = require('firebase-admin');
const { authenticateToken } = require('../middleware/auth');

// Initialize Firebase Admin safely
try {
  let serviceAccount;
  let source = '';
  let envVarError = null;

  // Robust function to parse FIREBASE_SERVICE_ACCOUNT environment variable JSON safely
  function safeParseServiceAccount(rawEnv) {
    if (!rawEnv) return null;
    const trimmed = rawEnv.trim();
    if (!trimmed) return null;

    let jsonStr = trimmed;

    // 1. Check if Base64 encoded (does not start with '{' or '[')
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
      try {
        const sanitizedBase64 = trimmed.replace(/\s+/g, '');
        const decoded = Buffer.from(sanitizedBase64, 'base64').toString('utf8');
        if (decoded.trim().startsWith('{')) {
          jsonStr = decoded.trim();
          console.log('[FCM-DEBUG] Successfully decoded Base64 payload.');
        }
      } catch (e) {
        console.log(`[FCM-DEBUG] Base64 decode skipped/failed: ${e.message}`);
      }
    }

    // 2. Remove potential leading/trailing outer quotes (often added by environment loaders)
    if ((jsonStr.startsWith('"') && jsonStr.endsWith('"')) || (jsonStr.startsWith("'") && jsonStr.endsWith("'"))) {
      jsonStr = jsonStr.slice(1, -1).trim();
    }

    // 3. Try standard JSON.parse first
    try {
      const parsed = JSON.parse(jsonStr);
      if (parsed && typeof parsed === 'object') {
        return parsed;
      }
    } catch (err) {
      console.warn(`[FCM-WARNING] Direct JSON.parse failed: ${err.message}. Attempting recovery...`);
    }

    // 4. Try escaping literal newlines inside string values (literal newlines break JSON.parse)
    try {
      let sanitized = '';
      let inString = false;
      let stringChar = null;
      for (let i = 0; i < jsonStr.length; i++) {
        const char = jsonStr[i];
        if (char === '"' || char === "'") {
          if (!inString) {
            inString = true;
            stringChar = char;
            sanitized += char;
          } else if (stringChar === char && jsonStr[i - 1] !== '\\') {
            inString = false;
            stringChar = null;
            sanitized += char;
          } else {
            sanitized += char;
          }
        } else if (char === '\n' || char === '\r') {
          if (inString) {
            sanitized += '\\n';
          } else {
            sanitized += char;
          }
        } else {
          sanitized += char;
        }
      }

      const parsed = JSON.parse(sanitized);
      if (parsed && typeof parsed === 'object') {
        console.log('[FCM-DEBUG] Successfully parsed after escaping literal newlines.');
        return parsed;
      }
    } catch (err) {
      console.warn(`[FCM-WARNING] Sanitization recovery failed: ${err.message}. Trying regex extraction fallback...`);
    }

    // 5. Try regex key-value extraction fallback for heavily malformed structure (e.g. trailing commas)
    try {
      const extracted = {};
      const regexFlexible = /['"]?([a-zA-Z0-9_-]+)['"]?\s*:\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')/g;
      let match;
      while ((match = regexFlexible.exec(jsonStr)) !== null) {
        const key = match[1];
        let val = match[2] !== undefined ? match[2] : match[3];
        // Unescape escaped quotes and backslashes
        val = val.replace(/\\"/g, '"').replace(/\\'/g, "'").replace(/\\\\/g, '\\');
        extracted[key] = val;
      }

      if (extracted.private_key && extracted.client_email && extracted.project_id) {
        console.log('[FCM-DEBUG] Successfully recovered Firebase Service Account via regex parsing.');
        return extracted;
      }
    } catch (regexErr) {
      console.warn(`[FCM-WARNING] Regex fallback parsing failed: ${regexErr.message}`);
    }

    throw new Error('Unable to parse service account JSON correctly.');
  }

  if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    try {
      const rawEnv = process.env.FIREBASE_SERVICE_ACCOUNT;
      console.log(`[FCM-DEBUG] FIREBASE_SERVICE_ACCOUNT env var found. Length: ${rawEnv.length} chars.`);
      
      serviceAccount = safeParseServiceAccount(rawEnv);
      if (serviceAccount) {
        source = 'Environment Variable';
      }
    } catch (err) {
      envVarError = err;
      console.warn('[FCM-WARNING] Failed to parse FIREBASE_SERVICE_ACCOUNT env var:', err.message);
      console.log('[FCM-LOG] Falling back to check for secret file...');
    }
  }

  // If env var was not set or failed to parse, check for secret file
  if (!serviceAccount) {
    const fs = require('fs');
    const path = require('path');
    const pathsToTry = [
      path.join(__dirname, '../firebase-service-account.json'), // backend/firebase-service-account.json
      path.join(__dirname, '../../firebase-service-account.json'), // root/firebase-service-account.json
      path.join(process.cwd(), 'firebase-service-account.json'), // cwd root
      path.join(process.cwd(), 'backend', 'firebase-service-account.json') // cwd backend
    ];

    let foundPath;
    for (const p of pathsToTry) {
      if (fs.existsSync(p)) {
        foundPath = p;
        break;
      }
    }

    if (foundPath) {
      source = `Secret File (${path.basename(foundPath)})`;
      console.log(`[FCM-DEBUG] Loading service account from file: ${foundPath}`);
      const fileContent = fs.readFileSync(foundPath, 'utf8');
      console.log(`[FCM-DEBUG] File content length: ${fileContent.length} chars.`);
      
      serviceAccount = JSON.parse(fileContent);
    } else {
      if (envVarError) {
        throw envVarError; // Re-throw the original environment variable parsing error if no file fallback exists
      }
      throw new Error('firebase-service-account.json not found in any standard path, and no valid environment variable provided.');
    }
  }

  // Normalize private key newline formatting if present
  if (serviceAccount && serviceAccount.private_key) {
    // Preserve escaped \n by mapping literal \\n sequences to actual newlines required by cert helper
    serviceAccount.private_key = serviceAccount.private_key.replace(/\\n/g, '\n');
  }

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    console.log('[FCM] Firebase Admin initialized successfully');
    console.log('[FCM] Push notification service ready');
  }
} catch (error) {
  console.error('[FCM-ERROR] Firebase Admin initialization failed:', error.message);
  console.log('[FCM-WARNING] Firebase Admin not initialized. Please configure valid Firebase credentials.');
}

// Middleware to check DB connection
const checkDB = (req, res, next) => {
  if (mongoose.connection.readyState !== 1) {
    return res.status(503).json({ success: false, message: 'Database disconnected' });
  }
  next();
};

// 1. Get user notifications
router.get('/:userId', checkDB, authenticateToken, async (req, res) => {
  try {
    if (req.user.role !== 'Admin' && req.params.userId !== req.user.id) {
      return res.status(403).json({ success: false, message: 'Forbidden. Cannot access other users\' notifications.' });
    }
    const notifications = await Notification.find({ userId: req.params.userId })
      .sort({ createdAt: -1 })
      .limit(50);
    res.json({ success: true, notifications });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Failed to fetch notifications' });
  }
});

// 2. Mark as read
router.put('/read/:notificationId', checkDB, authenticateToken, async (req, res) => {
  try {
    const notification = await Notification.findById(req.params.notificationId);
    if (!notification) {
      return res.status(404).json({ success: false, message: 'Notification not found' });
    }
    if (req.user.role !== 'Admin' && notification.userId !== req.user.id) {
      return res.status(403).json({ success: false, message: 'Forbidden. You do not own this notification.' });
    }
    notification.isRead = true;
    await notification.save();
    res.json({ success: true, message: 'Marked as read' });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Update failed' });
  }
});

// 3. Update FCM Token
router.post('/token', checkDB, authenticateToken, async (req, res) => {
  try {
    const { userId, fcmToken } = req.body;
    if (!userId || !fcmToken) return res.status(400).json({ success: false, message: 'Missing fields' });
    
    if (req.user.role !== 'Admin' && userId !== req.user.id) {
      return res.status(403).json({ success: false, message: 'Forbidden. Cannot update FCM token for another user.' });
    }
    
    await User.findByIdAndUpdate(userId, { fcmToken });
    res.json({ success: true, message: 'Token updated' });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Failed to update token' });
  }
});

// Helper function to send notification via Firebase Admin
const sendPushNotification = async (userId, title, body, type, data = {}) => {
  try {
    // 1. Save to DB
    const notification = new Notification({ userId, title, body, type, data });
    await notification.save();

    // 2. Get User's FCM Token and send push
    const user = await User.findById(userId);
    
    if (!user) {
      console.log(`[FCM-LOG] Notification failed: User ${userId} not found.`);
      return false;
    }

    if (type === 'new_load') {
      console.log(`[FCM-LOG] Driver notification triggered for User ${userId}`);
    } else if (type === 'load_accepted') {
      console.log(`[FCM-LOG] Owner notification triggered for User ${userId}`);
    }

    if (user.fcmToken) {
        console.log(`[FCM] Dispatching to ${user.fcmToken}: ${title}`);
        
        if (admin.apps.length > 0) {
          // Convert all values inside data payload to string to prevent FCM validation failures (e.g. Mongoose ObjectIds)
          const stringData = {
            type: String(type || ''),
            click_action: 'FLUTTER_NOTIFICATION_CLICK'
          };

          for (const [key, val] of Object.entries(data)) {
            if (val !== null && val !== undefined) {
              stringData[key] = typeof val === 'object' ? 
                (val.toString && typeof val.toString === 'function' ? val.toString() : JSON.stringify(val)) : 
                String(val);
            }
          }

          const message = {
            notification: {
              title: title,
              body: body,
            },
            data: stringData,
            token: user.fcmToken,
            android: {
              priority: 'high',
              notification: {
                sound: 'default',
                channelId: 'transify_go_channel', // Matches Flutter local channel
                icon: 'ic_notification',
                color: '#0D47A1'
              }
            },
            apns: {
              payload: {
                aps: {
                  sound: 'default',
                  badge: 1,
                  'content-available': 1
                }
              }
            }
          };

          try {
            await admin.messaging().send(message);
            console.log("FCM_SEND_SUCCESS");
          } catch(error) {
            console.error("FCM_SEND_FAILED", error);
          }
        } else {
          console.log('[FCM-WARNING] Firebase admin not configured. Skipping real push dispatch.');
        }
    } else {
        console.log(`[FCM-LOG] Token invalid or missing for User ${userId}.`);
    }
    return true;
  } catch (err) {
    console.error(`[FCM-LOG] Push Notification Error for User ${userId}:`, err.message);
    return false;
  }
};

module.exports = { router, sendPushNotification };
