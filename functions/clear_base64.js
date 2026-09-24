const admin = require('firebase-admin');
const serviceAccount = require('./connect-call-ed891-firebase-adminsdk-r709r-c9fc380b2d.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

async function run() {
  const usersRef = admin.firestore().collection('users');
  const snapshot = await usersRef.get();
  let count = 0;
  
  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (data.profileImageUrl && data.profileImageUrl.startsWith('data:image')) {
      console.log(`Clearing huge base64 image for user: ${doc.id}`);
      await usersRef.doc(doc.id).update({
        profileImageUrl: ''
      });
      count++;
    }
  }
  
  console.log(`Cleared ${count} base64 images from Firestore.`);
  process.exit(0);
}

run().catch(console.error);
