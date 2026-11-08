import { test } from 'node:test';
import assert from 'node:assert/strict';
import { calibration, adjustPixels, neutral, safeName, filename, mimeFor, progress, nextView } from '../core.mjs';

test('neutral correction preserves every channel and alpha', () => {
  const pixels = Uint8ClampedArray.from([0, 25, 200, 128, 255, 64, 180, 255]);
  assert.deepEqual(adjustPixels(pixels.slice(), neutral()), pixels);
});
test('exposure acts in linear light and preserves alpha', () => {
  const out = adjustPixels(Uint8ClampedArray.from([100, 100, 100, 123]), { ...neutral(), exposure: 1 });
  assert.ok(out[0] > 130 && out[0] < 145);
  assert.equal(out[3], 123);
});
test('grey reference correction neutralizes a color cast', () => {
  const rgb = [160, 130, 100];
  const out = adjustPixels(Uint8ClampedArray.from([...rgb, 255]), { ...neutral(), gains: calibration(rgb) });
  assert.ok(Math.max(...out.slice(0, 3)) - Math.min(...out.slice(0, 3)) <= 1);
});
test('clipped or very dark reference is rejected', () => {
  for (const rgb of [[255, 200, 100], [5, 5, 5], [NaN, 100, 100]]) assert.throws(() => calibration(rgb));
});
test('warm correction increases red relative to blue', () => {
  const out = adjustPixels(Uint8ClampedArray.from([100, 100, 100, 255]), { ...neutral(), temperature: 50 });
  assert.ok(out[0] > out[2]);
});
test('file exports cannot introduce a path and retain original extension', () => {
  assert.equal(safeName('../../Céline / bianca'), 'Celine-bianca');
  const photo = { id: '12345678-abcd', kind: 'label', name: 'IMG_001.HEIC', type: 'image/heic' };
  assert.equal(filename({ name: 'Gucci' }, photo), 'Gucci_label_12345678.HEIC');
  assert.equal(filename({ name: 'Gucci' }, photo, true), 'Gucci_label_12345678_corretta.jpg');
});
test('repeated photos do not inflate product coverage', () => {
  const photos = [{ kind: 'front' }, { kind: 'front' }, { kind: 'label' }];
  assert.equal(progress(photos), 2);
  assert.equal(nextView(photos), 'back');
});
test('HEIC is not relabelled as JPEG when Safari supplies no MIME type', () => {
  assert.equal(mimeFor({ name: 'IMG_002.HEIC', type: '' }), 'image/heic');
  assert.equal(mimeFor({ name: 'image.png', type: '' }), 'image/png');
});
