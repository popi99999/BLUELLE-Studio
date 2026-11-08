import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: ProductSession?
    @State private var renaming: ProductSession?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Group {
                if library.products.isEmpty {
                    ContentUnavailableView("Il tuo archivio, ordinato.", systemImage: "square.stack", description: Text("Crea un prodotto e fotografa le sei viste. Gli originali restano sul tuo iPhone."))
                } else {
                    List(library.products) { product in
                        NavigationLink {
                            ProductGallery(productID: product.id, closeLibrary: { dismiss() })
                        } label: {
                            HStack(spacing: 14) {
                                if let shot = product.shots.first {
                                    LocalThumbnail(url: library.url(for: shot, in: product))
                                        .frame(width: 58, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    Image(systemName: "tshirt").font(.title2).frame(width: 58, height: 72).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                                }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(product.name).font(.system(.headline, design: .serif))
                                    Text("\(product.shots.count) foto · \(product.completedKinds.count)/6 viste").font(.caption).foregroundStyle(.secondary)
                                    Text(product.createdAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 5)
                        }
                        .swipeActions {
                            Button("Elimina", role: .destructive) { pendingDelete = product }
                            Button("Rinomina") { newName = product.name; renaming = product }.tint(.gray)
                        }
                        .contextMenu {
                            Button("Rinomina", systemImage: "pencil") { newName = product.name; renaming = product }
                            Button("Elimina", systemImage: "trash", role: .destructive) { pendingDelete = product }
                        }
                    }
                }
            }
            .navigationTitle("Archivio")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fine") { dismiss() }.accessibilityIdentifier("closeLibrary") } }
            .deleteProductAlert(product: $pendingDelete)
            .renameProductAlert(product: $renaming, name: $newName)
        }.preferredColorScheme(.dark)
    }
}

private struct ProductGallery: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    let productID: UUID
    let closeLibrary: () -> Void
    @State private var share = false
    @State private var pendingDelete: ProductSession?
    @State private var renaming: ProductSession?
    @State private var newName = ""
    @State private var shotToDelete: ShotRecord?
    private var product: ProductSession? { library.products.first { $0.id == productID } }

    var body: some View {
        ScrollView {
            if let product {
                VStack(alignment: .leading, spacing: 22) {
                    Text("\(product.completedKinds.count) di 6 viste documentate").font(.subheadline).foregroundStyle(.secondary)
                    Button("Continua a fotografare", systemImage: "camera") { library.selectedID = product.id; closeLibrary() }
                        .buttonStyle(.borderedProminent).foregroundStyle(StudioTheme.background)
                    if product.shots.isEmpty {
                        ContentUnavailableView("Pronto per il primo scatto", systemImage: "camera.aperture", description: Text("Fronte, retro, logo, etichetta, tessuto e difetti."))
                    } else {
                        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 16) {
                            ForEach(product.shots) { shot in
                                NavigationLink {
                                    ShotDetail(product: product, shot: shot)
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        LocalThumbnail(url: library.url(for: shot, in: product)).aspectRatio(3 / 4, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
                                        HStack { Text(shot.kind.title).font(.subheadline); Spacer(); if shot.raw != nil { Text("RAW").font(.system(size: 8, weight: .bold)).foregroundStyle(StudioTheme.accent) } }
                                        Text("\(shot.width) × \(shot.height)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Aggiungi a Foto", systemImage: "photo.badge.plus") { library.saveToPhotos([shot], in: product) }
                                    Button("Elimina foto", systemImage: "trash", role: .destructive) { shotToDelete = shot }
                                }
                            }
                        }
                        Button("Esporta tutti gli originali", systemImage: "square.and.arrow.up") { share = true }.buttonStyle(.bordered)
                        Button("Aggiungi tutto a Foto", systemImage: "photo.badge.plus") { library.saveToPhotos(product.shots, in: product) }.buttonStyle(.bordered)
                        Text("JPEG e DNG, quando presente. I file portano il nome del prodotto e della vista e non vengono ridimensionati dall’app; il servizio scelto per condividerli può applicare una propria compressione.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(20)
            }
        }
        .navigationTitle(product?.name ?? "Prodotto").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let product {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Rinomina", systemImage: "pencil") { newName = product.name; renaming = product }
                        Button("Elimina prodotto", systemImage: "trash", role: .destructive) { pendingDelete = product }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("Altre azioni")
                }
            }
        }
        .sheet(isPresented: $share) { if let product { ShareFiles(urls: library.files(for: product)) } }
        .deleteProductAlert(product: $pendingDelete) { dismiss() }
        .renameProductAlert(product: $renaming, name: $newName)
        .alert("Eliminare questa foto?", isPresented: Binding(get: { shotToDelete != nil }, set: { if !$0 { shotToDelete = nil } }), presenting: shotToDelete) { shot in
            Button("Elimina", role: .destructive) { if let product { library.deleteShot(shot, in: product) } }
            Button("Annulla", role: .cancel) {}
        } message: { _ in Text("Il JPEG e l’eventuale DNG vengono cancellati da questo iPhone. Non si può annullare.") }
    }
}

private struct ShotDetail: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    let product: ProductSession
    let shot: ShotRecord
    @State private var share = false
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 16) {
            ZoomablePhoto(url: library.url(for: shot, in: product))
            Text("Pizzica per ingrandire · doppio tocco per i dettagli").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("\(shot.width) × \(shot.height)").font(.system(.caption, design: .monospaced))
                Spacer()
                Text(shot.raw == nil ? "JPEG originale" : "JPEG + RAW originali").font(.caption).foregroundStyle(StudioTheme.accent)
            }.padding(.horizontal)
            HStack {
                Button("Condividi", systemImage: "square.and.arrow.up") { share = true }.buttonStyle(.bordered)
                Button("Aggiungi a Foto", systemImage: "photo.badge.plus") { library.saveToPhotos([shot], in: product) }.buttonStyle(.bordered)
                Button("Elimina", systemImage: "trash", role: .destructive) { confirmDelete = true }.buttonStyle(.bordered)
                    .labelStyle(.iconOnly).accessibilityLabel("Elimina foto")
            }.padding(.bottom)
        }
        .navigationTitle(shot.kind.title).navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $share) {
            ShareFiles(urls: [library.url(for: shot, in: product)] + (shot.raw.map { [library.disk.folder(for: product.id).appendingPathComponent($0)] } ?? []))
        }
        .alert("Eliminare questa foto?", isPresented: $confirmDelete) {
            Button("Elimina", role: .destructive) { library.deleteShot(shot, in: product); dismiss() }
            Button("Annulla", role: .cancel) {}
        } message: { Text("Il JPEG e l’eventuale DNG vengono cancellati da questo iPhone. Non si può annullare.") }
    }
}

private extension View {
    func deleteProductAlert(product: Binding<ProductSession?>, onDelete: @escaping () -> Void = {}) -> some View {
        modifier(DeleteProductAlert(product: product, onDelete: onDelete))
    }

    func renameProductAlert(product: Binding<ProductSession?>, name: Binding<String>) -> some View {
        modifier(RenameProductAlert(product: product, name: name))
    }
}

private struct DeleteProductAlert: ViewModifier {
    @EnvironmentObject private var library: LibraryModel
    @Binding var product: ProductSession?
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content.alert("Eliminare il prodotto?", isPresented: Binding(get: { product != nil }, set: { if !$0 { product = nil } }), presenting: product) { product in
            Button("Elimina", role: .destructive) { library.deleteProduct(product); onDelete() }
            Button("Annulla", role: .cancel) {}
        } message: { product in
            Text("“\(product.name)” e i suoi \(product.shots.count) scatti originali vengono cancellati da questo iPhone. Non si può annullare.")
        }
    }
}

private struct RenameProductAlert: ViewModifier {
    @EnvironmentObject private var library: LibraryModel
    @Binding var product: ProductSession?
    @Binding var name: String

    func body(content: Content) -> some View {
        content.alert("Rinomina prodotto", isPresented: Binding(get: { product != nil }, set: { if !$0 { product = nil } }), presenting: product) { product in
            TextField("Nome del prodotto", text: $name)
            Button("Salva") { library.rename(product, to: name) }
            Button("Annulla", role: .cancel) {}
        } message: { _ in Text("I nuovi scatti useranno questo nome nei file.") }
    }
}

struct LocalThumbnail: View {
    let url: URL
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            StudioTheme.surface
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
        .task(id: url) {
            let source = url
            image = await Task.detached(priority: .utility) { thumbnail(at: source) }.value
        }
    }
}

private struct ZoomablePhoto: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PhotoScrollView { PhotoScrollView(url: url) }
    func updateUIView(_ view: PhotoScrollView, context: Context) {}
}

private final class PhotoScrollView: UIScrollView, UIScrollViewDelegate {
    /// Longest side decoded for viewing. A 48 MP original decoded in full needs about 200 MB of memory.
    private static let viewingSize = 4096
    private let photo = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var fitted = false

    init(url: URL) {
        super.init(frame: .zero)
        backgroundColor = .black
        delegate = self
        addSubview(photo)
        spinner.startAnimating()
        addSubview(spinner)
        let tap = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        addGestureRecognizer(tap)
        DispatchQueue.global(qos: .userInitiated).async {
            let image = thumbnail(at: url, maximum: Self.viewingSize)
            DispatchQueue.main.async { [weak self] in self?.show(image) }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func show(_ image: UIImage?) {
        spinner.stopAnimating()
        spinner.removeFromSuperview()
        photo.image = image
        photo.frame = CGRect(origin: .zero, size: image?.size ?? .zero)
        contentSize = photo.frame.size
        fitted = false
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        guard photo.bounds.width > 0, photo.bounds.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        if !fitted {
            let fit = min(bounds.width / photo.bounds.width, bounds.height / photo.bounds.height)
            minimumZoomScale = fit
            maximumZoomScale = max(fit * 8, 1)
            zoomScale = fit
            fitted = true
        }
        centerPhoto()
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { photo }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPhoto() }
    private func centerPhoto() {
        contentInset = UIEdgeInsets(top: max(0, (bounds.height - contentSize.height) / 2), left: max(0, (bounds.width - contentSize.width) / 2), bottom: 0, right: 0)
    }
    @objc private func doubleTap(_ tap: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale * 1.1 { setZoomScale(minimumZoomScale, animated: true); return }
        let scale = min(maximumZoomScale, max(minimumZoomScale * 3, 1 / UIScreen.main.scale))
        let point = tap.location(in: photo)
        zoom(to: CGRect(x: point.x - bounds.width / scale / 2, y: point.y - bounds.height / scale / 2, width: bounds.width / scale, height: bounds.height / scale), animated: true)
    }
}
