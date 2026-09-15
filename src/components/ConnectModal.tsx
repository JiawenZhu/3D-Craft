import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { Check, Copy, Terminal, X } from 'lucide-react';

const INSTALL = 'venv/bin/python -m pip install -e ./integrations';
const CONFIG = 'venv/bin/craft --workspace /absolute/path/to/your/game mcp-config';
const EXAMPLE = 'venv/bin/craft generate --prompt "A stylized stone watchtower"\nvenv/bin/craft status run-ID --wait\nvenv/bin/craft pull a-ID --output assets/watchtower.glb';

export function ConnectModal({ onClose }: { onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [copied, setCopied] = useState('');
  const [error, setError] = useState('');
  useEffect(() => { dialog.current?.showModal(); }, []);
  async function copy(value: string) {
    try { await navigator.clipboard.writeText(value); setCopied(value); setError(''); }
    catch { setError('Copy is unavailable. Select and copy the command below.'); }
  }
  const snippet = (value: string) => (
    <div className="relative mt-2 rounded-xl border border-white/10 bg-black/25 p-3 pr-12">
      <pre className="overflow-x-auto whitespace-pre-wrap break-all font-mono text-[11px] leading-6 text-chalk">{value}</pre>
      <button aria-label="Copy command" className="absolute right-3 top-3 text-chalk-faint hover:text-white" onClick={() => copy(value)}>
        {copied === value ? <Check className="h-4 w-4 text-emerald-400" /> : <Copy className="h-4 w-4" />}
      </button>
    </div>
  );
  return createPortal(
    <dialog ref={dialog} onClose={onClose} onClick={(e) => { if (e.target === e.currentTarget) dialog.current?.close(); }}
      aria-labelledby="connect-title"
      className="fixed inset-0 m-auto max-h-[85dvh] w-[calc(100%_-_2rem)] max-w-xl overflow-y-auto rounded-3xl border border-white/15 bg-ink-900 p-6 text-chalk shadow-2xl backdrop:bg-black/60 backdrop:backdrop-blur-sm sm:p-8">
      <div className="flex items-start justify-between gap-4">
        <div>
          <Terminal className="mb-3 h-6 w-6 text-lilac" />
          <h2 id="connect-title" className="text-xl font-semibold text-white">Bring 3D Craft into your workspace</h2>
        </div>
        <button aria-label="Close connections" onClick={() => dialog.current?.close()} className="rounded-full p-1 text-chalk-faint hover:text-white"><X className="h-5 w-5" /></button>
      </div>
      <p className="mt-3 text-sm leading-6 text-chalk-dim">Generate from images or text, check progress, and pull models into your game project through the CLI or a local MCP client.</p>
      <ol className="mt-6 space-y-5 text-sm">
        <li><strong className="font-medium text-white">1. Install the bridge in your Studio checkout</strong>{snippet(INSTALL)}</li>
        <li><strong className="font-medium text-white">2. Choose a workspace and get your MCP config</strong>{snippet(CONFIG)}
          <p className="mt-2 text-xs leading-5 text-chalk-dim">Replace the example path with your game folder. Add the printed configuration to your MCP client. Keep the local Studio API running.</p>
        </li>
        <li><strong className="font-medium text-white">3. Ask your agent to create and download an asset</strong>
          <p className="mt-2 text-xs leading-5 text-chalk-dim">Or use the CLI below. Replace run-ID and a-ID with the identifiers returned by your job. Generation uses your server’s configured providers and may incur charges.</p>{snippet(EXAMPLE)}
        </li>
      </ol>
      <p role="status" className="mt-3 text-xs text-coral">{error || (copied ? 'Copied to clipboard.' : '')}</p>
      <div className="mt-5 border-t border-white/10 pt-4 text-xs leading-5 text-chalk-faint">Local preview · GLB, OBJ bundle, STL and PLY downloads. Hosted ChatGPT connections and commercial account billing are not enabled yet.</div>
    </dialog>, document.body,
  );
}
