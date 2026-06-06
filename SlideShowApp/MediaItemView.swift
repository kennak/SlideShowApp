import SwiftUI
import AVKit

struct MediaItemView: View {
    let item: MediaItem
    @ObservedObject var vm: SlideShowViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch item.type {
            case .photo:
                photoView

            case .video:
                videoView
            }
        }
    }

    // MARK: - Photo
    @ViewBuilder
    private var photoView: some View {
        if let img = item.image {
            let content = Image(uiImage: img)
                .resizable()
                .scaledToFit()

            switch vm.settings.transitionType {
            case .kenBurns:
                content
                    .scaleEffect(vm.kenBurnsScale)
                    .offset(vm.kenBurnsOffset)
                    .clipped()
                    .ignoresSafeArea()

            default:
                content
            }
        }
    }

    // MARK: - Video
    @ViewBuilder
    private var videoView: some View {
        if let player = vm.makeVideoPlayer() {
            VideoPlayer(player: player)
                .ignoresSafeArea()
        } else if let thumb = item.image {
            // 動画読み込み中はサムネイル表示
            Image(uiImage: thumb)
                .resizable()
                .scaledToFit()
        }
    }
}
