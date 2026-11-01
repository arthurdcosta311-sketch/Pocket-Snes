//
//  AppSettings.swift
//  Pocket Snes
//
//  Interface preferences. The display and audio values are read here and passed
//  to the engine once it is wired in.
//

import Foundation

enum VideoFilter: String, CaseIterable, Identifiable, Hashable {
    case sharp
    case crt
    case smooth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sharp:
            return "Sharp"
        case .crt:
            return "CRT"
        case .smooth:
            return "Soft"
        }
    }
}

enum ScreenFit: String, CaseIterable, Identifiable, Hashable {
    case fit
    case fill
    case pixelPerfect

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fit:
            return "Fit"
        case .fill:
            return "Fill"
        case .pixelPerfect:
            return "Integer"
        }
    }
}

enum ControllerSkin: String, CaseIterable, Identifiable, Hashable {
    case snesPocket
    case classic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .snesPocket:
            return "Pocket"
        case .classic:
            return "Classic"
        }
    }
}

final class AppSettings: ObservableObject {
    @Published var scanlines: Bool = true
    @Published var videoFilter: VideoFilter = .sharp
    @Published var screenFit: ScreenFit = .fit

    @Published var volume: Double = 0.8
    @Published var muted: Bool = false

    @Published var controlSkin: ControllerSkin = .snesPocket
    @Published var controlOpacity: Double = 0.92
    @Published var haptics: Bool = true
    @Published var showsShoulders: Bool = true

    var volumeLabel: String {
        return "\(Int((volume * 100).rounded()))%"
    }

    var controlOpacityLabel: String {
        return "\(Int((controlOpacity * 100).rounded()))%"
    }
}
