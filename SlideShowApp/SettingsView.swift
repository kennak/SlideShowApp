import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SlideShowSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                // MARK: - 再生モード
                Section("再生モード") {
                    Picker("モード", selection: $settings.playMode) {
                        ForEach(PlayMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                }

                // MARK: - 表示時間
                Section {
                    durationRow(
                        title: "写真の表示時間",
                        icon: "photo",
                        value: $settings.displayDuration,
                        range: 3...60
                    )
                    durationRow(
                        title: "動画の最大表示時間",
                        icon: "video",
                        value: $settings.videoDuration,
                        range: 3...60
                    )
                } header: {
                    Text("表示時間")
                } footer: {
                    Text("動画が最大表示時間より短い場合は、終了後に静止して残り時間を待ちます。")
                }

                // MARK: - トランジション
                Section("トランジション") {
                    Picker("種類", selection: $settings.transitionType) {
                        ForEach(TransitionType.allCases) { type in
                            Label(type.rawValue, systemImage: type.systemImage)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.inline)

                    durationRow(
                        title: "切り替え時間",
                        icon: "clock",
                        value: $settings.transitionDuration,
                        range: 0.3...2.0,
                        step: 0.1,
                        unit: "秒"
                    )
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }

    // MARK: - Helper
    @ViewBuilder
    private func durationRow(
        title: String,
        icon: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1.0,
        unit: String = "秒"
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
            HStack {
                Slider(value: value, in: range, step: step)
                Text(String(format: step < 1 ? "%.1f\(unit)" : "%.0f\(unit)", value.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }
}
