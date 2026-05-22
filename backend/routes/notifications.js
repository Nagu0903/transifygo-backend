const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const Notification = require('../models/Notification');
const User = require('../models/User');
const admin = require('firebase-admin');

// Initialize Firebase Admin safely
try {
  let serviceAccount;
  let source = '';
  let envVarError = null;

  if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    try {
      const rawEnv = process.env.FIREBASE_SERVICE_ACCOUNT.trim();
      console.log(`[FCM-DEBUG] FIREBASE_SERVICE_ACCOUNT env var found. Length: ${rawEnv.length} chars.`);
      
      let parsedString = rawEnv;
      if (!rawEnv.startsWith('{')) {
        console.log('[FCM-DEBUG] Env var does not start with "{". Treating as Base64 encoded.');
        const sanitizedBase64 = rawEnv.replace(/\s+/g, '');
        console.log(`[FCM-DEBUG] Sanitized Base64 length: ${sanitizedBase64.length} chars.`);
        parsedString = Buffer.from(sanitizedBase64, 'base64').toString('utf8');
      } else {
        console.log('[FCM-DEBUG] Env var starts with "{". Treating as raw JSON.');
      }
      
      const safeFirst = parsedString.slice(0, 30);
      const safeLast = parsedString.slice(-30);
      console.log(`[FCM-DEBUG] Attempting to parse JSON string. First 30: "${safeFirst}" | Last 30: "${safeLast}"`);
      
      serviceAccount = JSON.parse(parsedString);
      source = 'Environment Variable';
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
      
      const safeFirst = fileContent.slice(0, 30);
      const safeLast = fileContent.slice(-30);
      console.log(`[FCM-DEBUG] Attempting to parse file JSON. First 30: "${safeFirst}" | Last 30: "${safeLast}"`);
      
      serviceAccount = JSON.parse(fileContent);
    } else {
      if (envVarError) {
        throw envVarError; // Re-throw the original environment variable parsing error if no file fallback exists
      }
      throw new Error('firebase-service-account.json not found in any standard path, and no valid environment variable provided.');
    }
  }

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    console.log(`[FCM] Firebase Admin Initialized successfully from ${source}.`);
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
router.get('/:userId', checkDB, async (req, res) => {
  try {
    const notifications = await Notification.find({ userId: req.params.userId })
      .sort({ createdAt: -1 })
      .limit(50);
    res.json({ success: true, notifications });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Failed to fetch notifications' });
  }
});

// 2. Mark as read
router.put('/read/:notificationId', checkDB, async (req, res) => {
  try {
    await Notification.findByIdAndUpdate(req.params.notificationId, { isRead: true });
    res.json({ success: true, message: 'Marked as read' });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Update failed' });
  }
});

// 3. Update FCM Token
router.post('/token', checkDB, async (req, res) => {
  try {
    const { userId, fcmToken } = req.body;
    if (!userId || !fcmToken) return res.status(400).json({ success: false, message: 'Missing fields' });
    
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
          const message = {
            notification: {
              title: title,
              body: body,
            },
            data: {
              type: type,
              ...data,
              click_action: 'FLUTTER_NOTIFICATION_CLICK' // Triggers foreground/background handling
            },
            token: user.fcmToken,
            android: {
              priority: 'high',
              notification: {
                sound: 'default',
                channelId: 'transify_go_channel', // Matches Flutter local channel
                icon: 'ic_notification',
                color: '#0D47A1'
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
