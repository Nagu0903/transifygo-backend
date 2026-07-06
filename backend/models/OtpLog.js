const mongoose = require('mongoose');

const otpLogSchema = new mongoose.Schema({
  phone: { type: String, required: true },
  action: { type: String, enum: ['SEND_OTP', 'VERIFY_SUCCESS', 'VERIFY_FAILED', 'BLOCKED'], required: true },
  ip: { type: String },
  userAgent: { type: String },
  details: { type: String },
  timestamp: { type: Date, default: Date.now }
});

module.exports = mongoose.model('OtpLog', otpLogSchema);
