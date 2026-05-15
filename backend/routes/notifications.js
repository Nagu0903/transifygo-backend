const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const Notification = require('../models/Notification');
const User = require('../models/User');
// Note: In a real prod environment, you'd use 'firebase-admin'
// For this implementation, we will simulate the FCM sending logic 
// or provide the structure to plug in firebase-admin easily.

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

// Helper function to send notification (Simulated or Real Firebase Admin)
const sendPushNotification = async (userId, title, body, type, data = {}) => {
  try {
    // 1. Save to DB
    const notification = new Notification({ userId, title, body, type, data });
    await notification.save();

    // 2. Get User's FCM Token
    const user = await User.findById(userId);
    if (user && user.fcmToken) {
        console.log(`[FCM] Sending to ${user.fcmToken}: ${title} - ${body}`);
        // Here you would normally use admin.messaging().sendToDevice(...)
    }
    return true;
  } catch (err) {
    console.error('Push Notification Error:', err);
    return false;
  }
};

module.exports = { router, sendPushNotification };
