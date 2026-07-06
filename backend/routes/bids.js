const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const Bid = require('../models/Bid');
const { authenticateToken, requireRole } = require('../middleware/auth');

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

// Place Bid (For Drivers)
// POST /api/bids/place
router.post('/place', checkDB, authenticateToken, requireRole(['Driver', 'Admin']), async (req, res) => {
  try {
    const { loadId, driverId, bidAmount, message } = req.body;

    if (!loadId || !driverId || !bidAmount) {
      return res.status(400).json({ success: false, message: 'Missing required fields' });
    }

    // Role check: Driver can only bid as themselves
    if (req.user.role !== 'Admin' && driverId !== req.user.id) {
      return res.status(403).json({ success: false, message: 'Forbidden. Cannot place bid for another driver.' });
    }

    if (process.env.IS_TESTING === 'true') {
      console.log(`[DEBUG-TEST] Bid submission attempt: loadId=${loadId}, driverId=${driverId}, amount=${bidAmount}, message="${message || ''}"`);
    }

    // Check if the driver has already placed a bid on this load
    let bid = await Bid.findOne({ loadId, driverId });
    if (bid) {
      // Update existing bid
      bid.bidAmount = Number(bidAmount);
      bid.message = message || '';
      bid.status = 'Pending'; // Reset status if it was previously rejected
      bid.createdAt = new Date();
      await bid.save();
      console.log(`✅ Bid updated for load ${loadId} by driver ${driverId} (Amount: ₹${bidAmount})`);
      
      if (process.env.IS_TESTING === 'true') {
        console.log(`[DEBUG-TEST] Bid updated successfully: bidId=${bid._id}`);
      }
      
      return res.status(200).json({ success: true, message: 'Bid placed successfully', bid });
    }

    // Create new bid
    bid = new Bid({
      loadId,
      driverId,
      bidAmount: Number(bidAmount),
      message: message || '',
      status: 'Pending'
    });

    await bid.save();
    console.log(`✅ New Bid placed for load ${loadId} by driver ${driverId} (Amount: ₹${bidAmount})`);
    
    if (process.env.IS_TESTING === 'true') {
      console.log(`[DEBUG-TEST] Bid created successfully: bidId=${bid._id}`);
    }

    res.status(201).json({ success: true, message: 'Bid placed successfully', bid });
  } catch (err) {
    console.error('Place Bid Error:', err);
    res.status(500).json({ success: false, message: 'Failed to place bid', error: err.message });
  }
});

module.exports = router;
