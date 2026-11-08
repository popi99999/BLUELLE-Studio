import SwiftUI

struct CameraControls: View {
    @ObservedObject var camera: CameraService
    @Environment(\.dismiss) private var dismiss
    @State private var kelvin: Double = 5200
    @State private var tint: Double = 0
    @State private var bias: Double = 0
    @State private var iso: Double = 100
    @State private var shutterPosition: Double = 0.5
    @State private var lens: Double = 0.5
    @State private var calibrate = false
    @AppStorage("captureRAW") private var captureRAW = false
    @AppStorage("showPeaking") private var peaking = false

    private var limits: CameraLimits { camera.limits }
    private var manualExposure: Bool { camera.exposureState == .manual }
    private var manualFocus: Bool { camera.focusState == .manual }
    private var shutterSeconds: Double {
        ExposureScale.seconds(at: shutterPosition, minimum: limits.minSeconds, maximum: limits.maxSeconds)
    }
    private var isoRange: ClosedRange<Double> {
        let lower = Double(limits.minISO)
        return lower...max(lower + 1, Double(limits.maxISO))
    }
    private var biasRange: ClosedRange<Double> {
        let lower = max(-3, Double(limits.minBias)), upper = min(3, Double(limits.maxBias))
        return lower < upper ? lower...upper : -2...2
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Obiettivo principale fisso · 1×", systemImage: "camera.aperture")
                    Text("Evita cambi automatici di obiettivo durante la serie. Per avvicinarti a un’etichetta, sposta il telefono: se non mette a fuoco, allontanati.")
                        .font(.caption).foregroundStyle(.secondary)
                    if limits.minimumFocusDistance > 0 {
                        Text("Distanza minima di messa a fuoco su questo iPhone: circa \(Int((Double(limits.minimumFocusDistance) / 10).rounded())) cm.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("Una serie coerente") }

                Section {
                    HStack {
                        Text("Bilanciamento del bianco")
                        Spacer()
                        Text(camera.whiteBalanceLocked ? "BLOCCATO" : "AUTO")
                            .font(.caption2.weight(.semibold)).foregroundStyle(StudioTheme.accent)
                    }
                    Button("Blocca il colore attuale", systemImage: "lock") { camera.lockWhiteBalance() }
                        .disabled(!camera.ready)
                    Button("Calibra con cartoncino grigio", systemImage: "square.dashed") { calibrate = true }
                        .disabled(!camera.ready)
                    Button("Torna al colore automatico") { camera.autoWhiteBalance() }.disabled(!camera.ready)
                    Text("Il blocco mantiene lo stesso bilanciamento tra le foto. Non certifica il colore reale: per calibrarlo serve un riferimento neutro e luce costante.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Colore") }

                Section {
                    HStack { Text("Temperatura"); Spacer(); Text("\(Int(kelvin)) K").monospacedDigit() }
                    Slider(value: $kelvin, in: 2500...9000, step: 50, onEditingChanged: { editing in if !editing { applyTemperature() } })
                        .accessibilityLabel("Temperatura colore")
                    HStack { Text("Tinta verde / magenta"); Spacer(); Text("\(Int(tint))").monospacedDigit() }
                    Slider(value: $tint, in: -100...100, step: 1, onEditingChanged: { editing in if !editing { applyTemperature() } })
                        .accessibilityLabel("Tinta colore")
                    Text("Questi valori si applicano quando rilasci il cursore e attivano il blocco colore. Restano soggetti ai limiti della fotocamera.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Regolazione manuale") }
                    .disabled(!camera.ready)

                exposureSection
                focusSection

                Section {
                    Toggle(camera.rawKind == .proRAW ? "Conserva anche Apple ProRAW (DNG)" : "Conserva anche RAW (DNG)", isOn: $captureRAW)
                        .disabled(!camera.rawAvailable)
                        .accessibilityIdentifier("rawToggle")
                    Text(rawDescription).font(.caption).foregroundStyle(.secondary)
                    Text("JPEG alla massima risoluzione del sensore (\(camera.resolution)), qualità 95 %, con la massima elaborazione di dettaglio di iOS. I file non vengono ridimensionati né ritoccati dall’app.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("File originali") }

                Section {
                    Text("Luce diffusa, una sola temperatura di luce, lente pulita e telefono parallelo al prodotto: la livella diventa verde quando sei dritto. Con il treppiede usa il timer o i tasti volume come scatto.")
                    Text("Nessun punteggio di nitidezza o fedeltà colore: ISO, tempo, giroscopio e istogramma sono indizi, non una misura della foto finale.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Prima di scattare") }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                CameraPreview(session: camera.session, onFocus: { camera.focus(at: $0) })
                    .frame(height: 180).background(.black)
                    .overlay(alignment: .bottomLeading) {
                        Text(camera.adjustingColor ? "Regolazione colore…" : "ANTEPRIMA DAL VIVO · 1× · ISO \(Int(camera.telemetry.iso)) · \(camera.telemetry.shutter)")
                            .font(.system(size: 9, weight: .semibold)).padding(8).background(.black.opacity(0.5))
                    }
            }
            .navigationTitle("Controlli")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fine") { dismiss() }.accessibilityIdentifier("closeControls") } }
            .confirmationDialog("Riferimento neutro", isPresented: $calibrate, titleVisibility: .visible) {
                Button("Calibra ora e blocca") { camera.lockWhiteBalance(calibrate: true) }
                Button("Annulla", role: .cancel) {}
            } message: { Text("Posiziona un vero cartoncino grigio neutro al centro, occupando almeno metà dell’inquadratura, sotto la stessa luce del prodotto. Attendi che l’anteprima si stabilizzi. Un tessuto bianco o uno sfondo colorato possono falsare la calibrazione.") }
        }
        .onAppear { syncControls() }
        .onChange(of: camera.colorRevision) { _, _ in syncControls() }
        .onChange(of: captureRAW) { _, value in camera.setRAWEnabled(value) }
        .preferredColorScheme(.dark)
    }

    private var exposureSection: some View {
        Section {
            Picker("Modalità", selection: Binding(get: { manualExposure }, set: { $0 ? enterManualExposure() : camera.setExposureLocked(false) })) {
                Text("Automatica").tag(false)
                Text("Manuale").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(!camera.ready || !limits.manualExposure)
            .accessibilityIdentifier("exposureMode")

            if manualExposure {
                HStack { Text("ISO"); Spacer(); Text("\(Int(iso))").monospacedDigit() }
                Slider(value: $iso, in: isoRange, step: 1, onEditingChanged: { editing in if !editing { applyManualExposure() } })
                    .accessibilityLabel("ISO")
                HStack { Text("Tempo"); Spacer(); Text(ExposureScale.label(shutterSeconds)).monospacedDigit() }
                Slider(value: $shutterPosition, in: 0...1, onEditingChanged: { editing in if !editing { applyManualExposure() } })
                    .accessibilityLabel("Tempo di scatto")
                    .accessibilityValue(ExposureScale.label(shutterSeconds))
                HStack {
                    Text("Esposimetro")
                    Spacer()
                    Text(String(format: "%+.1f EV", camera.telemetry.meterOffset)).monospacedDigit()
                        .foregroundStyle(abs(camera.telemetry.meterOffset) <= 0.3 ? StudioTheme.accent : .orange)
                }
                Text("Su treppiede: ISO al minimo e tempo più lungo danno il file più pulito. A mano libera resta sopra 1/60 s. L’esposimetro vicino a 0 indica l’esposizione che sceglierebbe l’automatico.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack { Text("Compensazione"); Spacer(); Text(String(format: "%+.1f EV", bias)).monospacedDigit() }
                Slider(value: $bias, in: biasRange, step: 0.1, onEditingChanged: { editing in if !editing { camera.setExposureBias(Float(bias)) } })
                    .disabled(camera.exposureState == .locked || !camera.ready).accessibilityLabel("Compensazione esposizione")
                Toggle("Blocca l’esposizione", isOn: Binding(get: { camera.exposureState == .locked }, set: { camera.setExposureLocked($0) }))
                    .disabled(!camera.ready)
                Text("Tocca il prodotto nell’inquadratura per misurare la luce lì. Su un capo bianco abbassa la compensazione finché Zebra sparisce dalle zone con trama.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: { Text("Luce") }
    }

    private var focusSection: some View {
        Section {
            Toggle("Fuoco manuale", isOn: Binding(get: { manualFocus }, set: { $0 ? applyLens() : camera.setFocusLocked(false) }))
                .disabled(!camera.ready || !limits.manualFocus)
                .accessibilityIdentifier("manualFocus")
            if manualFocus {
                HStack { Text("Vicino"); Spacer(); Text("Lontano") }.font(.caption).foregroundStyle(.secondary)
                Slider(value: $lens, in: 0...1, onEditingChanged: { editing in if !editing { applyLens() } })
                    .accessibilityLabel("Distanza di messa a fuoco")
                Toggle("Peaking: evidenzia in verde ciò che è a fuoco", isOn: $peaking)
            }
            Text("Per etichette e loghi: metti il telefono su un supporto, attiva il fuoco manuale e sposta il cursore finché il testo è nitido e verde con Peaking. Il fuoco non cambia più tra uno scatto e l’altro.")
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text("Fuoco") }
    }

    private var rawDescription: String {
        switch camera.rawKind {
        case .proRAW:
            return "Apple ProRAW alla massima risoluzione con la fusione multi-scatto di iOS: massimo margine per bianchi, neri e colore in Lightroom o Foto. File molto pesanti (fino a circa 75 MB a 48 MP)."
        case .bayer:
            return "RAW Bayer a scatto singolo, senza riduzione rumore né nitidezza di iOS. Va sviluppato in un editor ed è più pesante; il JPEG accanto resta elaborato da iOS."
        case .none:
            return "RAW non disponibile in questa configurazione. Gli scatti saranno JPEG alla risoluzione supportata."
        }
    }

    private func applyTemperature() { camera.lockWhiteBalance(kelvin: Float(kelvin), tint: Float(tint)) }

    private func enterManualExposure() {
        iso = min(isoRange.upperBound, max(isoRange.lowerBound, Double(camera.telemetry.iso)))
        shutterPosition = ExposureScale.position(for: camera.telemetry.seconds, minimum: limits.minSeconds, maximum: limits.maxSeconds)
        applyManualExposure()
    }

    private func applyManualExposure() { camera.setManualExposure(seconds: shutterSeconds, iso: Float(iso)) }

    private func applyLens() { camera.setLensPosition(Float(lens)) }

    private func syncControls() {
        kelvin = min(9000, max(2500, Double(camera.temperature)))
        tint = min(100, max(-100, Double(camera.tint)))
        bias = min(biasRange.upperBound, max(biasRange.lowerBound, Double(camera.exposureBias)))
        lens = min(1, max(0, Double(camera.telemetry.lensPosition)))
        if manualExposure {
            iso = min(isoRange.upperBound, max(isoRange.lowerBound, Double(camera.telemetry.iso)))
            shutterPosition = ExposureScale.position(for: camera.telemetry.seconds, minimum: limits.minSeconds, maximum: limits.maxSeconds)
        }
    }
}
