# Prova su iPhone

La build del simulatore verifica il codice e la navigazione. Per considerare pronta la fotocamera occorre completare questa prova su un telefono fisico. Nessun risultato è presunto.

Registra modello iPhone, versione iOS, formato attivo, risoluzione effettiva e disponibilità RAW. Confronta gli originali, non screenshot o anteprime iCloud.

1. **Permessi:** primo avvio con accesso fotocamera consentito; ripeti con accesso negato e ritorno da Impostazioni. Nessuna richiesta di leggere la libreria Foto. L’aggiunta a Foto avviene soltanto con il comando esplicito.
2. **Colore:** sotto luce costante, calibra con riferimento neutro. Scatta alternativamente un capo chiaro e uno scuro; verifica che il blocco rimanga attivo e osserva il riferimento nei file. Non dedurre un errore cromatico numerico senza una procedura di misura.
3. **Controlli:** imposta temperatura/tinta/EV, chiudi e riapri Controlli; verifica che i valori visualizzati corrispondano a quelli del dispositivo. Cambia tinta senza perdere la temperatura. Ritorna ad automatico.
4. **Assestamento:** con timer spento, tenta lo scatto immediatamente dopo la calibrazione. Il servizio deve attendere la conclusione del cambio colore o segnalare che è ancora in corso, senza salvare come riuscita una richiesta respinta.
5. **Dettagli:** fotografa un’etichetta piana a distanze diverse; conferma il fuoco al tocco, il blocco e il comportamento sotto la distanza minima. Nessun cambio automatico al grandangolo/macro.
6. **File:** acquisisci JPEG e, quando disponibile, JPEG + DNG. Riavvia l’app, verifica dimensioni effettive, presenza dei file, apertura del DNG in un editor e possibilità di esportare entrambi. Controlla che il servizio ricevente non comprima il confronto.
7. **Ciclo di vita:** passa in background durante il timer, ritorna e ripeti. Interrompi durante scatto/elaborazione, torna e verifica che né la foto né il blocco del pulsante restino sospesi. Prova anche un’interruzione di sistema della fotocamera.
8. **Archivio:** crea almeno due prodotti, ripeti una vista e cambia sessione. Verifica la persistenza dopo chiusura. Con un archivio di prova, rendi illeggibile un solo manifest: gli altri prodotti devono rimanere visibili e l’app deve segnalarlo.
9. **Resa:** con supporto, stessa luce e stessa inquadratura, confronta l’app con Fotocamera Apple su tessuti scuri, capi bianchi, logo e cartoncino neutro. Valuta il dettaglio degli originali alla stessa scala. Documenta eventuali regressioni prima di affermare un miglioramento.

Firma, distribuzione TestFlight/App Store e questa validazione hardware sono passaggi separati dalla pubblicazione del codice su GitHub.
