export function BankIcon({ className = '' }: { className?: string }) {
  return <svg className={className} viewBox="0 0 40 40" fill="none" aria-hidden="true"><path d="M5 14 20 5l15 9H5Zm3 19h24M5 37h30M11 18v10m9-10v10m9-10v10" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" /></svg>;
}
export function Arrow({ diagonal = false }: { diagonal?: boolean }) {
  return <svg className="icon" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d={diagonal ? 'M6 18 18 6M6 6h12v12' : 'M4 12h15m-6-6 6 6-6 6'} stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" /></svg>;
}
export function LockIcon({ unlocked = false }: { unlocked?: boolean }) {
  return <svg className="icon" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d={unlocked ? 'M8 10V7a4 4 0 0 1 8 0' : 'M8 10V7a4 4 0 0 1 8 0v3'} stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" /><rect x="5" y="10" width="14" height="11" rx="2" stroke="currentColor" strokeWidth="1.8" /><path d="M12 14v3" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" /></svg>;
}
export function WalletIcon() {
  return <svg className="icon" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M19 7V4H5a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16V7H5a1 1 0 0 1 0-2" stroke="currentColor" strokeWidth="1.8" strokeLinejoin="round" /><path d="M21 11h-6v5h6m-3-2.5h-.1" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" /></svg>;
}

// Original code-native illustration: a banker's golden handcuffs, an open cuff and a BIC coin.
export function GoldenCuffs() {
  return <svg className="cuffs-art" viewBox="0 0 590 286" fill="none" aria-hidden="true">
    <defs>
      <linearGradient id="gold" x1="190" y1="25" x2="315" y2="238" gradientUnits="userSpaceOnUse"><stop stopColor="#f4df9e" /><stop offset=".3" stopColor="#d6ad56" /><stop offset=".5" stopColor="#f6e4b1" /><stop offset=".75" stopColor="#ad7933" /><stop offset="1" stopColor="#e1bb69" /></linearGradient>
      <linearGradient id="coin" x1="423" y1="167" x2="503" y2="235" gradientUnits="userSpaceOnUse"><stop stopColor="#f4df9e" /><stop offset="1" stopColor="#bd8b40" /></linearGradient>
      <pattern id="hatch" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(25)"><path d="M0 0v6" stroke="#8d652f" strokeWidth=".6" opacity=".24" /></pattern>
    </defs>
    <path d="M16 252h552" stroke="#d4c7a5" />
    <path d="M38 248c92-8 188-11 297-6 94 3 137-5 197 2" stroke="#d4c7a5" strokeWidth="2" />
    <g transform="translate(90 40) rotate(-21 95 95)">
      <path d="M169 103a72 72 0 1 1-142-16 72 72 0 0 1 142 16Z" fill="url(#gold)" stroke="#845a29" strokeWidth="2" />
      <path d="M157 102a59 59 0 1 1-117-13 59 59 0 0 1 117 13Z" fill="#f8f5eb" stroke="#845a29" strokeWidth="2" />
      <path d="M164 101a67 67 0 1 1-132-15 67 67 0 0 1 132 15Z" stroke="#fff1c5" strokeWidth="2" />
      <path d="M146 65 167 76 152 116 133 105Z" fill="url(#gold)" stroke="#845a29" strokeWidth="2" />
      <path d="M154 78 141 105M157 80l-13 28" stroke="#845a29" opacity=".6" />
      <path d="m172 88 23 9-5 17-25-7" fill="url(#gold)" stroke="#845a29" strokeWidth="2" />
      <circle cx="153" cy="94" r="3" fill="#845a29" />
      <path d="m148 95-2 5" stroke="#845a29" strokeWidth="2" />
      <path d="M58 135c20 25 57 27 81 7M57 139c20 25 57 27 81 7" stroke="#a27537" strokeWidth=".8" />
    </g>
    <g stroke="#845a29" strokeWidth="2">
      <path d="m267 110 20 5a9 9 0 0 1-4 17l-20-5a9 9 0 0 1 4-17Z" fill="url(#gold)" />
      <path d="m267 115 18 5a4 4 0 0 1-2 7l-18-5a4 4 0 0 1 2-7Z" fill="#f8f5eb" />
      <path d="m288 122 24 10a9 9 0 0 1-7 16l-24-10a9 9 0 0 1 7-16Z" fill="url(#gold)" />
      <path d="m288 127 20 9a4 4 0 0 1-3 7l-20-9a4 4 0 0 1 3-7Z" fill="#f8f5eb" />
    </g>
    <g transform="translate(265 76) rotate(24 92 88)">
      <path d="M62 14a74 74 0 1 0 94 93l-16-7a56 56 0 1 1-72-69Z" fill="url(#gold)" stroke="#845a29" strokeWidth="2" />
      <path d="M62 21a66 66 0 1 0 85 82" stroke="#fff1c5" strokeWidth="2" />
      <path d="m60 8 24 1 1 41-24 1Z" fill="url(#gold)" stroke="#845a29" strokeWidth="2" />
      <path d="M75 15v29m4-29v29" stroke="#845a29" opacity=".5" />
      <circle cx="69" cy="28" r="3" fill="#845a29" /><path d="M69 29v7" stroke="#845a29" strokeWidth="2" />
      <path d="M143 105c15-28 35-53 61-66l5 10c-23 14-40 35-53 62Z" fill="url(#gold)" stroke="#845a29" strokeWidth="2" />
      <path d="m154 96 7 4m-2-12 8 4m-2-13 8 5m-1-13 7 5m1-12 7 5m2-12 7 5m3-11 6 4" stroke="#845a29" strokeWidth="1.5" />
      <path d="M70 146c17 7 33 5 48-1M69 150c17 7 33 5 48-1" stroke="#a27537" strokeWidth=".8" />
    </g>
    <g transform="translate(438 184) rotate(-12)">
      <ellipse cx="31" cy="34" rx="41" ry="38" fill="#a87935" stroke="#845a29" strokeWidth="2" />
      <circle cx="28" cy="28" r="40" fill="url(#coin)" stroke="#845a29" strokeWidth="2" />
      <circle cx="28" cy="28" r="34" stroke="#845a29" strokeWidth="1" strokeDasharray="1 3" />
      <circle cx="28" cy="28" r="30" stroke="#fff1c5" />
      <path d="m11 18 17-9 17 9H11Zm3 24h28M11 46h34M18 22v15m10-15v15m10-15v15" stroke="#845a29" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </g>
    <g stroke="#9b752e" strokeWidth="1.5" strokeLinecap="round"><path d="M480 63v16m-8-8h16M80 177v12m-6-6h12M382 20v10m-5-5h10" /><path d="m218 211 3 3m0-3-3 3" /></g>
    <path d="M25 248 47 232m-12 16 17-13m471 13 17-12m-7 12 9-7" stroke="#d4c7a5" />
  </svg>;
}
