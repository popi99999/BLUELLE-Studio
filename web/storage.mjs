let database;

export function openLibrary() {
  if (database) return Promise.resolve(database);
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('bluelle-studio-web', 1);
    request.onupgradeneeded = () => {
      const db = request.result;
      db.createObjectStore('products', { keyPath: 'id' });
      const photos = db.createObjectStore('photos', { keyPath: 'id' });
      photos.createIndex('productID', 'productID', { unique: false });
    };
    request.onsuccess = () => {
      database = request.result;
      database.onversionchange = () => { database.close(); database = null; };
      resolve(database);
    };
    request.onerror = () => reject(request.error);
    request.onblocked = () => reject(new Error('Chiudi le altre schede dello studio e riapri questa pagina.'));
  });
}

async function transaction(stores, mode, action) {
  const db = await openLibrary();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(stores, mode);
    let result;
    tx.oncomplete = () => resolve(result);
    tx.onerror = () => reject(tx.error || new Error('Archivio non disponibile.'));
    tx.onabort = () => reject(tx.error || new Error('Salvataggio interrotto. Il file non è stato aggiunto.'));
    try { action(tx, value => { result = value; }); }
    catch (error) { tx.abort(); reject(error); }
  });
}

export const products = () => transaction(['products'], 'readonly', (tx, done) => {
  tx.objectStore('products').getAll().onsuccess = event => done(event.target.result.sort((a, b) => b.createdAt - a.createdAt));
});
export const photos = productID => transaction(['photos'], 'readonly', (tx, done) => {
  tx.objectStore('photos').index('productID').getAll(productID).onsuccess = event => done(event.target.result.sort((a, b) => a.createdAt - b.createdAt));
});
export const putProduct = product => transaction(['products'], 'readwrite', tx => tx.objectStore('products').put(product));
export const putPhoto = photo => transaction(['products', 'photos'], 'readwrite', tx => {
  tx.objectStore('products').get(photo.productID).onsuccess = event => {
    if (!event.target.result) { tx.abort(); return; }
    tx.objectStore('photos').put(photo);
  };
});
export const deletePhoto = id => transaction(['photos'], 'readwrite', tx => tx.objectStore('photos').delete(id));
export const deleteProduct = id => transaction(['products', 'photos'], 'readwrite', tx => {
  tx.objectStore('products').delete(id);
  tx.objectStore('photos').index('productID').openKeyCursor(id).onsuccess = event => {
    const cursor = event.target.result;
    if (cursor) { tx.objectStore('photos').delete(cursor.primaryKey); cursor.continue(); }
  };
});
