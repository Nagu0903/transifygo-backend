const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const Notification = require('../models/Notification');
const User = require('../models/User');
const admin = require('firebase-admin');

// Initialize Firebase Admin safely
try {
  // To make push notifications work in prod, place your firebase service account JSON file in the backend root
  const serviceAccount = require('../firebase-service-account.json');
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    console.log('[FCM] Firebase Admin Initialized successfully.');
  }
} catch (error) {
  console.log('[FCM-WARNING] Firebase Admin not initialized. Please add firebase-service-account.json to the backend folder.');
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
    if (user && user.fcmToken) {
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
                channelId: 'transify_go_channel' // Matches Flutter local channel
              }
            }
          };

          const response = await admin.messaging().send(message);
          console.log('[FCM] Successfully sent message:', response);
        } else {
          console.log('[FCM-WARNING] Firebase admin not configured. Skipping real push dispatch.');
        }
    }
    return true;
  } catch (err) {
    console.error('[FCM-ERROR] Push Notification Error:', err);
    return false;
  }
};

module.exports = { router, sendPushNotification };
