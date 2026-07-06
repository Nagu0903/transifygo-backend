const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const User = require('../models/User');
const Load = require('../models/Load');
const Bid = require('../models/Bid');
const Assignment = require('../models/Assignment');
const BlockedPhone = require('../models/BlockedPhone');
const OtpLog = require('../models/OtpLog');
const { authenticateToken, requireRole } = require('../middleware/auth');

// Apply admin protection middleware globally to this router
router.use(authenticateToken);
router.use(requireRole(['Admin']));

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

// GET /api/admin/otp-logs - Fetch recent OTP login logs and history
router.get('/otp-logs', checkDB, async (req, res) => {
  try {
    const logs = await OtpLog.find().sort({ timestamp: -1 }).limit(100);
    res.json({ success: true, logs });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Failed to fetch OTP logs' });
  }
});

// GET /api/admin/blocked-phones - Fetch list of blocked suspicious numbers
router.get('/blocked-phones', checkDB, async (req, res) => {
  try {
    const blocked = await BlockedPhone.find().sort({ createdAt: -1 });
    res.json({ success: true, blocked });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Failed to fetch blocked phones' });
  }
});

// POST /api/admin/block-phone - Block a suspicious number
router.post('/block-phone', checkDB, async (req, res) => {
  try {
    const { phone, reason } = req.body;
    if (!phone || phone.length !== 10) {
      return res.status(400).json({ success: false, message: 'Invalid 10-digit phone number' });
    }

    // Add to BlockedPhone collection
    await BlockedPhone.findOneAndUpdate(
      { phone },
      { reason: reason || 'Suspicious login activity' },
      { upsert: true, new: true }
    );

    // Also toggle block on existing User if exists
    await User.updateMany({ phone }, { isBlocked: true });

    res.json({ success: true, message: `Phone number ${phone} blocked successfully` });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Failed to block phone number' });
  }
});

// POST /api/admin/unblock-phone - Unblock a number
router.post('/unblock-phone', checkDB, async (req, res) => {
  try {
    const { phone } = req.body;
    if (!phone) {
      return res.status(400).json({ success: false, message: 'Phone number is required' });
    }

    // Remove from BlockedPhone
    await BlockedPhone.deleteOne({ phone });

    // Also unblock existing User if exists
    await User.updateMany({ phone }, { isBlocked: false });

    res.json({ success: true, message: `Phone number ${phone} unblocked successfully` });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Failed to unblock phone number' });
  }
});

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

// GET /api/admin/bids - Fetch all pending / current bids
router.get('/bids', checkDB, async (req, res) => {
  try {
    const bids = await Bid.find().sort({ createdAt: -1 }).lean();
    
    const populatedBids = await Promise.all(bids.map(async (bid) => {
      let load = null;
      if (bid.loadId && mongoose.Types.ObjectId.isValid(bid.loadId)) {
        load = await Load.findById(bid.loadId).lean();
      }
      let driver = null;
      if (bid.driverId && mongoose.Types.ObjectId.isValid(bid.driverId)) {
        driver = await User.findById(bid.driverId).lean();
      }
      return {
        ...bid,
        loadDetails: load ? {
          id: load._id,
          fromLocation: load.fromLocation,
          toLocation: load.toLocation,
          material: load.material,
          price: load.price,
          weight: load.weight,
          truckType: load.truckType,
          status: load.status,
        } : null,
        driverDetails: driver ? {
          id: driver._id,
          name: driver.name,
          phone: driver.phone,
          truckType: driver.truckType,
          truckNumber: driver.truckNumber,
          rating: driver.rating || "5.0"
        } : null
      };
    }));

    // Filter out bids that don't have load or driver details anymore
    const validBids = populatedBids.filter(b => b.loadDetails && b.driverDetails);

    res.json({ success: true, bids: validBids });
  } catch (err) {
    console.error('Fetch Admin Bids Error:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch bids' });
  }
});

// POST /api/admin/bids/:bidId/accept - Accept a bid
router.post('/bids/:bidId/accept', checkDB, async (req, res) => {
  try {
    const bidId = req.params.bidId;
    const bid = await Bid.findById(bidId);
    if (!bid) {
      return res.status(404).json({ success: false, message: 'Bid not found' });
    }

    const load = await Load.findById(bid.loadId);
    if (!load) {
      return res.status(404).json({ success: false, message: 'Load not found' });
    }

    if (load.status === 'cancelled') {
      return res.status(400).json({ success: false, message: 'This load has been cancelled and cannot be accepted.' });
    }

    const driver = await User.findById(bid.driverId);
    if (!driver) {
      return res.status(404).json({ success: false, message: 'Driver not found' });
    }

    // Update current accepted bid
    bid.status = 'Accepted';
    await bid.save();

    // Reject other bids on the same load
    await Bid.updateMany(
      { loadId: bid.loadId, _id: { $ne: bidId } },
      { status: 'Rejected' }
    );

    // Update Load details
    load.status = 'accepted';
    load.driverId = driver._id.toString();
    load.driverName = driver.name;
    load.driverPhone = driver.phone;
    // Set the price of the load to the bid amount
    load.price = bid.bidAmount.toString();
    await load.save();

    // Create Assignment log
    const assignment = new Assignment({
      loadId: load._id.toString(),
      driverId: driver._id.toString(),
      driverName: driver.name,
      driverPhone: driver.phone
    });
    await assignment.save();

    if (process.env.IS_TESTING === 'true') {
      console.log(`[DEBUG-TEST] Assignment created for load ${load._id} and driver ${driver._id}: assignmentId=${assignment._id}`);
    }

    // Notify Owner and Driver using existing sendPushNotification
    const { sendPushNotification } = require('./notifications');
    
    // Notify Owner
    const ownerBody = `Your load from ${load.fromLocation} to ${load.toLocation} has been matched with driver ${driver.name} (Bid: ₹${bid.bidAmount}).`;
    sendPushNotification(
      load.userId,
      'Your load has been matched.',
      ownerBody,
      'load_accepted',
      { loadId: load._id.toString() }
    );

    // Notify Driver
    const driverBody = `Your bid of ₹${bid.bidAmount} for the load from ${load.fromLocation} to ${load.toLocation} has been accepted.`;
    sendPushNotification(
      driver._id.toString(),
      'Your bid has been accepted.',
      driverBody,
      'bid_accepted',
      { loadId: load._id.toString() }
    );

    res.json({ success: true, message: 'Bid accepted and load matched successfully', assignment });
  } catch (err) {
    console.error('Accept Bid Error:', err);
    res.status(500).json({ success: false, message: 'Failed to accept bid' });
  }
});

// POST /api/admin/bids/:bidId/reject - Reject a bid
router.post('/bids/:bidId/reject', checkDB, async (req, res) => {
  try {
    const bidId = req.params.bidId;
    const bid = await Bid.findById(bidId);
    if (!bid) {
      return res.status(404).json({ success: false, message: 'Bid not found' });
    }

    bid.status = 'Rejected';
    await bid.save();

    // Notify Driver
    const load = await Load.findById(bid.loadId);
    const { sendPushNotification } = require('./notifications');
    if (load) {
      const driverBody = `Your bid of ₹${bid.bidAmount} for the load from ${load.fromLocation} to ${load.toLocation} has been rejected.`;
      sendPushNotification(
        bid.driverId,
        'Your bid has been rejected.',
        driverBody,
        'bid_rejected',
        { loadId: load._id.toString() }
      );
    }

    res.json({ success: true, message: 'Bid rejected successfully' });
  } catch (err) {
    console.error('Reject Bid Error:', err);
    res.status(500).json({ success: false, message: 'Failed to reject bid' });
  }
});

// 8. Edit any load (For Admin)
// PUT /api/admin/loads/:loadId
router.put('/loads/:loadId', checkDB, async (req, res) => {
  try {
    const loadId = req.params.loadId;
    const updateData = req.body;

    const load = await Load.findByIdAndUpdate(loadId, updateData, { new: true });
    if (!load) {
      return res.status(404).json({ success: false, message: 'Load not found' });
    }

    console.log(`✅ Load ${loadId} updated by Admin`);
    res.json({ success: true, message: 'Load updated successfully by Admin', load });
  } catch (err) {
    console.error('Admin Edit Load Error:', err);
    res.status(500).json({ success: false, message: 'Failed to edit load', error: err.message });
  }
});

// 9. Add new load (For Admin)
// POST /api/admin/loads/create
router.post('/loads/create', checkDB, async (req, res) => {
  try {
    const { 
      userId, 
      fullName, 
      phone, 
      fromLocation, 
      fromDistrict,
      fromState,
      fromLat,
      fromLng,
      toLocation, 
      toDistrict,
      toState,
      toLat,
      toLng,
      truckType, 
      material, 
      price, 
      weight, 
      notes, 
      distance 
    } = req.body;

    if (!userId || !fromLocation || !toLocation || !price) {
      return res.status(400).json({ success: false, message: 'Missing required fields' });
    }

    const newLoad = new Load({
      userId,
      fullName,
      phone,
      fromLocation,
      fromDistrict,
      fromState,
      fromLat,
      fromLng,
      toLocation,
      toDistrict,
      toState,
      toLat,
      toLng,
      truckType,
      material,
      price,
      weight,
      notes,
      distance,
      status: 'pending',
      isActive: true,
      visibleToDrivers: true
    });

    await newLoad.save();
    console.log('✅ Load Created by Admin:', newLoad._id);
    res.status(201).json({ success: true, message: 'Load posted successfully by Admin', load: newLoad });
  } catch (err) {
    console.error('Admin Create Load Error:', err);
    res.status(500).json({ success: false, message: 'Failed to create load', error: err.message });
  }
});

// 10. Direct assign load to driver (For Admin)
// POST /api/admin/loads/:loadId/assign
router.post('/loads/:loadId/assign', checkDB, async (req, res) => {
  try {
    const loadId = req.params.loadId;
    const { driverId } = req.body;

    if (!driverId) {
      return res.status(400).json({ success: false, message: 'Missing driverId' });
    }

    const load = await Load.findById(loadId);
    if (!load) {
      return res.status(404).json({ success: false, message: 'Load not found' });
    }

    const driver = await User.findById(driverId);
    if (!driver) {
      return res.status(404).json({ success: false, message: 'Driver not found' });
    }

    load.status = 'accepted';
    load.driverId = driver._id.toString();
    load.driverName = driver.name;
    load.driverPhone = driver.phone;
    await load.save();

    // Create Assignment log
    const assignment = new Assignment({
      loadId: load._id.toString(),
      driverId: driver._id.toString(),
      driverName: driver.name,
      driverPhone: driver.phone
    });
    await assignment.save();

    if (process.env.IS_TESTING === 'true') {
      console.log(`[DEBUG-TEST] Assignment created via direct assign for load ${load._id} and driver ${driver._id}: assignmentId=${assignment._id}`);
    }

    res.json({ success: true, message: 'Driver assigned successfully', load, assignment });
  } catch (err) {
    console.error('Direct Assign Error:', err);
    res.status(500).json({ success: false, message: 'Failed to assign driver', error: err.message });
  }
});

module.exports = router;
