const axios = require('axios');

async function test() {
  console.log('Pinging production Render backend...');
  try {
    const resDb = await axios.get('https://transifygo-backend.onrender.com/api/test-db');
    console.log('test-db status:', resDb.status, resDb.data);
  } catch (err) {
    console.error('test-db error:', err.message, err.response ? err.response.data : '');
  }

  try {
    console.log('Sending start trip to production tracking/start...');
    const resStart = await axios.post('https://transifygo-backend.onrender.com/api/tracking/start', {
      loadId: '6a12f89685c0adb0c8a38225',
      driverId: '6a0d36536e6872cc8ccc0bf8',
      latitude: 12.9716,
      longitude: 77.5946
    });
    console.log('tracking/start status:', resStart.status, resStart.data);
  } catch (err) {
    console.error('tracking/start error:', err.message, err.response ? err.response.data : '');
  }
}

test();
