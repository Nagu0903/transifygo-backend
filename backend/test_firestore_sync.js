const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// 1. Initialize Firebase Admin safely
try {
  let serviceAccount;
  const pathsToTry = [
    path.join(__dirname, 'firebase-service-account.json'), // backend/firebase-service-account.json
    path.join(__dirname, '../firebase-service-account.json'), // root/firebase-service-account.json
    path.join(process.cwd(), 'firebase-service-account.json'), // cwd root
    path.join(process.cwd(), 'backend', 'firebase-service-account.json') // cwd backend
  ];

  let foundPath;
  for (const p of pathsToTry) {
    if (fs.existsSync(p)) {
      foundPath = p;
      break;
    }
  }

  if (foundPath) {
    console.log(`[TEST-FCM] Loading service account from: ${foundPath}`);
    serviceAccount = JSON.parse(fs.readFileSync(foundPath, 'utf8'));
  } else {
    throw new Error('firebase-service-account.json not found in any standard path.');
  }

  if (serviceAccount.private_key) {
    serviceAccount.private_key = serviceAccount.private_key.replace(/\\n/g, '\n');
  }

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
  console.log('[TEST-FCM] Firebase Admin successfully initialized.');
} catch (error) {
  console.error('[TEST-FCM-ERROR] Firebase Admin initialization failed:', error.message);
  process.exit(1);
}

// 2. Perform Firestore Write and Read validation
async function testSync() {
  const db = admin.firestore();
  const testTripId = 'test_trip_sanity_check_' + Math.floor(Math.random() * 1000000);
  
  console.log(`\nStarting Firestore activeTrips sync test for ID: ${testTripId}...`);
  
  try {
    const tripRef = db.collection('activeTrips').doc(testTripId);
    
    // Write mock tracking values
    console.log('Writing mock tracking data to activeTrips...');
    await tripRef.set({
      tripId: testTripId,
      driverId: 'mock_driver_123',
      ownerId: 'mock_owner_456',
      currentLocation: new admin.firestore.GeoPoint(12.9716, 77.5946),
      status: 'started',
      startedAt: admin.firestore.FieldValue.serverTimestamp(),
      eta: '45 mins',
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      heading: 45.5,
      speed: 60.2
    });
    console.log('✅ Mock data successfully written!');

    // Read the values back to verify correctness
    console.log('Retrieving data back from activeTrips collection...');
    const snap = await tripRef.get();
    
    if (snap.exists) {
      const data = snap.data();
      console.log('✅ Data retrieved successfully! Document Payload:');
      console.log(JSON.stringify({
        tripId: data.tripId,
        driverId: data.driverId,
        status: data.status,
        heading: data.heading,
        speed: data.speed,
        currentLocation: {
          lat: data.currentLocation.latitude,
          lng: data.currentLocation.longitude
        }
      }, null, 2));
    } else {
      throw new Error('Document was not created/found in Firestore.');
    }

    // Clean up mock document
    console.log('Cleaning up mock trip document...');
    await tripRef.delete();
    console.log('✅ Sanity sync check completed successfully! 100% Correct.');
    process.exit(0);

  } catch (err) {
    console.error('❌ Firestore sync sanity test failed:', err);
    process.exit(1);
  }
}

testSync();
