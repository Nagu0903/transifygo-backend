const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const User = require('../models/User');
const jwt = require('jsonwebtoken');
const admin = require('firebase-admin');
const Otp = require('../models/Otp');
const BlockedPhone = require('../models/BlockedPhone');
const OtpLog = require('../models/OtpLog');
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const axios = require('axios');

// Middleware to check DB connection
const checkDB = (req, res, next) => {
  if (mongoose.connection.readyState !== 1) {
    return res.status(503).json({ 
      success: false, 
      message: 'Database is not connected. Please check Atlas IP whitelist (0.0.0.0/0).' 
    });
  }
  next();
};

// Send OTP API using MSG91 with Rate Limiting
router.post('/send-otp', checkDB, async (req, res) => {
  console.log('--- Send OTP Request Started ---');
  try {
    const { phone } = req.body;
    if (!phone || phone.length !== 10) {
      return res.status(400).json({ success: false, message: 'Invalid 10-digit phone number' });
    }

    // 1. Check if phone is blocked in BlockedPhone collection
    const blockedEntry = await BlockedPhone.findOne({ phone });
    if (blockedEntry) {
      const log = new OtpLog({ phone, action: 'BLOCKED', ip: req.ip, userAgent: req.headers['user-agent'], details: `Blocked attempt: ${blockedEntry.reason}` });
      await log.save();
      return res.status(403).json({ success: false, message: `This phone number has been blocked: ${blockedEntry.reason}` });
    }

    // 2. Check if a User is blocked
    const existingUser = await User.findOne({ phone });
    if (existingUser && existingUser.isBlocked) {
      const log = new OtpLog({ phone, action: 'BLOCKED', ip: req.ip, userAgent: req.headers['user-agent'], details: 'User account is blocked' });
      await log.save();
      return res.status(403).json({ success: false, message: 'Your account has been blocked.' });
    }

    // 3. Enforce Rate Limit: Max 5 OTP requests per hour per number
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
    const requestCount = await OtpLog.countDocuments({ 
      phone, 
      action: 'SEND_OTP', 
      timestamp: { $gte: oneHourAgo } 
    });

    if (requestCount >= 5) {
      return res.status(429).json({ 
        success: false, 
        message: 'Too many OTP requests. Maximum 5 requests per hour. Please try again later.' 
      });
    }

    // 4. Generate secure 6-digit OTP
    const otp = crypto.randomInt(100000, 1000000).toString();

    // 5. Hash OTP and store in DB
    const salt = await bcrypt.genSalt(10);
    const otpHash = await bcrypt.hash(otp, salt);
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000); // 5 minutes expiry

    await Otp.findOneAndUpdate(
      { phone }, 
      { otpHash, attempts: 0, expiresAt }, 
      { upsert: true, new: true }
    );

    // 6. Log the OTP send event
    const log = new OtpLog({ phone, action: 'SEND_OTP', ip: req.ip, userAgent: req.headers['user-agent'] });
    await log.save();

    // 7. Deliver OTP via MSG91 (or fallback)
    const authKey = process.env.MSG91_AUTH_KEY;
    const templateId = process.env.MSG91_TEMPLATE_ID;

    if (authKey && templateId) {
      try {
        await axios.post('https://control.msg91.com/api/v5/flow/', {
          template_id: templateId,
          recipients: [
            {
              mobiles: `91${phone}`,
              otp: otp
            }
          ]
        }, {
          headers: {
            'authkey': authKey,
            'Content-Type': 'application/json'
          }
        });
        console.log(`[MSG91] OTP sent to 91${phone}`);
      } catch (err) {
        console.error('[MSG91] SMS delivery failed, falling back to console log:', err.response ? err.response.data : err.message);
        console.log(`[DEV ONLY] Generated OTP for 91${phone} is: ${otp}`);
      }
    } else {
      console.log(`[DEV ONLY] Generated OTP for 91${phone} is: ${otp}`);
    }

    res.json({ success: true, message: 'OTP sent successfully' });

  } catch (err) {
    console.error('Send OTP Error:', err);
    res.status(500).json({ success: false, message: 'Server error during OTP request', error: err.message });
  }
});

// Verify OTP and Authenticate User (Login / Auto-Signup)
router.post('/verify-otp', checkDB, async (req, res) => {
  console.log('--- Verify OTP Request Started ---');
  try {
    const { phone, otp, role } = req.body;
    if (!phone || !otp || !role) {
      return res.status(400).json({ success: false, message: 'Phone, OTP, and role are required' });
    }

    // 1. Fetch OTP record
    const otpDoc = await Otp.findOne({ phone });
    if (!otpDoc) {
      return res.status(400).json({ success: false, message: 'OTP expired or not found. Please request a new OTP.' });
    }

    // 2. Prevent brute-force (Max 5 attempts)
    if (otpDoc.attempts >= 5) {
      await Otp.deleteOne({ phone });
      return res.status(400).json({ success: false, message: 'Maximum verification attempts exceeded. Please request a new OTP.' });
    }

    // 3. Verify OTP code matches hash
    const isMatch = await bcrypt.compare(otp, otpDoc.otpHash);
    if (!isMatch) {
      otpDoc.attempts += 1;
      await otpDoc.save();

      const log = new OtpLog({ 
        phone, 
        action: 'VERIFY_FAILED', 
        ip: req.ip, 
        userAgent: req.headers['user-agent'], 
        details: `Incorrect code attempt. ${5 - otpDoc.attempts} remaining.` 
      });
      await log.save();

      return res.status(400).json({ 
        success: false, 
        message: `Invalid OTP. ${5 - otpDoc.attempts} verification attempts remaining.` 
      });
    }

    // 4. Verification Successful! Delete OTP record
    await Otp.deleteOne({ phone });

    // 5. Log verification success
    const log = new OtpLog({ phone, action: 'VERIFY_SUCCESS', ip: req.ip, userAgent: req.headers['user-agent'] });
    await log.save();

    // 6. Login existing user or auto-signup new user
    let user = await User.findOne({ phone, role });
    let isNewUser = false;

    if (!user) {
      isNewUser = true;
      // Auto register new user
      const name = 'User ' + phone.substring(phone.length - 4);
      user = new User({
        name,
        phone,
        password: 'TransifyGoOTP2026', // Secure default password/PIN for backward compatibility
        role,
        city: 'India',
        truckType: role === 'Driver' ? 'Open' : undefined,
        truckNumber: role === 'Driver' ? 'MH01AB1234' : undefined
      });
      await user.save();
      console.log('✅ Auto-Signup successful for:', name, phone);
    } else {
      // If user exists, verify they are not blocked
      if (user.isBlocked) {
        return res.status(403).json({ success: false, message: 'Your account has been blocked.' });
      }
      console.log('✅ Login successful for:', user.name, phone);
    }

    // 7. Mint JWT Token
    const token = jwt.sign(
      { id: user._id, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    res.json({
      success: true,
      message: isNewUser ? 'Registration successful' : 'Login successful',
      token,
      user: {
        id: user._id,
        fullName: user.name,
        name: user.name,
        phone: user.phone,
        role: user.role
      }
    });

  } catch (err) {
    console.error('Verify OTP Error:', err);
    res.status(500).json({ success: false, message: 'Server error during OTP verification', error: err.message });
  }
});

// Signup API
router.post('/signup', checkDB, async (req, res) => {
  console.log('--- Signup Request Started ---');
  console.log('Request Body:', { ...req.body, password: '***', pin: '***' }); // Log body safely

  try {
    const { name, fullName, phone, password, pin, role, city, truckType, truckNumber } = req.body;

    // Map fullName to name if provided, and pin to password
    const finalName = fullName || name;
    const finalPassword = pin || password;

    if (!finalName || !phone || !finalPassword || !role) {
      return res.status(400).json({ success: false, message: 'Missing required fields: name/fullName, phone, password/pin, and role are required.' });
    }

    // Secure Admin signup
    if (role === 'Admin') {
      const adminSecret = req.headers['x-admin-secret'] || req.body.adminSecret;
      const expectedSecret = process.env.ADMIN_SIGNUP_SECRET || 'transify_admin_secret_2026';
      if (adminSecret !== expectedSecret) {
        return res.status(403).json({ success: false, message: 'Forbidden. Unauthorized registration of Admin role.' });
      }
    }

    // Check if user already exists
    let user = await User.findOne({ phone });
    if (user) {
      return res.status(400).json({ success: false, message: 'User already exists with this phone number' });
    }

    // Create new user
    user = new User({
      name: finalName,
      phone,
      password: finalPassword,
      role,
      city,
      truckType,
      truckNumber
    });

    await user.save();

    // Create JWT
    const token = jwt.sign(
      { id: user._id, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    console.log('✅ Signup Successful for:', finalName, phone);

    res.status(201).json({
      success: true,
      message: 'Signup successful',
      token,
      user: {
        id: user._id,
        fullName: user.name,
        name: user.name,
        phone: user.phone,
        role: user.role
      }
    });

  } catch (err) {
    console.error('Signup Error:', err);
    res.status(500).json({ success: false, message: 'Server error during signup', error: err.message });
  }
});

// Login API
router.post('/login', checkDB, async (req, res) => {
  console.log('--- Login Request Started ---');
  console.log('Login Body:', { ...req.body, password: '***' });

  try {
    const { phone, password, role } = req.body;

    // 1. Check if user exists
    const user = await User.findOne({ phone, role });
    if (!user) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    // 2. Check if blocked
    if (user.isBlocked) {
      return res.status(403).json({ success: false, message: 'Your account has been blocked' });
    }

    // 3. Verify password
    const isMatch = await user.comparePassword(password);
    if (!isMatch) {
      return res.status(401).json({ success: false, message: 'Invalid credentials' });
    }

    // 4. Create JWT
    const token = jwt.sign(
      { id: user._id, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    res.json({
      success: true,
      message: 'Login successful',
      token,
      user: {
        id: user._id,
        fullName: user.name,
        name: user.name,
        phone: user.phone,
        role: user.role
      }
    });

  } catch (err) {
    console.error('Login Error:', err);
    res.status(500).json({ success: false, message: 'Server error during login', error: err.message });
  }
});

// Forgot Password API (Professional Implementation)
router.post('/forgot-password', checkDB, async (req, res) => {
  console.log('--- Forgot Password Request Started ---');
  try {
    const { phone, newPin } = req.body;

    if (!phone || !newPin) {
      return res.status(400).json({ success: false, message: 'Phone and new PIN are required' });
    }

    // Find user by phone only (phone is unique in schema)
    const user = await User.findOne({ phone });
    if (!user) {
      return res.status(404).json({ success: false, message: 'Account not found with this phone number' });
    }

    // Update password (User.js pre-save hook will hash it)
    user.password = newPin;
    await user.save();

    console.log('✅ Password Reset Successful for:', phone);
    res.json({
      success: true,
      message: 'Password reset successful'
    });

  } catch (err) {
    console.error('Forgot Password Error:', err);
    res.status(500).json({ success: false, message: 'Failed to reset password', error: err.message });
  }
});

// Legacy Reset Password API (Keeping for compatibility if needed elsewhere)
router.post('/reset-password', checkDB, async (req, res) => {
  console.log('--- Reset Password Request Started ---');
  try {
    const { phone, role, newPassword } = req.body;

    if (!phone || !role || !newPassword) {
      return res.status(400).json({ success: false, message: 'Phone, role, and new password are required' });
    }

    const user = await User.findOne({ phone, role });
    if (!user) {
      return res.status(404).json({ success: false, message: 'Account not found with this phone and role' });
    }

    // Update password (User.js pre-save hook will hash it)
    user.password = newPassword;
    await user.save();

    console.log('✅ Password Reset Successful for:', phone);
    res.json({ success: true, message: 'Password reset successful' });

  } catch (err) {
    console.error('Reset Password Error:', err);
    res.status(500).json({ success: false, message: 'Failed to reset password', error: err.message });
  }
});

// Firebase Custom Token API
router.post('/firebase-token', checkDB, async (req, res) => {
  console.log('--- Firebase Custom Token Request Started ---');
  try {
    const { userId } = req.body;
    if (!userId) {
      return res.status(400).json({ success: false, message: 'userId is required' });
    }

    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    // Mint custom Firebase token
    const customToken = await admin.auth().createCustomToken(user._id.toString());
    
    res.json({
      success: true,
      firebaseToken: customToken
    });

// Firebase ID Token Login / Auto-Signup API
router.post('/firebase-login', checkDB, async (req, res) => {
  console.log('--- Firebase Token Login Request Started ---');
  try {
    const authHeader = req.headers.authorization;
    // support passing token in headers or body
    let idToken = null;
    if (authHeader && authHeader.startsWith('Bearer ')) {
      idToken = authHeader.split('Bearer ')[1];
    } else if (req.body.idToken) {
      idToken = req.body.idToken;
    }

    if (!idToken) {
      return res.status(401).json({ success: false, message: 'Authorization token or idToken is missing' });
    }

    // 1. Verify Firebase ID Token using Firebase Admin SDK
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    const firebaseUid = decodedToken.uid;
    const phone = decodedToken.phone_number;

    if (!phone) {
      return res.status(400).json({ success: false, message: 'Firebase token does not contain a verified phone number' });
    }

    // 2. Normalize phone number (remove country code prefix +91 or 91)
    let normalizedPhone = phone;
    if (phone.startsWith('+91') && phone.length === 13) {
      normalizedPhone = phone.substring(3);
    } else if (phone.startsWith('91') && phone.length === 12) {
      normalizedPhone = phone.substring(2);
    } else if (phone.startsWith('+')) {
      // General E.164 normalization for other countries
      normalizedPhone = phone.replace('+', '');
    }

    const { role } = req.body;
    if (!role) {
      return res.status(400).json({ success: false, message: 'Role is required for auto-registration checks' });
    }

    // 3. Check if phone is blocked
    const blockedEntry = await BlockedPhone.findOne({ phone: normalizedPhone });
    if (blockedEntry) {
      return res.status(403).json({ success: false, message: `This phone number has been blocked: ${blockedEntry.reason}` });
    }

    // 4. Find or create user
    let user = await User.findOne({ phone: normalizedPhone, role });
    let isNewUser = false;

    if (!user) {
      isNewUser = true;
      const name = 'User ' + normalizedPhone.substring(normalizedPhone.length - 4);
      user = new User({
        name,
        phone: normalizedPhone,
        password: 'TransifyGoOTP2026', // Secure default PIN/password for backward compatibility
        role,
        city: 'India',
        truckType: role === 'Driver' ? 'Open' : undefined,
        truckNumber: role === 'Driver' ? 'MH01AB1234' : undefined
      });
      await user.save();
      console.log('✅ Auto-Signup successful via Firebase:', name, normalizedPhone);
    } else {
      if (user.isBlocked) {
        return res.status(403).json({ success: false, message: 'Your account has been blocked.' });
      }
      console.log('✅ Login successful via Firebase:', user.name, normalizedPhone);
    }

    // 5. Mint JWT application token
    const token = jwt.sign(
      { id: user._id, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    res.json({
      success: true,
      message: isNewUser ? 'Registration successful' : 'Login successful',
      token,
      user: {
        id: user._id,
        fullName: user.name,
        name: user.name,
        phone: user.phone,
        role: user.role
      }
    });

  } catch (err) {
    console.error('Firebase token verification failed:', err);
    res.status(401).json({ success: false, message: 'Firebase authentication failed', error: err.message });
  }
});

module.exports = router;
