import AppKit
import SwiftUI

struct MediaPlayerView: View {
    var musicManager: MusicManager
    var library: MediaLibrary = .shared

    @State private var hovered: String?
    @State private var renaming: String?
    @State private var draftName = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sourceRow
                .padding(.top, 12)

            Hairline()
                .padding(.top, 12)

            if musicManager.isIdle {
                playlistSection(columns: 2)
                    .padding(.top, NK.sectionGap)
                    .padding(.bottom, 12)
            } else {
                HStack(alignment: .top, spacing: 22) {
                    playerView
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    playlistSection(columns: 1)
                        .frame(width: 320, alignment: .topLeading)
                }
                .padding(.top, NK.sectionGap)
                .padding(.bottom, 12)
            }
        }
        .onAppear { library.refresh() }
    }

    // MARK: Source

    private var sourceRow: some View {
        HStack(spacing: 8) {
            SectionLabel("Source")

            ForEach(library.sources) { source in
                Button { library.setDefault(source) } label: {
                    HStack(spacing: 7) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: source.url.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(source.name)
                            .font(NK.ui(11, .semibold))
                    }
                    .foregroundStyle(isDefault(source) ? NK.t1 : NK.t3)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isDefault(source) ? Color.white.opacity(0.09) : Color.white.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isDefault(source) ? NK.accent.opacity(0.55) : .clear, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Utiliser \(source.name) par défaut")
            }

            Spacer(minLength: 8)

            if let source = library.defaultSource {
                Button { library.launchDefault() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Ouvrir \(source.name)")
                            .font(NK.ui(10.5, .semibold))
                    }
                    .foregroundStyle(NK.t2)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func isDefault(_ source: MediaSource) -> Bool {
        library.defaultSource?.bundleID == source.bundleID
    }

    // MARK: Playlists

    private var allPlaylists: [MediaPlaylist] {
        library.playlists + library.pinned
    }

    @ViewBuilder
    private func playlistSection(columns: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SectionLabel(library.isAppleMusic ? "Vos playlists" : "Playlists épinglées")
                Spacer(minLength: 0)
                if let note = library.note {
                    Text(note)
                        .font(NK.ui(9, .medium))
                        .foregroundStyle(NK.t4)
                        .lineLimit(1)
                }
                pinButton
            }

            if allPlaylists.isEmpty {
                emptyPlaylists
            } else if columns == 2 {
                let items = Array(allPlaylists.prefix(8))
                HStack(alignment: .top, spacing: 18) {
                    column(Array(items.prefix((items.count + 1) / 2)))
                    column(Array(items.dropFirst((items.count + 1) / 2)))
                }
            } else {
                column(Array(allPlaylists.prefix(4)))
            }
        }
    }

    private func column(_ items: [MediaPlaylist]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { playlist in
                playlistRow(playlist)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var pinButton: some View {
        Button { library.addPinnedFromPasteboard() } label: {
            HStack(spacing: 5) {
                Image(systemName: "pin")
                    .font(.system(size: 9, weight: .semibold))
                Text("Épingler le lien copié")
                    .font(NK.ui(9.5, .semibold))
            }
            .foregroundStyle(NK.accent)
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(Capsule().fill(NK.accent.opacity(0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Copiez un lien de playlist, puis épinglez-le ici")
    }

    @ViewBuilder
    private var emptyPlaylists: some View {
        VStack(alignment: .leading, spacing: 8) {
            if library.isAppleMusic && !library.isMusicRunning {
                Text("Ouvrez Musique pour lire vos playlists — l'app ne la lance pas toute seule.")
                    .font(NK.ui(11, .medium))
                    .foregroundStyle(NK.t3)
                    .fixedSize(horizontal: false, vertical: true)
                Button { library.launchDefault() } label: {
                    Text("Ouvrir Musique")
                        .font(NK.ui(11, .semibold))
                        .foregroundStyle(NK.accent)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(NK.accent.opacity(0.14)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text(library.isAppleMusic
                     ? "Aucune playlist dans votre bibliothèque."
                     : "Copiez le lien d'une playlist depuis \(library.defaultSource?.name ?? "votre app"), puis épinglez-le.")
                    .font(NK.ui(11, .medium))
                    .foregroundStyle(NK.t3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }

    private func playlistRow(_ playlist: MediaPlaylist) -> some View {
        let isHovered = hovered == playlist.id

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                if renaming == playlist.id {
                    renameField(playlist)
                } else {
                    Button { library.play(playlist) } label: {
                        HStack(spacing: 10) {
                            playlistArtwork(playlist, isHovered: isHovered)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(playlist.name)
                                    .font(NK.ui(11.5, .semibold))
                                    .foregroundStyle(NK.t1)
                                    .lineLimit(1)
                                Text(playlist.subtitle)
                                    .font(NK.ui(9.5, .medium))
                                    .foregroundStyle(NK.t4)
                            }

                            Spacer(minLength: 0)

                            if isHovered {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(NK.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if playlist.link != nil && isHovered && renaming != playlist.id {
                    rowButton("pencil", help: "Renommer") {
                        draftName = playlist.name
                        renaming = playlist.id
                        renameFocused = true
                    }
                    rowButton("arrow.triangle.2.circlepath", help: "Récupérer le nom et la pochette") {
                        library.fetchMetadata(for: playlist, force: true)
                    }
                    rowButton("xmark", help: "Retirer") { library.removePinned(playlist) }
                }
            }
            .padding(.vertical, 7)
            .onHover { hovered = $0 ? playlist.id : (hovered == playlist.id ? nil : hovered) }

            Hairline()
        }
        .animation(.smooth(duration: 0.15), value: isHovered)
    }

    /// Pochette récupérée pour les liens épinglés, icône sinon.
    @ViewBuilder
    private func playlistArtwork(_ playlist: MediaPlaylist, isHovered: Bool) -> some View {
        let icon = Image(systemName: playlist.link == nil ? "music.note.list" : "link")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isHovered ? NK.accent : NK.t4)

        if let artwork = playlist.artworkURL, let url = URL(string: artwork) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                icon
            }
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            icon.frame(width: 30)
        }
    }

    private func renameField(_ playlist: MediaPlaylist) -> some View {
        HStack(spacing: 8) {
            playlistArtwork(playlist, isHovered: true)
            TextField("Nom de la playlist", text: $draftName)
                .textFieldStyle(.plain)
                .font(NK.ui(11.5, .semibold))
                .foregroundStyle(NK.t1)
                .focused($renameFocused)
                .onSubmit { commitRename(playlist) }
                .onExitCommand { renaming = nil }
            rowButton("checkmark", help: "Valider") { commitRename(playlist) }
            rowButton("xmark", help: "Annuler") { renaming = nil }
        }
        .padding(.vertical, 2)
    }

    private func commitRename(_ playlist: MediaPlaylist) {
        library.rename(playlist, to: draftName)
        renaming = nil
    }

    private func rowButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(NK.t3)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Lecture en cours

    private var playerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                artworkView
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .shadow(color: .black.opacity(0.55), radius: 9, y: 4)

                VStack(alignment: .leading, spacing: 0) {
                    Text(musicManager.songTitle)
                        .font(NK.ui(16, .semibold))
                        .kerning(-0.3)
                        .foregroundStyle(NK.t1)
                        .lineLimit(2)
                    Text(musicManager.artistName)
                        .font(NK.ui(12, .medium))
                        .foregroundStyle(NK.t2)
                        .lineLimit(1)
                        .padding(.top, 4)
                    if !musicManager.albumName.isEmpty {
                        Text(musicManager.albumName)
                            .font(NK.ui(10.5, .medium))
                            .foregroundStyle(NK.t3)
                            .lineLimit(1)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            progressBar
                .padding(.top, 12)

            controlButtons
                .padding(.top, 12)
        }
    }

    private var artworkView: some View {
        Group {
            if let art = musicManager.albumArt {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [Color(red: 0.29, green: 0.18, blue: 0.43),
                             Color(red: 0.06, green: 0.11, blue: 0.20)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.white.opacity(0.28))
                )
            }
        }
    }

    private var progressBar: some View {
        VStack(spacing: 6) {
            MeterBar(value: progress, tint: .white, height: 3)
            HStack {
                Text(formatTime(musicManager.elapsedTime))
                Spacer()
                Text(formatTime(musicManager.songDuration))
            }
            .font(NK.mono(10, .medium))
            .foregroundStyle(NK.t3)
        }
    }

    private var progress: Double {
        musicManager.songDuration > 0
            ? min(1, musicManager.elapsedTime / musicManager.songDuration)
            : 0
    }

    private var controlButtons: some View {
        HStack(spacing: 26) {
            Spacer(minLength: 0)

            Button { Task { await musicManager.previousTrack() } } label: {
                Image(systemName: "backward.fill").font(.system(size: 16)).foregroundStyle(NK.t2)
            }
            .buttonStyle(.plain)

            Button { Task { await musicManager.togglePlay() } } label: {
                Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)

            Button { Task { await musicManager.nextTrack() } } label: {
                Image(systemName: "forward.fill").font(.system(size: 16)).foregroundStyle(NK.t2)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
