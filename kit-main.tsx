import React from 'react';
import { createRoot } from 'react-dom/client';
import './.claude/skills/studio-ui/assets/tokens.css';
import './src/index.css';
import { Demo } from './.claude/skills/studio-ui/assets/demo';
createRoot(document.getElementById('root')!).render(<React.StrictMode><Demo /></React.StrictMode>);
