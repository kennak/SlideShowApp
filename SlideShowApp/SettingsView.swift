import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SlideShowSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                // MARK: - 再生モード
                Section(String(localized: "settings.section.playmode")) {
                    Picker(String(localized: "settings.section.playmode"), selection: $settings.playMode) {
                        ForEach(PlayMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                }

                // MARK: - 表示時間
                Section {
                    durationRow(
                        title: String(localized: "settings.photo.duration"),
                        icon: "photo",
                        value: $settings.displayDuration,
                        range: 3...60
                    )
                    durationRow(
                        title: String(localized: "settings.video.duration"),
                        icon: "video",
                        value: $settings.videoDuration,
                        range: 3...60
                    )
                } header: {
                    Text(String(localized: "settings.section.duration"))
                } footer: {
                    Text(String(localized: "settings.video.footer"))
                }

                // MARK: - トランジション
                Section(String(localized: "settings.section.transition")) {
                    Picker(String(localized: "settings.transition.type"), selection: $settings.transitionType) {
                        ForEach(TransitionType.allCases) { type in
                            Label(type.displayName, systemImage: type.systemImage)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.inline)

                    durationRow(
                        title: String(localized: "settings.transition.duration"),
                        icon: "clock",
                        value: $settings.transitionDuration,
                        range: 0.3...2.0,
                        step: 0.1,
                        unit: String(localized: "settings.duration.unit")
                    )
                }
            }
            .navigationTitle(String(localized: "settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "settings.done")) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func durationRow(
        title: String,
        icon: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1.0,
        unit: String = "s"
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
            HStack {
                Slider(value: value, in: range, step: step)
                Text(String(format: step < 1 ? "%.1f\(unit)" : "%.0f\(unit)", value.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }
}
