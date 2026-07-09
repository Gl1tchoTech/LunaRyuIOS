//
//  HomeViewModel.swift
//  LunaAnime
//
//  Drives the Home tab: trending/popular feed, recent releases, debounced
//  search across the active provider.
//

import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {

    @Published var popular: [AnimeSummary] = []
    @Published var recent: [Episode] = []
    @Published var searchResults: [AnimeSummary] = []
    @Published var searchQuery: String = ""

    @Published private(set) var isLoadingPopular = false
    @Published private(set) var isLoadingRecent = false
    @Published private(set) var isLoadingSearch = false
    @Published var errorMessage: String?

    private var cancellables: Set<AnyCancellable> = []
    private let registry: ProviderRegistry

    init(registry: ProviderRegistry) {
        self.registry = registry
        // Debounce search input.
        $searchQuery
            .debounce(for: .milliseconds(350), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] q in
                guard let self = self else { return }
                Task { await self.runSearch(query: q) }
            }
            .store(in: &cancellables)
    }

    func loadAll() async {
        async let popularTask: () = loadPopular()
        async let recentTask: () = loadRecent()
        _ = await (popularTask, recentTask)
    }

    func loadPopular() async {
        isLoadingPopular = true
        defer { isLoadingPopular = false }
        do {
            popular = try await registry.execute({ try await $0.fetchPopular() })
        } catch let e as ProviderError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadRecent() async {
        isLoadingRecent = true
        defer { isLoadingRecent = false }
        do {
            recent = try await registry.execute({ try await $0.fetchRecentEpisodes() })
        } catch {
            Log.debug(.scraper, "Recent episodes failed: \(error)")
            recent = []
        }
    }

    private func runSearch(query: String) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            searchResults = []
            return
        }
        isLoadingSearch = true
        defer { isLoadingSearch = false }
        do {
            searchResults = try await registry.execute({ try await $0.search(query: q) })
        } catch {
            searchResults = []
        }
    }
}
