import { createGlobalStyle } from 'styled-components/macro';

export default createGlobalStyle`
    :root {
        --jz-primary: #08A8FF;
        --jz-secondary: #006DFF;
        --jz-bg: #05090F;
        --jz-sidebar: #070D15;
        --jz-card: #0A111C;
        --jz-card-hover: #0E1927;
        --jz-border: rgba(255,255,255,0.08);
        --jz-text: #E6EDF5;
        --jz-secondary-text: #94A3B8;
        --jz-muted: #64748B;
        --jz-success: #22C55E;
        --jz-warning: #F59E0B;
        --jz-danger: #EF4444;
        --jz-radius: 16px;
        --jz-shadow: 0 18px 55px rgba(0, 0, 0, .28);
    }

    @font-face {
        font-family: 'Inter';
        font-style: normal;
        font-display: swap;
        font-weight: 100 900;
        src: local('Inter');
    }

    * { box-sizing: border-box; }

    html, body, #app { min-height: 100%; }

    body {
        margin: 0;
        background:
            radial-gradient(circle at 10% 0%, rgba(8,168,255,.11), transparent 28rem),
            radial-gradient(circle at 90% 10%, rgba(0,109,255,.08), transparent 26rem),
            var(--jz-bg);
        color: var(--jz-text);
        font-family: Inter, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        letter-spacing: .01em;
        transition: background-color .25s ease;
    }

    body.jz-shell #app {
        padding-top: 64px;
        padding-left: 272px;
        transition: padding-left .25s ease;
    }

    body.jz-shell.jz-sidebar-collapsed #app { padding-left: 88px; }
    @media (max-width: 900px) { body.jz-shell #app { padding-top: 0; } }

    body.jz-shell .jz-main-content {
        position: relative;
        min-height: 100vh;
        background: transparent;
        padding-top: 64px;
    }
    body.jz-shell #app > div { min-height: 100vh; }

    h1,h2,h3,h4,h5,h6 {
        color: var(--jz-text);
        font-family: Inter, system-ui, sans-serif;
        font-weight: 700;
        letter-spacing: -.025em;
    }

    p { color: var(--jz-secondary-text); line-height: 1.6; }

    a { color: var(--jz-primary); transition: color .18s ease, opacity .18s ease; }
    a:hover { color: #7dd8ff; }

    ::selection { background: rgba(8,168,255,.28); color: white; }

    ::-webkit-scrollbar { width: 10px; height: 10px; }
    ::-webkit-scrollbar-track { background: rgba(255,255,255,.02); }
    ::-webkit-scrollbar-thumb {
        background: rgba(148,163,184,.24);
        border-radius: 999px;
        border: 2px solid transparent;
        background-clip: padding-box;
    }
    ::-webkit-scrollbar-thumb:hover { background: rgba(8,168,255,.42); background-clip: padding-box; }

    .jz-shell .bg-neutral-800,
    .jz-shell .bg-neutral-900,
    .jz-shell .bg-gray-900 { background-color: transparent !important; }

    .jz-shell .shadow-lg,
    .jz-shell .shadow-md,
    .jz-shell .shadow-xl { box-shadow: var(--jz-shadow) !important; }

    .jz-shell .rounded,
    .jz-shell .rounded-lg,
    .jz-shell .rounded-md { border-radius: var(--jz-radius) !important; }

    .jz-shell input,
    .jz-shell textarea,
    .jz-shell select {
        background: rgba(10,17,28,.9) !important;
        border: 1px solid var(--jz-border) !important;
        color: var(--jz-text) !important;
        border-radius: 12px !important;
        transition: border-color .18s ease, box-shadow .18s ease, transform .18s ease;
    }

    .jz-shell input:focus,
    .jz-shell textarea:focus,
    .jz-shell select:focus {
        border-color: rgba(8,168,255,.7) !important;
        box-shadow: 0 0 0 4px rgba(8,168,255,.11) !important;
    }

    .jz-shell button {
        transition: transform .16s ease, box-shadow .2s ease, filter .2s ease;
    }
    .jz-shell button:not(:disabled):hover { transform: translateY(-1px); }
    .jz-shell button:not(:disabled):active { transform: translateY(0) scale(.98); }

    .jz-shell .fade-enter,
    .jz-shell .fade-appear { opacity: 0; transform: translateY(8px); }
    .jz-shell .fade-enter-active,
    .jz-shell .fade-appear-active {
        opacity: 1;
        transform: translateY(0);
        transition: opacity .22s ease, transform .22s ease;
    }

    .jz-shell .jz-card {
        background: linear-gradient(145deg, rgba(10,17,28,.96), rgba(7,13,21,.88));
        border: 1px solid var(--jz-border);
        box-shadow: var(--jz-shadow);
        border-radius: var(--jz-radius);
    }

    .jz-shell .jz-card:hover {
        background: linear-gradient(145deg, rgba(14,25,39,.98), rgba(8,16,27,.94));
        border-color: rgba(8,168,255,.22);
        transform: translateY(-2px);
    }

    .jz-shell .jz-page-title {
        font-size: clamp(1.55rem, 3vw, 2.15rem);
        margin-bottom: .35rem;
    }

    @media (max-width: 900px) {
        body.jz-shell #app,
        body.jz-shell.jz-sidebar-collapsed #app { padding-left: 0; }
    }


    body.jz-auth-shell {
        overflow-x: hidden;
        background:
            radial-gradient(circle at 50% 20%, rgba(8,168,255,.16), transparent 22rem),
            radial-gradient(circle at 15% 85%, rgba(0,109,255,.12), transparent 24rem),
            #05090F !important;
    }
    body.jz-auth-shell::before {
        content: "";
        position: fixed;
        inset: -20%;
        pointer-events: none;
        background-image: radial-gradient(rgba(255,255,255,.07) 1px, transparent 1px);
        background-size: 32px 32px;
        mask-image: linear-gradient(to bottom, black, transparent 80%);
        opacity: .24;
        animation: jz-drift 18s linear infinite;
    }
    .jz-auth-brand {
        display:flex;
        align-items:center;
        justify-content:center;
        gap:14px;
        margin:clamp(24px,8vh,72px) 0 18px;
        position:relative;
        z-index:1;
    }
    .jz-auth-brand img { width:68px; height:68px; object-fit:contain; filter:drop-shadow(0 8px 22px rgba(8,168,255,.22)); }
    .jz-auth-name { color:#fff; font-size:24px; font-weight:800; letter-spacing:-.04em; }
    .jz-auth-name span { color:#08A8FF; }
    .jz-auth-tagline { color:#64748B; font-size:12px; margin-top:2px; }
    .jz-auth-card {
        position:relative;
        z-index:1;
        padding:28px;
        border-radius:22px;
        background:linear-gradient(145deg,rgba(10,17,28,.94),rgba(7,13,21,.86));
        border:1px solid rgba(255,255,255,.08);
        box-shadow:0 28px 90px rgba(0,0,0,.46), 0 0 0 1px rgba(8,168,255,.025);
        backdrop-filter:blur(22px);
        animation:jz-auth-in .5s cubic-bezier(.2,.8,.2,1);
    }
    .jz-auth-heading { display:flex; gap:14px; align-items:center; margin-bottom:24px; }
    .jz-auth-emoji {
        width:50px; height:50px; flex:none; display:grid; place-items:center;
        border-radius:15px; background:rgba(8,168,255,.1); border:1px solid rgba(8,168,255,.18);
        font-size:25px;
    }
    .jz-auth-heading h1 { margin:0; color:#E6EDF5; font-size:25px; }
    .jz-auth-heading p { margin:3px 0 0; color:#94A3B8; font-size:13px; }
    .jz-auth-footer { position:relative; z-index:1; text-align:center; color:#475569; font-size:11px; margin:14px 0 28px; }
    @keyframes jz-drift { from { transform:translate3d(0,0,0); } to { transform:translate3d(32px,32px,0); } }
    @keyframes jz-auth-in { from { opacity:0; transform:translateY(14px) scale(.985); } to { opacity:1; transform:none; } }

    @media (prefers-reduced-motion: reduce) {
        *, *::before, *::after {
            scroll-behavior: auto !important;
            transition-duration: .01ms !important;
            animation-duration: .01ms !important;
            animation-iteration-count: 1 !important;
        }
    }
`;
