const mongoose = require('mongoose');

const bidSchema = new mongoose.Schema({
  loadId: { type: String, required: true },
  driverId: { type: String, required: true },
  bidAmount: { type: Number, required: true },
  message: { type: String, default: '' },
  status: { 
    type: String, 
    enum: ['Pending', 'Accepted', 'Rejected'], 
    default: 'Pending' 
  },
  createdAt: { type: Date, default: Date.now }
});

const collectionName = process.env.IS_TESTING === 'true' ? 'bids_test' : 'bids';
module.exports = mongoose.model('Bid', bidSchema, collectionName);
