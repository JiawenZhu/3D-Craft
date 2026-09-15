import { useEffect, useState } from 'react';
import { getBlob, getStorage, ref } from 'firebase/storage';
import { auth, app } from '../../lib/firebase';
import type { Creation } from '../../lib/creationLibrary';

/** Private Storage reads use Firebase Auth; object URLs live only with the view. */
export function CreationImage({item, alt, loading}: {item: Creation; alt: string; loading?: 'lazy' | 'eager'}) {
  const [source, setSource] = useState('');
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let active = true, objectURL = '';
    setSource(''); setFailed(false);
    const uid = auth.currentUser?.uid;
    if (!item.previewStoragePath) { setSource(item.preview || ''); return; }
    const prefix = uid ? `users/${uid}/previews/` : '';
    if (!prefix || !item.previewStoragePath.startsWith(prefix) || item.previewStoragePath.includes('..')) { setFailed(true); return; }
    void getBlob(ref(getStorage(app), item.previewStoragePath),20*1024*1024).then(blob => {
      if (!active || uid !== auth.currentUser?.uid) return;
      objectURL=URL.createObjectURL(blob); setSource(objectURL);
    }).catch(() => { if (active) setFailed(true); });
    return () => { active=false; if(objectURL) URL.revokeObjectURL(objectURL); };
  }, [item.id, item.previewStoragePath, item.preview]);
  return source ? <img src={source} alt={alt} loading={loading}/> : <span role="status">{failed ? 'Preview unavailable' : 'Loading preview…'}</span>;
}
