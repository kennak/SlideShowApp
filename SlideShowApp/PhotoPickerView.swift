import SwiftUI
import Photos
import PhotosUI
import AVFoundation

// MARK: - アルバム一覧 → 写真一覧 → 選択 の独自ピッカー

struct SmartPhotoPickerView: View {
    let onComplete: ([PHAsset]) -> Void

    @State private var albums: [AlbumItem] = []
    @State private var selectedAlbum: AlbumItem? = nil

    var body: some View {
        NavigationView {
            AlbumListView(albums: albums, onSelectAlbum: { album in
                selectedAlbum = album
            })
            .navigationTitle("アルバム")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { fetchAlbums() }
            .sheet(item: $selectedAlbum) { album in
                AssetGridView(album: album, onComplete: { assets in
                    selectedAlbum = nil
                    onComplete(assets)
                })
            }
        }
    }

    private func fetchAlbums() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            guard status == .authorized || status == .limited else { return }
            var result: [AlbumItem] = []

            // スマートアルバム（最近の項目、お気に入りなど）
            let smartTypes: [PHAssetCollectionSubtype] = [
                .smartAlbumUserLibrary, .smartAlbumFavorites,
                .smartAlbumVideos, .smartAlbumScreenshots, .smartAlbumSelfPortraits
            ]
            for subtype in smartTypes {
                let cols = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
                cols.enumerateObjects { col, _, _ in
                    let count = PHAsset.fetchAssets(in: col, options: nil).count
                    if count > 0 {
                        result.append(AlbumItem(collection: col, count: count))
                    }
                }
            }

            // ユーザー作成アルバム
            let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            userAlbums.enumerateObjects { col, _, _ in
                let count = PHAsset.fetchAssets(in: col, options: nil).count
                if count > 0 {
                    result.append(AlbumItem(collection: col, count: count))
                }
            }

            DispatchQueue.main.async { albums = result }
        }
    }
}

// MARK: - アルバムモデル
struct AlbumItem: Identifiable {
    let id = UUID()
    let collection: PHAssetCollection
    let count: Int
    var title: String { collection.localizedTitle ?? "アルバム" }
}

// MARK: - アルバム一覧ビュー
struct AlbumListView: View {
    let albums: [AlbumItem]
    let onSelectAlbum: (AlbumItem) -> Void

    var body: some View {
        List(albums) { album in
            Button(action: { onSelectAlbum(album) }) {
                HStack(spacing: 12) {
                    AlbumThumbnailView(collection: album.collection)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(album.title)
                            .foregroundColor(.primary)
                            .font(.body)
                        Text("\(album.count)件")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - アルバムサムネイル
struct AlbumThumbnailView: View {
    let collection: PHAssetCollection
    @State private var thumbnail: UIImage? = nil

    var body: some View {
        Group {
            if let img = thumbnail {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.3)
                    .overlay(Image(systemName: "photo").foregroundColor(.white))
            }
        }
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        let fetch = PHAsset.fetchAssets(in: collection, options: nil)
        guard let asset = fetch.lastObject else { return }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .fastFormat
        opts.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset, targetSize: CGSize(width: 120, height: 120),
            contentMode: .aspectFill, options: opts
        ) { image, _ in
            DispatchQueue.main.async { thumbnail = image }
        }
    }
}

// MARK: - アセットグリッドビュー（写真一覧 + 全選択）
struct AssetGridView: View {
    let album: AlbumItem
    let onComplete: ([PHAsset]) -> Void

    @State private var assets: [PHAsset] = []
    @State private var selected: Set<String> = []   // localIdentifier
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        AssetCell(asset: asset, isSelected: selected.contains(asset.localIdentifier))
                            .onTapGesture { toggle(asset) }
                    }
                }
            }
            .navigationTitle(album.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isAllSelected ? "全解除" : "全選択") { toggleAll() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加 (\(selected.count))") {
                        let result = assets.filter { selected.contains($0.localIdentifier) }
                        onComplete(result)
                    }
                    .disabled(selected.isEmpty)
                    .fontWeight(.bold)
                }
            }
            .onAppear { fetchAssets() }
        }
    }

    private var isAllSelected: Bool { selected.count == assets.count && !assets.isEmpty }

    private func toggle(_ asset: PHAsset) {
        if selected.contains(asset.localIdentifier) {
            selected.remove(asset.localIdentifier)
        } else {
            selected.insert(asset.localIdentifier)
        }
    }

    private func toggleAll() {
        if isAllSelected {
            selected.removeAll()
        } else {
            selected = Set(assets.map { $0.localIdentifier })
        }
    }

    private func fetchAssets() {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let fetch = PHAsset.fetchAssets(in: album.collection, options: opts)
        var result: [PHAsset] = []
        fetch.enumerateObjects { asset, _, _ in result.append(asset) }
        assets = result
    }
}

// MARK: - グリッドセル
struct AssetCell: View {
    let asset: PHAsset
    let isSelected: Bool
    @State private var thumbnail: UIImage? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let img = thumbnail {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.3)
                }
            }
            .frame(width: cellSize, height: cellSize)
            .clipped()
            .overlay(isSelected ? Color.blue.opacity(0.3) : Color.clear)

            // 動画バッジ
            if asset.mediaType == .video {
                Text(formatDuration(asset.duration))
                    .font(.caption2).foregroundColor(.white)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }

            // 選択チェック
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .blue : .white.opacity(0.8))
                .font(.title3)
                .shadow(radius: 1)
                .padding(4)
        }
        .onAppear { loadThumbnail() }
    }

    private var cellSize: CGFloat {
        (UIScreen.main.bounds.width - 4) / 3
    }

    private func loadThumbnail() {
        let size = CGSize(width: cellSize * 2, height: cellSize * 2)
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .fastFormat
        opts.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset, targetSize: size, contentMode: .aspectFill, options: opts
        ) { image, _ in
            DispatchQueue.main.async { thumbnail = image }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
