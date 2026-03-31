/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{svelte,ts,js}'],
  theme: {
    extend: {
      colors: {
        attack: { DEFAULT: '#ef4444', light: '#fca5a5', dark: '#7f1d1d' },
        defend: { DEFAULT: '#10b981', light: '#6ee7b7', dark: '#064e3b' },
        agent:  { DEFAULT: '#6366f1', light: '#a5b4fc', dark: '#1e1b4b' },
      },
      animation: {
        'pulse-red': 'pulse-red 1.5s ease-in-out infinite',
      },
      keyframes: {
        'pulse-red': {
          '0%, 100%': { boxShadow: '0 0 0 0 rgba(239, 68, 68, 0.4)' },
          '50%':       { boxShadow: '0 0 0 8px rgba(239, 68, 68, 0)' },
        },
      },
    },
  },
  plugins: [],
}
