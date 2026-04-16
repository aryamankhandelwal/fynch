import SwiftUI

// MARK: - Supporting Types

private enum BulkMatchStatus {
    case new
    case inMyList
    case inWatchlist
    case notFound
}

private struct BulkMatchResult: Identifiable {
    let id = UUID()
    let query: String
    let match: TMDBSearchResult?
    var isSelected: Bool
    var status: BulkMatchStatus
}

private enum BulkPhase {
    case input
    case searching
    case review
    case adding
    case error(String)
}

// MARK: - View

struct BulkAddView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let tmdbService: TMDBService
    let destination: AddDestination
    let onAdded: () -> Void

    @State private var inputText = ""
    @State private var phase: BulkPhase = .input
    @State private var results: [BulkMatchResult] = []

    private var selectedCount: Int {
        results.filter { $0.isSelected && $0.status == .new }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .input:
                    inputView
                case .searching:
                    searchingView
                case .review:
                    reviewView
                case .adding:
                    addingView
                case .error(let message):
                    errorView(message)
                }
            }
            .navigationTitle("Bulk Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Input Phase

    private var inputView: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $inputText)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if inputText.isEmpty {
                    Text("Type or paste a list of shows you watch.\n\nWorks with any format:\n  Breaking Bad\n  The Wire, Succession\n  1. Severance\n  • The Bear")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                }
            }

            Divider()

            Button {
                let candidates = BulkAddView.parseInput(inputText)
                guard !candidates.isEmpty else { return }
                phase = .searching
                Task { await findShows(candidates: candidates) }
            } label: {
                Text("Find Shows")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding()
        }
    }

    // MARK: - Searching Phase

    private var searchingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Finding your shows…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Review Phase

    private var reviewView: some View {
        let newIndices       = results.indices.filter { results[$0].status == .new }
        let myListIndices    = results.indices.filter { results[$0].status == .inMyList }
        let watchlistIndices = results.indices.filter { results[$0].status == .inWatchlist }
        let notFoundIndices  = results.indices.filter { results[$0].status == .notFound }

        return List {
            if !newIndices.isEmpty {
                Section("Found") {
                    ForEach(newIndices, id: \.self) { i in
                        selectableRow(resultIndex: i)
                    }
                }
            }

            if !myListIndices.isEmpty {
                Section("Already in My List") {
                    ForEach(myListIndices, id: \.self) { i in
                        alreadyAddedRow(resultIndex: i)
                    }
                }
            }

            if !watchlistIndices.isEmpty {
                Section("Already in Watchlist") {
                    ForEach(watchlistIndices, id: \.self) { i in
                        alreadyAddedRow(resultIndex: i)
                    }
                }
            }

            if !notFoundIndices.isEmpty {
                Section("Not Found") {
                    ForEach(notFoundIndices, id: \.self) { i in
                        HStack(spacing: 14) {
                            Image(systemName: "questionmark.circle")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                                .frame(width: 40, height: 40)

                            Text(results[i].query)
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selectedCount > 0 {
                addButton
            }
        }
    }

    // Selectable row for shows not yet added
    private func selectableRow(resultIndex i: Int) -> some View {
        let match = results[i].match!
        let colorIndex = match.id % Show.palette.count

        return HStack(spacing: 14) {
            Circle()
                .fill(Show.palette[colorIndex].gradient)
                .frame(width: 40, height: 40)
                .overlay {
                    Text(match.name.prefix(1))
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(match.name)
                    .font(.msHeadline)

                if results[i].query.lowercased() != match.name.lowercased() {
                    Text("\u{201C}\(results[i].query)\u{201D}")
                        .font(.msCaption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: results[i].isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(results[i].isSelected ? .blue : .secondary)
                .font(.title2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            results[i].isSelected.toggle()
        }
    }

    // Non-interactive row for shows already in My List or Watchlist
    private func alreadyAddedRow(resultIndex i: Int) -> some View {
        let match = results[i].match!

        return HStack(spacing: 14) {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(match.name.prefix(1))
                        .font(.headline.bold())
                        .foregroundStyle(Color.secondary)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(match.name)
                    .font(.msHeadline)
                    .foregroundStyle(.secondary)

                if results[i].query.lowercased() != match.name.lowercased() {
                    Text("\u{201C}\(results[i].query)\u{201D}")
                        .font(.msCaption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .opacity(0.6)
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button {
            let selected = results.compactMap { $0.isSelected && $0.status == .new ? $0.match : nil }
            phase = .adding
            Task {
                do {
                    try await appState.addShowsFromTMDB(searchResults: selected, service: tmdbService, destination: destination)
                    dismiss()
                    onAdded()
                } catch {
                    phase = .error(error.localizedDescription)
                }
            }
        } label: {
            Text("Add \(selectedCount) Show\(selectedCount == 1 ? "" : "s")")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal)
        .padding(.bottom)
        .background(.bar)
    }

    // MARK: - Adding Phase

    private var addingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Adding shows…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error Phase

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView(
            "Something went wrong",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Try Again") {
                    phase = .input
                    results = []
                }
            }
        }
    }

    // MARK: - Parsing

    private static func parseInput(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: "\n,;|")
        var seen = Set<String>()
        var out: [String] = []

        for fragment in text.components(separatedBy: separators) {
            var s = fragment.trimmingCharacters(in: .whitespaces)

            // Strip leading numeric list markers: "1.", "23."
            if let r = s.range(of: #"^\d+\.\s*"#, options: .regularExpression) {
                s = String(s[r.upperBound...])
            }

            // Strip leading bullet markers: -, •, *
            if let first = s.first, "-•*".contains(first) {
                s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
            }

            s = s.trimmingCharacters(in: .whitespaces)
            guard s.count >= 2 else { continue }

            let key = s.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(s)
        }

        return out
    }

    // MARK: - TMDB Search

    private func findShows(candidates: [String]) async {
        var found: [BulkMatchResult] = []
        let myListTmdbIds    = Set(appState.myListShows.map { $0.tmdbId })
        let watchlistTmdbIds = Set(appState.watchlistShows.map { $0.tmdbId })

        await withTaskGroup(of: BulkMatchResult.self) { group in
            for candidate in candidates {
                group.addTask {
                    let searchResults = try? await tmdbService.searchShows(query: candidate)
                    guard let pick = searchResults?.first else {
                        return BulkMatchResult(query: candidate, match: nil, isSelected: false, status: .notFound)
                    }
                    let status: BulkMatchStatus
                    if myListTmdbIds.contains(pick.id) {
                        status = .inMyList
                    } else if watchlistTmdbIds.contains(pick.id) {
                        status = .inWatchlist
                    } else {
                        status = .new
                    }
                    return BulkMatchResult(query: candidate, match: pick, isSelected: status == .new, status: status)
                }
            }
            for await result in group {
                found.append(result)
            }
        }

        // Restore input order
        results = candidates.compactMap { c in found.first(where: { $0.query == c }) }
        phase = .review
    }
}
