const admin = require('firebase-admin');
admin.initializeApp();

async function resetBusy() {
  const db = admin.firestore();
  const usersSnapshot = await db.collection('users').get();
  
  const batch = db.batch();
  let count = 0;
  
  usersSnapshot.forEach(doc => {
    batch.update(doc.ref, { isBusy: false });
    count++;
  });
  
  await batch.commit();
  console.log(`Reset isBusy to false for ${count} users.`);
}

resetBusy().catch(console.error);
