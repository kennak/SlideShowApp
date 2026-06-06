import SwiftUI

struct SlideShowView: View {
    @ObservedObject var vm: SlideShowViewModel
    @ObservedObject private var cache: AssetCache  // キャッシュの変化を監視

    @State private var showControls = true
    @State private var controlHideTask: Task<Void, Never>?
    @State private var displayedIndex: Int = 0
    @State private var nextIndex: Int? = nil
    @State private var crossFadeOpacity: Double = 0.0

    init(vm: SlideShowViewModel) {
        self.vm = vm
        self.cache = vm.cache
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !vm.hasMedia {
                emptyPlaceholder
            } else if cache.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.5)
            } else {
                mediaContent
            }

            if showControls {
                controlOverlay
            }
        }
        .onTapGesture { toggleControls() }
        .onAppear { scheduleHideControls() }
        .onChange(of: vm.currentIndex) { newIndex in
            animateTransition(to: newIndex)
        }
        .statusBar(hidden: false)
    }

    // MARK: - Media Content
    @ViewBuilder
    private var mediaContent: some View {
        switch vm.settings.transitionType {
        case .crossFade, .kenBurns:
            ZStack {
                if let item = cache.currentItem, displayedIndex == vm.currentIndex {
                    MediaItemView(item: item, vm: vm)
                        .ignoresSafeArea()
                }
                if nextIndex != nil, let item = cache.currentItem {
                    MediaItemView(item: item, vm: vm)
                        .ignoresSafeArea()
                        .opacity(crossFadeOpacity)
                }
            }
        case .slide:
            ZStack {
                if let item = cache.currentItem, displayedIndex == vm.currentIndex {
                    MediaItemView(item: item, vm: vm)
                        .ignoresSafeArea()
                        .offset(x: nextIndex != nil ? -UIScreen.main.bounds.width * (1 - crossFadeOpacity) : 0)
                }
                if nextIndex != nil, let item = cache.currentItem {
                    MediaItemView(item: item, vm: vm)
                        .ignoresSafeArea()
                        .offset(x: UIScreen.main.bounds.width * (1 - crossFadeOpacity))
                }
            }
        }
    }

    // MARK: - Transition
    private func animateTransition(to newIndex: Int) {
        let duration = vm.settings.transitionDuration
        nextIndex = newIndex
        crossFadeOpacity = 0.0
        withAnimation(.easeInOut(duration: duration)) {
            crossFadeOpacity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            displayedIndex = newIndex
            nextIndex = nil
            crossFadeOpacity = 0.0
        }
    }

    // MARK: - Control Overlay
    private var controlOverlay: some View {
        VStack {
            HStack {
                Button(action: { vm.showSettings = true }) {
                    Image(systemName: "gear")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Spacer()
                if vm.hasMedia {
                    Text("\(vm.currentIndex + 1) / \(vm.totalCount)")
                        .foregroundColor(.white)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
                Button(action: { vm.showPicker = true }) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()

            HStack(spacing: 48) {
                Button(action: { vm.goPrevious(); resetHideTimer() }) {
                    Image(systemName: "backward.fill")
                        .font(.largeTitle).foregroundColor(.white)
                }
                .disabled(!vm.hasMedia)

                Button(action: { vm.togglePlayPause(); resetHideTimer() }) {
                    Image(systemName: vm.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64)).foregroundColor(.white)
                }
                .disabled(!vm.hasMedia)

                Button(action: { vm.goNext(); resetHideTimer() }) {
                    Image(systemName: "forward.fill")
                        .font(.largeTitle).foregroundColor(.white)
                }
                .disabled(!vm.hasMedia)
            }
            .padding(.bottom, 60)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: showControls)
    }

    // MARK: - Empty state
    private var emptyPlaceholder: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.stack")
                .font(.system(size: 72))
                .foregroundColor(.white.opacity(0.4))
            Text("写真・動画を選択してください")
                .foregroundColor(.white.opacity(0.6))
                .font(.headline)
            Button(action: { vm.showPicker = true }) {
                Label("アルバムを開く", systemImage: "photo.on.rectangle")
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(.white.opacity(0.15), in: Capsule())
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Controls visibility
    private func toggleControls() {
        withAnimation { showControls.toggle() }
        if showControls { scheduleHideControls() }
    }

    private func scheduleHideControls() {
        controlHideTask?.cancel()
        controlHideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { withAnimation { showControls = false } }
        }
    }

    private func resetHideTimer() {
        showControls = true
        scheduleHideControls()
    }
}
