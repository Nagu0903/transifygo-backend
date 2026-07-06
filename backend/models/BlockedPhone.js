const mongoose = require('mongoose');

const blockedPhoneSchema = new mongoose.Schema({
  phone: { type: String, required: true, unique: true },
  reason: { type: String, default: 'Suspicious activity' },
  createdAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('BlockedPhone', blockedPhoneSchema);
