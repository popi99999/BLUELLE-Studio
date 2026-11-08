import { views, neutral, calibration, adjustPixels, filename, mimeFor, progress, nextView } from './core.mjs';
import * as library from './storage.mjs';

const $ = id => document.getElementById(id);
const state = { product: null, photos: [], photo: null, image: null, kind: 'front', settings: neutral(), picking: false, usePreset: false, busy: false, revision: 0, urls: [] };
const canvas = $('preview');
const context = canvas.getContext('2d', { willReadFrequently: true });
let toastTimer, renderFrame, originalPixels;

function toast(message) {
  clearTimeout(toastTimer);
  $('toast').textContent = message;
  $('toast').hidden = false;
  toastTimer = setTimeout(() => { $('toast').hidden = true; }, 6500);
}
function report(error) {
  console.error(error);
  toast(error.name === 'QuotaExceededError' ? 'Spazio insufficiente. Esporta alcune foto e libera spazio prima di riprovare.' : error.message || 'Operazione non riuscita. Riprova.');
}
function busy(value) {
  state.busy = value;
  document.body.classList.toggle('busy', value);
  for (const id of ['capture', 'import', 'new-product', 'open-archive', 'start-product']) $(id).disabled = value;
}
function dialog(id) { $(id).showModal(); }
function needProduct() {
  if (state.product) return true;
  dialog('product-dialog');
  return false;
}
function button(text, className, action) {
  const element = document.createElement('button');
  element.type = 'button'; element.textContent = text; element.className = className;
  element.addEventListener('click', action);
  return element;
}
function releaseURLs() { state.urls.forEach(URL.revokeObjectURL); state.urls = []; }

function renderViews() {
  $('shot-kinds').replaceChildren(...views.map(view => {
    const done = state.photos.some(p => p.kind === view.id);
    const item = button(view.title, `${view.id === state.kind ? 'active' : ''} ${done ? 'done' : ''}`, () => { state.kind = view.id; renderViews(); });
    item.setAttribute('aria-pressed', String(view.id === state.kind));
    return item;
  }));
  $('shot-hint').textContent = views.find(v => v.id === state.kind).hint;
  $('coverage').textContent = `${progress(state.photos)} / 6 viste`;
}

function renderFilmstrip() {
  releaseURLs();
  $('filmstrip').replaceChildren(...state.photos.map(photo => {
    const item = button('', photo.id === state.photo?.id ? 'selected' : '', () => selectPhoto(photo.id).catch(report));
    item.setAttribute('aria-label', `${views.find(v => v.id === photo.kind)?.title || 'Foto'}: ${photo.name}`);
    const thumb = document.createElement('img');
    const url = URL.createObjectURL(photo.thumbnail || photo.blob); state.urls.push(url);
    thumb.src = url; thumb.alt = ''; thumb.loading = 'lazy';
    const label = document.createElement('span'); label.textContent = views.find(v => v.id === photo.kind)?.title || 'Foto';
    item.append(thumb, label); return item;
  }));
}

function setEditable(enabled) {
  $('edit-controls').disabled = !state.photo;
  for (const id of ['exposure', 'temperature', 'tint', 'pick-neutral', 'reset', 'export-edited', 'use-preset']) $(id).disabled = !enabled;
  $('edit-empty').hidden = Boolean(state.photo);
  $('photo-tag-row').hidden = !state.photo;
  if (state.photo) $('photo-tag').value = state.photo.kind;
}

function syncSliders() {
  for (const key of ['exposure', 'temperature', 'tint']) {
    $(key).value = state.settings[key];
    $(`${key}-value`).textContent = key === 'exposure' ? `${Number(state.settings[key]).toFixed(2)} EV` : state.settings[key];
  }
  $('use-preset').checked = state.usePreset;
  $('preset-status').hidden = !state.product?.preset || state.usePreset;
  $('preset-status').textContent = 'La sessione usa altre regolazioni salvate. Spunta per sostituirle con quelle di questa foto.';
  $('clear-preset').hidden = !state.product?.preset;
}

function drawPreview() {
  if (!state.image || !originalPixels) return;
  const pixels = new ImageData(new Uint8ClampedArray(originalPixels.data), originalPixels.width, originalPixels.height);
  adjustPixels(pixels.data, state.settings);
  context.putImageData(pixels, 0, 0);
}

function loadImage(blob) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    const url = URL.createObjectURL(blob);
    image.onload = () => { URL.revokeObjectURL(url); resolve(image); };
    image.onerror = () => { URL.revokeObjectURL(url); reject(new Error('Questo browser non visualizza il formato della foto. Puoi comunque esportare il file ricevuto.')); };
    image.src = url;
  });
}

async function selectPhoto(id) {
  const revision = ++state.revision;
  state.photo = state.photos.find(photo => photo.id === id) || null;
  state.image = null; originalPixels = null; state.picking = false;
  $('viewfinder').classList.remove('picking'); $('pick-neutral').classList.remove('active');
  $('empty-frame').hidden = Boolean(state.photo);
  canvas.hidden = true;
  renderFilmstrip(); setEditable(false);
  if (!state.photo) {
    $('photo-kind').textContent = 'Studio fotografico'; $('photo-format').textContent = 'iPhone / web';
    $('dimensions').textContent = 'File alla risoluzione ricevuta';
    $('empty-frame').querySelector('h2').innerHTML = 'Il tuo prodotto.<br>La sua luce.';
    $('empty-frame').querySelector('p').innerHTML = 'Scatta con l’iPhone o importa una foto.<br>Cominciamo dal fronte.';
    $('start-product').hidden = Boolean(state.product);
    return;
  }
  const photo = state.photo;
  state.settings = structuredClone(photo.settings || neutral());
  state.usePreset = Boolean(state.product.preset && JSON.stringify(state.product.preset) === JSON.stringify(state.settings));
  syncSliders();
  $('photo-kind').textContent = views.find(view => view.id === photo.kind)?.title || 'Foto';
  $('photo-format').textContent = photo.type.split('/')[1]?.toUpperCase() || 'FOTO';
  $('dimensions').textContent = photo.width ? `${photo.width} × ${photo.height} · ${(photo.blob.size / 1e6).toFixed(1)} MB` : `${(photo.blob.size / 1e6).toFixed(1)} MB`;
  try {
    const image = await loadImage(photo.blob);
    if (revision !== state.revision) return;
    state.image = image;
    const scale = Math.min(1, 1400 / Math.max(image.naturalWidth, image.naturalHeight));
    canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
    canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
    context.fillStyle = '#fff'; context.fillRect(0, 0, canvas.width, canvas.height);
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    originalPixels = context.getImageData(0, 0, canvas.width, canvas.height);
    canvas.hidden = false; setEditable(true); drawPreview();
  } catch (error) {
    if (revision !== state.revision) return;
    $('empty-frame').hidden = false;
    $('empty-frame').querySelector('h2').textContent = 'Anteprima non disponibile';
    $('empty-frame').querySelector('p').textContent = 'Esporta il file ricevuto per aprirlo sul tuo dispositivo.';
    $('start-product').hidden = true;
    report(error);
  }
}

async function openProduct(product) {
  state.revision++;
  state.product = product;
  state.photos = await library.photos(product.id);
  state.kind = nextView(state.photos);
  $('product-title').textContent = product.name;
  try { localStorage.setItem('bluelle-current-product', product.id); } catch {}
  renderViews();
  await selectPhoto(state.photos.at(-1)?.id);
}

async function saveSettings() {
  if (!state.photo) return;
  state.photo.settings = structuredClone(state.settings);
  await library.putPhoto(state.photo);
  if (state.usePreset) {
    state.product.preset = structuredClone(state.settings);
    await library.putProduct(state.product);
  }
}

function toBlob(target, type = 'image/jpeg', quality = 0.95) {
  return new Promise((resolve, reject) => target.toBlob(blob => blob ? resolve(blob) : reject(new Error('Il browser non riesce a esportare questa dimensione. Salva il file ricevuto.')), type, quality));
}

async function importFiles(files) {
  if (!files.length || !state.product || state.busy) return;
  busy(true);
  const productID = state.product.id, kind = state.kind;
  let saved = 0, lastID;
  try {
    for (const file of files) {
      if (!/^image\/(jpeg|png|webp|heic|heif|avif|tiff)$/i.test(file.type) && !/\.(jpe?g|png|webp|hei[cf]|avif|tiff?)$/i.test(file.name)) {
        throw new Error('Scegli foto JPEG, HEIC, PNG, WebP, AVIF o TIFF.');
      }
      let width = 0, height = 0, thumbnail = null;
      try {
        const image = await loadImage(file);
        width = image.naturalWidth; height = image.naturalHeight;
        const small = document.createElement('canvas');
        const scale = Math.min(1, 240 / Math.max(width, height));
        small.width = Math.max(1, Math.round(width * scale)); small.height = Math.max(1, Math.round(height * scale));
        const thumbContext = small.getContext('2d');
        thumbContext.fillStyle = '#fff'; thumbContext.fillRect(0, 0, small.width, small.height);
        thumbContext.drawImage(image, 0, 0, small.width, small.height);
        thumbnail = await toBlob(small, 'image/jpeg', 0.75);
        small.width = small.height = 1;
      } catch { /* Keep the received file even if this browser cannot decode it. */ }
      const photo = { id: crypto.randomUUID(), productID, kind, name: file.name, type: mimeFor(file), blob: file, thumbnail, width, height, createdAt: Date.now(), settings: structuredClone(state.product.preset || neutral()) };
      await library.putPhoto(photo);
      state.photos.push(photo); saved++; lastID = photo.id;
    }
    state.kind = nextView(state.photos);
    toast(saved === 1 ? 'Foto salvata sul dispositivo.' : `${saved} foto salvate nella vista ${views.find(v => v.id === kind).title}.`);
  } catch (error) { report(error); }
  finally {
    busy(false); renderViews();
    if (lastID) await selectPhoto(lastID);
  }
}

async function exportBlob(blob, name) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a'); link.href = url; link.download = name;
  document.body.append(link); link.click(); link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60000);
  toast('Se si apre l’immagine, usa Condividi → Salva in File per conservarla.');
}

async function exportEdited() {
  if (!state.photo || !state.image || state.busy) return;
  busy(true);
  const image = state.image, settings = structuredClone(state.settings), photo = state.photo, product = state.product;
  let full;
  try {
    full = document.createElement('canvas');
    full.width = image.naturalWidth; full.height = image.naturalHeight;
    const ctx = full.getContext('2d', { willReadFrequently: true });
    if (!ctx) throw new Error('Memoria insufficiente per questa foto. Esporta il file ricevuto.');
    ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, full.width, full.height);
    ctx.drawImage(image, 0, 0);
    const pixels = ctx.getImageData(0, 0, full.width, full.height);
    adjustPixels(pixels.data, settings); ctx.putImageData(pixels, 0, 0);
    const blob = await toBlob(full);
    await exportBlob(blob, filename(product, photo, true));
  } catch (error) { report(error); }
  finally { if (full) full.width = full.height = 1; busy(false); }
}

async function renderArchive() {
  const products = await library.products();
  const items = [];
  for (const product of products) {
    const photos = await library.photos(product.id);
    const card = document.createElement('div'); card.className = 'product-card';
    const open = button('', 'product-open', () => { $('archive-dialog').close(); openProduct(product).catch(report); });
    const name = document.createElement('strong'); name.textContent = product.name;
    const detail = document.createElement('small'); detail.textContent = `${photos.length} foto · ${progress(photos)} / 6 viste`;
    open.append(name, detail);
    const remove = button('×', 'product-delete', async () => {
      if (!confirm(`Eliminare “${product.name}” e le sue foto dall’archivio locale? Esporta prima i file da conservare.`)) return;
      try {
        await library.deleteProduct(product.id);
        if (state.product?.id === product.id) {
          state.product = null; state.photos = []; $('product-title').textContent = 'Ogni dettaglio conta.'; renderViews(); await selectPhoto(null);
        }
        await renderArchive();
      } catch (error) { report(error); }
    });
    remove.setAttribute('aria-label', `Elimina prodotto ${product.name}`);
    card.append(open, remove); items.push(card);
  }
  if (!items.length) {
    const empty = document.createElement('p'); empty.className = 'empty-library'; empty.textContent = 'Il prossimo prodotto può essere il primo. Crea una sessione per cominciare.'; items.push(empty);
  }
  $('products-list').replaceChildren(...items);
}

$('new-product').onclick = $('start-product').onclick = () => dialog('product-dialog');
$('photo-tag').replaceChildren(...views.map(view => { const option = document.createElement('option'); option.value = view.id; option.textContent = view.title; return option; }));
$('photo-tag').onchange = async () => {
  if (!state.photo) return;
  const previous = state.photo.kind;
  state.photo.kind = $('photo-tag').value;
  try {
    await library.putPhoto(state.photo);
    $('photo-kind').textContent = views.find(view => view.id === state.photo.kind).title;
    renderViews(); renderFilmstrip();
  } catch (error) { state.photo.kind = previous; $('photo-tag').value = previous; report(error); }
};
$('archive-new').onclick = () => { $('archive-dialog').close(); dialog('product-dialog'); };
document.querySelectorAll('[data-close]').forEach(element => element.onclick = () => $(element.dataset.close).close());
$('help').onclick = $('install').onclick = () => dialog('help-dialog');
$('open-archive').onclick = async () => { try { await renderArchive(); dialog('archive-dialog'); } catch (error) { report(error); } };
$('capture').onclick = () => { if (needProduct()) $('camera-input').click(); };
$('import').onclick = () => { if (needProduct()) $('import-input').click(); };
for (const id of ['camera-input', 'import-input']) $(id).onchange = async event => {
  const files = Array.from(event.target.files || []); event.target.value = '';
  try { await importFiles(files); } catch (error) { report(error); }
};
$('product-form').onsubmit = async event => {
  event.preventDefault();
  const name = $('product-name').value.trim(); if (!name) return;
  const submit = event.submitter; submit.disabled = true;
  try {
    const product = { id: crypto.randomUUID(), name, createdAt: Date.now(), preset: null };
    await library.putProduct(product); await openProduct(product);
    $('product-dialog').close(); $('product-form').reset(); toast('Sessione creata. Tocca il pulsante centrale per scattare.');
  } catch (error) { report(error); }
  finally { submit.disabled = false; }
};
for (const key of ['exposure', 'temperature', 'tint']) {
  $(key).oninput = () => {
    state.settings[key] = Number($(key).value); syncSliders();
    cancelAnimationFrame(renderFrame); renderFrame = requestAnimationFrame(drawPreview);
  };
  $(key).onchange = () => saveSettings().catch(report);
}
$('reset').onclick = async () => {
  state.settings = neutral(); syncSliders(); drawPreview();
  try { await saveSettings(); toast('Regolazioni ripristinate.'); } catch (error) { report(error); }
};
$('use-preset').onchange = async () => {
  state.usePreset = $('use-preset').checked;
  state.product.preset = state.usePreset ? structuredClone(state.settings) : null;
  try { await library.putProduct(state.product); syncSliders(); } catch (error) { report(error); }
};
$('clear-preset').onclick = async () => {
  state.product.preset = null; state.usePreset = false;
  try { await library.putProduct(state.product); syncSliders(); } catch (error) { report(error); }
};
$('pick-neutral').onclick = () => {
  state.picking = !state.picking;
  $('viewfinder').classList.toggle('picking', state.picking); $('pick-neutral').classList.toggle('active', state.picking);
  $('reference-hint').textContent = state.picking ? 'Tocca nella foto il cartoncino grigio neutro, evitando riflessi e ombre.' : 'Usa un cartoncino grigio fotografato sotto la stessa luce.';
  if (state.picking) $('viewfinder').scrollIntoView({ block: 'center', behavior: 'smooth' });
};
canvas.onclick = async event => {
  if (!state.picking || !originalPixels) return;
  const bounds = canvas.getBoundingClientRect();
  const scale = Math.min(bounds.width / canvas.width, bounds.height / canvas.height);
  const x = Math.round((event.clientX - bounds.left - (bounds.width - canvas.width * scale) / 2) / scale);
  const y = Math.round((event.clientY - bounds.top - (bounds.height - canvas.height * scale) / 2) / scale);
  if (x < 0 || y < 0 || x >= canvas.width || y >= canvas.height) return;
  const rgb = [0, 0, 0]; let count = 0;
  for (let py = Math.max(0, y - 4); py <= Math.min(canvas.height - 1, y + 4); py++) {
    for (let px = Math.max(0, x - 4); px <= Math.min(canvas.width - 1, x + 4); px++) {
      const offset = (py * canvas.width + px) * 4;
      for (let channel = 0; channel < 3; channel++) rgb[channel] += originalPixels.data[offset + channel];
      count++;
    }
  }
  try {
    state.settings.gains = calibration(rgb.map(value => value / count));
    state.settings.temperature = 0; state.settings.tint = 0;
    state.picking = false; $('viewfinder').classList.remove('picking'); $('pick-neutral').classList.remove('active');
    syncSliders(); drawPreview(); await saveSettings(); toast('Riferimento applicato alla foto. Il file ricevuto resta invariato.');
  } catch (error) { report(error); }
};
$('toggle-grid').onclick = () => { $('grid').hidden = !$('grid').hidden; };
$('export-original').onclick = () => { if (state.photo) exportBlob(state.photo.blob, filename(state.product, state.photo)).catch(report); };
$('export-edited').onclick = () => exportEdited();
$('delete-photo').onclick = async () => {
  if (!state.photo || !confirm('Eliminare questo scatto dall’archivio locale?')) return;
  try {
    const id = state.photo.id; await library.deletePhoto(id);
    state.photos = state.photos.filter(photo => photo.id !== id); renderViews(); await selectPhoto(state.photos.at(-1)?.id);
    toast('Scatto eliminato.');
  } catch (error) { report(error); }
};
$('persist-storage').onclick = async () => {
  try {
    const persisted = await navigator.storage?.persist?.();
    $('storage-status').textContent = persisted ? 'Il browser ha concesso l’archiviazione persistente. Esporta comunque una copia dei file importanti.' : 'Il browser decide autonomamente la conservazione. Esporta regolarmente una copia delle foto.';
  } catch { $('storage-status').textContent = 'Richiesta non disponibile. Esporta le foto da conservare.'; }
};

async function start() {
  renderViews();
  try {
    await library.openLibrary();
    const products = await library.products();
    let id; try { id = localStorage.getItem('bluelle-current-product'); } catch {}
    const current = products.find(product => product.id === id) || products[0];
    if (current) await openProduct(current);
  } catch (error) { report(new Error(`Archivio non disponibile: ${error.message}. Evita la navigazione privata e riprova.`)); }
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('./sw.js').catch(() => { toast('Modalità offline non disponibile in questa sessione.'); });
}
start();
