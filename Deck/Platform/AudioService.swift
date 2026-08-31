import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// The sound vocabulary.
///
/// Cards, paper and a printing press — no casino. A card landing is a short
/// papery snap, not a chime; the achievement mark is a two-note stamp, not a
/// fanfare.
public enum SoundCue: String, CaseIterable, Sendable {
    case cardPlace
    case cardPickUp
    case cardDeal
    case cardFlip
    case shuffle
    case invalid
    case turnChange
    case handoff
    case reveal
    case collect
    case chip
    case victory
    case defeat
    case achievement
    case boss
    case stamp
}

/// Plays the sound cues.
///
/// Sounds are synthesised rather than shipped as files: each cue is a short
/// shaped burst of filtered noise or a two-partial tone, which keeps the app
/// small, keeps every cue in the same sonic family, and lets a sound pack
/// re-tune the whole set by changing a few numbers.
public final class AudioService: @unchecked Sendable {
    public static let shared = AudioService()

    public var isEnabled: Bool = true
    /// The selected sound pack, which retunes the whole set.
    public var packID: String = "sound.paper"

    #if canImport(AVFoundation)
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var format: AVAudioFormat?
    private var buffers: [SoundCue: AVAudioPCMBuffer] = [:]
    #endif
    private var isPrepared = false

    private init() {}

    /// Builds the audio graph and renders every cue once.
    public func prepare() {
        guard !isPrepared else { return }
        isPrepared = true
        #if canImport(AVFoundation)
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        self.engine = engine
        self.player = player
        self.format = format

        // Playback shares the session with other apps rather than taking it
        // over: nobody wants a card game to stop their music.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        for cue in SoundCue.allCases {
            buffers[cue] = render(cue: cue, format: format)
        }
        try? engine.start()
        player.play()
        #endif
    }

    public func play(_ cue: SoundCue) {
        guard isEnabled else { return }
        #if canImport(AVFoundation)
        guard let player, let buffer = buffers[cue] else { return }
        if engine?.isRunning == false { try? engine?.start() }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        #endif
    }

    /// Stops everything, for backgrounding.
    public func suspend() {
        #if canImport(AVFoundation)
        player?.stop()
        engine?.pause()
        #endif
    }

    public func resume() {
        #if canImport(AVFoundation)
        guard let engine, let player else { return }
        try? engine.start()
        player.play()
        #endif
    }

    #if canImport(AVFoundation)
    /// Renders one cue into a buffer.
    ///
    /// Two ingredients: filtered noise for anything made of paper, and a decaying
    /// sine pair for anything that is a mark or a stamp.
    private func render(cue: SoundCue, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let recipe = self.recipe(for: cue)
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * recipe.duration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        var noiseState: UInt64 = 0x1234_5678_9ABC_DEF0
        // A one-pole low-pass, which is what turns white noise into paper.
        var filtered: Float = 0
        let cutoff = Float(recipe.brightness)

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let progress = t / recipe.duration
            // Fast attack, exponential decay: the shape of something being put down.
            let attack = min(1.0, t / max(0.0005, recipe.attack))
            let decay = exp(-Double(progress) * recipe.decay)
            let envelope = Float(attack * decay)

            var sample: Float = 0
            if recipe.noise > 0 {
                noiseState ^= noiseState << 13
                noiseState ^= noiseState >> 7
                noiseState ^= noiseState << 17
                let white = Float(Int32(truncatingIfNeeded: noiseState)) / Float(Int32.max)
                filtered += cutoff * (white - filtered)
                sample += filtered * Float(recipe.noise)
            }
            for partial in recipe.partials {
                let frequency = partial.frequency * (1.0 + partial.sweep * progress)
                sample += Float(sin(2 * Double.pi * frequency * t) * partial.level)
            }
            channel[frame] = sample * envelope * Float(recipe.level)
        }
        return buffer
    }

    private struct Partial {
        var frequency: Double
        var level: Double
        /// Fractional pitch change over the length of the cue.
        var sweep: Double = 0
    }

    private struct Recipe {
        var duration: Double
        var attack: Double
        var decay: Double
        var noise: Double
        var brightness: Double
        var level: Double
        var partials: [Partial]
    }

    /// The pack retunes brightness and pitch; the shapes stay the same, which is
    /// why every pack still sounds like DECK.
    private func recipe(for cue: SoundCue) -> Recipe {
        let packBrightness: Double
        let packPitch: Double
        switch packID {
        case "sound.felt": packBrightness = 0.10; packPitch = 0.92
        case "sound.press": packBrightness = 0.34; packPitch = 1.10
        default: packBrightness = 0.22; packPitch = 1.0
        }

        func tone(_ frequency: Double, _ level: Double, sweep: Double = 0) -> Partial {
            Partial(frequency: frequency * packPitch, level: level, sweep: sweep)
        }

        switch cue {
        case .cardPlace:
            return Recipe(duration: 0.09, attack: 0.001, decay: 26, noise: 0.9,
                          brightness: packBrightness, level: 0.5, partials: [tone(180, 0.06)])
        case .cardPickUp:
            return Recipe(duration: 0.07, attack: 0.002, decay: 30, noise: 0.7,
                          brightness: packBrightness * 1.4, level: 0.35, partials: [])
        case .cardDeal:
            return Recipe(duration: 0.11, attack: 0.001, decay: 22, noise: 1.0,
                          brightness: packBrightness * 1.2, level: 0.42, partials: [])
        case .cardFlip:
            return Recipe(duration: 0.13, attack: 0.001, decay: 18, noise: 0.85,
                          brightness: packBrightness * 1.6, level: 0.45,
                          partials: [tone(240, 0.05, sweep: -0.3)])
        case .shuffle:
            return Recipe(duration: 0.55, attack: 0.02, decay: 5, noise: 1.0,
                          brightness: packBrightness * 1.1, level: 0.4, partials: [])
        case .invalid:
            return Recipe(duration: 0.16, attack: 0.002, decay: 14, noise: 0.3,
                          brightness: 0.08, level: 0.4,
                          partials: [tone(150, 0.5), tone(101, 0.35)])
        case .turnChange:
            return Recipe(duration: 0.14, attack: 0.003, decay: 16, noise: 0.15,
                          brightness: packBrightness, level: 0.32,
                          partials: [tone(440, 0.3), tone(660, 0.12)])
        case .handoff:
            return Recipe(duration: 0.34, attack: 0.004, decay: 7, noise: 0.4,
                          brightness: packBrightness * 0.8, level: 0.42,
                          partials: [tone(196, 0.35, sweep: -0.15), tone(294, 0.18)])
        case .reveal:
            return Recipe(duration: 0.30, attack: 0.005, decay: 8, noise: 0.35,
                          brightness: packBrightness * 1.3, level: 0.42,
                          partials: [tone(330, 0.3, sweep: 0.25), tone(495, 0.15)])
        case .collect:
            return Recipe(duration: 0.22, attack: 0.002, decay: 12, noise: 0.8,
                          brightness: packBrightness, level: 0.45, partials: [tone(160, 0.2)])
        case .chip:
            return Recipe(duration: 0.10, attack: 0.001, decay: 24, noise: 0.35,
                          brightness: 0.5, level: 0.4,
                          partials: [tone(1400, 0.22), tone(2100, 0.1)])
        case .victory:
            return Recipe(duration: 0.75, attack: 0.006, decay: 4, noise: 0.1,
                          brightness: packBrightness, level: 0.44,
                          partials: [tone(392, 0.3), tone(523, 0.26), tone(659, 0.2)])
        case .defeat:
            return Recipe(duration: 0.6, attack: 0.008, decay: 5, noise: 0.12,
                          brightness: packBrightness * 0.6, level: 0.4,
                          partials: [tone(294, 0.3, sweep: -0.12), tone(233, 0.24)])
        case .achievement:
            return Recipe(duration: 0.5, attack: 0.003, decay: 6, noise: 0.2,
                          brightness: packBrightness * 1.4, level: 0.46,
                          partials: [tone(523, 0.28), tone(784, 0.22, sweep: 0.04)])
        case .boss:
            return Recipe(duration: 0.7, attack: 0.02, decay: 4, noise: 0.3,
                          brightness: packBrightness * 0.5, level: 0.46,
                          partials: [tone(110, 0.4), tone(147, 0.2, sweep: 0.05)])
        case .stamp:
            return Recipe(duration: 0.18, attack: 0.0008, decay: 15, noise: 0.7,
                          brightness: packBrightness * 0.7, level: 0.55,
                          partials: [tone(90, 0.4)])
        }
    }
    #endif
}
