/** @type {import('tailwindcss').Config} */
export default {
  content: [
    './index.html',
    './src/**/*.{js,ts,jsx,tsx}',
    // The studio-ui kit lives in .claude/skills/ as a portable deliverable, not
    // as part of this app. Scanning it in dev makes /kit.html render properly;
    // excluding it from the production build keeps ~6 kB of CSS the app never
    // uses out of what users download.
    ...(process.env.NODE_ENV === 'production'
      ? []
      : ['./kit.html', './kit-main.tsx', './.claude/skills/**/*.{ts,tsx}']),
  ],
  theme: {
    extend: {
      colors: {
        // Sampled directly from hyper3d.ai/workspace/rodin
        ink: {
          DEFAULT: '#121317', // --bg
          950: '#0d0e11',
          900: '#17181c',
          850: '#1c1d21',
          800: '#232323',
          750: '#262626',
          700: '#2c2c2c',
          600: '#373737',
          500: '#4a4a4a',
          400: '#5c5c5c',
        },
        chalk: {
          DEFAULT: '#cfcfcf', // --themeTextColor
          bright: '#ffffff',
          dim: '#9c9c9c',
          faint: '#707070',
          ghost: '#565656',
        },
        // exact accents read off the live controls
        ember: '#d67830',   // hero glow warm
        amber: '#ffd98e',
        mauve: '#9e76ac',
        rose: '#e6765d',    // gradient text start
        coral: '#ff989b',   // primary UI gradient start
        lilac: '#d8a1f1',   // primary UI gradient end
        blush: '#d19ee9',   // gradient text end
        speedy: '#ff886f',  // "Speedy" quality tint
        iris: '#875de7',
      },
      fontFamily: {
        sans: ['Inter', 'SF Pro Display', '-apple-system', 'Helvetica Neue', 'sans-serif'],
        display: ['Playfair Display', 'Georgia', 'serif'],
        mono: ['JetBrains Mono', 'SFMono-Regular', 'monospace'],
      },
      boxShadow: {
        pill: '0 1px 0 0 rgba(255,255,255,0.06) inset, 0 8px 24px -8px rgba(0,0,0,0.8)',
        lift: '0 24px 60px -20px rgba(0,0,0,0.85)',
        glow: '0 0 60px -6px rgba(158,118,172,0.55)',
      },
      backdropBlur: { xs: '2px' },
      keyframes: {
        drift: {
          '0%,100%': { transform: 'translate3d(0,0,0) scale(1)' },
          '33%': { transform: 'translate3d(4%,-6%,0) scale(1.08)' },
          '66%': { transform: 'translate3d(-5%,4%,0) scale(0.94)' },
        },
        draw: { to: { strokeDashoffset: '0' } },
        riseIn: { from: { opacity: '0', transform: 'translateY(10px)' }, to: { opacity: '1', transform: 'none' } },
        popIn: { from: { opacity: '0', transform: 'translateY(6px) scale(0.97)' }, to: { opacity: '1', transform: 'none' } },
        shimmer: { '100%': { transform: 'translateX(100%)' } },
        spinSlow: { to: { transform: 'rotate(360deg)' } },
      },
      animation: {
        drift: 'drift 26s ease-in-out infinite',
        riseIn: 'riseIn .5s cubic-bezier(.16,1,.3,1) both',
        popIn: 'popIn .18s cubic-bezier(.16,1,.3,1) both',
        shimmer: 'shimmer 1.8s infinite',
        spinSlow: 'spinSlow 3s linear infinite',
      },
    },
  },
  plugins: [],
}
