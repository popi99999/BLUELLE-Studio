import SwiftUI

struct CameraControls: View {
    @ObservedObject var camera: CameraService
    @Environment(\.dismiss) private var dismiss
    @State private var kelvin: Double = 5200
    @State private var tint: Double = 0
    @State private var bias: Double = 0
    @State private var calibrate = false
    @AppStorage("captureRAW") private var captureRAW = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Obiettivo principale fisso · 1×", systemImage: "camera.aperture")
                    Text("Evita cambi automatici di obiettivo durante la serie. Per avvicinarti a un’etichetta, sposta il telefono: se non mette a fuoco, allontanati.")
                        .font(.caption).foregroundStyle(.secondary)
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

                Section {
                    HStack { Text("Compensazione"); Spacer(); Text(String(format: "%+.1f EV", bias)).monospacedDigit() }
                    Slider(value: $bias, in: -2...2, step: 0.1, onEditingChanged: { editing in if !editing { camera.setExposureBias(Float(bias)) } })
                        .disabled(camera.exposureLocked || !camera.ready).accessibilityLabel("Compensazione esposizione")
                    Toggle("Blocca l’esposizione", isOn: Binding(get: { camera.exposureLocked }, set: { camera.setExposureLocked($0) }))
                        .disabled(!camera.ready)
                    Text("Uno sfondo scuro o un capo bianco possono influenzare l’esposizione automatica. Regola osservando anche la trama delle zone chiare.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Luce") }

                Section {
                    Toggle("Conserva anche RAW (DNG)", isOn: $captureRAW).disabled(!camera.rawAvailable)
                        .accessibilityIdentifier("rawToggle")
                    Text(camera.rawAvailable ? "Salva JPEG + Bayer RAW. Il DNG richiede sviluppo in un editor ed è più pesante; il JPEG resta elaborato da iOS." : "Bayer RAW non disponibile in questa configurazione. Gli scatti saranno JPEG alla risoluzione supportata.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("I file acquisiti non vengono ridimensionati né ritoccati dall’app. La risoluzione effettiva è visibile su ogni foto salvata.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("File originali") }

                Section {
                    Text("Luce diffusa, una sola temperatura di luce, lente pulita e telefono parallelo al prodotto. Usa il timer con un supporto per le etichette.")
                    Text("Nessun punteggio di nitidezza o fedeltà colore: ISO, tempo e giroscopio sono indizi sul rischio di mosso, non una misura della foto finale.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Prima di scattare") }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                CameraPreview(session: camera.session) { camera.focus(at: $0) }
                    .frame(height: 180).background(.black)
                    .overlay(alignment: .bottomLeading) {
                        Text(camera.adjustingColor ? "Regolazione colore…" : "ANTEPRIMA DAL VIVO · 1×")
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
        .preferredColorScheme(.dark)
    }

    private func applyTemperature() { camera.lockWhiteBalance(kelvin: Float(kelvin), tint: Float(tint)) }
    private func syncControls() {
        kelvin = min(9000, max(2500, Double(camera.temperature)))
        tint = min(100, max(-100, Double(camera.tint)))
        bias = Double(camera.exposureBias)
    }
}
