const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const User = require('../models/User');
const jwt = require('jsonwebtoken');

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

module.exports = router;
