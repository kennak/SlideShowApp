import Foundation
import Combine

enum TransitionType: String, CaseIterable, Identifiable {
    case crossFade = "クロスフェード"
    case slide     = "スライド"
    case kenBurns  = "ケン・バーンズ"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .crossFade: return "circle.lefthalf.filled"
        case .slide:     return "arrow.right.circle"
        case .kenBurns:  return "viewfinder"
        }
    }
}

enum PlayMode: String, CaseIterable, Identifiable {
    case sequential = "順番"
    case loop       = "ループ"
    case random     = "ランダム"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .sequential: return "arrow.right"
        case .loop:       return "repeat"
        case .random:     return "shuffle"
        }
    }
}

// MARK: - UserDefaults キー
enum UDKeys {
    // 設定
    static let displayDuration    = "displayDuration"
    static let videoDuration      = "videoDuration"
    static let transitionType     = "transitionType"
    static let transitionDuration = "transitionDuration"
    static let playMode           = "playMode"
    // 再生状態
    static let assetIdentifiers   = "assetIdentifiers"   // [String]
    static let currentIndex       = "currentIndex"       // Int
}

// MARK: - 設定モデル（UserDefaults で永続化）
class SlideShowSettings: ObservableObject {

    @Published var displayDuration: Double {
        didSet { UserDefaults.standard.set(displayDuration, forKey: UDKeys.displayDuration) }
    }
    @Published var videoDuration: Double {
        didSet { UserDefaults.standard.set(videoDuration, forKey: UDKeys.videoDuration) }
    }
    @Published var transitionType: TransitionType {
        didSet { UserDefaults.standard.set(transitionType.rawValue, forKey: UDKeys.transitionType) }
    }
    @Published var transitionDuration: Double {
        didSet { UserDefaults.standard.set(transitionDuration, forKey: UDKeys.transitionDuration) }
    }
    @Published var playMode: PlayMode {
        didSet { UserDefaults.standard.set(playMode.rawValue, forKey: UDKeys.playMode) }
    }

    init() {
        let ud = UserDefaults.standard
        displayDuration    = ud.object(forKey: UDKeys.displayDuration)    as? Double ?? 15.0
        videoDuration      = ud.object(forKey: UDKeys.videoDuration)      as? Double ?? 15.0
        transitionDuration = ud.object(forKey: UDKeys.transitionDuration) as? Double ?? 1.0

        if let raw = ud.string(forKey: UDKeys.transitionType),
           let saved = TransitionType(rawValue: raw) {
            transitionType = saved
        } else {
            transitionType = .crossFade
        }

        if let raw = ud.string(forKey: UDKeys.playMode),
           let saved = PlayMode(rawValue: raw) {
            playMode = saved
        } else {
            playMode = .loop
        }
    }
}
