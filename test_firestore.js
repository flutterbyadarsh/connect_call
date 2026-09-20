const admin = require('firebase-admin');
const serviceAccount = require('./functions/connect-call-ed891-firebase-adminsdk-r709r-c9fc380b2d.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

async function run() {
  const users = await admin.firestore().collection('users').get();
  console.log('Total users:', users.size);
  users.forEach(doc => {
    console.log(doc.id, '=>', doc.data());
  });
  process.exit(0);
}
run();
