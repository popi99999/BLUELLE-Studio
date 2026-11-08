export const views = [
  { id: 'front', title: 'Fronte', hint: 'Inquadra il capo intero, lasciando un piccolo margine.' },
  { id: 'back', title: 'Retro', hint: 'Mantieni la stessa luce e la stessa distanza del fronte.' },
  { id: 'logo', title: 'Logo', hint: 'Tieni il telefono parallelo al logo. Evita lo zoom digitale.' },
  { id: 'label', title: 'Etichetta', hint: 'Stendi l’etichetta. Se il testo sfoca, allontana il telefono.' },
  { id: 'fabric', title: 'Tessuto', hint: 'Usa luce diffusa di lato per mostrare bene la trama.' },
  { id: 'flaw', title: 'Difetti', hint: 'Documenta usura e difetti con una foto ravvicinata.' }
];

export const neutral = () => ({ exposure: 0, temperature: 0, tint: 0, gains: [1, 1, 1] });
export const clamp = (value, low, high) => Math.min(high, Math.max(low, Number.isFinite(value) ? value : low));
const linear = x => x <= 0.04045 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4;
const srgb = x => x <= 0.0031308 ? x * 12.92 : 1.055 * x ** (1 / 2.4) - 0.055;

export function calibration(rgb) {
  if (rgb.some(x => !Number.isFinite(x) || x < 15 || x > 245)) {
    throw new Error('Scegli una zona grigia neutra, ben illuminata e senza riflessi.');
  }
  const channels = rgb.map(x => linear(x / 255));
  const middle = (channels[0] * channels[1] * channels[2]) ** (1 / 3);
  return channels.map(x => clamp(middle / x, 0.25, 4));
}

export function adjustPixels(data, settings) {
  const light = 2 ** clamp(settings.exposure, -2, 2);
  const temperature = clamp(settings.temperature, -60, 60) / 150;
  const tint = clamp(settings.tint, -40, 40) / 150;
  const gains = settings.gains || [1, 1, 1];
  const tables = gains.map((gain, channel) => {
    const warm = channel === 0 ? 1 + temperature : channel === 2 ? 1 - temperature : 1 - tint;
    return Uint8ClampedArray.from({ length: 256 }, (_, i) =>
      Math.round(clamp(srgb(linear(i / 255) * clamp(gain, 0.25, 4) * warm * light), 0, 1) * 255));
  });
  for (let i = 0; i < data.length; i += 4) {
    data[i] = tables[0][data[i]];
    data[i + 1] = tables[1][data[i + 1]];
    data[i + 2] = tables[2][data[i + 2]];
  }
  return data;
}

export function safeName(name) {
  return (name.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-zA-Z0-9_-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 65) || 'prodotto');
}

export function filename(product, photo, corrected = false) {
  const extension = corrected ? 'jpg' : (/\.([a-zA-Z0-9]{1,8})$/.exec(photo.name)?.[1] || (photo.type === 'image/png' ? 'png' : photo.type === 'image/heic' ? 'heic' : 'jpg'));
  return `${safeName(product.name)}_${photo.kind}_${photo.id.slice(0, 8)}${corrected ? '_corretta' : ''}.${extension}`;
}

export function mimeFor(file) {
  const extension = file.name.split('.').at(-1).toLowerCase();
  const known = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp', heic: 'image/heic', heif: 'image/heif', avif: 'image/avif', tif: 'image/tiff', tiff: 'image/tiff' };
  return known[extension] || file.type || 'application/octet-stream';
}

export function progress(photos) {
  return new Set(photos.filter(p => views.some(v => v.id === p.kind)).map(p => p.kind)).size;
}

export function nextView(photos) {
  return views.find(v => !photos.some(p => p.kind === v.id))?.id || 'front';
}
