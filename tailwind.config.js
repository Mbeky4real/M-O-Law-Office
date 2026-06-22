/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // MOLMS Design System Tokens
        primary: {
          DEFAULT: '#1B2A4A',
          50:  '#EAF0FA',
          100: '#C5D5EE',
          200: '#A0BAE2',
          300: '#7B9FD6',
          400: '#5684CA',
          500: '#2E5FA3',
          600: '#254E87',
          700: '#1B2A4A',
          800: '#142039',
          900: '#0C1527',
        },
        accent: {
          DEFAULT: '#B8860B',
          light:   '#FBF7EE',
          mid:     '#D4A017',
          dark:    '#8B6508',
        },
        // Status colours
        status: {
          open:       { DEFAULT: '#2563EB', bg: '#EFF6FF' },
          'in-progress': { DEFAULT: '#059669', bg: '#ECFDF5' },
          awaiting:   { DEFAULT: '#D97706', bg: '#FFFBEB' },
          review:     { DEFAULT: '#7C3AED', bg: '#F5F3FF' },
          completed:  { DEFAULT: '#0D6E6E', bg: '#F0FDFA' },
          closed:     { DEFAULT: '#475569', bg: '#F1F5F9' },
        },
        // Priority colours
        priority: {
          low:    '#94A3B8',
          normal: '#2563EB',
          high:   '#D97706',
          urgent: '#DC2626',
        },
        // Surface colours
        surface:  '#FFFFFF',
        sidebar:  '#F8FAFC',
        border:   '#E2E8F0',
        // Text colours
        text: {
          primary:   '#1E293B',
          secondary: '#64748B',
          muted:     '#94A3B8',
        },
        // Hover / subtle
        hover:  '#F1F5F9',
        subtle: '#F8FAFC',
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'Courier New', 'monospace'],
      },
      fontSize: {
        'xs':   ['11px', { lineHeight: '1.4' }],
        'sm':   ['13px', { lineHeight: '1.5' }],
        'base': ['15px', { lineHeight: '1.6' }],
        'lg':   ['18px', { lineHeight: '1.5' }],
        'xl':   ['22px', { lineHeight: '1.4' }],
        '2xl':  ['28px', { lineHeight: '1.3' }],
        '4xl':  ['36px', { lineHeight: '1.2' }],
      },
      spacing: {
        '13': '52px',
        '15': '60px',
        '18': '72px',
      },
      width: {
        sidebar:          '240px',
        'sidebar-collapsed': '64px',
      },
      height: {
        topbar: '64px',
      },
      maxWidth: {
        content: '1400px',
      },
      boxShadow: {
        card: '0 1px 3px rgba(0,0,0,0.06)',
        'card-hover': '0 4px 12px rgba(0,0,0,0.10)',
        dropdown: '0 8px 24px rgba(0,0,0,0.12)',
      },
      borderRadius: {
        DEFAULT: '6px',
      },
      transitionDuration: {
        DEFAULT: '150ms',
      },
    },
  },
  plugins: [],
}
