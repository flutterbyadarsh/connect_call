const PROJECT_ID = 'connect-call-ed891';
const API_KEY = 'AIzaSyAj87c_Rp0AA1Z_8yCZhwn_kRnfosfHZhE';

async function run() {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/users?key=${API_KEY}`;
  
  const res = await fetch(url);
  const data = await res.json();
  
  if (!data.documents) {
    console.log('No documents found.');
    return;
  }
  
  let count = 0;
  for (const doc of data.documents) {
    const fields = doc.fields || {};
    if (fields.profileImageUrl && fields.profileImageUrl.stringValue && fields.profileImageUrl.stringValue.startsWith('data:image')) {
      const docPath = doc.name.split('/').slice(-1)[0];
      console.log(`Clearing base64 image for user: ${docPath}`);
      
      const patchUrl = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/users/${docPath}?updateMask.fieldPaths=profileImageUrl&key=${API_KEY}`;
      
      const patchRes = await fetch(patchUrl, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          fields: {
            profileImageUrl: { stringValue: '' }
          }
        })
      });
      
      if (patchRes.ok) {
        console.log(`Successfully cleared ${docPath}`);
        count++;
      } else {
        console.error(`Failed to clear ${docPath}:`, await patchRes.text());
      }
    }
  }
  
  console.log(`Cleared ${count} base64 images from Firestore via REST.`);
}

run().catch(console.error);
