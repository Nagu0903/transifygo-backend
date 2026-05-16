const mongoose = require('mongoose');

const loadSchema = new mongoose.Schema({
  userId: { type: String, required: true }, // Owner who posted the load
  fullName: { type: String, required: true },
  phone: { type: String, required: true },
  fromLocation: { type: String, required: true },
  fromDistrict: { type: String },
  fromState: { type: String },
  fromLat: { type: Number },
  fromLng: { type: Number },
  toLocation: { type: String, required: true },
  toDistrict: { type: String },
  toState: { type: String },
  toLat: { type: Number },
  toLng: { type: Number },
  truckType: { type: String, required: true },
  material: { type: String, required: true },
  price: { type: String, required: true },
  weight: { type: String }, // Optional extra
  notes: { type: String },
  distance: { type: String },
  status: { 
    type: String, 
    enum: ['pending', 'accepted', 'completed', 'cancelled'], 
    default: 'pending' 
  },
  driverId: { type: String }, // ID of driver who accepted
  driverName: { type: String },
  driverPhone: { type: String },
  isActive: { type: Boolean, default: true },
  visibleToDrivers: { type: Boolean, default: true },
  cancelledBy: { type: String }, // 'owner', 'driver', 'admin'
  cancelledAt: { type: Date },
  createdAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('Load', loadSchema);
