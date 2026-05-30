// Generates Android notification small icons (white silhouette) from logo
// Run: node resources/gen-notification-icons.js
const sharp = require('sharp');
const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, 'icon.png');
const ANDROID_RES = path.join(__dirname, '..', 'android', 'app', 'src', 'main', 'res');

const SIZES = {
  'drawable-mdpi':    24,
  'drawable-hdpi':    36,
  'drawable-xhdpi':   48,
  'drawable-xxhdpi':  72,
  'drawable-xxxhdpi': 96,
};

(async () => {
  // Read source image (logo with transparent or white BG)
  const src = sharp(SRC);

  for (const [dir, size] of Object.entries(SIZES)) {
    const outDir = path.join(ANDROID_RES, dir);
    fs.mkdirSync(outDir, { recursive: true });
    const outPath = path.join(outDir, 'ic_stat_drilex.png');

    // Strategy:
    // 1. Resize logo to target size
    // 2. Extract alpha channel (silhouette)
    // 3. Use alpha as the new image's RGB+alpha (white pixels, alpha = original alpha)
    await src
      .clone()
      .resize(size, size, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
      .threshold(128)   // make pure black/white based on luminance
      .negate({ alpha: false })   // invert: dark logo becomes white, white BG becomes black
      .ensureAlpha()
      .composite([{
        input: Buffer.from([255, 255, 255, 255]),  // white pixel
        raw: { width: 1, height: 1, channels: 4 },
        tile: true,
        blend: 'in',     // intersect: keep only where current image is non-transparent
      }])
      .png()
      .toFile(outPath);

    console.log(`✓ ${dir}/ic_stat_drilex.png (${size}×${size})`);
  }
  console.log('Done.');
})().catch(e => { console.error(e); process.exit(1); });
