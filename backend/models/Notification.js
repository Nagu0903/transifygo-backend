const mongoose = require('mongoose');

const notificationSchema = new mongoose.Schema({
  userId: { type: String, required: true }, // Recipient
  title: { type: String, required: true },
  body: { type: String, required: true },
  type: { type: String, enum: ['new_load', 'load_accepted', 'load_cancelled', 'load_completed', 'admin_broadcast'], required: true },
  data: { type: Object }, // Extra info like loadId
  isRead: { type: Boolean, default: false },
  createdAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('Notification', notificationSchema);
