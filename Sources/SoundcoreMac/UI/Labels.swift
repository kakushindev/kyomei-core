import SoundcoreKit

extension AmbientSoundMode {
    var title: String {
        switch self {
        case .noiseCanceling: "Noise Cancelling"
        case .transparency: "Transparency"
        case .normal: "Normal"
        }
    }

    var shortTitle: String {
        switch self {
        case .noiseCanceling: "ANC"
        case .transparency: "Aware"
        case .normal: "Off"
        }
    }

    var symbol: String {
        switch self {
        case .noiseCanceling: "waveform.badge.minus"
        case .transparency: "ear.and.waveform"
        case .normal: "speaker.wave.2"
        }
    }

    var caption: String {
        switch self {
        case .noiseCanceling: "Block outside noise"
        case .transparency: "Hear your surroundings"
        case .normal: "No processing"
        }
    }
}

extension NoiseCancelingMode {
    var title: String {
        switch self {
        case .adaptive: "Adaptive"
        case .manual: "Manual"
        case .multiScene: "Scene"
        case .transportation: "Transport"
        case .transport: "Transport"
        case .outdoor: "Outdoor"
        case .indoor: "Indoor"
        case .custom: "Custom"
        }
    }

    var symbol: String {
        switch self {
        case .adaptive: "sparkles"
        case .manual: "slider.horizontal.3"
        case .multiScene: "square.grid.2x2"
        case .transportation, .transport: "tram.fill"
        case .outdoor: "tree.fill"
        case .indoor: "house.fill"
        case .custom: "dial.medium"
        }
    }
}

extension TransparencyMode {
    var title: String {
        switch self {
        case .fullyTransparent: "Fully Transparent"
        case .vocal: "Vocal Mode"
        case .talk: "Talk Mode"
        case .manual: "Custom"
        }
    }
}

extension MultiSceneMode {
    var title: String {
        switch self {
        case .transport: "Transport"
        case .outdoor: "Outdoor"
        case .indoor: "Indoor"
        }
    }

    var symbol: String {
        switch self {
        case .transport: "tram.fill"
        case .outdoor: "tree.fill"
        case .indoor: "house.fill"
        }
    }
}

extension TransportationMode {
    var title: String {
        switch self {
        case .plane: "Plane"
        case .train: "Train"
        case .bus: "Bus"
        case .car: "Car"
        }
    }

    var symbol: String {
        switch self {
        case .plane: "airplane"
        case .train: "tram.fill"
        case .bus: "bus.fill"
        case .car: "car.fill"
        }
    }
}

extension SpatialAudioMode {
    var title: String {
        switch self {
        case .music: "Music"
        case .movie: "Movie"
        case .gaming: "Gaming"
        }
    }

    var symbol: String {
        switch self {
        case .music: "music.note"
        case .movie: "film"
        case .gaming: "gamecontroller"
        }
    }
}

extension PressKind {
    var title: String {
        switch self {
        case .single: "Single Tap"
        case .double: "Double Tap"
        case .triple: "Triple Tap"
        case .long: "Press and Hold"
        }
    }

    var symbol: String {
        switch self {
        case .single: "hand.tap"
        case .double: "hand.tap.fill"
        case .triple: "circle.grid.3x3"
        case .long: "hand.point.up.left"
        }
    }
}

extension ButtonAction {
    var title: String {
        switch self {
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .previousSong: "Previous Track"
        case .nextSong: "Next Track"
        case .ambientSoundMode: "Switch Sound Mode"
        case .voiceAssistant: "Voice Assistant"
        case .playPause: "Play / Pause"
        case .bassUp: "BassUp"
        case .gamingMode: "Gaming Mode"
        }
    }
}

extension DecibelRefreshRate {
    var title: String {
        switch self {
        case .realTime: "Real Time"
        case .tenSeconds: "Every 10 s"
        case .oneMinute: "Every Minute"
        }
    }
}

extension DeviceFlag {
    var title: String {
        switch self {
        case .ldac: "LDAC"
        case .touchTone: "Touch Tone"
        case .lowBatteryPrompt: "Low Battery Prompt"
        case .wearingDetection: "Wear Detection"
        case .wearingTone: "Wearing Tone"
        case .autoPlayPause: "Auto Play / Pause"
        case .gamingMode: "Gaming Mode"
        case .touchLock: "Touch Lock"
        case .soundLeakCompensation: "Sound Leak Compensation"
        case .surroundSound: "3D Surround"
        case .voicePrompt: "Voice Prompts"
        case .batteryAlert: "Battery Alert"
        case .ambientSoundModeVoicePrompt: "Sound Mode Voice Prompt"
        }
    }

    var detail: String? {
        switch self {
        case .ldac: "High-resolution Bluetooth audio. macOS streams AAC/SBC, so this mostly matters for Android sources."
        case .wearingDetection: "Pause when you take the headphones off."
        case .autoPlayPause: "Resume playback when you put them back on."
        case .gamingMode: "Lower latency for games and video."
        case .touchLock: "Ignore accidental touches."
        case .soundLeakCompensation: "Keeps bass full when the fit is loose."
        case .surroundSound: "Virtual 3D sound stage."
        default: nil
        }
    }

    var symbol: String {
        switch self {
        case .ldac: "hifispeaker"
        case .touchTone: "hand.tap"
        case .lowBatteryPrompt, .batteryAlert: "battery.25percent"
        case .wearingDetection: "ear"
        case .wearingTone: "bell"
        case .autoPlayPause: "playpause"
        case .gamingMode: "gamecontroller"
        case .touchLock: "lock"
        case .soundLeakCompensation: "drop"
        case .surroundSound: "dot.radiowaves.left.and.right"
        case .voicePrompt, .ambientSoundModeVoicePrompt: "text.bubble"
        }
    }

    /// Settings shown in the Audio group rather than General.
    var isAudio: Bool { [.ldac, .gamingMode, .soundLeakCompensation, .surroundSound].contains(self) }
}

func formatFrequency(_ hz: Int) -> String {
    hz >= 1000 ? (hz % 1000 == 0 ? "\(hz / 1000)k" : String(format: "%.1fk", Double(hz) / 1000)) : "\(hz)"
}

func formatDecibels(_ tenths: Int16) -> String {
    let db = Double(tenths) / 10
    return (db > 0 ? "+" : "") + String(format: "%.1f", db)
}

let equalizerFrequencies = [100, 200, 400, 800, 1600, 3200, 6400, 12800]
