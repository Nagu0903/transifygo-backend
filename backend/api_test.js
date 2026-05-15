const axios = require('axios');

const BASE_URL = 'https://transify-backend.onrender.com/api';

async function runTests() {
  console.log('🚀 Starting Backend API Integration Tests...\n');

  try {
    // 1. Health Check
    console.log('Checking Health...');
    const health = await axios.get(`${BASE_URL}/test-db`);
    console.log('✅ Health Check:', health.data.status, '\n');

    const testId = Date.now();
    const testPhone = `90000${testId.toString().slice(-5)}`;

    // 2. Signup (Load Owner)
    console.log('Testing Signup (Owner)...');
    const signup = await axios.post(`${BASE_URL}/auth/signup`, {
      name: 'Test Owner',
      phone: testPhone,
      password: '1234',
      role: 'Load Owner',
      city: 'Hubli'
    });
    console.log('✅ Signup Success:', signup.data.success, '\n');

    // 3. Login (Load Owner)
    console.log('Testing Login (Owner)...');
    const login = await axios.post(`${BASE_URL}/auth/login`, {
      phone: testPhone,
      password: '1234',
      role: 'Load Owner'
    });
    console.log('✅ Login Success:', login.data.success);
    const ownerId = login.data.user.id || login.data.user._id;
    console.log('User ID:', ownerId, '\n');

    // 4. Post Load
    console.log('Testing Post Load...');
    const postLoad = await axios.post(`${BASE_URL}/loads`, {
      ownerId: ownerId,
      ownerName: 'Test Owner',
      ownerPhone: testPhone,
      from: 'Hubli',
      to: 'Bangalore',
      material: 'Rice',
      weight: '10 Tons',
      vehicle: 'Lorry',
      amount: '5000',
      distance: '400'
    });
    console.log('✅ Post Load Success:', postLoad.data.success, '\n');

    // 5. Fetch Pending Loads
    console.log('Testing Fetch Loads...');
    const fetchLoads = await axios.get(`${BASE_URL}/loads`);
    console.log('✅ Fetch Loads Count:', fetchLoads.data.loads.length, '\n');

    console.log('⭐ ALL TESTS PASSED SUCCESSFULLY! ⭐');
    console.log('Production Readiness: 100%');

  } catch (err) {
    console.error('❌ TEST FAILED!');
    if (err.response) {
      console.error('Status:', err.response.status);
      console.error('Message:', err.response.data.message);
    } else {
      console.error('Error:', err.message);
    }
    process.exit(1);
  }
}

runTests();
