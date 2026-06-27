const mongoose = require('mongoose');
const MONGODB_URI = 'mongodb+srv://transifyadmin:Transify2005@transifycluster.2v5gsdn.mongodb.net/transify?retryWrites=true&w=majority&appName=TransifyCluster&authSource=admin';

const Tracking = require('./models/Tracking');
const Load = require('./models/Load');

async function run() {
  try {
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB successfully.');

    // Count records
    const trackingCount = await Tracking.countDocuments();
    const loadCount = await Load.countDocuments();
    console.log(`Tracking records count: ${trackingCount}`);
    console.log(`Load records count: ${loadCount}`);

    // Check active tracking sessions
    const activeTracking = await Tracking.find({ tripStatus: 'active' });
    console.log('\n--- Active Tracking Sessions ---');
    activeTracking.forEach(t => {
      console.log({
        id: t._id,
        loadId: t.loadId,
        driverId: t.driverId,
        latitude: t.latitude,
        longitude: t.longitude,
        timestamp: t.timestamp,
        tripStatus: t.tripStatus
      });
    });

    // Check recent accepted loads
    const acceptedLoads = await Load.find({ status: 'accepted' }).limit(5);
    console.log('\n--- Recent Accepted Loads ---');
    acceptedLoads.forEach(l => {
      console.log({
        id: l._id,
        status: l.status,
        driverId: l.driverId,
        driverName: l.driverName,
        from: l.fromLocation,
        to: l.toLocation
      });
    });

  } catch (err) {
    console.error('❌ Error running check:', err);
  } finally {
    await mongoose.disconnect();
    console.log('Disconnected from DB.');
  }
}

run();
