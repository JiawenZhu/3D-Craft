import { Component, Suspense, lazy, useEffect, useRef, useState, type ReactNode } from 'react';
import { getBlob, getStorage, ref as storageRef } from 'firebase/storage';
import { auth, app } from '../../lib/firebase';
import { Box, Download, Minus, Plus, RotateCcw, X } from 'lucide-react';
import { CreationImage } from './CreationImage';
import type { Creation } from '../../lib/creationLibrary';
import type { Asset, StudioLight, ViewportShading } from '../../types';
import type { ViewportHandle } from '../workbench/Viewport';
const Viewport = lazy(() => import('../workbench/Viewport').then(m => ({ default: m.Viewport })));

class ViewerError extends Component<{children: ReactNode}, {failed: boolean}> {
  state = {failed:false};
  static getDerivedStateFromError() { return {failed:true}; }
  render() { return this.state.failed ? <div className="model-status" role="alert">This model couldn’t open. Close and retry, or download the GLB file.</div> : this.props.children; }
}

export default function CreationDetail({ item, onClose }: {item: Creation; onClose:()=>void}) {
  const [model, setModel] = useState('');
  const [error, setError] = useState('');
  const [selected, setSelected] = useState(item.hasModel ? 'model' : item.id);
  const [shading, setShading] = useState<ViewportShading>('material');
  const [rotate, setRotate] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const [light, setLight] = useState<StudioLight>('studio');
  const [lighting, setLighting] = useState({directional:1, environment:1, exposure:1});
  const view = useRef<ViewportHandle>(null);
  const dialog = useRef<HTMLDivElement>(null);
  const concepts = item.concepts?.length ? item.concepts : !item.hasModel && (item.preview || item.previewStoragePath) ? [{...item,hasModel:false}] : [];
  const picture = concepts.find(c => c.id === selected) || item;
  useEffect(() => {
    const before = document.activeElement as HTMLElement | null;
    const overflow = document.body.style.overflow; document.body.style.overflow = 'hidden';
    dialog.current?.focus();
    const keyboard = (event: KeyboardEvent) => {
      if(event.key === 'Escape') onClose();
      if(event.key === 'Tab') {
        const nodes = dialog.current?.querySelectorAll<HTMLElement>('button:not(:disabled),a[href],input:not(:disabled),select:not(:disabled),summary,[tabindex="0"]');
        if (!nodes?.length) return;
        const first = nodes[0], last = nodes[nodes.length-1];
        if (event.shiftKey && (document.activeElement === first || document.activeElement === dialog.current)) {event.preventDefault();last.focus();}
        else if (!event.shiftKey && document.activeElement === last) {event.preventDefault();first.focus();}
      }
    };
    window.addEventListener('keydown',keyboard);
    return () => { document.body.style.overflow=overflow; window.removeEventListener('keydown',keyboard); before?.focus(); };
  }, []);
  useEffect(() => {
    let active = true, blobUrl = '';
    let deadline: ReturnType<typeof setTimeout> | undefined;
    setModel('');setError('');
    const load = async () => {
      if (item.modelStoragePath) {
        const uid = auth.currentUser?.uid;
        if (!uid || !new RegExp(`^users/${uid}/models/[a-f0-9]{64}\\.glb$`).test(item.modelStoragePath)) throw Error();
        const storage = getStorage(app);
        // Bound SDK retries as well as the overall token/download wait below.
        storage.maxOperationRetryTime = 20_000;
        const blob = await Promise.race([
          getBlob(storageRef(storage,item.modelStoragePath),100*1024*1024),
          new Promise<never>((_,reject) => { deadline=setTimeout(()=>reject(Error('timeout')),45_000); }),
        ]);
        clearTimeout(deadline);
        if (!active || uid !== auth.currentUser?.uid) return;
        blobUrl=URL.createObjectURL(blob);setModel(blobUrl);
      } else if(item.modelUrl) {
        if (active) setModel(new URL(item.modelUrl,location.origin).href);
      } else if(item.hasModel) {
        setError('The 3D file is still syncing from your app. Your concept images are available below.');
      }
    };
    void load().catch(() => { clearTimeout(deadline); if(active) setError('Your 3D model couldn’t load. Check your connection and try again.'); });
    return () => {active=false;clearTimeout(deadline);if(blobUrl) URL.revokeObjectURL(blobUrl);};
  }, [item.id,item.modelStoragePath,item.modelUrl,attempt]);
  const asset = {id:item.id,name:item.name,modelUrl:model} as Asset;
  return <div className="creation-detail-backdrop" onClick={onClose}>
    <div className="creation-detail" role="dialog" aria-modal="true" aria-label={item.name} ref={dialog} tabIndex={-1} onClick={e=>e.stopPropagation()}>
      <header><span><Box size={20}/> {item.hasModel ? 'Your 3D studio' : 'Your concepts'}</span><button onClick={onClose} aria-label="Close preview"><X/></button></header>
      <div className="detail-layout">
        <div className="detail-stage">
          {selected === 'model' && item.hasModel ? model ? <ViewerError key={model}><Suspense fallback={<div className="model-status">Opening 3D studio…</div>}>
            <Viewport ref={view} asset={asset} shading={shading} light={light} autoRotate={rotate} showGrid={false} showGizmo={false} trim={{exposure:.8*lighting.exposure,directional:.75*lighting.directional,environment:.85*lighting.environment}} background="#e8f2ee"/>
          </Suspense></ViewerError> : <div className="model-status" role="status">{error || 'Loading your 3D model…'}{error && item.modelStoragePath && <button className="detail-model-select" onClick={()=>setAttempt(n=>n+1)}>Try again</button>}</div> : (picture.preview || picture.previewStoragePath) ? <CreationImage item={picture} alt={item.name}/> : <div className="model-status">No concept preview available.</div>}
          {selected === 'model' && model && <div className="detail-camera"><button aria-label="Zoom in" onClick={()=>view.current?.zoom(.8)}><Plus/></button><button aria-label="Zoom out" onClick={()=>view.current?.zoom(1.25)}><Minus/></button><button aria-label="Reset view" onClick={()=>view.current?.fit()}><RotateCcw/></button></div>}
          <span className="detail-hint">{selected === 'model' ? 'Drag to rotate · Scroll or pinch to zoom' : 'Concept image'}</span>
        </div>
        <aside className="detail-info">
          <span className="showcase-eyebrow">{item.projectId ? 'MADE BY YOU' : '3D CRAFT COLLECTION'}</span>
          <h2>{item.name}</h2>
          <p>{item.hasModel ? (concepts.length ? `${concepts.length} concept${concepts.length===1?'':'s'} → one 3D object` : 'Saved 3D object') : 'Your idea, taking shape.'}</p>
          <h3>{item.selectionKnown ? 'Selected concepts' : 'Related concepts'}</h3>
          {!concepts.length && <p>No linked concept images were saved with this older model.</p>}
          <div className="detail-concepts">{concepts.map((c,i)=><button key={c.id} aria-label={`View concept ${i+1}`} aria-pressed={selected===c.id} onClick={()=>setSelected(c.id)}>{(c.preview || c.previewStoragePath) && <CreationImage item={c} alt={`Concept ${i+1}`}/>}<span>{i+1}</span></button>)}</div>
          {item.hasModel && <button className="detail-model-select" aria-pressed={selected==='model'} onClick={()=>setSelected('model')}><Box size={18}/> View 3D object</button>}
          {item.prompt && <details><summary>Creation prompt</summary><p>{item.prompt}</p></details>}
          {selected==='model' && model && <><h3>Appearance</h3><div className="detail-options">{(['material','solid','wireframe'] as ViewportShading[]).map(mode=><button key={mode} aria-pressed={shading===mode} onClick={()=>setShading(mode)}>{mode==='wireframe'?'Wire':mode[0].toUpperCase()+mode.slice(1)}</button>)}</div><label className="detail-turntable"><input type="checkbox" checked={rotate} onChange={e=>setRotate(e.target.checked)}/> Auto rotate</label></>}
          {selected==='model' && model && <section className="detail-lighting" aria-label="Lighting studio">
            <div className="lighting-heading"><h3>Lighting studio</h3><button onClick={()=>{setLight('studio');setLighting({directional:1,environment:1,exposure:1});}}>Reset lighting</button></div>
            <div className="detail-options lighting-presets">{(['studio','rim','sunset','night','flat'] as StudioLight[]).map(preset=><button key={preset} aria-pressed={light===preset} onClick={()=>setLight(preset)}>{preset[0].toUpperCase()+preset.slice(1)}</button>)}</div>
            {([{key:'directional',label:'Key & rim light',min:0,max:2},{key:'environment',label:'Environment fill',min:0,max:2},{key:'exposure',label:'Exposure',min:.5,max:1.6}] as const).map(control=><label className="lighting-adjustment" key={control.key}>
              <span>{control.label}<output>{lighting[control.key].toFixed(2)}×</output></span>
              <input type="range" aria-label={control.label} min={control.min} max={control.max} step="0.05" value={lighting[control.key]} onChange={e=>setLighting(current=>({...current,[control.key]:Number(e.target.value)}))}/>
            </label>)}
          </section>}
          {model && <a className="download-model-btn" href={model} download={`${item.name.replace(/[^a-z0-9 -]/gi,'').slice(0,80)}.glb`}><Download size={17}/> Download 3D model</a>}
        </aside>
      </div>
    </div>
  </div>;
}
