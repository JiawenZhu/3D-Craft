import { useRef, useState } from 'react';
import { authenticatedFetch, API_BASE } from '../../lib/api';

export function AdminCredits() {
  const [open, setOpen] = useState(false);
  const [email, setEmail] = useState('');
  const [credits, setCredits] = useState(200);
  const [reason, setReason] = useState('Demo access');
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState('');
  const attempt = useRef<{body:string; id:string} | null>(null);
  async function grant(event: React.FormEvent) {
    event.preventDefault(); if (busy) return;
    setBusy(true); setNotice('');
    const body = JSON.stringify({recipientEmail:email.trim(), credits, reason:reason.trim()});
    if (attempt.current?.body !== body) attempt.current = {body, id:crypto.randomUUID()};
    try {
      const response = await authenticatedFetch(`${API_BASE}/api/billing/admin/credits`, {
        method:'POST', headers:{'Content-Type':'application/json'},
        body:JSON.stringify({...JSON.parse(body), requestId:attempt.current.id}),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(typeof result.detail === 'string' ? result.detail : 'Could not grant credits.');
      setNotice(`${result.granted} credits granted to ${email.trim()}. No purchase required.`);
      setEmail(''); attempt.current = null;
    } catch(error) {setNotice(error instanceof Error ? error.message : 'Could not grant credits.');}
    finally {setBusy(false);}
  }
  return <div className="mt-3">
    <button className="underline" onClick={()=>setOpen(!open)} aria-expanded={open}>Admin · Grant demo credits</button>
    {open && <form onSubmit={grant} className="mt-3 grid max-w-sm gap-3 rounded-2xl bg-white p-5 text-sm shadow-lg">
      <label>Registered user’s email<input required type="email" value={email} disabled={busy} onChange={e=>setEmail(e.target.value)} className="mt-1 w-full rounded-lg border p-2"/></label>
      <label>Credits<input required type="number" min={1} max={100000} step={1} value={credits} disabled={busy} onChange={e=>setCredits(Number(e.target.value))} className="mt-1 w-full rounded-lg border p-2"/></label>
      <label>Reason<input required maxLength={500} value={reason} disabled={busy} onChange={e=>setReason(e.target.value)} className="mt-1 w-full rounded-lg border p-2"/></label>
      <button disabled={busy} className="rounded-full bg-[#206853] p-3 text-white">{busy?'Granting…':'Grant credits'}</button>
      <p role="status">{notice}</p>
    </form>}
  </div>;
}
