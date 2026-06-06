import Foundation
import Combine

enum TransitionType: String, CaseIterable, Identifiable {
    case crossFade
    case slide
    case kenBurns

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .crossFade: return String(localized: "transition.crossfade")
        case .slide:     return String(localized: "transition.slide")
        case .kenBurns:  return String(localized: "transition.kenburns")
        }
    }

    var systemImage: String {
        switch self {
        case .crossFade: return "circle.lefthalf.filled"
        case .slide:     return "arrow.right.circle"
        case .kenBurns:  return "viewfinder"
        }
    }
}

enum PlayMode: String, CaseIterable, Identifiable {
    case sequential
    case loop
    case random

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sequential: return String(localized: "playmode.sequential")
        case .loop:       return String(localized: "playmode.loop")
        case .random:     return String(localized: "playmode.random")
        }
    }

    var systemImage: String {
        switch self {
        case .sequential: return "arrow.right"
        case .loop:       return "repeat"
        case .random:     return "shuffle"
        }
    }
}

enum UDKeys {
    static let displayDuration    = "displayDuration"
    static let videoDuration      = "videoDuration"
    static let transitionType     = "transitionType"
    static let transitionDuration = "transitionDuration"
    static let playMode           = "playMode"
    static let assetIdentifiers   = "assetIdentifiers"
    static let currentIndex       = "currentIndex"
}

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
