import Foundation
import Combine
import Photos
import AVFoundation
import SwiftUI

@MainActor
class SlideShowViewModel: ObservableObject {

    // MARK: - Published
    @Published var currentIndex: Int = 0 {
        didSet { UserDefaults.standard.set(currentIndex, forKey: UDKeys.currentIndex) }
    }
    @Published var isPlaying:    Bool = false
    @Published var showPicker:   Bool = false
    @Published var showSettings: Bool = false
    @Published var kenBurnsScale:  CGFloat = 1.0
    @Published var kenBurnsOffset: CGSize  = .zero

    let cache = AssetCache()
    let settings: SlideShowSettings

    // MARK: - Private
    /// 再生の全時間管理を担う単一Task。コマ切替のたびにキャンセル→新規起動。
    private var playTask: Task<Void, Never>?
    private var videoPlayer: AVPlayer?
    private var videoObserver: Any?
    private var randomHistory: [Int] = []
    private var randomQueue:   [Int] = []

    init(settings: SlideShowSettings) {
        self.settings = settings
    }

    // MARK: - Computed
    var totalCount: Int  { cache.count }
    var hasMedia:   Bool { cache.count > 0 }
    var currentItem: MediaItem? { cache.currentItem }

    // MARK: - 起動時復元
    func restoreSessionIfNeeded() async {
        let ud = UserDefaults.standard
        guard let ids = ud.stringArray(forKey: UDKeys.assetIdentifiers), !ids.isEmpty else { return }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assetMap: [String: PHAsset] = [:]
        fetchResult.enumerateObjects { a, _, _ in assetMap[a.localIdentifier] = a }
        let assets = ids.compactMap { assetMap[$0] }
        guard !assets.isEmpty else {
            ud.removeObject(forKey: UDKeys.assetIdentifiers)
            ud.removeObject(forKey: UDKeys.currentIndex)
            return
        }
        cache.setAssets(assets)
        resetRandomQueue()
        let savedIndex = ud.integer(forKey: UDKeys.currentIndex)
        currentIndex = min(savedIndex, assets.count - 1)
        await cache.prepare(index: currentIndex)
    }

    // MARK: - アセットロード
    func loadAssets(_ assets: [PHAsset]) async {
        stopPlayTask()
        stopVideo()
        let ids = assets.map { $0.localIdentifier }
        UserDefaults.standard.set(ids, forKey: UDKeys.assetIdentifiers)
        cache.setAssets(assets)
        currentIndex = 0
        resetRandomQueue()
        await cache.prepare(index: 0)
    }

    // MARK: - Playback control
    func startSlideShow() {
        guard hasMedia else { return }
        isPlaying = true
        launchPlayTask(for: currentIndex)
    }

    func stopSlideShow() {
        isPlaying = false
        stopPlayTask()
        stopVideo()
        resetKenBurns()
    }

    func togglePlayPause() {
        if isPlaying { stopSlideShow() } else { startSlideShow() }
    }

    func goNext() {
        guard hasMedia else { return }
        stopPlayTask()
        stopVideo()
        currentIndex = consumeNextIndex()
        if isPlaying {
            launchPlayTask(for: currentIndex)
        } else {
            Task { await cache.prepare(index: currentIndex) }
        }
    }

    func goPrevious() {
        guard hasMedia else { return }
        stopPlayTask()
        stopVideo()
        currentIndex = consumePrevIndex()
        if isPlaying {
            launchPlayTask(for: currentIndex)
        } else {
            Task { await cache.prepare(index: currentIndex) }
        }
    }

    // MARK: - 単一再生Task
    private func launchPlayTask(for index: Int) {
        stopPlayTask()

        playTask = Task { [weak self] in
            guard let self else { return }

            await self.cache.prepare(index: index)
            guard !Task.isCancelled, self.isPlaying else { return }
            guard let item = self.currentItem else { return }

            self.resetKenBurns()

            switch item.type {
            case .photo:
                await self.runPhotoTimer()
            case .video:
                await self.runVideoTimer(item: item)
            }

            guard !Task.isCancelled, self.isPlaying else { return }
            self.advanceToNext()
        }
    }

    // MARK: - 写真タイマー（Task.sleep ループで正確に計測）
    private func runPhotoTimer() async {
        startKenBurnsIfNeeded()
        let ticks = Int(ceil(settings.displayDuration / 0.05))
        for _ in 0..<ticks {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        }
    }

    // MARK: - 動画タイマー
    // 設計：
    //   - 動画終了通知を Continuation で非同期待機
    //   - 上限タイマーは playTask と同じ Task.sleep ループ（キャンセルに自動連動）
    //   - 両方をシンプルな async let で競争させる代わりに、
    //     上限ループを先に回しながら動画終了フラグをポーリングする方式を採用
    //     （withTaskGroup の actor 境界問題を回避）
    private func runVideoTimer(item: MediaItem) async {
        guard let url = item.videoURL else {
            await runPhotoTimer(); return
        }

        stopVideo()
        let player = AVPlayer(url: url)
        videoPlayer = player

        // 動画終了フラグ（メインアクター上でのみ読み書き）
        var videoFinished = false
        let obs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            // メインキューで呼ばれるのでメインアクター保証あり
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                videoFinished = true
            }
        }
        videoObserver = obs

        player.play()
        objectWillChange.send()

        // 上限まで50msずつ待ちながら動画終了を検知
        let videoDuration = settings.videoDuration
        let ticks = Int(ceil(videoDuration / 0.05))
        var elapsed = 0.0

        for _ in 0..<ticks {
            guard !Task.isCancelled else {
                cleanupVideo(player: player, obs: obs)
                return
            }
            if videoFinished { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
            elapsed += 0.05
        }

        // 動画が上限より短かった → 残り時間を静止待機
        if videoFinished && !Task.isCancelled {
            let played = player.currentTime().seconds
            let remaining = max(0.0, videoDuration - played)
            let remainTicks = Int(ceil(remaining / 0.05))
            for _ in 0..<remainTicks {
                guard !Task.isCancelled else { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        cleanupVideo(player: player, obs: obs)
    }

    private func cleanupVideo(player: AVPlayer, obs: Any) {
        player.pause()
        NotificationCenter.default.removeObserver(obs)
        if videoObserver as AnyObject? === obs as AnyObject? {
            videoObserver = nil
        }
        if videoPlayer === player {
            videoPlayer = nil
        }
    }

    // MARK: - 自動進行（タイマー完了時のみ）
    private func advanceToNext() {
        switch settings.playMode {
        case .sequential:
            let next = currentIndex + 1
            if next >= totalCount { isPlaying = false; return }
            currentIndex = next
        case .loop:
            currentIndex = (currentIndex + 1) % totalCount
        case .random:
            randomHistory.append(currentIndex)
            if randomQueue.isEmpty { refillRandomQueue() }
            currentIndex = randomQueue.removeFirst()
        }
        launchPlayTask(for: currentIndex)
    }

    // MARK: - インデックス計算（手動スキップ専用）
    private func consumeNextIndex() -> Int {
        switch settings.playMode {
        case .sequential:
            return min(currentIndex + 1, totalCount - 1)
        case .loop:
            return (currentIndex + 1) % totalCount
        case .random:
            randomHistory.append(currentIndex)
            if randomQueue.isEmpty { refillRandomQueue() }
            return randomQueue.removeFirst()
        }
    }

    private func consumePrevIndex() -> Int {
        if settings.playMode == .random, let prev = randomHistory.popLast() {
            return prev
        }
        return (currentIndex - 1 + totalCount) % totalCount
    }

    // MARK: - Task / Video 管理
    private func stopPlayTask() {
        playTask?.cancel()
        playTask = nil
    }

    private func stopVideo() {
        videoPlayer?.pause()
        if let obs = videoObserver {
            NotificationCenter.default.removeObserver(obs)
            videoObserver = nil
        }
        videoPlayer = nil
    }

    func makeVideoPlayer() -> AVPlayer? { videoPlayer }

    // MARK: - Random queue
    private func resetRandomQueue() {
        randomHistory = []; randomQueue = []; refillRandomQueue()
    }

    private func refillRandomQueue() {
        guard totalCount > 0 else { return }
        var indices = Array(0..<totalCount).shuffled()
        if indices.first == currentIndex, indices.count > 1 { indices.swapAt(0, 1) }
        randomQueue = indices
    }

    // MARK: - Ken Burns
    private func startKenBurnsIfNeeded() {
        guard settings.transitionType == .kenBurns else { return }
        kenBurnsScale = 1.0; kenBurnsOffset = .zero
        withAnimation(.linear(duration: settings.displayDuration)) {
            kenBurnsScale = 1.15
            kenBurnsOffset = CGSize(
                width: CGFloat.random(in: -30...30),
                height: CGFloat.random(in: -20...20)
            )
        }
    }

    private func resetKenBurns() { kenBurnsScale = 1.0; kenBurnsOffset = .zero }
}
