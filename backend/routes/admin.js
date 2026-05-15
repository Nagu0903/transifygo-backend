const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const User = require('../models/User');
const Load = require('../models/Load');

// Middleware to check DB connection
const checkDB = (req, res, next) => {
  if (mongoose.connection.readyState !== 1) {
    return res.status(503).json({ 
      success: false, 
      message: 'Database is not connected.' 
    });
  }
  next();
};

// 1. Professional Admin Stats
// GET /api/admin/stats
router.get('/stats', checkDB, async (req, res) => {
  try {
    const [totalUsers, totalDrivers, totalLoadOwners, totalLoads, pendingLoads, acceptedLoads, completedLoads, cancelledLoads] = await Promise.all([
      User.countDocuments(),
      User.countDocuments({ role: 'Driver' }),
      User.countDocuments({ role: 'Load Owner' }),
      Load.countDocuments(),
      Load.countDocuments({ status: 'pending' }),
      Load.countDocuments({ status: 'accepted' }),
      Load.countDocuments({ status: 'completed' }),
      Load.countDocuments({ status: 'cancelled' })
    ]);

    res.json({
      success: true,
      stats: {
        totalUsers,
        totalDrivers,
        totalLoadOwners,
        totalLoads,
        pendingLoads,
        acceptedLoads,
        completedLoads,
        cancelledLoads
      }
    });
  } catch (err) {
    console.error('Admin Stats Error:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch admin stats' });
  }
});

// 2. Live Loads Monitoring
// GET /api/admin/live-loads (Alias: /loads)
router.get(['/live-loads', '/loads'], checkDB, async (req, res) => {
  try {
    const loads = await Load.find().sort({ createdAt: -1 });
    res.json({ success: true, loads });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Failed to fetch live loads' });
  }
});

// 3. Drivers List
// GET /api/admin/drivers
router.get('/drivers', checkDB, async (req, res) => {
  try {
    const drivers = await User.find({ role: 'Driver' }).sort({ createdAt: -1 });
    res.json({ success: true, drivers });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Failed to fetch drivers' });
  }
});

// 4. Load Owners List
// GET /api/admin/loadowners (Alias: /users)
router.get(['/loadowners', '/users'], checkDB, async (req, res) => {
  try {
    const users = await User.find({ role: 'Load Owner' }).sort({ createdAt: -1 });
    res.json({ success: true, users });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Failed to fetch load owners' });
  }
});

// 5. Specific Status Loads
// GET /api/admin/pending
router.get('/pending', checkDB, async (req, res) => {
  try {
    const loads = await Load.find({ status: 'pending' }).sort({ createdAt: -1 });
    res.json({ success: true, loads });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Failed to fetch pending loads' });
  }
});

// GET /api/admin/accepted
router.get('/accepted', checkDB, async (req, res) => {
  try {
    const loads = await Load.find({ status: 'accepted' }).sort({ createdAt: -1 });
    res.json({ success: true, loads });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Failed to fetch accepted loads' });
  }
});

// GET /api/admin/completed
router.get('/completed', checkDB, async (req, res) => {
  try {
    const loads = await Load.find({ status: 'completed' }).sort({ createdAt: -1 });
    res.json({ success: true, loads });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Failed to fetch completed loads' });
  }
});

// 6. Delete a Load
// DELETE /api/admin/loads/:loadId
router.delete('/loads/:loadId', checkDB, async (req, res) => {
  try {
    const load = await Load.findByIdAndDelete(req.params.loadId);
    if (!load) return res.status(404).json({ success: false, message: 'Load not found' });
    res.json({ success: true, message: 'Load deleted successfully' });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Failed to delete load' });
  }
});

// 7. Block/Unblock a User
// PUT /api/admin/users/:userId/block
router.put(['/users/:userId/block', '/loadowners/:userId/block'], checkDB, async (req, res) => {
  try {
    const { isBlocked } = req.body;
    const user = await User.findByIdAndUpdate(req.params.userId, { isBlocked }, { new: true });
    if (!user) return res.status(404).json({ success: false, message: 'User not found' });
    res.json({ success: true, message: `User ${isBlocked ? 'blocked' : 'unblocked'} successfully` });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Failed to update user status' });
  }
});

module.exports = router;
