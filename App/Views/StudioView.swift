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
    @State private var countdown = 0
    @State private var captureRequested = false
    @State private var countdownTask: Task<Void, Never>?
    @AppStorage("timerSeconds") private var timerSeconds = 2
    @AppStorage("captureRAW") private var captureRAW = false
    @AppStorage("showGrid") private var grid = true
    @AppStorage("showLevel") private var showLevel = true
    @AppStorage("showZebra") private var zebra = true
    @AppStorage("showPeaking") private var peaking = false

    private var working: Bool { captureRequested || camera.isCapturing || library.busy }
    private var hardwareShutter: Bool { camera.ready && !showControls && !showLibrary && !showProductName }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        productBar
                        viewfinder
                            .frame(height: max(250, min(geometry.size.width * 4 / 3, geometry.size.height * 0.49)))
                        overlayChips
                        shotList
                        HStack(spacing: 8) {
                            lockButton("Colore", icon: "paintpalette", locked: camera.whiteBalanceLocked) {
                                camera.whiteBalanceLocked ? camera.autoWhiteBalance() : camera.lockWhiteBalance()
                            }
                            lockButton(focusTitle, icon: camera.focusState == .point ? "scope" : "viewfinder", locked: focusFixed) {
                                camera.setFocusLocked(!focusFixed)
                            }
                            lockButton(camera.exposureState == .manual ? "Manuale" : "Luce", icon: "sun.max", locked: camera.exposureState != .auto) {
                                camera.setExposureLocked(camera.exposureState == .auto)
                            }
                        }
                        .disabled(!camera.ready || working)
                        if camera.ready {
                            ConditionsPanel(camera: camera, frames: camera.frames)
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
        .task {
            camera.setRAWEnabled(captureRAW)
            camera.setOverlays(zebra: zebra, peaking: peaking)
            camera.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera.start() }
            else { cancelCountdown(); camera.stop() }
        }
        .onChange(of: captureRAW) { _, value in camera.setRAWEnabled(value) }
        .onChange(of: zebra) { _, value in camera.setOverlays(zebra: value, peaking: peaking) }
        .onChange(of: peaking) { _, value in camera.setOverlays(zebra: zebra, peaking: value) }
        .onChange(of: library.selectedID) { _, _ in selectedKind = library.current?.nextKind ?? .front }
    }

    private var focusFixed: Bool { camera.focusState == .locked || camera.focusState == .manual }
    private var focusTitle: String {
        switch camera.focusState {
        case .auto, .locked: return "Fuoco"
        case .point: return "Punto"
        case .manual: return "Fuoco M"
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("BLUELLE").font(.system(size: 22, weight: .regular, design: .serif)).tracking(5)
                Text("PRODUCT STUDIO").font(.system(size: 8, weight: .semibold)).tracking(3.4).foregroundStyle(.secondary)
            }
            Spacer()
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
            CameraPreview(session: camera.session, onFocus: { camera.focus(at: $0) },
                          shutterEnabled: hardwareShutter, onShutter: { working ? cancelCountdown() : takePhoto() })
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
            if camera.ready {
                AnalysisOverlay(frames: camera.frames)
                if grid { CompositionGrid().aspectRatio(3 / 4, contentMode: .fit).allowsHitTesting(false) }
                if showLevel { LevelOverlay(motion: camera.motion).allowsHitTesting(false) }
            }
            VStack {
                HStack {
                    Label("1× PRINCIPALE", systemImage: "camera.aperture").font(.system(size: 9, weight: .semibold)).tracking(0.5)
                    Spacer()
                    Text(captureRAW && camera.rawAvailable ? "\(camera.rawKind.title) + JPG" : "JPG").font(.system(size: 9, weight: .semibold))
                }
                Spacer()
                if camera.ready {
                    HStack(alignment: .bottom) {
                        HistogramView(frames: camera.frames)
                        Spacer()
                    }
                }
                HStack {
                    Text(camera.ready ? exposureLine : "FOTO PRODOTTO")
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

    private var exposureLine: String {
        var parts = ["ISO \(Int(camera.telemetry.iso))", camera.telemetry.shutter]
        if camera.exposureState == .manual {
            parts.append(String(format: "M %+.1f EV", camera.telemetry.meterOffset))
        } else if abs(camera.exposureBias) >= 0.05 {
            parts.append(String(format: "%+.1f EV", camera.exposureBias))
        }
        return parts.joined(separator: "  ")
    }

    private var overlayChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Griglia", icon: "grid", isOn: $grid, identifier: "toggleGrid")
                chip("Livella", icon: "level", isOn: $showLevel, identifier: "toggleLevel")
                chip("Zebra", icon: "circle.lefthalf.filled", isOn: $zebra, identifier: "toggleZebra")
                chip("Peaking", icon: "scope", isOn: $peaking, identifier: "togglePeaking")
            }
        }
    }

    private func chip(_ title: String, icon: String, isOn: Binding<Bool>, identifier: String) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12).frame(minHeight: 36)
                .background(isOn.wrappedValue ? StudioTheme.accent.opacity(0.16) : StudioTheme.surface, in: Capsule())
                .foregroundStyle(isOn.wrappedValue ? StudioTheme.accent : StudioTheme.ink)
        }
        .accessibilityLabel(title)
        .accessibilityValue(isOn.wrappedValue ? "attivo" : "spento")
        .accessibilityIdentifier(identifier)
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
                ForEach([0, 2, 5, 10], id: \.self) { seconds in Button(seconds == 0 ? "Timer spento" : "\(seconds) secondi") { timerSeconds = seconds } }
            } label: {
                VStack(spacing: 5) { Image(systemName: "timer").font(.title3); Text(timerSeconds == 0 ? "OFF" : "\(timerSeconds) SEC").font(.system(size: 9)) }.frame(width: 66, height: 64)
            }.disabled(working).accessibilityLabel("Timer \(timerSeconds) secondi")
        }.padding(.horizontal, 28).padding(.vertical, 12).background(StudioTheme.background)
    }

    private func takePhoto() {
        guard camera.ready, !working, !camera.adjustingColor else { return }
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
            camera.capture(raw: captureRAW && camera.rawAvailable, angle: camera.motion.captureAngle) { result in
                switch result {
                case .success(let payload):
                    library.save(payload, productID: product.id, kind: kind) { saved in
                        captureRequested = false
                        if saved {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            if library.selectedID == product.id { selectedKind = library.current?.nextKind ?? .front }
                        }
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

/// Camera-shake advice plus clipping warnings from the live histogram.
private struct ConditionsPanel: View {
    @ObservedObject var camera: CameraService
    @ObservedObject var frames: FrameMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let advice = camera.telemetry.advice
            row(icon: advice == .steady ? "checkmark.circle" : "info.circle", color: advice == .steady ? StudioTheme.accent : .orange,
                title: advice.title, detail: advice.detail)
            if frames.highlights > 0.005 {
                row(icon: "exclamationmark.triangle", color: .orange,
                    title: "Bianchi bruciati · \(frames.highlights.formatted(.percent.precision(.fractionLength(1))))",
                    detail: "Le zone bianche perdono la trama. Riduci l’esposizione o ammorbidisci la luce; Zebra mostra dove.")
            }
            if frames.shadows > 0.02 {
                row(icon: "moon", color: .orange,
                    title: "Neri chiusi · \(frames.shadows.formatted(.percent.precision(.fractionLength(1))))",
                    detail: "Le zone scure perdono dettaglio. Aggiungi luce o aumenta l’esposizione.")
            }
        }
    }

    private func row(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Zebra (clipped whites) and focus peaking drawn over the live preview.
private struct AnalysisOverlay: View {
    @ObservedObject var frames: FrameMonitor

    var body: some View {
        if let image = frames.overlay {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .allowsHitTesting(false)
        }
    }
}

private struct HistogramView: View {
    @ObservedObject var frames: FrameMonitor

    var body: some View {
        Canvas { context, size in
            let values = frames.histogram
            guard let peak = values.max(), peak > 0 else { return }
            let barWidth = size.width / CGFloat(values.count)
            var bars = Path()
            for (index, value) in values.enumerated() {
                let height = size.height * CGFloat((value / peak).squareRoot())
                bars.addRect(CGRect(x: CGFloat(index) * barWidth, y: size.height - height, width: max(1, barWidth - 0.5), height: height))
            }
            context.fill(bars, with: .color(.white.opacity(0.75)))
            if frames.highlights > 0.005 {
                context.fill(Path(CGRect(x: size.width - 2, y: 0, width: 2, height: size.height)), with: .color(.red))
            }
            if frames.shadows > 0.02 {
                context.fill(Path(CGRect(x: 0, y: 0, width: 2, height: size.height)), with: .color(.red))
            }
        }
        .frame(width: 96, height: 30)
        .padding(4)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}

/// Horizon line when the phone faces the product, bubble when it looks down at a flat lay.
private struct LevelOverlay: View {
    @ObservedObject var motion: MotionMonitor

    var body: some View {
        if let level = motion.level {
            let color: Color = level.isLevel ? StudioTheme.accent : .white
            switch level.mode {
            case .upright:
                ZStack {
                    HStack {
                        Rectangle().frame(width: 22, height: 1.5)
                        Spacer()
                        Rectangle().frame(width: 22, height: 1.5)
                    }
                    .frame(width: 230)
                    .foregroundStyle(.white.opacity(0.55))
                    .rotationEffect(.degrees(level.reference))
                    Rectangle().fill(color).frame(width: 160, height: level.isLevel ? 2 : 1.5)
                        .rotationEffect(.degrees(level.horizon))
                    Text(uprightLabel(level))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(level.isLevel && level.isVertical ? StudioTheme.accent : .white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.4), in: Capsule())
                        .offset(y: 26)
                }
            case .flat:
                ZStack {
                    Circle().stroke(.white.opacity(0.55), lineWidth: 1).frame(width: 72, height: 72)
                    Circle().stroke(.white.opacity(0.4), lineWidth: 1).frame(width: 16, height: 16)
                    Circle().fill(color).frame(width: 12, height: 12)
                        .offset(x: CGFloat(level.bubbleX) * 36, y: CGFloat(level.bubbleY) * 36)
                    Text(String(format: "%.1f°", level.degrees))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.4), in: Capsule())
                        .offset(y: 50)
                }
            }
        }
    }

    private func uprightLabel(_ level: LevelReading) -> String {
        var text = String(format: "%.1f°", abs(level.degrees))
        if !level.isVertical { text += String(format: "  ↕ %.0f°", abs(level.pitch)) }
        return text
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
