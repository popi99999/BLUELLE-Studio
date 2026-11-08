import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss

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
                    }
                }
            }
            .navigationTitle("Archivio")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fine") { dismiss() }.accessibilityIdentifier("closeLibrary") } }
        }.preferredColorScheme(.dark)
    }
}

private struct ProductGallery: View {
    @EnvironmentObject private var library: LibraryModel
    let productID: UUID
    let closeLibrary: () -> Void
    @State private var share = false
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
                                }.buttonStyle(.plain)
                            }
                        }
                        Button("Esporta tutti gli originali", systemImage: "square.and.arrow.up") { share = true }.buttonStyle(.bordered)
                        Text("JPEG e DNG, quando presente. I file non vengono ridimensionati dall’app; il servizio scelto per condividerli può applicare una propria compressione.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(20)
            }
        }
        .navigationTitle(product?.name ?? "Prodotto").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $share) { if let product { ShareFiles(urls: library.files(for: product)) } }
    }
}

private struct ShotDetail: View {
    @EnvironmentObject private var library: LibraryModel
    let product: ProductSession
    let shot: ShotRecord
    @State private var share = false

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
                Button("Aggiungi a Foto", systemImage: "photo.badge.plus") { library.saveToPhotos(shot, in: product) }.buttonStyle(.bordered)
            }.padding(.bottom)
        }
        .navigationTitle(shot.kind.title).navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $share) {
            ShareFiles(urls: [library.url(for: shot, in: product)] + (shot.raw.map { [library.disk.folder(for: product.id).appendingPathComponent($0)] } ?? []))
        }
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
    private let photo = UIImageView()
    private var fitted = false

    init(url: URL) {
        super.init(frame: .zero)
        backgroundColor = .black
        delegate = self
        photo.image = UIImage(contentsOfFile: url.path)
        photo.frame.size = photo.image?.size ?? .zero
        addSubview(photo)
        contentSize = photo.frame.size
        let tap = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
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
