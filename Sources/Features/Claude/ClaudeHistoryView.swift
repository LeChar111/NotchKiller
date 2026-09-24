import SwiftUI

/// Historique des conversations Claude Code, par profil, avec reprise dans
/// le terminal ou l'éditeur de son choix — notamment après un crash.
struct ClaudeHistoryView: View {
    var model: ClaudeHistoryModel = .shared
    var store: ClaudeSessionStore = .shared

    @AppStorage("claudeHistoryProfile") private var profileID = ""
    @State private var query = ""
    @State private var hovered: String?
    @State private var feedback: String?

    private var profiles: [ClaudeProfile] { ClaudeProfile.all }

    private var profile: ClaudeProfile? {
        profiles.first { $0.id == profileID } ?? profiles.first
    }

    /// Au-delà, la liste devient illisible dans l'encoche : la recherche prend le relais.
    private static let limit = 80

    private var filtered: [ClaudeHistoryEntry] {
        guard let profile else { return [] }
        let all = model.entries[profile] ?? []
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return all }
        return all.filter {
            $0.displayTitle.lowercased().contains(needle)
                || $0.projectName.lowercased().contains(needle)
                || ($0.lastPrompt?.lowercased().contains(needle) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, NK.sectionGap)
            search
                .padding(.top, 10)
            list
                .padding(.top, 12)
                .padding(.bottom, 8)
        }
        .onAppear { model.refresh() }
        .task {
            // La page reste ouverte : on suit les conversations qui avancent.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                model.refresh()
            }
        }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 8) {
            SectionLabel("Historique")
            Hairline()
            if let feedback {
                Text(feedback)
                    .font(NK.ui(9.5, .semibold))
                    .foregroundStyle(NK.ok)
                    .transition(.opacity)
            }
            if model.isLoading {
                ProgressView().controlSize(.mini)
            }
            profileSwitch
        }
    }

    private var profileSwitch: some View {
        HStack(spacing: 2) {
            ForEach(profiles) { item in
                let selected = item.id == profile?.id
                Button {
                    profileID = item.id
                } label: {
                    Text(item.name)
                        .font(NK.ui(10, .semibold))
                        .foregroundStyle(selected ? NK.t1 : NK.t3)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(Capsule().fill(selected ? NK.surfaceRaised : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(item.directory.path)
            }
        }
        .padding(2)
        .background(Capsule().fill(NK.surface))
    }

    private var search: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NK.t3)
            TextField("Rechercher un titre, un projet, un message", text: $query)
                .textFieldStyle(.plain)
                .font(NK.ui(11))
                .foregroundStyle(NK.t1)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(NK.t3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: NK.radiusControl, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NK.radiusControl, style: .continuous)
                .stroke(NK.line, lineWidth: 1)
        )
    }

    // MARK: Liste

    @ViewBuilder
    private var list: some View {
        let entries = filtered
        if entries.isEmpty {
            Text(model.lastRefresh == nil ? "Lecture des conversations…" : "Aucune conversation.")
                .font(NK.ui(11))
                .foregroundStyle(NK.t3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else {
            let interrupted = entries.filter { model.status(of: $0) == .interrupted }
            let others = entries.filter { model.status(of: $0) != .interrupted }.prefix(Self.limit)

            AdaptiveScrollView(maxHeight: NotchConstants.maxExpandedContentHeight - 118) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if !interrupted.isEmpty {
                        groupLabel("Interrompues", tint: NK.warn)
                        ForEach(interrupted) { row($0) }
                    }
                    ForEach(Self.groups(Array(others)), id: \.title) { group in
                        groupLabel(group.title, tint: NK.t3)
                        ForEach(group.entries) { row($0) }
                    }
                }
            }
        }
    }

    private func groupLabel(_ title: String, tint: Color) -> some View {
        Text(title.uppercased())
            .font(NK.ui(8.5, .bold))
            .tracking(1.2)
            .foregroundStyle(tint)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func row(_ entry: ClaudeHistoryEntry) -> some View {
        let status = model.status(of: entry)
        let isHovered = hovered == entry.id

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.displayTitle)
                        .font(NK.ui(11.5, .semibold))
                        .foregroundStyle(NK.t1)
                        .lineLimit(1)
                    switch status {
                    case .live:        StatusPill(text: "En cours", tint: NK.ok)
                    case .interrupted: StatusPill(text: "Interrompue", tint: NK.warn)
                    case .ended:       EmptyView()
                    }
                }
                HStack(spacing: 5) {
                    Text(entry.projectName)
                        .foregroundStyle(entry.directoryExists ? NK.t2 : NK.bad)
                    Text("·")
                    Text(Self.time(entry.updatedAt))
                    if let prompt = entry.lastPrompt, prompt != entry.title {
                        Text("·")
                        Text("« \(prompt) »").lineLimit(1)
                    }
                }
                .font(NK.ui(9.5, .medium))
                .foregroundStyle(NK.t3)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered || status == .interrupted {
                actions(entry, status: status)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovered ? NK.surfaceRaised : (status == .interrupted ? NK.warn.opacity(0.06) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { inside in
            hovered = inside ? entry.id : (hovered == entry.id ? nil : hovered)
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    @ViewBuilder
    private func actions(_ entry: ClaudeHistoryEntry, status: ClaudeHistoryModel.Status) -> some View {
        HStack(spacing: 4) {
            if status == .live, let session = store.sessions[entry.id] {
                pill("Revenir", icon: "arrow.up.forward.app.fill") {
                    TerminalFocus.focus(ancestors: session.ancestorPIDs)
                }
            } else {
                pill("Reprendre", icon: "arrow.clockwise") {
                    resume(entry, in: ClaudeLauncher.preferredTerminal)
                }
                .disabled(!entry.directoryExists)
                ForEach(ClaudeLauncher.Target.available.filter { $0 != ClaudeLauncher.preferredTerminal }) { target in
                    iconButton(target.symbol, help: target == .copy ? target.title : "Reprendre dans \(target.title)") {
                        resume(entry, in: target)
                    }
                }
            }
            iconButton("folder", help: "Ouvrir un terminal dans \(entry.workingDirectory)") {
                ClaudeLauncher.openTerminal(at: entry.workingDirectory)
            }
            .disabled(!entry.directoryExists)
        }
    }

    private func resume(_ entry: ClaudeHistoryEntry, in target: ClaudeLauncher.Target) {
        ClaudeLauncher.resume(entry, in: target)
        switch target {
        case .copy:   flash("Commande copiée")
        case .cursor: flash(entry.profile.isDefault ? "Ouvert dans Cursor" : "Cursor ouvert · commande copiée")
        default:      flash("Reprise dans \(target.title)")
        }
    }

    private func flash(_ text: String) {
        withAnimation { feedback = text }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { if feedback == text { feedback = nil } }
        }
    }

    private func pill(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 8.5, weight: .semibold))
                Text(title).font(NK.ui(9.5, .semibold))
            }
            .foregroundStyle(NK.accent)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(NK.accent.opacity(0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(NK.t2)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Regroupement par jour

    private struct Group {
        let title: String
        let entries: [ClaudeHistoryEntry]
    }

    private static func groups(_ entries: [ClaudeHistoryEntry]) -> [Group] {
        let calendar = Calendar.current
        var result: [Group] = []
        for entry in entries {
            let title: String
            if calendar.isDateInToday(entry.updatedAt) { title = "Aujourd'hui" }
            else if calendar.isDateInYesterday(entry.updatedAt) { title = "Hier" }
            else { title = dayFormatter.string(from: entry.updatedAt) }

            if let last = result.last, last.title == title {
                result[result.count - 1] = Group(title: title, entries: last.entries + [entry])
            } else {
                result.append(Group(title: title, entries: [entry]))
            }
        }
        return result
    }

    private static func time(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) || Calendar.current.isDateInYesterday(date)
            ? timeFormatter.string(from: date)
            : dayTimeFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
        return f
    }()
}
