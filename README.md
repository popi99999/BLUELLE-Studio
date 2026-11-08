# BLUELLE Studio

Fotocamera nativa per iPhone dedicata a prodotti moda: una serie coerente di foto del capo, del logo, delle etichette e dei dettagli.

**Prima versione da provare su un iPhone reale.** I controlli sul nucleo sono eseguibili sul Mac; la build iOS e le schermate del simulatore sono verificate dal workflow GitHub Actions. Un simulatore non può verificare messa a fuoco, colori o RAW di una fotocamera fisica. Non è stata misurata una percentuale di miglioramento rispetto a Fotocamera Apple.

<p>
  <img src="docs/screenshots/studio.png" width="230" alt="Schermata di scatto nel simulatore">
  <img src="docs/screenshots/controlli.png" width="230" alt="Controlli colore con anteprima">
  <img src="docs/screenshots/archivio.png" width="230" alt="Archivio dei prodotti">
</p>

Anteprime reali dal simulatore: il riquadro nero sostituisce la fotocamera fisica, senza simulare scatti. [Build e prova della navigazione superate](https://github.com/popi99999/BLUELLE-Studio/actions/runs/42519818265), insieme ai 15 controlli sul nucleo.

## Cosa include

- Obiettivo posteriore principale fisso a 1×, senza zoom digitale o passaggi automatici al macro.
- Fuoco al tocco, blocco del fuoco e dell’esposizione, compensazione EV.
- Blocco del bilanciamento del bianco, temperatura e tinta manuali, calibrazione con cartoncino grigio neutro. Anteprima dal vivo anche nei controlli.
- JPEG con priorità alla qualità e richiesta della massima dimensione ammessa dal formato attivo. La dimensione effettiva, che può essere inferiore, viene registrata per ogni scatto.
- JPEG + Bayer RAW (DNG) quando la configurazione del dispositivo lo supporta. La modalità RAW usa una priorità di acquisizione conservativa; il JPEG rimane elaborato dalla pipeline iOS.
- Timer 0/2/5 secondi; indicazioni basate su ISO, tempo, stato del fuoco e giroscopio. Sono avvisi sul rischio di mosso, **non punteggi di nitidezza**, misure di colore o garanzie di resa.
- Sessioni per prodotto con sei viste: fronte, retro, logo, etichetta, tessuto e difetti. Una vista già scattata può essere ripetuta.
- Archivio locale, visualizzazione con zoom, condivisione dei file originali e aggiunta volontaria a Foto.

Non applica ritocchi generativi, rimozione di difetti, saturazione automatica o ricostruzione dei loghi. I dati JPEG/DNG restituiti da AVFoundation vengono conservati senza ricodifica. Le anteprime nell’archivio sono ridotte solo per la visualizzazione.

## Aprire sull’iPhone

Richiede **iOS 17 o successivo**, un Mac con Xcode e un iPhone collegato. Nessuna libreria esterna è necessaria per l’app.

1. Scarica o clona il repository.
2. Apri `BluelleStudio.xcodeproj` in Xcode. Il progetto generato è già incluso.
3. In **Signing & Capabilities**, seleziona il tuo Team Apple; modifica l’identificatore del bundle se Xcode lo richiede.
4. Seleziona l’iPhone come destinazione ed esegui **Run**. Segui le eventuali richieste di iOS per l’esecuzione delle app di sviluppo.

GitHub contiene il codice sorgente: non è un link di installazione TestFlight o App Store. L’artefatto di CI è per il **simulatore**, non installabile su un telefono.

Per rigenerare il progetto dopo modifiche a `project.yml`:

```sh
brew install xcodegen
xcodegen generate
```

## Una sessione consigliata

1. Pulisci la lente, prepara luce diffusa e costante e crea il prodotto con `+`.
2. In **Controlli**, inquadra un cartoncino grigio neutro al centro per almeno metà fotogramma. Attendi che l’anteprima sia stabile, poi calibra e blocca. Senza cartoncino puoi bloccare il colore attuale, ma non verificarne la fedeltà.
3. Scatta il fronte. Mantieni la stessa luce per il retro e i dettagli.
4. Per le etichette, tieni telefono e tessuto paralleli, tocca il testo e aspetta il fuoco. Se sei troppo vicino, allontanati: il principale ha una distanza minima di messa a fuoco e non passa automaticamente al macro.
5. Controlla le foto ingrandite nell’archivio. Se necessario ripeti una vista. Usa un supporto e il timer quando il tempo è lento.
6. Esporta da Archivio. Il sistema di condivisione riceve i file integri; app di messaggistica o piattaforme esterne possono comprimerli successivamente.

La luce, il riferimento neutro, la distanza e la stabilità rimangono determinanti. Un DNG richiede sviluppo in un editor; non equivale a un JPEG già corretto.

## File e privacy

- Nessun server, login applicativo, analytics o invio automatico di immagini.
- Ogni prodotto ha una cartella UUID e un `product.json` nella directory Documenti dell’app, visibile in **File → Sul mio iPhone → BLUELLE Studio**.
- I file vengono scritti prima di aggiornare atomicamente il manifest. Una scrittura fallita non viene conteggiata come foto riuscita.
- Un manifest illeggibile viene segnalato senza nascondere gli altri prodotti. I relativi file restano sul dispositivo per il recupero.
- La fotocamera è l’unico accesso chiesto all’avvio. L’autorizzazione ad aggiungere a Foto viene chiesta solo premendo **Aggiungi a Foto**. L’app non legge la libreria Foto esistente.
- Non raccoglie la posizione. I normali backup e le funzioni di condivisione del sistema restano gestiti da iOS e dall’utente.
- Nessuna foto personale della libreria usata come riferimento è inclusa nel repository.

## Verifica

```sh
swift run StudioCoreChecks
```

Il runner senza dipendenze verifica limiti del bilanciamento, avvisi di acquisizione, round trip del manifest, byte degli originali conservati, coppia JPEG/RAW, errori di salvataggio e recupero di sessioni sane accanto a manifest danneggiati.

Con Xcode:

```sh
xcodebuild test -project BluelleStudio.xcodeproj -scheme BluelleStudio \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

Adatta il nome al simulatore installato. Il workflow `.github/workflows/ios.yml` sceglie automaticamente un iPhone disponibile, esegue lo smoke test dell’interfaccia e conserva app del simulatore, screenshot e risultato XCTest come artefatto. La modalità `--ui-testing` disabilita la fotocamera e non genera foto finte.

Per validare l’hardware, segui [la prova su iPhone](docs/device-validation.md).

## Riferimenti Apple

- [Priorità qualità foto](https://developer.apple.com/documentation/avfoundation/avcapturephotosettings/photoqualityprioritization).
- [Dimensioni massime e formato attivo](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/maxphotodimensions).
- [Cartoncino neutro e gray-world gains](https://developer.apple.com/documentation/avfoundation/avcapturedevice/grayworlddevicewhitebalancegains).
- [Limiti e completamento del blocco bilanciamento](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setwhitebalancemodelocked(with:completionhandler:)).

