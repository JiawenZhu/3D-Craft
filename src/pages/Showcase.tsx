import { lazy, Suspense, useEffect, useState } from 'react';
import { ArrowDown, ArrowUpRight, Box, LogOut, RefreshCw, Smartphone, Sparkles } from 'lucide-react';
import { auth, logoutUser, onAuthStateChanged, type User, db } from '../lib/firebase';
import { collection, onSnapshot } from 'firebase/firestore';
import { AuthModal } from '../components/auth/AuthModal';
import { API_ACCESS_PATH } from './apiAccessPath';
import { LegalFooter } from './LegalPages';
import publicCatalog from '../../public/gallery/catalog.json';
import { libraryGroups, type Creation } from '../lib/creationLibrary';
import './showcase.css';
import { CreationImage } from '../components/showcase/CreationImage';
const CreationDetail = lazy(() => import('../components/showcase/CreationDetail'));
const storeUrl = 'https://apps.apple.com/app/id6811466883';
type PreviewModalState = Creation | null;

function CreationCard({ item, onOpen }: {item: Creation; onOpen:(item:Creation)=>void}) {
  const concepts = item.concepts || [];
  const cover = item.preview || item.previewStoragePath ? item : concepts[0];
  return <article className="creation-card explore-card">
    <button onClick={()=>onOpen(item)} aria-label={`Open ${item.name}`}>
      {cover ? <CreationImage item={cover} alt={item.name} loading="lazy"/> : <div className="creation-placeholder"><Box/><span>Preview unavailable</span></div>}
      <span className="model-badge"><Box size={13}/>{item.hasModel?'Explore 3D':'Concepts'}</span>
    </button>
    <div className="card-info">
      <div className="card-top-meta"><span className="card-kind-badge">{item.hasModel ? (['character','flying'].includes(item.kind) ? 'Character' : '3D object') : 'Concept images'}</span><span className="card-engine">{item.createdAt ? new Date(item.createdAt).toLocaleDateString(undefined,{month:'short',day:'numeric',year:'numeric'}) : ''}</span></div>
      <h3>{item.name}</h3>
      {concepts.length>0 && <div className="card-concept-flow"><div>{concepts.map((c,i)=><CreationImage key={c.id} item={c} alt={`Concept ${i+1}`} loading="lazy"/>)}</div><span>{item.hasModel ? '→' : ''}</span>{item.hasModel && <Box size={24}/>}</div>}
      <p className="card-flow-label">{concepts.length ? `${concepts.length} concept${concepts.length===1?'':'s'}` : 'Saved creation'}{item.hasModel?' · 1 3D object':''}</p>
    </div>
  </article>;
}

function ExploreSection({onOpen}:{onOpen:(item:Creation)=>void}) {
  const [filter,setFilter]=useState<'characters'|'objects'>('characters');
  const characters=['character','flying','creature','animal','humanoid'];
  const filtered=publicCatalog.filter(a=>characters.includes(a.kind)===(filter==='characters'));
  return <section className="showcase-explore" id="explore">
    <div className="explore-header"><div className="explore-title-group"><span className="showcase-eyebrow"><Sparkles size={15}/> PUBLIC COLLECTION</span><h2>What will you create?</h2><p>20 characters, objects and little worlds. Open any example to explore its 3D model.</p></div>
      <div className="explore-filter-pills">{(['characters','objects'] as const).map(key=><button key={key} aria-pressed={filter===key} className={filter===key?'pill-active':''} onClick={()=>setFilter(key)}>{key==='characters'?'Characters':'Objects'}</button>)}<a href="#library">User created</a></div>
    </div>
    <div className="creation-grid">{filtered.map(item=>{
      const concept:Creation={id:'concept:'+item.id,name:item.name,kind:'Concept image',createdAt:0,hasImage:true,hasModel:false,preview:item.thumbUrl};
      const asset:Creation={id:item.id,name:item.name,kind:item.kind,createdAt:0,hasImage:true,hasModel:true,preview:item.thumbUrl,modelUrl:item.modelUrl,prompt:item.prompt,concepts:[concept],selectionKnown:true};
      return <CreationCard key={item.id} item={asset} onOpen={onOpen}/>;
    })}</div>
  </section>;
}

export function Showcase() {
  const [user, setUser] = useState<User | null>(null);
  const [ready, setReady] = useState(false);
  const [login, setLogin] = useState(false);
  const [items, setItems] = useState<Creation[]>([]);
  const [libraryFilter, setLibraryFilter] = useState<'all' | 'models' | 'concepts'>('all');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [revision, setRevision] = useState(0);
  const [preview, setPreview] = useState<PreviewModalState>(null);
  const groups = libraryGroups(items);

  useEffect(() => onAuthStateChanged(auth, u => {
    setUser(u && !u.isAnonymous ? u : null);
    setReady(true);
    setItems([]);
    setPreview(null);
  }), []);

  useEffect(() => {
    if (!user) return;
    setLoading(true);
    setError('');
    return onSnapshot(
      collection(db, 'users', user.uid, 'mobileCreations'),
      snapshot => {
        const saved = snapshot.docs.map(doc => {
          const d = doc.data();
          return {
            id: doc.id,
            name: d.name || 'Untitled creation',
            kind: d.kind || 'Concept image',
            createdAt: typeof d.createdAt === 'number' ? (d.createdAt < 1e12 ? d.createdAt * 1000 : d.createdAt) : 0,
            projectId: typeof d.projectId === 'string' ? d.projectId : '',
            conceptIds: Array.isArray(d.conceptIds) ? d.conceptIds.filter((x:unknown)=>typeof x==='string') : [],
            selectionKnown: d.selectionKnown === true,
            modelStoragePath: typeof d.modelStoragePath === 'string' ? d.modelStoragePath : '',
            prompt: typeof d.prompt === 'string' ? d.prompt : '',
            previewStoragePath: typeof d.previewStoragePath === 'string' ? d.previewStoragePath : '',
            hasImage: !!(d.previewStoragePath || d.preview),
            hasModel: d.kind === '3D object',
            preview: typeof d.preview === 'string' && (d.preview.startsWith('data:image/') || d.preview.startsWith('http://') || d.preview.startsWith('https://')) ? d.preview : '',
          } as Creation;
        });
        setItems(saved.sort((a, b) => b.createdAt - a.createdAt));
        setLoading(false);
        setError('');
      },
      () => {
        setError('Your cloud library could not be loaded. Please try again shortly.');
        setLoading(false);
      }
    );
  }, [user?.uid, revision]);

  useEffect(() => {
    if (!preview) return;
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setPreview(null);
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [preview]);

  const appButton = (
    <a className="craft-download" href={storeUrl} target="_blank" rel="noreferrer">
      <Smartphone size={25} />
      <span>
        <small>Discover 3D Craft on the</small>
        <strong>App Store</strong>
      </span>
      <ArrowUpRight size={19} />
    </a>
  );

  return (
    <div className="craft-showcase">
      <header className="showcase-nav">
        <a className="showcase-brand" href="/">
          <img src="/craft-icon.png" alt="3D Craft" width="38" height="38" />
          3D Craft
        </a>
        <nav>
          <a href="#explore">Characters & Objects</a>
          <a href="#how">How it works</a>
          <a href="#comparisons">Compare models</a>
          <a href="#library">User Created</a>
          {user && <a href={API_ACCESS_PATH}>API access</a>}
          {user ? (
            <button onClick={() => void logoutUser()}>
              <LogOut size={16} />
              Sign out
            </button>
          ) : (
            <button onClick={() => setLogin(true)}>
              Sign in <ArrowUpRight size={16} />
            </button>
          )}
        </nav>
      </header>

      <main>
        <section className="showcase-hero">
          <div className="hero-copy">
            <span className="showcase-eyebrow">
              <Sparkles size={15} /> A little idea. A whole new world.
            </span>
            <h1>
              Imagine it.<br />Make it <em>yours.</em>
            </h1>
            <p>
              Turn your ideas into unforgettable characters, beautiful concept images and 3D objects. Your creative studio, right on your iPhone and iPad.
            </p>
            {appButton}
            <div className="hero-note">Create in the app. Rediscover it here.</div>
            <a className="quiet-link" href="#explore">
              Explore characters & 3D objects <ArrowDown size={15} />
            </a>
          </div>
          <div className="hero-art">
            <div className="hero-orbit" />
            <img src="/images/showcase/lantern-cat.png" alt="An orange cat adventurer holding a lantern — a 3D Craft concept example" />
            <div className="art-caption">
              <Sparkles size={18} />
              <span>
                Big adventures.<br /><b>Start with one idea.</b>
              </span>
            </div>
            <span className="art-label">Concept example</span>
          </div>
        </section>

        {/* Public for everyone */}
        <ExploreSection onOpen={setPreview} />

        <section className="showcase-how" id="how">
          <div>
            <span className="showcase-eyebrow">MADE FOR YOUR IMAGINATION</span>
            <h2>From “what if”<br />to something wonderful.</h2>
          </div>
          <div className="how-steps">
            {[
              ['01', 'Start with a spark', 'Describe your idea or bring a reference photo into the app.'],
              ['02', 'Find their personality', 'Explore concept images and refine the details that make it yours.'],
              ['03', 'Bring it into 3D', 'Create your object in the app, then revisit your creations here.']
            ].map(([n, title, body]) => (
              <article key={n}>
                <span>{n}</span>
                <h3>{title}</h3>
                <p>{body}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="showcase-comparisons" id="comparisons" aria-labelledby="comparisons-title">
          <div className="comparisons-heading">
            <span className="showcase-eyebrow"><Sparkles size={15} /> OPEN RESEARCH</span>
            <h2 id="comparisons-title">See the results for yourself.</h2>
            <p>Explore real outputs from the same blue-dragon reference. Rotate the 3D results, watch the video samples, and compare their measured costs. These are snapshots from specific tests; your result and current quote may differ.</p>
          </div>
          <div className="comparison-cards">
            <a className="comparison-card" href="/docs/design/image-to-3d-comparison/index.html">
              <div className="comparison-card-art comparison-card-art-3d">
                <img src="/docs/design/image-to-3d-comparison/media/thumb-tripo.png" alt="Tripo H3.1 blue-dragon 3D sample" loading="lazy" />
              </div>
              <div className="comparison-card-copy">
                <span>01 / INTERACTIVE 3D</span>
                <h3>Image-to-3D comparison <ArrowUpRight size={21} /></h3>
                <p>See 11 real results from one dragon picture. Compare the look and price, then rotate each finished 3D model.</p>
              </div>
            </a>
            <a className="comparison-card" href="/docs/design/video-provider-comparison/index.html">
              <div className="comparison-card-art comparison-card-art-video">
                <img src="/docs/design/mascot-animations/source/cloud-dragon-960.jpg" alt="Blue-dragon reference used for six animation samples" loading="lazy" />
                <span>Six real clips</span>
              </div>
              <div className="comparison-card-copy">
                <span>02 / VIDEO MOTION</span>
                <h3>Video model comparison <ArrowUpRight size={21} /></h3>
                <p>Watch six versions of the same dragon animation, with example prices beside each video.</p>
              </div>
            </a>
          </div>
        </section>

        {/* User created section */}
        <section className="showcase-library" id="library">
          <div className="library-heading">
            <div>
              <span className="showcase-eyebrow">YOUR PRIVATE SYNCED COLLECTION</span>
              <h2>Made by you.</h2>
              <p>Your concepts and their 3D objects, together. Synced privately from your iPhone and iPad.</p>
            </div>
            {user && (
              <button className="refresh-library" disabled={loading} onClick={() => setRevision(x => x + 1)}>
                <RefreshCw size={17} />
                Refresh
              </button>
            )}
          </div>
          {user && items.length > 0 && (
            <div className="explore-filter-pills" style={{ marginTop: '20px' }}>
              <button className={libraryFilter === 'all' ? 'pill-active' : ''} onClick={() => setLibraryFilter('all')}>
                All ({groups.length})
              </button>
              <button className={libraryFilter === 'models' ? 'pill-active' : ''} onClick={() => setLibraryFilter('models')}>
                3D Objects ({groups.filter(i => i.hasModel).length})
              </button>
              <button className={libraryFilter === 'concepts' ? 'pill-active' : ''} onClick={() => setLibraryFilter('concepts')}>
                Concept sets ({groups.filter(i => !i.hasModel).length})
              </button>
            </div>
          )}
          {!ready ? (
            <div className="library-empty">Loading your account…</div>
          ) : !user ? (
            <div className="library-empty">
              <Box size={34} />
              <h3>Your imagination has a home.</h3>
              <p>Sign in with the same account you use in 3D Craft to see your creations. No purchase is needed to browse your library.</p>
              <button className="showcase-primary" onClick={() => setLogin(true)}>
                Sign in to view creations <ArrowUpRight size={17} />
              </button>
            </div>
          ) : error ? (
            <div className="library-empty" role="alert">
              <h3>Let’s reconnect your library.</h3>
              <p>{error}</p>
              <button className="showcase-primary" onClick={() => setRevision(x => x + 1)}>
                Try again
              </button>
            </div>
          ) : loading && !items.length ? (
            <div className="library-empty" role="status">Loading your creations…</div>
          ) : items.length ? (
            <div className="creation-grid" key={user.uid}>
              {groups
                .filter(item => {
                  if (libraryFilter === 'models') return item.kind === '3D object';
                  if (libraryFilter === 'concepts') return item.kind === 'Concept image';
                  return true;
                })
                .map(item => (
                  <CreationCard key={item.id} item={item} onOpen={setPreview} />
                ))}
            </div>
          ) : (
            <div className="library-empty">
              <Sparkles size={32} />
              <h3>Your next idea belongs here.</h3>
              <p>Create something in the app using this same account. Your synced concepts and 3D object previews will appear here. Older creations may need the latest app update to sync.</p>
              {appButton}
            </div>
          )}
        </section>

        <section className="showcase-end">
          <span className="showcase-eyebrow">TAKE YOUR IDEAS WITH YOU</span>
          <h2>Your next character<br />is waiting to meet you.</h2>
          {appButton}
          <p>For iPhone and iPad</p>
        </section>
      </main>

      <LegalFooter />
      <AuthModal open={login} onClose={() => setLogin(false)} />

      {preview && <Suspense fallback={<div className="model-status">Opening creation…</div>}><CreationDetail key={preview.id} item={preview} onClose={()=>setPreview(null)}/></Suspense>}
    </div>
  );
}
