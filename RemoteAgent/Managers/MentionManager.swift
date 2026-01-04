import Foundation
import Combine

@MainActor
class MentionManager: ObservableObject {
    @Published var isAutocompleteVisible = false
    @Published var suggestions: [String] = []
    @Published var mentionRange: Range<String.Index>?

    private var searchTask: Task<Void, Never>?
    private let debounceDelay: TimeInterval = 0.3
    private var justSelectedSuggestion = false

    func handleTextChange(_ text: String) {
        if justSelectedSuggestion {
            justSelectedSuggestion = false
            return
        }
        
        if let mentionInfo = findMention(in: text) {
            mentionRange = mentionInfo.range
            triggerSearch(for: mentionInfo.query)
        } else {
            hideAutocomplete()
        }
    }

    func hideAutocomplete() {
        isAutocompleteVisible = false
        suggestions = []
        mentionRange = nil
        searchTask?.cancel()
        searchTask = nil
    }

    func selectSuggestion(_ suggestion: String, in text: String) -> (String, Int) {
        guard let mentionRange = mentionRange else {
            return (text, text.count)
        }

        var newText = text
        let replacement = "@\(suggestion) "
        newText.replaceSubrange(mentionRange, with: replacement)

        justSelectedSuggestion = true
        hideAutocomplete()
        return (newText, newText.count)
    }

    private func findMention(in text: String) -> (query: String, range: Range<String.Index>)? {
        guard let atIndex = text.lastIndex(of: "@") else {
            return nil
        }

        let prevIndex = atIndex > text.startIndex ? text.index(before: atIndex) : text.startIndex

        guard atIndex == text.startIndex || text[prevIndex].isWhitespace || text[prevIndex] == "\n" else {
            return nil
        }

        let afterAt = text.index(after: atIndex)

        guard afterAt <= text.endIndex else {
            return nil
        }

        let queryStart = afterAt
        let queryRange = queryStart..<text.endIndex
        let query = String(text[queryRange])

        return (query: query, range: atIndex..<text.endIndex)
    }

    private func triggerSearch(for query: String) {
        searchTask?.cancel()

        searchTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))

            guard !Task.isCancelled else { return }

            do {
                let results = try await OpenCodeAPIClient.shared.searchDirectories(query: query)
                let limitedResults = Array(results.prefix(20))

                if !Task.isCancelled {
                    suggestions = limitedResults
                    isAutocompleteVisible = !limitedResults.isEmpty
                }
            } catch {
                if !Task.isCancelled {
                    isAutocompleteVisible = false
                    suggestions = []
                }
            }
        }
    }
}
