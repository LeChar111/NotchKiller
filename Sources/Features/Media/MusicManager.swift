import AppKit
import Combine

@MainActor
@Observable
final class MusicManager {
    static let shared = MusicManager()

    var songTitle: String = ""
    var artistName: String = ""
    var albumName: String = ""
    var albumArt: NSImage?
    var isPlaying: Bool = false
    var isIdle: Bool = true
    var songDuration: TimeInterval = 0
    var elapsedTime: TimeInterval = 0
    var volume: Double = 0.5
    var isShuffled: Bool = false
    var repeatMode: RepeatMode = .off
    var bundleIdentifier: String = ""
    var lastUpdated: Date = .distantPast

    private var pollTimer: Timer?
    private var appleMusicNotificationTask: Task<Void, Never>?
    private var spotifyNotificationTask: Task<Void, Never>?

    private init() {
        if Demo.isActive {
            songTitle = "Midnight Circuit"
            artistName = "Neon Harbor"
            albumName = "Low Tide Signals"
            albumArt = Demo.artwork()
            isPlaying = true
            isIdle = false
            songDuration = 214
            elapsedTime = 83
            bundleIdentifier = "com.apple.Music"
            lastUpdated = Date()
            return
        }
        setupNotificationObservers()
        startPolling()
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Playback Controls

    func togglePlay() async {
        if bundleIdentifier == "com.spotify.client" {
            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to playpause")
        } else {
            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to playpause")
        }
        try? await Task.sleep(for: .milliseconds(100))
        await updatePlaybackInfo()
    }

    func nextTrack() async {
        if bundleIdentifier == "com.spotify.client" {
            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to next track")
        } else {
            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to next track")
        }
        try? await Task.sleep(for: .milliseconds(200))
        await updatePlaybackInfo()
    }

    func previousTrack() async {
        if bundleIdentifier == "com.spotify.client" {
            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to previous track")
        } else {
            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to previous track")
        }
        try? await Task.sleep(for: .milliseconds(200))
        await updatePlaybackInfo()
    }

    // MARK: - Setup

    private func setupNotificationObservers() {
        appleMusicNotificationTask = Task { [weak self] in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: NSNotification.Name("com.apple.Music.playerInfo")
            )
            for await _ in notifications {
                await self?.updatePlaybackInfo()
            }
        }

        spotifyNotificationTask = Task { [weak self] in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: NSNotification.Name("com.spotify.client.PlaybackStateChanged")
            )
            for await _ in notifications {
                await self?.updatePlaybackInfo()
            }
        }
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updatePlaybackInfo()
            }
        }
        pollTimer?.tolerance = 1.0
        Task { await updatePlaybackInfo() }
    }

    // MARK: - Update

    func updatePlaybackInfo() async {
        // Try Apple Music first, then Spotify
        let musicRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.Music"
        }
        let spotifyRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.spotify.client"
        }

        if musicRunning {
            await updateFromAppleMusic()
        } else if spotifyRunning {
            await updateFromSpotify()
        } else {
            isIdle = true
            isPlaying = false
        }
    }

    private func updateFromAppleMusic() async {
        let script = """
        tell application "Music"
            try
                set playerState to player state is playing
                set currentTrackName to name of current track
                set currentTrackArtist to artist of current track
                set currentTrackAlbum to album of current track
                set trackPosition to player position
                set trackDuration to duration of current track
                set currentVolume to sound volume
                try
                    set artData to data of artwork 1 of current track
                on error
                    set artData to ""
                end try
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, currentVolume, artData}
            on error
                return {false, "", "", "", 0, 0, 50, ""}
            end try
        end tell
        """

        guard let descriptor = try? await AppleScriptHelper.execute(script),
              descriptor.numberOfItems >= 7 else { return }

        let playing = descriptor.atIndex(1)?.booleanValue ?? false
        let title = descriptor.atIndex(2)?.stringValue ?? ""
        let artist = descriptor.atIndex(3)?.stringValue ?? ""
        let album = descriptor.atIndex(4)?.stringValue ?? ""
        let position = descriptor.atIndex(5)?.doubleValue ?? 0
        let duration = descriptor.atIndex(6)?.doubleValue ?? 0
        let vol = descriptor.atIndex(7)?.int32Value ?? 50
        let artData = descriptor.atIndex(8)?.data as Data?

        bundleIdentifier = "com.apple.Music"
        songTitle = title
        artistName = artist
        albumName = album
        isPlaying = playing
        elapsedTime = position
        songDuration = duration
        volume = Double(vol) / 100.0
        lastUpdated = Date()
        isIdle = title.isEmpty && !playing

        if let artData, let image = NSImage(data: artData) {
            albumArt = image
        }
    }

    private func updateFromSpotify() async {
        let script = """
        tell application "Spotify"
            try
                set playerState to player state is playing
                set currentTrackName to name of current track
                set currentTrackArtist to artist of current track
                set currentTrackAlbum to album of current track
                set trackPosition to player position
                set trackDuration to duration of current track
                set currentVolume to sound volume
                set artworkURL to artwork url of current track
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, currentVolume, artworkURL}
            on error
                return {false, "", "", "", 0, 0, 50, ""}
            end try
        end tell
        """

        guard let descriptor = try? await AppleScriptHelper.execute(script),
              descriptor.numberOfItems >= 7 else { return }

        let playing = descriptor.atIndex(1)?.booleanValue ?? false
        let title = descriptor.atIndex(2)?.stringValue ?? ""
        let artist = descriptor.atIndex(3)?.stringValue ?? ""
        let album = descriptor.atIndex(4)?.stringValue ?? ""
        let position = descriptor.atIndex(5)?.doubleValue ?? 0
        let duration = (descriptor.atIndex(6)?.doubleValue ?? 0) / 1000
        let vol = descriptor.atIndex(7)?.int32Value ?? 50
        let artworkURL = descriptor.atIndex(8)?.stringValue ?? ""

        bundleIdentifier = "com.spotify.client"
        songTitle = title
        artistName = artist
        albumName = album
        isPlaying = playing
        elapsedTime = position
        songDuration = duration
        volume = Double(vol) / 100.0
        lastUpdated = Date()
        isIdle = title.isEmpty && !playing

        // Fetch Spotify artwork from URL
        if !artworkURL.isEmpty, let url = URL(string: artworkURL) {
            Task.detached {
                if let data = try? Data(contentsOf: url),
                   let image = NSImage(data: data) {
                    await MainActor.run { [weak self] in
                        self?.albumArt = image
                    }
                }
            }
        }
    }
}
