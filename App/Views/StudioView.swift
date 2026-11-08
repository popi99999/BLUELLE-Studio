import SwiftUI

struct StudioView: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = CameraService()
    @State private var selectedKind: ShotKind = .front
    @State private var showControls = false
    @State private var showLibrary = false
    @State private var showProductName = false
    @State private var name = ""
    @State private var grid = true
    @State private var countdown = 0
    @State private var captureRequested = false
    @State private var countdownTask: Task<Void, Never>?
    @AppStorage("timerSeconds") private var timerSeconds = 2
    @AppStorage("captureRAW") private var captureRAW = false

    private var working: Bool { captureRequested || camera.isCapturing || library.busy }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        productBar
                        viewfinder
                            .frame(height: max(250, min(geometry.size.width * 4 / 3, geometry.size.height * 0.49)))
                        shotList
                        HStack(spacing: 8) {
                            lockButton("Colore", icon: "paintpalette", locked: camera.whiteBalanceLocked) {
                                camera.whiteBalanceLocked ? camera.autoWhiteBalance() : camera.lockWhiteBalance()
                            }
                            lockButton("Fuoco", icon: "viewfinder", locked: camera.focusLocked) { camera.setFocusLocked(!camera.focusLocked) }
                            lockButton("Luce", icon: "sun.max", locked: camera.exposureLocked) { camera.setExposureLocked(!camera.exposureLocked) }
                        }
                        .disabled(!camera.ready || working)
                        if camera.ready {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: camera.telemetry.advice == .steady ? "checkmark.circle" : "info.circle")
                                    .foregroundStyle(camera.telemetry.advice == .steady ? StudioTheme.accent : .orange)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(camera.telemetry.advice.title).font(.subheadline.weight(.medium))
                                    Text(camera.telemetry.advice.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                }
                shutterBar
            }
            .background(StudioTheme.background)
        }
        .foregroundStyle(StudioTheme.ink)
        .sheet(isPresented: $showControls) { CameraControls(camera: camera).presentationDetents([.large]) }
        .sheet(isPresented: $showLibrary) { LibraryView().environmentObject(library) }
        .alert("Nome del prodotto", isPresented: $showProductName) {
            TextField("Es. Celine bianca", text: $name).accessibilityIdentifier("productNameField")
            Button("Crea sessione") { library.create(name: name); selectedKind = .front; name = "" }
            Button("Annulla", role: .cancel) {}
        } message: { Text("Tutti gli scatti di questo capo resteranno insieme.") }
        .alert("BLUELLE Studio", isPresented: Binding(get: { camera.error != nil || library.error != nil }, set: { if !$0 { camera.error = nil; library.error = nil } })) {
            Button("OK") { camera.error = nil; library.error = nil }
        } message: { Text(camera.error ?? library.error ?? "") }
        .overlay(alignment: .top) {
            if let notice = library.notice {
                Button { library.notice = nil } label: {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold)).padding(14)
                        .background(StudioTheme.accent, in: Capsule()).foregroundStyle(StudioTheme.background)
                }.padding(.top, 66)
            }
        }
        .task { camera.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera.start() }
            else { cancelCountdown(); camera.stop() }
        }
        .onChange(of: library.selectedID) { _, _ in selectedKind = library.current?.nextKind ?? .front }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("BLUELLE").font(.system(size: 22, weight: .regular, design: .serif)).tracking(5)
                Text("PRODUCT STUDIO").font(.system(size: 8, weight: .semibold)).tracking(3.4).foregroundStyle(.secondary)
            }
            Spacer()
            Button { grid.toggle() } label: { Image(systemName: grid ? "grid" : "square").frame(width: 44, height: 44) }
                .accessibilityLabel("Griglia composizione")
            Button { showControls = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                .accessibilityLabel("Controlli fotocamera").accessibilityIdentifier("cameraControls")
        }.padding(.horizontal, 20).padding(.top, 8)
    }

    private var productBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("SESSIONE PRODOTTO").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
                Text(library.current?.name ?? "Il prossimo scatto, fatto bene.")
                    .font(.system(size: 18, weight: .medium, design: .serif)).lineLimit(2)
            }
            Spacer(minLength: 10)
            Button { showProductName = true } label: { Image(systemName: "plus").frame(width: 44, height: 44).background(StudioTheme.surface, in: Circle()) }
                .accessibilityLabel("Nuovo prodotto").accessibilityIdentifier("newProduct").disabled(working)
        }
    }

    private var viewfinder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(.black)
            CameraPreview(session: camera.session) { camera.focus(at: $0) }
            if !camera.ready {
                VStack(spacing: 16) {
                    Image(systemName: camera.isPreview ? "tshirt" : "camera.aperture").font(.system(size: 60, weight: .ultraLight))
                    Text(camera.isPreview ? "Anteprima interfaccia" : camera.permissionDenied ? "Consenti l’accesso alla fotocamera" : "La tua luce. I tuoi colori.")
                        .font(.system(.title3, design: .serif)).multilineTextAlignment(.center)
                    Text(camera.isPreview ? "La fotocamera si usa su un iPhone reale." : "Obiettivo principale 1× · nessuno zoom digitale")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if camera.permissionDenied {
                        Button("Apri Impostazioni") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    } else if !camera.isPreview {
                        Button("Avvia fotocamera") { camera.start() }.buttonStyle(.bordered)
                    }
                }.padding(32).allowsHitTesting(true)
            }
            if grid && camera.ready {
                CompositionGrid().aspectRatio(3 / 4, contentMode: .fit).allowsHitTesting(false)
            }
            VStack {
                HStack {
                    Label("1× PRINCIPALE", systemImage: "camera.aperture").font(.system(size: 9, weight: .semibold)).tracking(0.5)
                    Spacer()
                    Text(captureRAW && camera.rawAvailable ? "RAW + JPG" : "JPG").font(.system(size: 9, weight: .semibold))
                }
                Spacer()
                HStack {
                    Text(camera.ready ? "ISO \(Int(camera.telemetry.iso))   \(camera.telemetry.shutter)" : "FOTO PRODOTTO")
                    Spacer()
                    Text(camera.resolution)
                }.font(.system(size: 10, design: .monospaced))
            }.padding(14).allowsHitTesting(false)
            if countdown > 0 {
                Text("\(countdown)").font(.system(size: 88, weight: .ultraLight, design: .rounded)).shadow(radius: 10).allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08)))
        .accessibilityIdentifier("viewfinder")
    }

    private var shotList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LO SCATTO").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
                Spacer()
                Text("\(library.current?.completedKinds.count ?? 0) / 6 viste").font(.caption2).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ShotKind.allCases) { kind in
                        Button { selectedKind = kind } label: {
                            HStack(spacing: 5) {
                                if library.current?.completedKinds.contains(kind) == true { Image(systemName: "checkmark").font(.caption2) }
                                Text(kind.title).font(.caption.weight(.medium))
                            }.padding(.horizontal, 14).padding(.vertical, 11)
                                .background(selectedKind == kind ? StudioTheme.accent : StudioTheme.surface, in: Capsule())
                                .foregroundStyle(selectedKind == kind ? StudioTheme.background : StudioTheme.ink)
                        }.accessibilityIdentifier("shot-\(kind.rawValue)")
                    }
                }
            }.disabled(working)
            Text(selectedKind.hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func lockButton(_ title: String, icon: String, locked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) { Image(systemName: locked ? "lock.fill" : icon); Text(title) }
                .font(.caption.weight(.medium)).frame(maxWidth: .infinity).frame(minHeight: 44)
                .background(locked ? StudioTheme.accent.opacity(0.16) : StudioTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(locked ? StudioTheme.accent : StudioTheme.ink)
        }.accessibilityLabel("\(title): \(locked ? "bloccato" : "automatico")")
    }

    private var shutterBar: some View {
        HStack(alignment: .center) {
            Button { showLibrary = true } label: {
                VStack(spacing: 5) { Image(systemName: "square.stack").font(.title3); Text("Archivio").font(.system(size: 9)) }.frame(width: 66, height: 64)
            }.accessibilityIdentifier("openLibrary").disabled(working)
            Spacer()
            Button { working ? cancelCountdown() : takePhoto() } label: {
                ZStack {
                    Circle().stroke(StudioTheme.ink, lineWidth: 1.5).frame(width: 76, height: 76)
                    Circle().fill(StudioTheme.ink).frame(width: 64, height: 64)
                    if countdown > 0 { Image(systemName: "xmark").foregroundStyle(StudioTheme.background) }
                    else if working { ProgressView().tint(StudioTheme.background) }
                }
            }
            .disabled((!camera.ready && countdown == 0) || (working && countdown == 0) || camera.adjustingColor)
            .accessibilityLabel(countdown > 0 ? "Annulla timer" : "Scatta foto").accessibilityIdentifier("shutter")
            Spacer()
            Menu {
                ForEach([0, 2, 5], id: \.self) { seconds in Button(seconds == 0 ? "Timer spento" : "\(seconds) secondi") { timerSeconds = seconds } }
            } label: {
                VStack(spacing: 5) { Image(systemName: "timer").font(.title3); Text(timerSeconds == 0 ? "OFF" : "\(timerSeconds) SEC").font(.system(size: 9)) }.frame(width: 66, height: 64)
            }.disabled(working).accessibilityLabel("Timer \(timerSeconds) secondi")
        }.padding(.horizontal, 28).padding(.vertical, 12).background(StudioTheme.background)
    }

    private func takePhoto() {
        guard let product = library.current else { showProductName = true; return }
        let kind = selectedKind
        captureRequested = true
        countdownTask = Task { @MainActor in
            if timerSeconds > 0 {
                for value in stride(from: timerSeconds, through: 1, by: -1) {
                    countdown = value
                    do { try await Task.sleep(for: .seconds(1)) }
                    catch { countdown = 0; captureRequested = false; return }
                }
            }
            countdown = 0
            guard !Task.isCancelled else { captureRequested = false; return }
            camera.capture(raw: captureRAW && camera.rawAvailable) { result in
                switch result {
                case .success(let payload):
                    library.save(payload, productID: product.id, kind: kind) { saved in
                        captureRequested = false
                        if saved && library.selectedID == product.id { selectedKind = library.current?.nextKind ?? .front }
                    }
                case .failure(let error): captureRequested = false; camera.error = error.localizedDescription
                }
            }
        }
    }

    private func cancelCountdown() {
        guard countdown > 0 else { return }
        countdownTask?.cancel(); countdown = 0; captureRequested = false
    }
}

private struct CompositionGrid: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                for part in [1.0 / 3, 2.0 / 3] {
                    path.move(to: CGPoint(x: geometry.size.width * part, y: 0)); path.addLine(to: CGPoint(x: geometry.size.width * part, y: geometry.size.height))
                    path.move(to: CGPoint(x: 0, y: geometry.size.height * part)); path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height * part))
                }
            }.stroke(.white.opacity(0.22), lineWidth: 0.5)
        }
    }
}
