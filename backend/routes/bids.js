const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const Bid = require('../models/Bid');

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
router.post('/place', checkDB, async (req, res) => {
  try {
    const { loadId, driverId, bidAmount, message } = req.body;

    if (!loadId || !driverId || !bidAmount) {
      return res.status(400).json({ success: false, message: 'Missing required fields' });
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
    res.status(201).json({ success: true, message: 'Bid placed successfully', bid });
  } catch (err) {
    console.error('Place Bid Error:', err);
    res.status(500).json({ success: false, message: 'Failed to place bid', error: err.message });
  }
});

module.exports = router;
