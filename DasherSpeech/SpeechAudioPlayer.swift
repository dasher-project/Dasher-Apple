#if os(macOS) || os(iOS)
import AVFoundation
import Foundation

@MainActor
final class SpeechAudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var completion: ((Error?) -> Void)?
    #if os(iOS)
    private var audioSessionActive = false
    #endif

    func play(_ data: Data, completion: @escaping (Error?) -> Void) throws {
        let player = try AVAudioPlayer(data: data)
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
        audioSessionActive = true
        #endif
        player.delegate = self
        self.player = player
        self.completion = completion
        guard player.play() else {
            stop()
            throw SpeechSetupError.playbackFailed
        }
    }

    func stop() {
        player?.delegate = nil
        player?.stop()
        player = nil
        completion = nil
        #if os(iOS)
        if audioSessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioSessionActive = false
        }
        #endif
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        didFinish(ObjectIdentifier(player), error: flag ? nil : SpeechSetupError.playbackFailed)
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        didFinish(ObjectIdentifier(player), error: error ?? SpeechSetupError.playbackFailed)
    }

    private nonisolated func didFinish(_ playerID: ObjectIdentifier, error: Error?) {
        Task { @MainActor in
            guard let player, ObjectIdentifier(player) == playerID else { return }
            let completion = self.completion
            stop()
            completion?(error)
        }
    }
}
#endif
