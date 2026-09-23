import AppKit
import SwiftUI

struct DevPageView: View {
    var model: DevModel = .shared
    var settings: AppSettings = .shared

    @State private var showFavoritesOnly = false
    @State private var hovered: String?

    private var listed: [DevProject] {
        let source = showFavoritesOnly ? model.projects.filter(\.isFavorite) : model.projects
        return Array(source.prefix(6))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            editorColumn
                .frame(width: 246, alignment: .topLeading)

            projectColumn
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .onAppear { model.refresh() }
    }

    // MARK: Éditeurs

    private var editorColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                SectionLabel("Éditeur")
                Spacer(minLength: 0)
                if let action = model.lastAction {
                    Text(action)
                        .font(NK.ui(9, .medium))
                        .foregroundStyle(NK.t4)
                        .lineLimit(1)
                }
            }

            if model.editors.isEmpty {
                Text("Aucun éditeur détecté.")
                    .font(NK.ui(11, .medium))
                    .foregroundStyle(NK.t3)
                    .padding(.vertical, 10)
            } else {
                ForEach(model.editors) { editor in
                    editorRow(editor)
                }
            }

            if model.overleafInstalled {
                overleafRow
            }

            Text("« Défaut » choisit l'éditeur qui ouvrira les projets ; la flèche lance l'app.")
                .font(NK.ui(9.5, .medium))
                .foregroundStyle(NK.t4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    /// Overleaf local : un clic démarre Docker, les conteneurs, puis ouvre l'onglet.
    private var overleafRow: some View {
        Button { model.launchOverleaf() } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.28, green: 0.66, blue: 0.36))
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Overleaf local")
                        .font(NK.ui(11.5, .semibold))
                        .foregroundStyle(NK.t1)
                        .lineLimit(1)
                    Text(model.overleafStatus ?? "Docker + serveur + onglet")
                        .font(NK.ui(9, .medium))
                        .foregroundStyle(NK.t4)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Group {
                    if model.overleafBusy {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(NK.t3)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: NK.radiusControl, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .contentShape(RoundedRectangle(cornerRadius: NK.radiusControl, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.overleafBusy)
        .help("Démarre Docker Desktop, Overleaf local (localhost:8090) puis ouvre l'onglet")
    }

    private func editorRow(_ editor: DevEditor) -> some View {
        let isDefault = model.defaultEditor?.bundleID == editor.bundleID

        return HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: editor.url.path))
                .resizable()
                .frame(width: 20, height: 20)

            Text(editor.name)
                .font(NK.ui(11.5, .semibold))
                .foregroundStyle(NK.t1)
                .lineLimit(1)

            Spacer(minLength: 6)

            Button { model.setDefaultEditor(editor) } label: {
                Text("Défaut")
                    .font(NK.ui(9.5, .semibold))
                    .foregroundStyle(isDefault ? NK.accent : NK.t3)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(
                        Capsule()
                            .fill(isDefault ? NK.accent.opacity(0.16) : Color.white.opacity(0.05))
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(isDefault ? "Éditeur utilisé pour ouvrir un projet" : "Définir comme éditeur par défaut")

            Button { model.launch(editor) } label: {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NK.t3)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ouvrir \(editor.name)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: NK.radiusControl, style: .continuous)
                .fill(isDefault ? Color.white.opacity(0.07) : Color.white.opacity(0.03))
        )
    }

    // MARK: Projets

    private var projectColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SectionLabel(showFavoritesOnly ? "Favoris" : "Projets récents")
                Spacer(minLength: 0)
                filterToggle
            }
            .padding(.bottom, 8)

            if listed.isEmpty {
                Text(showFavoritesOnly
                     ? "Aucun favori — épinglez un projet avec l'étoile."
                     : "Aucun projet trouvé sous \(settings.projectRoots.joined(separator: ", ")).")
                    .font(NK.ui(11, .medium))
                    .foregroundStyle(NK.t3)
                    .padding(.vertical, 16)
            } else {
                ForEach(listed) { project in
                    projectRow(project)
                }
            }
        }
    }

    private var filterToggle: some View {
        HStack(spacing: 3) {
            filterButton("Récents", active: !showFavoritesOnly) { showFavoritesOnly = false }
            filterButton("Favoris", active: showFavoritesOnly) { showFavoritesOnly = true }
        }
    }

    private func filterButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(NK.ui(10, .semibold))
                .foregroundStyle(active ? NK.t1 : NK.t3)
                .padding(.horizontal, 9)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? Color.white.opacity(0.09) : .clear)
                )
        }
        .buttonStyle(.plain)
    }

    private func projectRow(_ project: DevProject) -> some View {
        let isHovered = hovered == project.path

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { model.open(project) } label: {
                    HStack(spacing: 10) {
                        Text(project.name)
                            .font(NK.ui(11.5, .semibold))
                            .foregroundStyle(NK.t1)
                            .lineLimit(1)

                        if let branch = project.branch {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 8, weight: .semibold))
                                Text(branch)
                                    .font(NK.mono(9))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(NK.t3)
                            .padding(.horizontal, 6)
                            .frame(height: 17)
                            .background(Capsule().fill(Color.white.opacity(0.05)))
                        }

                        Text(project.displayPath)
                            .font(NK.mono(9))
                            .foregroundStyle(NK.t4)
                            .lineLimit(1)
                            .truncationMode(.head)

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 2) {
                    if isHovered {
                        rowAction(icon: "apple.terminal") { model.openInTerminal(project) }
                        rowAction(icon: "folder") { model.revealInFinder(project) }
                    }
                    rowAction(icon: project.isFavorite ? "star.fill" : "star",
                              tint: project.isFavorite ? NK.warn : NK.t4) {
                        model.toggleFavorite(project)
                    }
                }
            }
            .padding(.vertical, 7)
            .onHover { hovered = $0 ? project.path : (hovered == project.path ? nil : hovered) }

            Hairline()
        }
        .animation(.smooth(duration: 0.15), value: isHovered)
    }

    private func rowAction(icon: String, tint: Color = NK.t3, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }
}
