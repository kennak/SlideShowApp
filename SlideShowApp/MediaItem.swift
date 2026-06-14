import Foundation
import Combine
import Photos
import UIKit
import AVFoundation

enum MediaType {
    case photo
    case video
}

struct MediaItem {
    let type:     MediaType
    let image:    UIImage?
    let videoURL: URL?
}

// MARK: - オンデマンドローダー（1枚ずつロード・キャンセル可能）
actor AssetLoader {

    // 動画の一時ファイルを追跡して破棄できるようにする
    private var tempVideoURLs: [URL] = []

    func load(asset: PHAsset) async -> MediaItem? {
        switch asset.mediaType {
        case .image:
            return await loadPhoto(asset: asset)
        case .video:
            // スロー動画（可変フレームレート）は AVComposition で返され
            // AVURLAsset へのキャストが失敗するため、サムネイルを写真として扱う
            if asset.mediaSubtypes.contains(.videoHighFrameRate) {
                return await loadPhoto(asset: asset)
            }
            return await loadVideo(asset: asset)
        default:
            return nil
        }
    }

    private func loadPhoto(asset: PHAsset) async -> MediaItem? {
        await withCheckedContinuation { continuation in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.isNetworkAccessAllowed = true
            opts.resizeMode = .exact

            // 画面サイズに合わせた解像度（フルサイズは不要）
            // UIScreen.main は iOS16以降非推奨のため、固定の高解像度サイズを使用
            // 実際の表示はscaledToFitで調整されるため、2048pxで十分な品質
            let size   = CGSize(width: 2048, height: 2048)

            PHImageManager.default().requestImage(
                for: asset, targetSize: size,
                contentMode: .aspectFit, options: opts
            ) { image, info in
                // degraded（低解像度の中間結果）は無視
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                continuation.resume(returning: image.map {
                    MediaItem(type: .photo, image: $0, videoURL: nil)
                })
            }
        }
    }

    private func loadVideo(asset: PHAsset) async -> MediaItem? {
        await withCheckedContinuation { continuation in
            let opts = PHVideoRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.isNetworkAccessAllowed = true

            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { avAsset, _, _ in
                guard let urlAsset = avAsset as? AVURLAsset else {
                    continuation.resume(returning: nil); return
                }
                // 一時コピー（元URLは再生後に無効になる場合がある）
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(urlAsset.url.pathExtension)
                try? FileManager.default.copyItem(at: urlAsset.url, to: dest)

                // サムネイル
                let gen = AVAssetImageGenerator(asset: AVAsset(url: dest))
                gen.appliesPreferredTrackTransform = true
                let thumb = try? gen.copyCGImage(at: .zero, actualTime: nil)
                let ui    = thumb.map { UIImage(cgImage: $0) }

                continuation.resume(returning: MediaItem(type: .video, image: ui, videoURL: dest))
            }
        }
    }

    // 動画一時ファイルを削除
    func cleanupTempFiles() {
        for url in tempVideoURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempVideoURLs.removeAll()
    }
}

// MARK: - スライディングキャッシュ（前・現在・次の最大3枚だけ保持）
@MainActor
class AssetCache: ObservableObject {

    @Published var currentItem: MediaItem? = nil
    @Published var isLoading:   Bool = false

    private var assets:  [PHAsset] = []
    private var cache:   [Int: MediaItem] = [:]   // index → MediaItem（最大3枚）
    private let loader = AssetLoader()
    private var loadingTasks: [Int: Task<Void, Never>] = [:]

    // アセット一覧をセット（以前のキャッシュはクリア）
    func setAssets(_ newAssets: [PHAsset]) {
        assets = newAssets
        cache.removeAll()
        cancelAllTasks()
        Task { await loader.cleanupTempFiles() }
    }

    var count: Int { assets.count }

    func asset(at index: Int) -> PHAsset? {
        guard index >= 0, index < assets.count else { return nil }
        return assets[index]
    }

    // 指定インデックスに切り替え（前後1枚をプリフェッチ）
    func prepare(index: Int) async {
        guard !assets.isEmpty else { return }

        isLoading = currentItem == nil

        // まず現在のコマを取得
        let item = await fetchItem(at: index)
        currentItem = item
        isLoading = false

        // 前後をバックグラウンドでプリフェッチ
        prefetch(index: index + 1)
        prefetch(index: index - 1)

        // 不要なキャッシュを破棄（3枚を超えた分）
        evict(keepIndices: [index - 1, index, index + 1])
    }

    // MARK: - Private
    private func fetchItem(at index: Int) async -> MediaItem? {
        guard index >= 0, index < assets.count else { return nil }
        if let cached = cache[index] { return cached }

        let asset = assets[index]
        let item  = await loader.load(asset: asset)
        if let item { cache[index] = item }
        return item
    }

    private func prefetch(index: Int) {
        guard index >= 0, index < assets.count else { return }
        guard cache[index] == nil, loadingTasks[index] == nil else { return }
        loadingTasks[index] = Task { [weak self] in
            guard let self else { return }
            let item = await self.loader.load(asset: self.assets[index])
            if let item { self.cache[index] = item }
            self.loadingTasks.removeValue(forKey: index)
        }
    }

    private func evict(keepIndices: [Int]) {
        let keep = Set(keepIndices)
        for key in cache.keys where !keep.contains(key) {
            // 動画の一時ファイルを削除
            if let url = cache[key]?.videoURL {
                try? FileManager.default.removeItem(at: url)
            }
            cache.removeValue(forKey: key)
        }
    }

    private func cancelAllTasks() {
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()
    }
}
