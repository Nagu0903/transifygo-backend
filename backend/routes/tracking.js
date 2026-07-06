const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const Tracking = require('../models/Tracking');
const admin = require('firebase-admin');
const { authenticateToken, requireRole } = require('../middleware/auth');

// Helper to update Firestore real-time trip document in collection 'activeTrips'
const updateFirestoreTrip = async (tripId, data) => {
  try {
    if (admin.apps.length > 0) {
      const db = admin.firestore();
      
      // Clone payload to avoid side-effects
      const updatePayload = { ...data };
      
      // Map latitude and longitude to GeoPoint if present
      if (updatePayload.latitude !== undefined && updatePayload.longitude !== undefined) {
        updatePayload.currentLocation = new admin.firestore.GeoPoint(
          Number(updatePayload.latitude),
          Number(updatePayload.longitude)
        );
        delete updatePayload.latitude;
        delete updatePayload.longitude;
      }
      
      // Map timestamp fields correctly
      if (updatePayload.lastUpdated) {
        updatePayload.lastUpdated = admin.firestore.Timestamp.fromDate(new Date(updatePayload.lastUpdated));
      } else {
        updatePayload.lastUpdated = admin.firestore.FieldValue.serverTimestamp();
      }
      
      if (updatePayload.startedAt) {
        updatePayload.startedAt = admin.firestore.Timestamp.fromDate(new Date(updatePayload.startedAt));
      }

      await db.collection('activeTrips').doc(tripId).set(updatePayload, { merge: true });
      console.log(`[FIRESTORE] Synchronized trip ${tripId} successfully with status: ${data.status || 'updated'}`);
    } else {
      console.warn('[FIRESTORE-WARNING] Firebase Admin not initialized. Skipping Firestore sync.');
    }
  } catch (err) {
    console.error(`[FIRESTORE-ERROR] Failed to sync trip ${tripId}:`, err.message);
  }
};

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

// 1. Start Trip Tracking
// POST /api/tracking/start
router.post('/start', checkDB, authenticateToken, requireRole(['Driver', 'Admin']), async (req, res) => {
  console.log('--- Start Trip Tracking Request ---');
  try {
    const { loadId, driverId, latitude, longitude, ownerId } = req.body;

    if (!loadId || !driverId || latitude === undefined || longitude === undefined) {
      return res.status(400).json({ success: false, message: 'Missing required fields' });
    }

    // Role check: Driver can only start tracking for themselves
    if (req.user.role !== 'Admin' && driverId !== req.user.id) {
      return res.status(403).json({ success: false, message: 'Forbidden. Cannot start tracking for another driver.' });
    }

    // Verify driver is assigned to the load
    const Load = require('../models/Load');
    const load = await Load.findById(loadId);
    if (!load) {
      return res.status(404).json({ success: false, message: 'Load not found' });
    }
    if (req.user.role !== 'Admin' && load.driverId !== req.user.id) {
      return res.status(403).json({ success: false, message: 'Forbidden. You are not the driver assigned to this load.' });
    }

    // Try to fetch ownerId dynamically if not supplied in the request body
    let finalOwnerId = ownerId || load.userId;

    // Upsert tracking details: create or update existing trip record for this load in MongoDB
    const tracking = await Tracking.findOneAndUpdate(
      { loadId },
      {
        driverId,
        latitude: Number(latitude),
        longitude: Number(longitude),
        heading: 0,
        speed: 0,
        timestamp: new Date(),
        tripStatus: 'active'
      },
      { new: true, upsert: true }
    );

    // Sync to Firestore activeTrips collection
    await updateFirestoreTrip(loadId, {
      tripId: loadId,
      driverId,
      ownerId: finalOwnerId || '',
      latitude,
      longitude,
      heading: 0,
      speed: 0,
      status: 'started',
      startedAt: new Date(),
      lastUpdated: new Date()
    });

    console.log(`✅ Tracking started for Load ${loadId}`);
    res.status(200).json({ success: true, tracking });
  } catch (err) {
    console.error('Start Tracking Error:', err);
    res.status(500).json({ success: false, message: 'Failed to start tracking', error: err.message });
  }
});

// 2. Update Live Location
// POST /api/tracking/update
router.post('/update', checkDB, authenticateToken, requireRole(['Driver', 'Admin']), async (req, res) => {
  try {
    const { loadId, latitude, longitude, heading, speed, timestamp } = req.body;

    if (!loadId || latitude === undefined || longitude === undefined) {
      return res.status(400).json({ success: false, message: 'Missing required fields' });
    }

    // Check if the trip is currently active before updating coordinates in MongoDB
    const tracking = await Tracking.findOne({ loadId });
    if (!tracking) {
      return res.status(404).json({ success: false, message: 'No tracking session found for this load' });
    }

    if (tracking.tripStatus !== 'active') {
      return res.status(400).json({ success: false, message: 'Cannot update location for an inactive trip' });
    }

    // Role check: Ensure the caller is the driver assigned to the tracking session
    if (req.user.role !== 'Admin' && tracking.driverId !== req.user.id) {
      return res.status(403).json({ success: false, message: 'Forbidden. You are not the driver assigned to this trip.' });
    }

    tracking.latitude = Number(latitude);
    tracking.longitude = Number(longitude);
    if (heading !== undefined) tracking.heading = Number(heading);
    if (speed !== undefined) tracking.speed = Number(speed);
    tracking.timestamp = timestamp ? new Date(timestamp) : new Date();
    await tracking.save();

    // Sync to Firestore
    await updateFirestoreTrip(loadId, {
      latitude,
      longitude,
      heading: heading !== undefined ? Number(heading) : 0,
      speed: speed !== undefined ? Number(speed) : 0,
      status: 'moving',
      lastUpdated: timestamp ? new Date(timestamp) : new Date()
    });

    res.status(200).json({ success: true, tracking });
  } catch (err) {
    console.error('Update Location Error:', err);
    res.status(500).json({ success: false, message: 'Failed to update location', error: err.message });
  }
});

// 3. Stop Trip Tracking
// POST /api/tracking/stop
router.post('/stop', checkDB, authenticateToken, requireRole(['Driver', 'Admin']), async (req, res) => {
  console.log('--- Stop Trip Tracking Request ---');
  try {
    const { loadId } = req.body;

    if (!loadId) {
      return res.status(400).json({ success: false, message: 'Missing loadId' });
    }

    const tracking = await Tracking.findOne({ loadId });
    if (!tracking) {
      return res.status(404).json({ success: false, message: 'No tracking session found' });
    }

    // Role check: Ensure the caller is the driver assigned to this tracking session
    if (req.user.role !== 'Admin' && tracking.driverId !== req.user.id) {
      return res.status(403).json({ success: false, message: 'Forbidden. You are not the driver assigned to this trip.' });
    }

    tracking.tripStatus = 'stopped';
    tracking.timestamp = new Date();
    await tracking.save();

    // Sync status to Firestore
    await updateFirestoreTrip(loadId, {
      status: 'completed',
      lastUpdated: new Date()
    });

    console.log(`✅ Tracking stopped for Load ${loadId}`);
    res.status(200).json({ success: true, tracking });
  } catch (err) {
    console.error('Stop Tracking Error:', err);
    res.status(500).json({ success: false, message: 'Failed to stop tracking', error: err.message });
  }
});

// 3.5. Get All Active Trips (For Admin Fleet Monitor Map)
// GET /api/tracking/active/all
router.get('/active/all', checkDB, authenticateToken, requireRole(['Admin']), async (req, res) => {
  try {
    const Load = require('../models/Load');
    const [loads, trackings] = await Promise.all([
      Load.find({ status: 'accepted' }),
      Tracking.find({ tripStatus: 'active' })
    ]);
    
    // Create a map of tracking records by loadId
    const trackingMap = {};
    trackings.forEach(t => {
      trackingMap[t.loadId] = t;
    });
    
    // Combine them
    const activeTrips = loads.map(load => {
      const tracking = trackingMap[load._id.toString()];
      return {
        load,
        tracking: tracking || null
      };
    });
    
    res.status(200).json({ success: true, trips: activeTrips });
  } catch (err) {
    console.error('Fetch Active Trips Error:', err);
    res.status(500).json({ success: false, message: 'Failed to retrieve active trips', error: err.message });
  }
});

// 4. Get Live Location
// GET /api/tracking/:loadId
router.get('/:loadId', checkDB, authenticateToken, requireRole(['Driver', 'Load Owner', 'Admin']), async (req, res) => {
  try {
    const tracking = await Tracking.findOne({ loadId: req.params.loadId });
    if (!tracking) {
      return res.status(404).json({ success: false, message: 'No live tracking data available' });
    }

    // Check permissions: Owner of load or assigned Driver can view
    if (req.user.role !== 'Admin') {
      const Load = require('../models/Load');
      const load = await Load.findById(req.params.loadId);
      if (!load) {
        return res.status(404).json({ success: false, message: 'Load not found' });
      }
      if (req.user.role === 'Driver' && load.driverId !== req.user.id) {
        return res.status(403).json({ success: false, message: 'Forbidden. You are not the driver assigned to this load.' });
      }
      if (req.user.role === 'Load Owner' && load.userId !== req.user.id) {
        return res.status(403).json({ success: false, message: 'Forbidden. You do not own this load.' });
      }
    }

    res.status(200).json({ success: true, tracking });
  } catch (err) {
    console.error('Get Location Error:', err);
    res.status(500).json({ success: false, message: 'Failed to retrieve location' });
  }
});

module.exports = router;
