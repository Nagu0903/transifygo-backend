const mongoose = require('mongoose');

const assignmentSchema = new mongoose.Schema({
  loadId: { type: String, required: true },
  driverId: { type: String, required: true },
  driverName: { type: String },
  driverPhone: { type: String },
  assignedAt: { type: Date, default: Date.now },
  status: { type: String, default: 'active' }
});

const collectionName = process.env.IS_TESTING === 'true' ? 'assignments_test' : 'assignments';
module.exports = mongoose.model('Assignment', assignmentSchema, collectionName);
