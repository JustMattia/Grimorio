const fs = require('fs');
const path = require('path');

const dist = path.join(process.cwd(), 'dist');
if (!fs.existsSync(dist)) {
  fs.mkdirSync(dist, { recursive: true });
}

const filesToCopy = [
  'index.html',
  '_headers',
  'manifest.webmanifest',
  'sw.js',
  'favicon.ico',
  'favicon.png',
  'apple-touch-icon.png',
  'icon-192.png',
  'icon-512.png',
  'icon-maskable-512.png'
];

let copied = 0;
for (const file of filesToCopy) {
  if (fs.existsSync(file)) {
    fs.copyFileSync(file, path.join(dist, file));
    copied++;
  }
}

console.log(`✓ Cartella dist pronta! Copiati ${copied} file (inclusi manifest, Service Worker e icone PWA).`);

