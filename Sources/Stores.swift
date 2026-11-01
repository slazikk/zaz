import Foundation
import AVFoundation

@MainActor
final class SessionStore: ObservableObject {
    @Published var isAuthenticated = false
    @Published var error: String?
    init() {
        if let token = SecureStore.read() { isAuthenticated = true; Task { await ZvukAPI.shared.configure(token: token) } }
    }
    func signIn(token: String) async {
        error = nil
        do { try await ZvukAPI.shared.verifyToken(token); SecureStore.save(token); isAuthenticated = true }
        catch { self.error = error.localizedDescription }
    }
    func signOut() { SecureStore.delete(); isAuthenticated = false; Task { await ZvukAPI.shared.configure(token: nil) } }
}

@MainActor
final class PlayerStore: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var current: Track?
    @Published var isPlaying = false
    @Published var progress = 0.0
    @Published var duration = 0.0
    @Published var error: String?
    private var player: AVPlayer?
    private var observer: Any?
    func play(_ track: Track) async {
        error = nil
        do {
            let url = try await ZvukAPI.shared.streamURL(for: track.id)
            observer.map { player?.removeTimeObserver($0) }
            let newPlayer = AVPlayer(url: url); player = newPlayer; current = track; newPlayer.play(); isPlaying = true
            observer = newPlayer.addPeriodicTimeObserver(forInterval: .init(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
                Task { @MainActor in self?.progress = time.seconds.isFinite ? time.seconds : 0; self?.duration = newPlayer.currentItem?.duration.seconds.isFinite == true ? newPlayer.currentItem!.duration.seconds : Double(track.duration ?? 0) }
            }
        } catch { self.error = error.localizedDescription }
    }
    func toggle() { guard let player else { return }; isPlaying ? player.pause() : player.play(); isPlaying.toggle() }
    func seek(_ value: Double) { player?.seek(to: .init(seconds: value, preferredTimescale: 600)); progress = value }
}
