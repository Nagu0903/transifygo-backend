const mongoose = require('mongoose');

const trackingSchema = new mongoose.Schema({
  loadId: { type: String, required: true, unique: true },
  driverId: { type: String, required: true },
  latitude: { type: Number, required: true },
  longitude: { type: Number, required: true },
  heading: { type: Number, default: 0 },
  speed: { type: Number, default: 0 },
  timestamp: { type: Date, default: Date.now },
  tripStatus: { type: String, enum: ['active', 'stopped'], default: 'active' }
});

module.exports = mongoose.model('Tracking', trackingSchema);

