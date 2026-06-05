/* BeOS-style isometric application icons, hand-built as compact SVG.
   Style cues from the BeOS R5 Tracker icon set: chunky 3/4 / isometric
   forms, saturated fills, dark 1px outline, a soft contact shadow. */
window.BEOS_ICONS = (function () {
  const SHADOW = '<ellipse cx="26" cy="46.5" rx="15" ry="3" fill="rgba(0,0,0,.16)"/>';

  // generic "application" icon = three stacked cubes (BeOS default app icon)
  const generic = `
    <g stroke="#23323f" stroke-width="1" stroke-linejoin="round">
      <polygon points="20,9 28.5,13.5 20,18 11.5,13.5" fill="#7faae8"/>
      <polygon points="11.5,13.5 20,18 20,27 11.5,22.5" fill="#3f6fc0"/>
      <polygon points="20,18 28.5,13.5 28.5,22.5 20,27" fill="#2f59a0"/>
      <polygon points="33,17 41.5,21.5 33,26 24.5,21.5" fill="#f7d456"/>
      <polygon points="24.5,21.5 33,26 33,35 24.5,30.5" fill="#d9ad22"/>
      <polygon points="33,26 41.5,21.5 41.5,30.5 33,35" fill="#bf9519"/>
      <polygon points="20,25 28.5,29.5 20,34 11.5,29.5" fill="#ec6a52"/>
      <polygon points="11.5,29.5 20,34 20,43 11.5,38.5" fill="#c43f2c"/>
      <polygon points="20,34 28.5,29.5 28.5,38.5 20,43" fill="#a23020"/>
    </g>`;

  const folder = `
    <g stroke="#7d5e12" stroke-width="1" stroke-linejoin="round">
      <path d="M7 16h11l3 3h23a2 2 0 0 1 2 2v17a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V18a2 2 0 0 1 2-2z" fill="#e6b736"/>
      <path d="M7 23h40a2 2 0 0 1 2 2l-2 13a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V25a2 2 0 0 1 2-2z" fill="#f8d669"/>
    </g>`;

  const browser = `
    <g stroke="#1c4f86" stroke-width="1">
      <circle cx="26" cy="24" r="15" fill="#3f8fd6"/>
      <ellipse cx="26" cy="24" rx="6.2" ry="15" fill="none"/>
      <ellipse cx="26" cy="24" rx="14" ry="6" fill="none"/>
      <line x1="11" y1="24" x2="41" y2="24"/>
      <path d="M14 16c5 3 19 3 24 0M14 32c5-3 19-3 24 0" fill="none"/>
      <path d="M18 14c3 2 4 17 0 20" fill="none" opacity=".5"/>
    </g>
    <path d="M17 16c2-3 7-5 9-5-7 1-11 6-12 11 0-2 1-4 3-6z" fill="#bfe0f6" opacity=".7"/>`;

  const mail = `
    <g stroke="#2b2b2b" stroke-width="1" stroke-linejoin="round">
      <rect x="6.5" y="14" width="39" height="25" rx="2" fill="#fafafa"/>
      <path d="M6.5 16 26 30 45.5 16" fill="none"/>
      <path d="M6.5 38 19 26M45.5 38 33 26" fill="none" opacity=".5"/>
    </g>
    <rect x="33" y="16.5" width="9" height="6" rx="1" fill="#e0584a" stroke="#9a2f24" stroke-width="1"/>`;

  const messages = `
    <g stroke="#2b6fb0" stroke-width="1" stroke-linejoin="round">
      <path d="M9 12h28a4 4 0 0 1 4 4v13a4 4 0 0 1-4 4H21l-8 7 1-7h-5a4 4 0 0 1-4-4V16a4 4 0 0 1 4-4z" fill="#ffffff"/>
    </g>
    <g fill="#4a9be0"><circle cx="16" cy="22.5" r="2.3"/><circle cx="23" cy="22.5" r="2.3"/><circle cx="30" cy="22.5" r="2.3"/></g>`;

  const maps = `
    <g stroke="#3a6a40" stroke-width="1" stroke-linejoin="round">
      <path d="M7 14 19 11 33 14 45 11v27l-12 3-14-3-12 3z" fill="#e7e0c7"/>
    </g>
    <g stroke="#7d7a66" stroke-width=".8" opacity=".7"><path d="M19 11v27M33 14v27" fill="none"/></g>
    <path d="M10 30c6-2 10 2 16-1s10 1 14-1" fill="none" stroke="#5a93cf" stroke-width="1.6"/>
    <path d="M33 16c4 0 6 3 6 6 0 4-6 9-6 9s-6-5-6-9c0-3 2-6 6-6z" fill="#d8453a" stroke="#8f261d" stroke-width="1"/>
    <circle cx="33" cy="22" r="2" fill="#fff"/>`;

  const photos = `
    <g stroke="#2b2b2b" stroke-width="1" stroke-linejoin="round">
      <rect x="6.5" y="12" width="39" height="29" rx="1.5" fill="#f5f5f5"/>
      <rect x="10" y="15.5" width="32" height="22" fill="#bfe3f5"/>
    </g>
    <circle cx="18" cy="22" r="3.4" fill="#f6d24a"/>
    <path d="M10 37.5 22 26l7 6 6-5 7 6.5v1H10z" fill="#5aa55a" stroke="#2f6b32" stroke-width="1" stroke-linejoin="round"/>`;

  const video = `
    <g stroke="#1c1c1c" stroke-width="1" stroke-linejoin="round">
      <rect x="6.5" y="13" width="39" height="25" rx="2.5" fill="#3a3f45"/>
      <rect x="9.5" y="16" width="33" height="19" rx="1" fill="#10242e"/>
      <rect x="20" y="40" width="12" height="3" rx="1.5" fill="#9aa0a6"/>
    </g>
    <path d="M23 21 33 25.5 23 30z" fill="#f4f4f4"/>`;

  const calendar = `
    <g stroke="#9a2f24" stroke-width="1" stroke-linejoin="round">
      <rect x="8.5" y="13" width="35" height="29" rx="2" fill="#ffffff" stroke="#8a8a8a"/>
      <path d="M8.5 15a2 2 0 0 1 2-2h31a2 2 0 0 1 2 2v6h-35z" fill="#d8453a"/>
    </g>
    <g stroke="#6a6a6a" stroke-width=".8" opacity=".6"><path d="M8.5 28h35M8.5 35h35M20 21v21M32 21v21" fill="none"/></g>
    <g fill="#c9c9c9" stroke="#8a8a8a" stroke-width="1"><rect x="16" y="9" width="3" height="8" rx="1.5"/><rect x="33" y="9" width="3" height="8" rx="1.5"/></g>
    <text x="26" y="39" font-family="Helvetica,Arial" font-size="11" font-weight="700" fill="#d8453a" text-anchor="middle">5</text>`;

  const people = `
    <g stroke="#2b2b2b" stroke-width="1" stroke-linejoin="round">
      <circle cx="17" cy="18" r="6" fill="#e08a3a"/>
      <path d="M6 41c0-7 5-12 11-12s11 5 11 12z" fill="#e08a3a"/>
      <circle cx="33" cy="16" r="6.5" fill="#4a90d6"/>
      <path d="M21 41c0-8 5.5-13 12-13s12 5 12 13z" fill="#4a90d6"/>
    </g>`;

  const notes = `
    <g stroke="#b39a1f" stroke-width="1" stroke-linejoin="round">
      <path d="M10 11h32v25l-7 7H10z" fill="#f7e463"/>
      <path d="M35 43v-7h7z" fill="#e3cf48"/>
    </g>
    <g stroke="#c9b53a" stroke-width="1.4" opacity=".8"><path d="M16 19h20M16 25h20M16 31h14" fill="none"/></g>`;

  const settings = `
    <g stroke="#3a4654" stroke-width="1" stroke-linejoin="round" fill="#aeb8c2">
      <path d="M26 8l3 4 5-1 1 5 5 2-2 5 3 4-4 3 1 5-5 1-2 5-5-2-5 2-2-5-5-1 1-5-4-3 3-4-2-5 5-2 1-5 5 1z"/>
    </g>
    <circle cx="26" cy="25" r="7" fill="#5f6b78" stroke="#2c3742" stroke-width="1"/>
    <circle cx="26" cy="25" r="3" fill="#d7dde3"/>`;

  const clock = `
    <g stroke="#5a5a5a" stroke-width="1">
      <circle cx="26" cy="25" r="16" fill="#fbfbfb"/>
      <circle cx="26" cy="25" r="16" fill="none" stroke="#9a9a9a" stroke-width="2"/>
    </g>
    <g stroke="#3a3a3a" stroke-width="1.6" stroke-linecap="round"><line x1="26" y1="25" x2="26" y2="15"/><line x1="26" y1="25" x2="33" y2="28"/></g>
    <line x1="26" y1="25" x2="20" y2="32" stroke="#d8453a" stroke-width="1.1" stroke-linecap="round"/>
    <circle cx="26" cy="25" r="1.6" fill="#3a3a3a"/>`;

  const calculator = `
    <g stroke="#5a5a5a" stroke-width="1" stroke-linejoin="round">
      <rect x="12" y="9" width="28" height="34" rx="3" fill="#d2d2d2"/>
      <rect x="15.5" y="12.5" width="21" height="8" rx="1" fill="#b6d4ad" stroke="#6f8a68"/>
    </g>
    <g fill="#4a4a4a"><circle cx="18.5" cy="27" r="1.8"/><circle cx="26" cy="27" r="1.8"/><circle cx="33.5" cy="27" r="1.8"/><circle cx="18.5" cy="33" r="1.8"/><circle cx="26" cy="33" r="1.8"/><circle cx="33.5" cy="33" r="1.8"/><circle cx="18.5" cy="39" r="1.8"/><circle cx="26" cy="39" r="1.8"/></g>
    <circle cx="33.5" cy="39" r="1.8" fill="#e0584a"/>`;

  const terminal = `
    <g stroke="#3a3a3a" stroke-width="1" stroke-linejoin="round">
      <rect x="7" y="12" width="38" height="27" rx="2" fill="#cfcfcf"/>
      <rect x="10" y="15" width="32" height="18" rx="1" fill="#0e2b15"/>
      <path d="M20 41h12l2 3H18z" fill="#b6b6b6"/>
    </g>
    <g stroke="#54d66a" stroke-width="1.4" fill="none" stroke-linecap="round"><path d="M13 19l4 3-4 3"/><line x1="19" y1="25" x2="26" y2="25"/></g>`;

  const text = `
    <g stroke="#2b2b2b" stroke-width="1" stroke-linejoin="round">
      <path d="M12 9h20l8 8v26H12z" fill="#ffffff"/>
      <path d="M32 9v8h8z" fill="#dcdcdc"/>
    </g>
    <g stroke="#9aa0c0" stroke-width="1.3" opacity=".8"><path d="M17 22h14M17 27h18M17 32h18M17 37h11" fill="none"/></g>`;

  const ICONS = { generic, folder, browser, mail, messages, maps, photos, video,
                  calendar, people, notes, settings, clock, calculator, terminal, text };

  function get(type) {
    const inner = ICONS[type] || ICONS.generic;
    return `<svg viewBox="0 0 52 52" width="46" height="46" shape-rendering="geometricPrecision">${SHADOW}${inner}</svg>`;
  }
  return { get, types: Object.keys(ICONS) };
})();
