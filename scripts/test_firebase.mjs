import { initializeApp } from 'firebase/app';
import { getAuth, signInAnonymously, createUserWithEmailAndPassword, signInWithEmailAndPassword, deleteUser } from 'firebase/auth';
import { getFirestore, doc, setDoc, getDoc, deleteDoc, collection, query, where, getDocs } from 'firebase/firestore';

const firebaseConfig = {
  projectId: "forma-studio-2026",
  appId: "1:869655507524:web:c35740f3460a4923524211",
  storageBucket: "forma-studio-2026.firebasestorage.app",
  apiKey: "AIzaSyCKjbzHGU6N4X16ZRkmm2otkkL27MeNQYI",
  authDomain: "forma-studio-2026.firebaseapp.com",
  messagingSenderId: "869655507524"
};

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);

async function main() {
  console.log('Testing Firebase Auth & Firestore on forma-studio-2026...');
  
  // 1. Test Anonymous Sign-in
  console.log('1. Signing in anonymously...');
  const anonCred = await signInAnonymously(auth);
  const uid = anonCred.user.uid;
  console.log('✔ Anonymous sign in successful, UID:', uid);

  // 2. Test Firestore Write
  const testAssetId = `test-asset-${Date.now()}`;
  const assetRef = doc(db, 'assets', testAssetId);
  const testAsset = {
    id: testAssetId,
    ownerId: uid,
    name: 'Forma Test Model',
    prompt: 'A sleek futuristic crystal sculpture',
    engine: 'trellis-2',
    modelUrl: '/models/test.glb',
    thumbUrl: '/models/test.png',
    faces: 12000,
    visibility: 'public',
    createdAt: Date.now()
  };

  console.log(`2. Writing test asset to assets/${testAssetId}...`);
  await setDoc(assetRef, testAsset);
  console.log('✔ Asset written to Firestore successfully');

  // 3. Test Firestore Read & Query
  console.log('3. Reading back asset...');
  const snap = await getDoc(assetRef);
  if (!snap.exists() || snap.data().name !== testAsset.name) {
    throw new Error('Read verification failed!');
  }
  console.log('✔ Document read verified:', snap.data().name);

  console.log(`4. Querying assets for ownerId == ${uid}...`);
  const q = query(collection(db, 'assets'), where('ownerId', '==', uid));
  const qSnap = await getDocs(q);
  console.log(`✔ Query returned ${qSnap.size} asset(s)`);

  // 5. Test Firestore Delete
  console.log(`5. Deleting test asset ${testAssetId}...`);
  await deleteDoc(assetRef);
  const afterDelete = await getDoc(assetRef);
  if (afterDelete.exists()) {
    throw new Error('Deletion failed!');
  }
  console.log('✔ Asset deleted from Firestore successfully');

  // 6. Test Email/Password Account Creation & Sign-in
  const testEmail = `forma_test_${Date.now()}@forma.ai`;
  const testPassword = 'TestPassword123!';
  console.log(`6. Testing Email/Password Auth with ${testEmail}...`);
  const emailCred = await createUserWithEmailAndPassword(auth, testEmail, testPassword);
  console.log('✔ User registered successfully with UID:', emailCred.user.uid);
  
  // Sign in with same email
  const loginCred = await signInWithEmailAndPassword(auth, testEmail, testPassword);
  console.log('✔ User signed in successfully with UID:', loginCred.user.uid);

  // Clean up user
  await deleteUser(loginCred.user);
  console.log('✔ Test user deleted cleanly');

  console.log('\n🎉 ALL FIREBASE TESTS PASSED SUCCESSFULLY!');
  process.exit(0);
}

main().catch((err) => {
  console.error('Firebase test failed:', err);
  process.exit(1);
});
