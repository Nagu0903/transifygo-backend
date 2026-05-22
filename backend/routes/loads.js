const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const Load = require('../models/Load');
const User = require('../models/User');
const { sendPushNotification } = require('./notifications');

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

// 1. Create a new load
// POST /api/loads/create
router.post('/create', checkDB, async (req, res) => {
  console.log('--- Create Load Request ---');
  try {
    const { userId, fullName, phone, fromLocation, toLocation, truckType, material, price, weight, notes, distance } = req.body;

    if (!userId || !fromLocation || !toLocation || !price) {
      return res.status(400).json({ success: false, message: 'Missing required fields' });
    }

    const newLoad = new Load({
      userId,
      fullName,
      phone,
      fromLocation,
      toLocation,
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
    console.log('✅ Load Created:', newLoad._id);

    // Notify Active Drivers with FCM Tokens asynchronously
    const notifyDrivers = async () => {
      console.log("NEW_LOAD_NOTIFY_STARTED");
      try {
        const drivers = await User.find({ 
          role: 'Driver', 
          isBlocked: { $ne: true },
          fcmToken: { $exists: true, $ne: '', $ne: null }
        });

        console.log("DRIVERS_FOUND", drivers.length);
        console.log(drivers.slice(0, 5));

        for (const driver of drivers) {
          console.log("DRIVER_TOKEN", driver.fcmToken);
          const bodyMsg = `New load posted from ${fromLocation || 'N/A'} to ${toLocation || 'N/A'} • ₹${price || 'N/A'}\nMaterial: ${material || 'N/A'} | Vehicle: ${truckType || 'N/A'}`;
          await sendPushNotification(
            driver._id.toString(), 
            '🚛 New Load Available', 
            bodyMsg, 
            'new_load', 
            { 
               loadId: newLoad._id.toString(),
               pickup: fromLocation || '',
               drop: toLocation || '',
               amount: price ? price.toString() : ''
            }
          );
        }
      } catch (notifyErr) {
        console.error('Background driver notification error:', notifyErr);
      }
    };
    
    // Execute asynchronously without blocking the API response
    notifyDrivers();

    res.status(201).json({ success: true, message: 'Load posted successfully', load: newLoad });
  } catch (err) {
    console.error('Create Load Error:', err);
    res.status(500).json({ success: false, message: 'Failed to create load', error: err.message });
  }
});

// 2. Fetch My Loads (Filtered by userId)
// GET /api/loads/my-loads/:userId
router.get('/my-loads/:userId', checkDB, async (req, res) => {
  try {
    const loads = await Load.find({ userId: req.params.userId }).sort({ createdAt: -1 });
    res.json({ success: true, loads });
  } catch (err) {
    console.error('Fetch My Loads Error:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch your loads' });
  }
});

// 3. Update Load Status
// PUT /api/loads/status/:loadId
router.put('/status/:loadId', checkDB, async (req, res) => {
  try {
    const { status, driverId, driverName, driverPhone, deliveryPhotoUrl, invoicePhotoUrl, unloadingProofUrl } = req.body;
    const loadId = req.params.loadId;

    const loadCheck = await Load.findById(loadId);
    if (loadCheck && loadCheck.status === 'cancelled') {
      return res.status(400).json({ success: false, message: 'This load has been cancelled and cannot be updated.' });
    }

    const updateData = { status };
    if (driverId) updateData.driverId = driverId;
    if (driverName) updateData.driverName = driverName;
    if (driverPhone) updateData.driverPhone = driverPhone;

    // URL Validation Helper
    const isValidFirebaseUrl = (url) => typeof url === 'string' && url.startsWith('https://firebasestorage.googleapis.com/');

    if (deliveryPhotoUrl) {
      if (!isValidFirebaseUrl(deliveryPhotoUrl)) return res.status(400).json({ success: false, message: 'Invalid delivery photo URL' });
      updateData.deliveryPhotoUrl = deliveryPhotoUrl;
    }
    if (invoicePhotoUrl) {
      if (!isValidFirebaseUrl(invoicePhotoUrl)) return res.status(400).json({ success: false, message: 'Invalid invoice photo URL' });
      updateData.invoicePhotoUrl = invoicePhotoUrl;
    }
    if (unloadingProofUrl) {
      if (!isValidFirebaseUrl(unloadingProofUrl)) return res.status(400).json({ success: false, message: 'Invalid unloading proof URL' });
      updateData.unloadingProofUrl = unloadingProofUrl;
    }

    if (status === 'completed') {
      updateData.completedAt = new Date();
      updateData.paymentStatus = 'pending';
    }

    const load = await Load.findByIdAndUpdate(loadId, updateData, { new: true });
    
    if (!load) {
      return res.status(404).json({ success: false, message: 'Load not found' });
    }

    // Notify Owner about Acceptance or Driver about Completion
    if (status === 'accepted') {
      console.log("ACCEPT_NOTIFY_STARTED");
      const owner = await User.findById(load.userId);
      console.log("OWNER_FOUND", owner?._id);
      console.log("OWNER_TOKEN", owner?.fcmToken);
      const acceptBody = `Driver: ${driverName || 'N/A'}\nFrom: ${load.fromLocation || 'N/A'} to ${load.toLocation || 'N/A'}\nVehicle: ${load.truckType || 'N/A'}\nAmount: ₹${load.price || 'N/A'}`;
      sendPushNotification(
        load.userId, 
        'Your load has been accepted by a driver.', 
        acceptBody, 
        'load_accepted', 
        { loadId: load._id.toString() }
      );
    } else if (status === 'completed') {
      sendPushNotification(
        load.userId, 
        'Load Delivered! 🎉', 
        `Your load from ${load.fromLocation} to ${load.toLocation} has been completed.`, 
        'load_completed', 
        { 
          loadId: load._id.toString(),
          loadData: JSON.stringify(load)
        }
      );
    }

    console.log(`✅ Load ${loadId} status updated to: ${status}`);
    res.json({ success: true, message: `Load ${status} successfully`, load });
  } catch (err) {
    console.error('Update Status Error:', err);
    res.status(500).json({ success: false, message: 'Failed to update load status' });
  }
});

// 3.5. Update Payment Status (For Owners)
// PUT /api/loads/:id/payment
router.put('/:id/payment', checkDB, async (req, res) => {
  try {
    const loadId = req.params.id;
    const { totalAmount, paidAmount, enteredAmount, paymentMethod, paymentNotes, paymentScreenshotUrl } = req.body;

    const load = await Load.findById(loadId);
    if (!load) return res.status(404).json({ success: false, message: 'Load not found' });
    if (load.status !== 'completed') {
      return res.status(400).json({ success: false, message: 'Payment can only be updated for completed loads' });
    }

    if (totalAmount !== undefined) load.totalAmount = Number(totalAmount);
    const currentTotal = load.totalAmount || 0;
    
    let isIncremental = false;
    let chunk = 0;

    if (enteredAmount !== undefined) {
      isIncremental = true;
      chunk = Number(enteredAmount) || 0;
      const oldPaid = load.paidAmount || 0;
      const newPaid = oldPaid + chunk;
      
      if (currentTotal > 0 && newPaid > currentTotal) {
        return res.status(400).json({ success: false, message: `Payment of ₹${chunk} exceeds the remaining balance of ₹${currentTotal - oldPaid}` });
      }
      
      load.paidAmount = newPaid;
      
      // Push to history
      if (chunk > 0) {
        if (!load.paymentHistory) load.paymentHistory = [];
        load.paymentHistory.push({
          amount: chunk,
          date: new Date(),
          method: paymentMethod || load.paymentMethod,
          notes: paymentNotes || load.paymentNotes,
          screenshotUrl: paymentScreenshotUrl
        });
      }
    } else if (paidAmount !== undefined) {
      // Legacy support for absolute overwrite
      load.paidAmount = Number(paidAmount);
    }

    // Safely update legacy fields for last payment info
    if (paymentMethod !== undefined) load.paymentMethod = paymentMethod;
    if (paymentNotes !== undefined) load.paymentNotes = paymentNotes;
    if (paymentScreenshotUrl !== undefined) load.paymentScreenshotUrl = paymentScreenshotUrl;

    // Auto-calculate remaining amount and status
    const currentPaid = load.paidAmount || 0;
    
    if (currentTotal > 0) {
      load.remainingAmount = Math.max(0, currentTotal - currentPaid);
      
      if (currentPaid >= currentTotal) {
        load.paymentStatus = 'paid';
      } else if (currentPaid > 0) {
        load.paymentStatus = 'partial';
      } else {
        load.paymentStatus = 'pending';
      }
    }

    load.paymentUpdatedAt = new Date();

    await load.save();

    // Notify Driver
    if (load.driverId) {
      const statusText = load.paymentStatus === 'paid' ? 'Full Payment Received! 💰' : 'Partial Payment Updated! 💵';
      const bodyText = `Owner has updated the payment for load ${load.fromLocation} to ${load.toLocation}. Paid: ₹${load.paidAmount}.`;
      
      sendPushNotification(
        load.driverId,
        statusText,
        bodyText,
        'payment_updated',
        { loadId: load._id.toString() }
      );
    }

    console.log(`✅ Payment updated for Load ${loadId}: ${load.paymentStatus}`);
    res.json({ success: true, message: 'Payment updated successfully', load });
  } catch (err) {
    console.error('Update Payment Error:', err);
    res.status(500).json({ success: false, message: 'Failed to update payment' });
  }
});

// 4. Get all pending loads (For Drivers)
// GET /api/loads
router.get('/', checkDB, async (req, res) => {
  try {
    console.log('[DRIVER] Fetching pending loads...');
    const loads = await Load.find({ 
      status: 'pending',
      isActive: true,
      visibleToDrivers: true
    }).sort({ createdAt: -1 });
    console.log(`[DRIVER] Found ${loads.length} visible loads.`);
    res.json({ success: true, loads });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Failed to fetch loads' });
  }
});

// 5. Get Loads by Driver ID
// GET /api/loads/driver/:driverId
router.get('/driver/:driverId', checkDB, async (req, res) => {
  try {
    // Filter out cancelled loads for drivers
    const loads = await Load.find({ 
      driverId: req.params.driverId,
      status: { $ne: 'cancelled' } 
    }).sort({ createdAt: -1 });
    res.json({ success: true, loads });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Failed to fetch accepted loads' });
  }
});

// 6. Dedicated Cancel Route
// PUT /api/load/cancel/:loadId
router.put('/cancel/:loadId', checkDB, async (req, res) => {
  try {
    const loadId = req.params.loadId;
    const load = await Load.findById(loadId);

    if (!load) {
      return res.status(404).json({ success: false, message: 'Load not found' });
    }

    if (load.status === 'completed') {
      return res.status(400).json({ success: false, message: 'Cannot cancel a completed load' });
    }

    load.status = 'cancelled';
    load.isActive = false;
    load.visibleToDrivers = false;
    load.cancelledBy = 'owner';
    load.cancelledAt = new Date();
    await load.save();

    console.log(`[CANCEL] Load ${loadId} marked as cancelled by Owner at ${load.cancelledAt}. Visibility revoked.`);

    console.log(`[CANCEL] Load ${loadId} marked as cancelled, inactive, and hidden.`);

    // Notify Driver if the load was already accepted
    if (load.driverId) {
      sendPushNotification(
        load.driverId, 
        'Load Cancelled ❌', 
        `The load from ${load.fromLocation} has been cancelled by the owner.`, 
        'load_cancelled', 
        { loadId: load._id }
      );
    }

    console.log(`✅ Load ${loadId} cancelled by owner`);
    res.json({ success: true, message: 'Load cancelled successfully', load });
  } catch (err) {
    console.error('Cancel Load Error:', err);
    res.status(500).json({ success: false, message: 'Failed to cancel load' });
  }
});

module.exports = router;
