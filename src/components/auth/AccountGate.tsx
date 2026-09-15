import { useEffect, useState, type ReactNode } from 'react';
import { auth, logoutUser, onAuthStateChanged, type User } from '../../lib/firebase';
import { authenticatedFetch, API_BASE } from '../../lib/api';
import { AdminCredits } from './AdminCredits';
import { AuthModal } from './AuthModal';
import { LegalFooter } from '../../pages/LegalPages';

type Balance = {available: number; isAdmin: boolean; checkoutAvailable: boolean; pack: {credits:number;usd:string}};
export function AccountGate({children}:{children:ReactNode}) {
  const [user,setUser]=useState<User|null>(null);
  const [loaded,setLoaded]=useState(false);
  const [balance,setBalance]=useState<Balance|null>(null);
  const [error,setError]=useState('');
  const [open,setOpen]=useState(false);
  const [busy,setBusy]=useState(false);
  useEffect(()=>onAuthStateChanged(auth,next=>{setUser(next);setLoaded(true);setBalance(null);setError('');}),[]);
  const signedIn=!!user && !user.isAnonymous;
  useEffect(()=>{
    if(!signedIn)return;
    let current=true;
    const refresh=()=>authenticatedFetch(`${API_BASE}/api/billing/account`).then(async r=>{
      const result=await r.json(); if(!r.ok)throw new Error(result.detail || 'Could not load your balance.');
      if(current){setBalance(result);setError('');}
    }).catch(e=>{if(current)setError(e.message)});
    void refresh(); const timer=setInterval(refresh,10000);
    return ()=>{current=false;clearInterval(timer)};
  },[user?.uid,signedIn]);
  async function buy(){
    setBusy(true);setError('');
    try{const r=await authenticatedFetch(`${API_BASE}/api/billing/checkout`,{method:'POST'});const d=await r.json();if(!r.ok)throw new Error(d.detail || 'Checkout is unavailable.');const url=new URL(d.url);if(url.protocol!=='https:' || url.hostname!=='checkout.stripe.com')throw new Error('Checkout returned an invalid address.');location.assign(url.href);}
    catch(e){setError(e instanceof Error?e.message:'Checkout is unavailable.');setBusy(false)}
  }
  // Account and balance checks are repeated on the server for every paid action.
  if(signedIn && balance && balance.available>0)return <><div className="fixed bottom-5 right-5 z-[100] rounded-full bg-white px-5 py-3 text-sm text-emerald-900 shadow-lg">{balance.available} credits <button className="ml-3 underline" onClick={buy} disabled={!balance.checkoutAvailable||busy}>Buy credits</button>{balance.isAdmin && <AdminCredits/>}</div>{children}</>;
  return <div className="min-h-screen bg-[#effaf6] text-[#206853]">
    <main className="mx-auto max-w-xl px-6 py-24">
      <a href="/" className="text-xl font-bold">◇ 3D Craft</a>
      <h1 className="mt-12 text-4xl font-semibold">{signedIn?'Credits for your next creation':'Your ideas belong to you.'}</h1>
      <p className="mt-5 text-lg">{signedIn?'Use purchased credits or demo credits granted by an admin to generate images, chat with the creative assistant, and create 3D objects.':'Sign in to create and keep your concepts, 3D objects and credits together across devices.'}</p>
      {!loaded?<p className="mt-8">Loading your account…</p>:!signedIn?<button className="mt-8 rounded-full bg-[#206853] px-7 py-4 text-white" onClick={()=>setOpen(true)}>Sign in or create account</button>:<>
        <p className="mt-6">{user?.email}</p>
        <div className="my-8 rounded-3xl bg-white p-7 shadow-sm"><p className="text-3xl font-semibold">$4.99 <span className="text-base">USD</span></p><p className="mt-2">200 credits · One-time purchase</p><p className="mt-3 text-sm">No subscription. Generation costs vary by model and options. The 15% service fee is included in usage charges.</p><p className="mt-4">Available: {balance?.available ?? '—'} credits</p></div>
        <button className="rounded-full bg-[#206853] px-7 py-4 text-white disabled:opacity-50" disabled={!balance?.checkoutAvailable||busy} onClick={buy}>{busy?'Opening secure checkout…':'Buy 200 credits'}</button>
        {balance && !balance.checkoutAvailable && <p className="mt-4 text-sm">Purchases are not available yet. We won’t charge you until the paid creation service is ready.</p>}
        {balance?.isAdmin && <AdminCredits/>}
        <button className="ml-5 underline" onClick={()=>void logoutUser()}>Sign out</button>
      </>}
      {error && <p role="alert" className="mt-5">{error}</p>}
      <AuthModal open={open} onClose={()=>setOpen(false)}/>
    </main><LegalFooter/>
  </div>;
}
