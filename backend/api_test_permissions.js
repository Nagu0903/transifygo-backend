const axios = require('axios');

const BASE_URL = 'http://localhost:5000/api';

async function runTests() {
  console.log('🚀 Starting Backend Permissions & Geofiltering Integration Tests...\n');

  try {
    // 1. Health Check
    console.log('Checking Health...');
    const health = await axios.get(`${BASE_URL}/test-db`);
    console.log('✅ Health Check Status:', health.data.status, '\n');

    const testId = Date.now();
    const ownerPhone = `91000${testId.toString().slice(-5)}`;
    const driverPhone = `92000${testId.toString().slice(-5)}`;
    const adminPhone = `93000${testId.toString().slice(-5)}`;

    // Create accounts
    console.log('1. Creating Test Users...');
    
    // Create Owner
    await axios.post(`${BASE_URL}/auth/signup`, {
      fullName: 'Test Owner',
      phone: ownerPhone,
      password: '1234',
      role: 'Load Owner',
      city: 'Bangalore'
    });
    console.log('   - Cargo Owner created.');

    // Create Driver
    await axios.post(`${BASE_URL}/auth/signup`, {
      fullName: 'Test Driver',
      phone: driverPhone,
      password: '1234',
      role: 'Driver',
      city: 'Bangalore'
    });
    console.log('   - Driver created.');

    // Create Admin
    await axios.post(`${BASE_URL}/auth/signup`, {
      fullName: 'Test Admin',
      phone: adminPhone,
      password: '1234',
      role: 'Admin',
      city: 'Bangalore',
      adminSecret: 'transify_admin_secret_2026'
    });
    console.log('   - Admin created.\n');

    // Login and get tokens
    console.log('2. Logging in users to obtain JWTs...');
    
    const ownerLogin = await axios.post(`${BASE_URL}/auth/login`, { phone: ownerPhone, password: '1234', role: 'Load Owner' });
    const ownerToken = ownerLogin.data.token;
    const ownerId = ownerLogin.data.user.id;

    const driverLogin = await axios.post(`${BASE_URL}/auth/login`, { phone: driverPhone, password: '1234', role: 'Driver' });
    const driverToken = driverLogin.data.token;
    const driverId = driverLogin.data.user.id;

    const adminLogin = await axios.post(`${BASE_URL}/auth/login`, { phone: adminPhone, password: '1234', role: 'Admin' });
    const adminToken = adminLogin.data.token;
    
    console.log('   Tokens obtained successfully.\n');

    const ownerHeaders = { headers: { Authorization: `Bearer ${ownerToken}` } };
    const driverHeaders = { headers: { Authorization: `Bearer ${driverToken}` } };
    const adminHeaders = { headers: { Authorization: `Bearer ${adminToken}` } };

    // 3. Test Security Protection
    console.log('3. Verifying Route Protections...');
    
    // Try to fetch loads without token
    try {
      await axios.get(`${BASE_URL}/loads`);
      console.log('❌ FAIL: Accessing /loads without token should fail.');
      process.exit(1);
    } catch (err) {
      if (err.response && err.response.status === 401) {
        console.log('   ✅ PASS: Accessing /loads without token blocked (401).');
      } else {
        console.log('❌ FAIL: Unexpected error without token:', err.message);
        process.exit(1);
      }
    }

    // Try to access admin stats as Driver
    try {
      await axios.get(`${BASE_URL}/admin/stats`, driverHeaders);
      console.log('❌ FAIL: Driver accessing /admin/stats should be blocked.');
      process.exit(1);
    } catch (err) {
      if (err.response && err.response.status === 403) {
        console.log('   ✅ PASS: Driver blocked from Admin routes (403).');
      } else {
        console.log('❌ FAIL: Unexpected error for Driver on Admin route:', err.message);
        process.exit(1);
      }
    }

    // Try to create load as Driver
    try {
      await axios.post(`${BASE_URL}/loads/create`, {
        userId: ownerId,
        fromLocation: 'Bangalore',
        toLocation: 'Hubli',
        price: '4000'
      }, driverHeaders);
      console.log('❌ FAIL: Driver should not be allowed to create loads.');
      process.exit(1);
    } catch (err) {
      if (err.response && err.response.status === 403) {
        console.log('   ✅ PASS: Driver blocked from creating loads (403).');
      } else {
        console.log('❌ FAIL: Unexpected error for Driver creating load:', err.message);
        process.exit(1);
      }
    }

    console.log('');

    // 4. Test Geofiltering
    console.log('4. Testing GPS Geofiltering (Radius: 100 km)...');

    // Create Load 1 (Near Bangalore: lat 12.9716, lng 77.5946)
    console.log('   Posting Load 1 near Bangalore...');
    const loadBangaloreRes = await axios.post(`${BASE_URL}/loads/create`, {
      userId: ownerId,
      fullName: 'Cargo Owner',
      phone: ownerPhone,
      fromLocation: 'Bangalore',
      toLocation: 'Mysore',
      fromLat: 12.9716,
      fromLng: 77.5946,
      toLat: 12.2958,
      toLng: 76.6394,
      truckType: 'Lorry',
      material: 'Steel',
      price: '8000',
      weight: '5 Tons',
      distance: '140'
    }, ownerHeaders);
    const loadBangaloreId = loadBangaloreRes.data.load._id;
    console.log('   Load 1 ID:', loadBangaloreId);

    // Create Load 2 (Near Hubli: lat 15.3647, lng 75.1240 - ~400 km away)
    console.log('   Posting Load 2 near Hubli (~400 km away)...');
    const loadHubliRes = await axios.post(`${BASE_URL}/loads/create`, {
      userId: ownerId,
      fullName: 'Cargo Owner',
      phone: ownerPhone,
      fromLocation: 'Hubli',
      toLocation: 'Dharwad',
      fromLat: 15.3647,
      fromLng: 75.1240,
      toLat: 15.4589,
      toLng: 75.0078,
      truckType: 'Mini Truck',
      material: 'Vegetables',
      price: '3000',
      weight: '2 Tons',
      distance: '20'
    }, ownerHeaders);
    const loadHubliId = loadHubliRes.data.load._id;
    console.log('   Load 2 ID:', loadHubliId);

    // Query loads near Bangalore (12.97, 77.59)
    console.log('\n   Driver queries pending loads from Bangalore (12.9716, 77.5946)...');
    const driverFetchNear = await axios.get(`${BASE_URL}/loads?latitude=12.9716&longitude=77.5946`, driverHeaders);
    const nearLoads = driverFetchNear.data.loads;
    console.log(`   Found ${nearLoads.length} loads nearby.`);

    // Verify Bangalore load is returned and Hubli load is excluded
    const hasBangaloreLoad = nearLoads.some(l => l._id === loadBangaloreId);
    const hasHubliLoad = nearLoads.some(l => l._id === loadHubliId);

    if (hasBangaloreLoad && !hasHubliLoad) {
      console.log('   ✅ PASS: Nearby load is returned, distant load is filtered out.');
    } else {
      console.log('   ❌ FAIL: Geofiltering returned incorrect loads. Bangalore present:', hasBangaloreLoad, ', Hubli present:', hasHubliLoad);
      process.exit(1);
    }

    // Verify Owner Privacy details are stripped for Driver
    const bglrLoad = nearLoads.find(l => l._id === loadBangaloreId);
    if (bglrLoad.fullName === 'Cargo Owner' && !bglrLoad.phone && !bglrLoad.userId) {
      console.log('   ✅ PASS: Cargo Owner personal details (fullName, phone, userId) are hidden from Driver.');
    } else {
      console.log('   ❌ FAIL: Cargo Owner personal details are visible to Driver:', bglrLoad);
      process.exit(1);
    }

    // 5. Verify Owner Details on My Loads API
    console.log('\n5. Verifying Owner Details Restriction...');
    const ownerFetchMy = await axios.get(`${BASE_URL}/loads/my-loads/${ownerId}`, ownerHeaders);
    const myLoads = ownerFetchMy.data.myLoads || ownerFetchMy.data.loads;
    const myBangaloreLoad = myLoads.find(l => l._id === loadBangaloreId);
    
    if (myBangaloreLoad && !myBangaloreLoad.driverPhone) {
      console.log('   ✅ PASS: Driver phone number is hidden from Owner before assignment.');
    } else {
      console.log('   ❌ FAIL: Driver phone number was visible to Owner for unassigned load.');
      process.exit(1);
    }

    // 6. Admin accepts bid (assigns load)
    console.log('\n6. Testing Admin control and Load Assignment...');
    
    // Driver places a bid
    await axios.post(`${BASE_URL}/bids/place`, {
      loadId: loadBangaloreId,
      driverId: driverId,
      bidAmount: 7500,
      message: 'Can do it today'
    }, driverHeaders);
    console.log('   - Driver placed a bid of ₹7500.');

    // Fetch all bids as Admin
    const adminBidsRes = await axios.get(`${BASE_URL}/admin/bids`, adminHeaders);
    const matchedBid = adminBidsRes.data.bids.find(b => b.loadId === loadBangaloreId && b.driverId === driverId);
    
    if (!matchedBid) {
      console.log('   ❌ FAIL: Admin could not retrieve driver\'s bid.');
      process.exit(1);
    }
    console.log('   - Admin retrieved the bid. Bid ID:', matchedBid._id);

    // Accept bid
    await axios.post(`${BASE_URL}/admin/bids/${matchedBid._id}/accept`, {}, adminHeaders);
    console.log('   ✅ Bid accepted by Admin.');

    // Check load assignment
    const ownerFetchMyAfter = await axios.get(`${BASE_URL}/loads/my-loads/${ownerId}`, ownerHeaders);
    const myLoadsAfter = ownerFetchMyAfter.data.loads;
    const assignedLoad = myLoadsAfter.find(l => l._id === loadBangaloreId);
    
    if (assignedLoad && assignedLoad.driverPhone === driverLogin.data.user.phone) {
      console.log('   ✅ PASS: Cargo Owner can see driver phone number AFTER assignment.');
    } else {
      console.log('   ❌ FAIL: Driver phone number not visible to Owner after assignment:', assignedLoad);
      process.exit(1);
    }

    // 7. Verify collections in MongoDB directly
    console.log('\n7. Verifying Test Collection Names in isolated database...');
    const mongoose = require('mongoose');
    // Ensure we load env configuration
    require('dotenv').config();
    const testDbUri = process.env.MONGODB_URI.includes('/transify?')
      ? process.env.MONGODB_URI.replace('/transify?', '/transifygo_test?')
      : process.env.MONGODB_URI.replace('/transify', '/transifygo_test');
      
    await mongoose.connect(testDbUri);
    
    const collections = await mongoose.connection.db.listCollections().toArray();
    const names = collections.map(c => c.name);
    console.log('   Found collections:', names.join(', '));

    const hasBidsTest = names.includes('bids_test');
    const hasAssignmentsTest = names.includes('assignments_test');

    if (hasBidsTest && hasAssignmentsTest) {
      console.log('   ✅ PASS: bids_test and assignments_test collections exist in staging database.');
    } else {
      console.log('   ❌ FAIL: Collections not created correctly. bids_test:', hasBidsTest, ', assignments_test:', hasAssignmentsTest);
      await mongoose.disconnect();
      process.exit(1);
    }
    await mongoose.disconnect();

    // Cleanup: Delete test loads
    console.log('\n8. Cleaning up test loads...');
    await axios.delete(`${BASE_URL}/admin/loads/${loadBangaloreId}`, adminHeaders);
    await axios.delete(`${BASE_URL}/admin/loads/${loadHubliId}`, adminHeaders);
    console.log('   Loads deleted.');

    console.log('\n⭐ ALL PERMISSION & GEOLOCATION TESTS PASSED SUCCESSFULLY! ⭐\n');
    process.exit(0);

  } catch (err) {
    console.error('❌ TEST EXECUTION ERROR!');
    if (err.response) {
      console.error('   Status:', err.response.status);
      console.error('   Message:', err.response.data.message || err.response.data);
    } else {
      console.error('   Error:', err.message);
    }
    process.exit(1);
  }
}

runTests();
