const mongoose = require('mongoose');
const MONGODB_URI = 'mongodb+srv://transifyadmin:Transify2005@transifycluster.2v5gsdn.mongodb.net/transify?retryWrites=true&w=majority&appName=TransifyCluster&authSource=admin';

const notificationSchema = new mongoose.Schema({
  userId: String,
  title: String,
  body: String,
  type: String,
  data: Object,
  isRead: Boolean,
  createdAt: Date
});

const Notification = mongoose.model('Notification', notificationSchema);

async function run() {
  try {
    await mongoose.connect(MONGODB_URI);
    console.log('Connected to DB');

    const counts = await Notification.aggregate([
      { $group: { _id: "$type", count: { $sum: 1 } } }
    ]);
    console.log('Notification types and counts:', counts);

    const latest = await Notification.find({}).sort({ createdAt: -1 }).limit(10);
    console.log('Latest 10 notifications:');
    latest.forEach(n => {
      console.log({
        id: n._id,
        userId: n.userId,
        title: n.title,
        type: n.type,
        data: n.data,
        createdAt: n.createdAt
      });
    });

  } catch (err) {
    console.error('Error running check:', err);
  } finally {
    await mongoose.disconnect();
  }
}

run();
