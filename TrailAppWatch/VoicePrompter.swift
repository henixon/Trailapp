import Foundation
import AVFoundation

/// Spoken turn prompts on the watch via AVSpeechSynthesizer.
///
/// Platform notes (verified against shipping watchOS apps):
/// - AVSpeechSynthesizer IS available on watchOS (part of AVFoundation).
/// - The *Speech* framework (SFSpeechRecognizer, speech-to-text) is NOT on
///   watchOS — we don't need it; prompts are text-to-speech only.
/// - Output routes to the watch speaker or paired Bluetooth headphones.
/// - Honors the silent-mode switch — prompts won't play when silenced.
/// - TODO (verify on device): audio behavior while an HKWorkoutSession is
///   active, and whether an AVAudioSession category tweak is needed for
///   reliable playback with the wrist down.
@MainActor
final class VoicePrompter: ObservableObject {
    /// User-facing kill switch, surfaced in the navigation UI.
    @Published var isEnabled = true

    private let synthesizer = AVSpeechSynthesizer()

    /// Speaks a prompt. When `interrupt` is true (safety/off-route), the
    /// current utterance is cut off immediately.
    func speak(_ text: String, interrupt: Bool = false) {
        guard isEnabled, !text.isEmpty else { return }
        if interrupt {
            synthesizer.stopSpeaking(at: .immediate)
        } else if synthesizer.isSpeaking {
            // Queue depth of one: never stack up stale prompts behind a slow
            // utterance — a hiker who missed the 200 m warning doesn't need it
            // read out after the 50 m one.
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
