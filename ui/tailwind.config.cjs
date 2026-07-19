module.exports = {
  darkmode: true,
  content: [
    "./index.html",
    "./src/**/*.{svelte,js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      // ps-mdt design language: near-black flat panels, hairline borders,
      // muted accents (see ps-mdt web/src/styles/variables.css).
      colors: {
        primary: '#0e0f0f',              // card headers  (--card-dark-bg)
        secondary: '#171717',            // card bodies   (--dark-bg)
        tertiary: '#1d1d1d',             // rows          (--secondary-bg)
        priority_primary: '#180f11',     // red-tinted header
        priority_secondary: '#1e1315',   // red-tinted body
        priority_tertiary: '#261a1c',    // red-tinted rows
        priority_quaternary: '#7f1d1d',  // emergency action
        accent: '#3b82f6',               // --accent-rgb 59,130,246
        accent_green: '#299e6d',         // --btn-primary
        accent_dark_green: '#22be83',    // --btn-primary-hover
        accent_cyan: '#06b6d4',
        accent_red: '#ef4444',
        accent_dark_red: '#7f1d1d',
        border_primary: 'rgba(255, 255, 255, 0.08)',
        hover_secondary: 'rgba(255, 255, 255, 0.05)',
      }
    },
  },
  plugins: [],
}
