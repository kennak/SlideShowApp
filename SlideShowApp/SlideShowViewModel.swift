import Foundation
import Combine
import Photos
import AVFoundation
import SwiftUI

@MainActor
class SlideShowViewModel: ObservableObject {

    // MARK: - Published
    @Published var currentIndex: Int = 0
    @Published var isPlaying:    Bool = false
    @Published var showPicker:   Bool = false
    @Published var showSettings: Bool = false

    @Published var kenBurnsScale:  CGFloat = 1.0
    @Published var kenBurnsOffset: CGSize  = .zero

    // キャッシュ（最大3枚のみメモリ保持）
    let cache = AssetCache()

    // MARK: - Dependencies
    let settings: SlideShowSettings

    // MARK: - Private
    private var timer: Timer?
    private var videoPlayer: AVPlayer?
    private var videoObserver: Any?
    private var elapsedTime: Double = 0
    private let tickInterval: Double = 0.25
    private var randomHistory: [Int] = []
    private var randomQueue:   [Int] = []

    init(settings: SlideShowSettings) {
        self.settings = settings
    }

    // MARK: - Computed
    var totalCount: Int  { cache.count }
    var hasMedia:   Bool { cache.count > 0 }
    var currentItem: MediaItem? { cache.currentItem }

    // MARK: - アセットロード（PHAsset配列を受け取るだけ。展開はオンデマンド）
    func loadAssets(_ assets: [PHAsset]) async {
        cache.setAssets(assets)
        currentIndex = 0
        resetRandomQueue()
        await cache.prepare(index: 0)
    }

    // MARK: - Playback control
    func startSlideShow() {
        guard hasMedia else { return }
        isPlaying = true
        resetRandomQueue()
        startCurrentItem()
    }

    func stopSlideShow() {
        isPlaying = false
        stopTimer()
        stopVideo()
        resetKenBurns()
    }

    func togglePlayPause() {
        if isPlaying { stopSlideShow() } else { startSlideShow() }
    }

    func goNext() { advance(manual: true) }

    func goPrevious() {
        stopTimer(); stopVideo()
        if settings.playMode == .random, let prev = randomHistory.popLast() {
            currentIndex = prev
        } else {
            currentIndex = (currentIndex - 1 + totalCount) % totalCount
        }
        Task { await cache.prepare(index: currentIndex) }
        if isPlaying { startCurrentItem() }
    }

    // MARK: - Internal playback
    private func startCurrentItem() {
        stopTimer(); stopVideo(); resetKenBurns()
        elapsedTime = 0
        guard let item = currentItem else { return }
        switch item.type {
        case .photo:
            startKenBurnsIfNeeded()
            startTimer(duration: settings.displayDuration)
        case .video:
            if let url = item.videoURL { setupVideo(url: url) }
            else { startTimer(duration: settings.videoDuration) }
        }
    }

    private func startTimer(duration: Double) {
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.elapsedTime += self.tickInterval
                if self.elapsedTime >= duration { self.advance(manual: false) }
            }
        }
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }

    private func advance(manual: Bool) {
        stopTimer(); stopVideo()
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
        // 次のコマをキャッシュ準備してから再生開始
        Task { [weak self] in
            guard let self else { return }
            await self.cache.prepare(index: self.currentIndex)
            if self.isPlaying { self.startCurrentItem() }
        }
    }

    private func resetRandomQueue() {
        randomHistory = []; randomQueue = []; refillRandomQueue()
    }

    private func refillRandomQueue() {
        guard totalCount > 0 else { return }
        var indices = Array(0..<totalCount).shuffled()
        if indices.first == currentIndex, indices.count > 1 { indices.swapAt(0, 1) }
        randomQueue = indices
    }

    // MARK: - Video
    private func setupVideo(url: URL) {
        let player = AVPlayer(url: url)
        videoPlayer = player
        videoObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let remaining = self.settings.videoDuration - self.elapsedTime
                if remaining > 0 { self.startTimer(duration: remaining + self.elapsedTime) }
                else { self.advance(manual: false) }
            }
        }
        startTimer(duration: settings.videoDuration)
        player.play()
        objectWillChange.send()
    }

    private func stopVideo() {
        videoPlayer?.pause()
        if let obs = videoObserver {
            NotificationCenter.default.removeObserver(obs); videoObserver = nil
        }
        videoPlayer = nil
    }

    func makeVideoPlayer() -> AVPlayer? { videoPlayer }

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
