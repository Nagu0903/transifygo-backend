const mongoose = require('mongoose');
const Load = require('./models/Load');
require('dotenv').config();

const cleanup = async () => {
  try {
    // 1. Connect to DB
    const MONGODB_URI = process.env.MONGODB_URI;
    if (!MONGODB_URI) throw new Error('MONGODB_URI not found in .env');
    await mongoose.connect(MONGODB_URI);
    console.log('--- Database Cleanup Started ---');

    // 2. Fix status flags for existing non-pending loads
    const result = await Load.updateMany(
      { status: { $in: ['cancelled', 'completed'] } },
      { $set: { isActive: false, visibleToDrivers: false } }
    );
    console.log(`✅ Updated ${result.modifiedCount} old cancelled/completed loads.`);

    // 3. Ensure all pending loads have the correct flags
    const resultPending = await Load.updateMany(
      { status: 'pending' },
      { $set: { isActive: true, visibleToDrivers: true } }
    );
    console.log(`✅ Updated ${resultPending.modifiedCount} pending loads visibility.`);

    // 4. Remove obvious duplicates (Same from/to/price/userId within 1 hour)
    // This is a simple heuristic cleanup
    console.log('--- Duplicate Check ---');
    const allPending = await Load.find({ status: 'pending' });
    let removedCount = 0;
    
    for (let i = 0; i < allPending.length; i++) {
        for (let j = i + 1; j < allPending.length; j++) {
            const a = allPending[i];
            const b = allPending[j];
            
            if (
                a.userId === b.userId &&
                a.fromLocation === b.fromLocation &&
                a.toLocation === b.toLocation &&
                a.price === b.price &&
                Math.abs(a.createdAt - b.createdAt) < 3600000 // 1 hour
            ) {
                await Load.findByIdAndDelete(b._id);
                removedCount++;
                allPending.splice(j, 1);
                j--;
            }
        }
    }
    console.log(`✅ Removed ${removedCount} duplicate pending loads.`);

    console.log('--- Cleanup Finished ---');
    process.exit(0);
  } catch (err) {
    console.error('Cleanup Error:', err);
    process.exit(1);
  }
};

cleanup();
