import { initializeApp, getApps, getApp } from 'firebase/app';
import {
  getAuth,
  signInWithEmailAndPassword,
  createUserWithEmailAndPassword,
  signInWithPopup,
  GoogleAuthProvider,
  signOut,
  onAuthStateChanged,
  type User,
} from 'firebase/auth';
import {
  getFirestore,
  collection,
  doc,
  setDoc,
  deleteDoc,
  query,
  where,
  onSnapshot,
  type Unsubscribe,
} from 'firebase/firestore';
import type { Asset } from '../types';

const resolveAuthDomain = () => {
  if (typeof window !== 'undefined' && window.location.host) {
    const host = window.location.host;
    if (host.includes('3d-craft.web.app') || host.includes('3d-craft.firebaseapp.com')) {
      return host;
    }
  }
  return '3d-craft.firebaseapp.com';
};

export const firebaseConfig = {
  projectId: 'forma-studio-2026',
  appId: '1:869655507524:web:c35740f3460a4923524211',
  storageBucket: 'forma-studio-2026.firebasestorage.app',
  apiKey: 'AIzaSyCKjbzHGU6N4X16ZRkmm2otkkL27MeNQYI',
  authDomain: resolveAuthDomain(),
  messagingSenderId: '869655507524',
};

// Initialize or reuse existing app instance
export const app = getApps().length > 0 ? getApp() : initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);

/* ------------------------------------------------------------------ Auth APIs */

export async function ensureAuthUser(): Promise<User> {
  if (auth.currentUser && !auth.currentUser.isAnonymous) {
    return auth.currentUser;
  }
  throw new Error("Sign in to your 3D Craft account to continue.");
}

export async function loginWithEmail(email: string, pass: string): Promise<User> {
  const cred = await signInWithEmailAndPassword(auth, email, pass);
  return cred.user;
}

export async function registerWithEmail(email: string, pass: string): Promise<User> {
  const cred = await createUserWithEmailAndPassword(auth, email, pass);
  return cred.user;
}

const googleProvider = new GoogleAuthProvider();
googleProvider.addScope('profile');
googleProvider.addScope('email');
googleProvider.setCustomParameters({
  prompt: 'select_account',
});

export async function loginWithGoogle(): Promise<User> {
  const cred = await signInWithPopup(auth, googleProvider);
  return cred.user;
}

export async function logoutUser(): Promise<void> {
  await signOut(auth);

}

export { onAuthStateChanged, type User };

/* ------------------------------------------------------------- Firestore Sync */

/**
 * Saves a user-generated asset to Firestore under the user's ownerId.
 */
export async function saveAssetToFirestore(asset: Asset, userId: string): Promise<void> {
  if (!userId) return;
  const assetRef = doc(db, 'assets', asset.id);

  // Strip undefined values which Firestore rejects
  const data: Record<string, any> = {
    id: asset.id,
    ownerId: userId,
    name: asset.name || 'Untitled Asset',
    prompt: asset.prompt || '',
    engine: asset.engine || 'trellis-2',
    createdAt: asset.createdAt || Date.now(),
    visibility: asset.visibility || 'public',
    liked: !!asset.liked,
    likes: asset.likes || 0,
    author: asset.author || 'you',
    local: !!asset.local,
  };

  if (asset.modelUrl) data.modelUrl = asset.modelUrl;
  if (asset.thumbUrl) data.thumbUrl = asset.thumbUrl;
  if (asset.seedShape) data.seedShape = asset.seedShape;
  if (asset.tint) data.tint = asset.tint;
  if (asset.faces !== undefined) data.faces = asset.faces;
  if (asset.vertices !== undefined) data.vertices = asset.vertices;
  if (asset.textureRes !== undefined) data.textureRes = asset.textureRes;
  if (asset.fileSizeMb !== undefined) data.fileSizeMb = asset.fileSizeMb;
  if (asset.runId) data.runId = asset.runId;
  if (asset.sourceRef) data.sourceRef = asset.sourceRef;
  if (asset.originRef) data.originRef = asset.originRef;
  if (asset.provider) data.provider = asset.provider;
  if (asset.note) data.note = asset.note;

  await setDoc(assetRef, data, { merge: true });
}

/**
 * Deletes a user asset from Firestore.
 */
export async function deleteAssetFromFirestore(assetId: string): Promise<void> {
  const assetRef = doc(db, 'assets', assetId);
  await deleteDoc(assetRef);
}

/**
 * Subscribes to real-time changes in the user's assets collection.
 */
export function subscribeToUserAssets(
  userId: string,
  onUpdate: (assets: Asset[]) => void,
): Unsubscribe {
  const q = query(
    collection(db, 'assets'),
    where('ownerId', '==', userId),
  );

  return onSnapshot(
    q,
    (snapshot) => {
      const list: Asset[] = [];
      snapshot.forEach((docSnap) => {
        const d = docSnap.data();
        list.push({
          id: d.id || docSnap.id,
          name: d.name || 'Untitled Asset',
          prompt: d.prompt || '',
          engine: d.engine || 'trellis-2',
          createdAt: d.createdAt || Date.now(),
          modelUrl: d.modelUrl,
          thumbUrl: d.thumbUrl,
          seedShape: d.seedShape,
          tint: d.tint,
          faces: d.faces ?? 0,
          vertices: d.vertices ?? 0,
          textureRes: d.textureRes ?? 0,
          fileSizeMb: d.fileSizeMb ?? 0,
          liked: !!d.liked,
          likes: d.likes ?? 0,
          author: d.author || 'you',
          visibility: d.visibility || 'public',
          local: !!d.local,
          runId: d.runId,
          sourceRef: d.sourceRef,
          originRef: d.originRef,
          provider: d.provider,
          note: d.note,
        } as Asset);
      });

      // Sort newest first
      list.sort((a, b) => b.createdAt - a.createdAt);
      onUpdate(list);
    },
    (err) => {
      console.error('Firestore subscription error:', err);
    },
  );
}
