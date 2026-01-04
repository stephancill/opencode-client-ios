import Foundation
import Combine

@MainActor
class MentionManager: ObservableObject {
    @Published var isAutocompleteVisible = false
    @Published var suggestions: [String] = []
    @Published var mentionRange: Range<String.Index>?

    private var searchTask: Task<Void, Never>?
    private let debounceDelay: TimeInterval = 0.3

    func handleTextChange(_ text: String, cursorPosition: Int) {
        guard cursorPosition >= 0 && cursorPosition <= text.count else {
            hideAutocomplete()
            return
        }

        let cursorIndex = text.index(text.startIndex, offsetBy: cursorPosition)

        if let mentionInfo = findMention(in: text, cursorPosition: cursorIndex) {
            if mentionInfo.query != text[mentionInfo.range] {
                mentionRange = mentionInfo.range
                triggerSearch(for: mentionInfo.query)
            }
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

        hideAutocomplete()
        return (newText, newText.count)
    }

    private func findMention(in text: String, cursorPosition: String.Index) -> (query: String, range: Range<String.Index>)? {
        guard cursorPosition > text.startIndex else { return nil }

        var currentIndex = text.index(before: cursorPosition)

        while currentIndex >= text.startIndex {
            let char = text[currentIndex]

            if char == "@" {
                let prevIndex = currentIndex > text.startIndex ? text.index(before: currentIndex) : text.startIndex

                if currentIndex == text.startIndex || text[prevIndex].isWhitespace || text[prevIndex] == "\n" {
                    let queryStart = text.index(after: currentIndex)
                    let queryRange = queryStart..<cursorPosition
                    let query = String(text[queryRange])
                    return (query: query, range: currentIndex..<cursorPosition)
                } else {
                    return nil
                }
            }

            if char.isWhitespace || char == "\n" {
                return nil
            }

            currentIndex = text.index(before: currentIndex)
        }

        return nil
    }

    private func triggerSearch(for query: String) {
        searchTask?.cancel()

        searchTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))

            guard !Task.isCancelled else { return }

            do {
                let results = try await OpenCodeAPIClient.shared.searchDirectories(query: query)
                let limitedResults = Array(results.prefix(3))

                if !Task.isCancelled {
                    suggestions = limitedResults
                    isAutocompleteVisible = !limitedResults.isEmpty
                }
            } catch {
                print("Failed to search directories: \(error)")
                if !Task.isCancelled {
                    isAutocompleteVisible = false
                    suggestions = []
                }
            }
        }
    }
}