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
