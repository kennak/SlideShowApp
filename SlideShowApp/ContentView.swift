import SwiftUI
import Photos

struct ContentView: View {
    @StateObject private var settings = SlideShowSettings()
    @StateObject private var vm: SlideShowViewModel

    init() {
        let s = SlideShowSettings()
        _settings = StateObject(wrappedValue: s)
        _vm = StateObject(wrappedValue: SlideShowViewModel(settings: s))
    }

    var body: some View {
        SlideShowView(vm: vm)
            .task {
                // 起動時：フォトライブラリへのアクセス権があれば前回の状態を復元
                let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                if status == .authorized || status == .limited {
                    await vm.restoreSessionIfNeeded()
                }
            }
            .sheet(isPresented: $vm.showPicker) {
                SmartPhotoPickerView { assets in
                    vm.showPicker = false
                    Task { await vm.loadAssets(assets) }
                }
            }
            .sheet(isPresented: $vm.showSettings) {
                SettingsView(settings: settings)
            }
    }
}
