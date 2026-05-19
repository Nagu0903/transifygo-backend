const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
require('dotenv').config();

const authRoutes = require('./routes/auth');
const { router: notificationRoutes } = require('./routes/notifications'); // Import notifications first
const loadRoutes = require('./routes/loads');
const adminRoutes = require('./routes/admin');

const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/loads', loadRoutes);
app.use('/api/load', loadRoutes); 
app.use('/api/admin', adminRoutes);
app.use('/api/notifications', notificationRoutes);

// Root endpoint for health check
app.get('/', (req, res) => {
  res.send('Transify Backend is Running');
});

// Test Database Connection
app.get('/api/test-db', async (req, res) => {
  try {
    const state = mongoose.connection.readyState;
    const states = ['Disconnected', 'Connected', 'Connecting', 'Disconnecting'];
    res.json({ 
      success: true, 
      status: states[state],
      database: mongoose.connection.name 
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// MongoDB Connection
const MONGODB_URI = process.env.MONGODB_URI;

mongoose.connect(MONGODB_URI, {
  serverSelectionTimeoutMS: 5000, // Fail fast if no connection
  socketTimeoutMS: 45000, // Close sockets after 45 seconds of inactivity
  maxPoolSize: 50, // Maintain up to 50 socket connections
  family: 4, // Use IPv4, skip trying IPv6
})
  .then(() => {
    // The exact string requested by the user
    console.log('MongoDB Connected Successfully');
  })
  .catch(err => {
    console.error('MongoDB Connection Failed:', err.message);
  });

// Auto-reconnect and error handling
mongoose.connection.on('error', (err) => {
  console.error('MongoDB Runtime Error:', err.message);
});

mongoose.connection.on('disconnected', () => {
  console.warn('MongoDB Disconnected! Mongoose will automatically attempt to reconnect.');
});


// Error handling middleware
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ 
    success: false, 
    message: 'Internal Server Error',
    error: err.message 
  });
});

const PORT = process.env.PORT || 5000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server Running on port ${PORT}`);
});
