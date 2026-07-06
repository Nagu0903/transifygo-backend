const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const Load = require('../models/Load');
const User = require('../models/User');
const { sendPushNotification } = require('./notifications');
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

// 1. Create a new load
// POST /api/loads/create
router.post('/create', checkDB, authenticateToken, requireRole(['Load Owner', 'Admin']), async (req, res) => {
  console.log('--- Create Load Request ---');
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

    // Role check: Load Owners can only create loads for themselves
    if (req.user.role !== 'Admin' && userId !== req.user.id) {
      return res.status(403).json({ success: false, message: 'Forbidden. Cannot create load for another user.' });
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
router.get('/my-loads/:userId', checkDB, authenticateToken, requireRole(['Load Owner', 'Admin']), async (req, res) => {
  try {
    if (req.user.role !== 'Admin' && req.params.userId !== req.user.id) {
      return res.status(403).json({ success: false, message: 'Forbidden. Cannot view other users\' loads.' });
    }

    const loads = await Load.find({ userId: req.params.userId }).sort({ createdAt: -1 }).lean();
    
    // Cargo owners cannot see driver phone numbers until a load is assigned
    const sanitizedLoads = loads.map(load => {
      if (load.status !== 'accepted' && load.status !== 'completed') {
        delete load.driverPhone;
      }
      return load;
    });

    res.json({ success: true, loads: sanitizedLoads });
  } catch (err) {
    console.error('Fetch My Loads Error:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch your loads' });
  }
});

// 3. Update Load Status
// PUT /api/loads/status/:loadId
router.put('/status/:loadId', checkDB, authenticateToken, requireRole(['Driver', 'Load Owner', 'Admin']), async (req, res) => {
  try {
    const loadId = req.params.loadId;
    const { status, driverId, driverName, driverPhone, deliveryPhotoUrl, invoicePhotoUrl, unloadingProofUrl } = req.body;

    const loadCheck = await Load.findById(loadId);
    if (!loadCheck) {
      return res.status(404).json({ success: false, message: 'Load not found' });
    }

    if (loadCheck.status === 'cancelled') {
      return res.status(400).json({ success: false, message: 'This load has been cancelled and cannot be updated.' });
    }

    // Role-based logic
    if (req.user.role === 'Driver') {
      // Drivers cannot edit or delete any load. They can only update status to accepted or completed.
      if (status === 'accepted') {
        if (loadCheck.status !== 'pending') {
          return res.status(400).json({ success: false, message: 'Load is no longer pending.' });
        }
        // Force the driverId to be the authenticated driver
        req.body.driverId = req.user.id;
        const driverUser = await User.findById(req.user.id);
        if (driverUser) {
          req.body.driverName = driverUser.name;
          req.body.driverPhone = driverUser.phone;
        }
      } else if (status === 'completed') {
        if (loadCheck.driverId !== req.user.id) {
          return res.status(403).json({ success: false, message: 'Forbidden. You are not the driver assigned to this load.' });
        }
      } else {
        return res.status(403).json({ success: false, message: 'Forbidden. Drivers can only accept or complete loads.' });
      }
    } else if (req.user.role === 'Load Owner') {
      if (loadCheck.userId !== req.user.id) {
        return res.status(403).json({ success: false, message: 'Forbidden. You do not own this load.' });
      }
      // Note: cargo owners usually cancel loads through the cancel route, but we allow other valid owner updates if any.
    }

    const updateData = { status };
    if (req.body.driverId) updateData.driverId = req.body.driverId;
    if (req.body.driverName) updateData.driverName = req.body.driverName;
    if (req.body.driverPhone) updateData.driverPhone = req.body.driverPhone;

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
      const acceptBody = `Driver: ${load.driverName || 'N/A'}\nFrom: ${load.fromLocation || 'N/A'} to ${load.toLocation || 'N/A'}\nVehicle: ${load.truckType || 'N/A'}\nAmount: ₹${load.price || 'N/A'}`;
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
router.put('/:id/payment', checkDB, authenticateToken, requireRole(['Load Owner', 'Admin']), async (req, res) => {
  try {
    const loadId = req.params.id;
    const { totalAmount, paidAmount, enteredAmount, paymentMethod, paymentNotes, paymentScreenshotUrl } = req.body;

    const load = await Load.findById(loadId);
    if (!load) return res.status(404).json({ success: false, message: 'Load not found' });
    
    if (req.user.role !== 'Admin' && load.userId !== req.user.id) {
      return res.status(403).json({ success: false, message: 'Forbidden. You do not own this load.' });
    }

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
router.get('/', checkDB, authenticateToken, requireRole(['Driver', 'Admin']), async (req, res) => {
  try {
    const { latitude, longitude } = req.query;
    console.log('[DRIVER] Fetching pending loads...', { latitude, longitude });

    let filter = {
      status: 'pending',
      isActive: true,
      visibleToDrivers: true
    };

    const radiusKm = Number(process.env.NEARBY_LOADS_RADIUS_KM) || 100;
    let loads = [];

    if (req.user.role === 'Driver') {
      if (latitude && longitude) {
        const driverLat = Number(latitude);
        const driverLng = Number(longitude);

        // Bounding box range calculation
        const deltaLat = radiusKm / 111.12;
        const cosLat = Math.cos((driverLat * Math.PI) / 180);
        const deltaLng = radiusKm / (111.12 * Math.max(cosLat, 0.1));

        filter.fromLat = { $gte: driverLat - deltaLat, $lte: driverLat + deltaLat };
        filter.fromLng = { $gte: driverLng - deltaLng, $lte: driverLng + deltaLng };

        if (process.env.IS_TESTING === 'true') {
          console.log(`[DEBUG-TEST] GPS Range Filtering: radius=${radiusKm}km, driverLat=${driverLat}, driverLng=${driverLng}`);
          console.log(`[DEBUG-TEST] Bounding box limits: lat [${driverLat - deltaLat} to ${driverLat + deltaLat}], lng [${driverLng - deltaLng} to ${driverLng + deltaLng}]`);
        }

        const candidateLoads = await Load.find(filter).lean();

        if (process.env.IS_TESTING === 'true') {
          console.log(`[DEBUG-TEST] Found ${candidateLoads.length} loads matching bounding box range query.`);
        }

        // Haversine exact distance filtering
        const calculateDistance = (lat1, lon1, lat2, lon2) => {
          const R = 6371;
          const dLat = ((lat2 - lat1) * Math.PI) / 180;
          const dLon = ((lon2 - lon1) * Math.PI) / 180;
          const a =
            Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos((lat1 * Math.PI) / 180) *
              Math.cos((lat2 * Math.PI) / 180) *
              Math.sin(dLon / 2) *
              Math.sin(dLon / 2);
          const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
          return R * c;
        };

        loads = candidateLoads
          .map((load) => {
            const dist = (load.fromLat !== undefined && load.fromLng !== undefined)
              ? calculateDistance(driverLat, driverLng, load.fromLat, load.fromLng)
              : null;
            return { ...load, calculatedDistance: dist };
          })
          .filter((load) => load.calculatedDistance !== null && load.calculatedDistance <= radiusKm)
          .sort((a, b) => a.calculatedDistance - b.calculatedDistance);

        if (process.env.IS_TESTING === 'true') {
          console.log(`[DEBUG-TEST] Filtered loads within precise circular radius: ${loads.length} loads.`);
        }
      } else {
        // Fallback: check driver's profile city
        const driverUser = await User.findById(req.user.id);
        if (driverUser && driverUser.city) {
          filter.fromLocation = new RegExp(driverUser.city, 'i');
          loads = await Load.find(filter).sort({ createdAt: -1 }).lean();
        } else {
          loads = [];
        }
      }

      // Hide cargo owner's personal details
      loads = loads.map((load) => {
        load.fullName = 'Cargo Owner';
        delete load.phone;
        delete load.userId;

        // Expected freight (price) visibility setting
        if (process.env.EXPECTED_FREIGHT_ENABLED === 'false') {
          delete load.price;
        }

        return load;
      });
    } else {
      // Admin gets everything
      loads = await Load.find(filter).sort({ createdAt: -1 }).lean();
    }

    console.log(`[DRIVER] Found ${loads.length} visible loads.`);
    res.json({ success: true, loads });
  } catch (err) {
    console.error('Fetch pending loads error:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch loads', error: err.message });
  }
});

// 5. Get Loads by Driver ID
// GET /api/loads/driver/:driverId
router.get('/driver/:driverId', checkDB, authenticateToken, requireRole(['Driver', 'Admin']), async (req, res) => {
  try {
    if (req.user.role !== 'Admin' && req.params.driverId !== req.user.id) {
      return res.status(403).json({ success: false, message: 'Forbidden. Cannot view another driver\'s loads.' });
    }

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
router.put('/cancel/:loadId', checkDB, authenticateToken, requireRole(['Load Owner', 'Admin']), async (req, res) => {
  try {
    const loadId = req.params.loadId;
    const load = await Load.findById(loadId);

    if (!load) {
      return res.status(404).json({ success: false, message: 'Load not found' });
    }

    if (req.user.role !== 'Admin' && load.userId !== req.user.id) {
      return res.status(403).json({ success: false, message: 'Forbidden. You do not own this load.' });
    }

    if (load.status === 'completed') {
      return res.status(400).json({ success: false, message: 'Cannot cancel a completed load' });
    }

    load.status = 'cancelled';
    load.isActive = false;
    load.visibleToDrivers = false;
    load.cancelledBy = req.user.role === 'Admin' ? 'admin' : 'owner';
    load.cancelledAt = new Date();
    await load.save();

    console.log(`[CANCEL] Load ${loadId} marked as cancelled by ${load.cancelledBy} at ${load.cancelledAt}. Visibility revoked.`);

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

    console.log(`✅ Load ${loadId} cancelled successfully`);
    res.json({ success: true, message: 'Load cancelled successfully', load });
  } catch (err) {
    console.error('Cancel Load Error:', err);
    res.status(500).json({ success: false, message: 'Failed to cancel load' });
  }
});

module.exports = router;
