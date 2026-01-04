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

        print("handleTextChange: text='\(text)', cursorPosition=\(cursorPosition)")

        if let mentionInfo = findMention(in: text, cursorPosition: cursorIndex) {
            print("Found mention: query='\(mentionInfo.query)', range=\(mentionInfo.range)")
            mentionRange = mentionInfo.range
            triggerSearch(for: mentionInfo.query)
        } else {
            print("No mention found, hiding autocomplete")
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

        while true {
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

            if currentIndex == text.startIndex {
                return nil
            }

            currentIndex = text.index(before: currentIndex)
        }
    }

    private func triggerSearch(for query: String) {
        print("triggerSearch: query='\(query)'")
        searchTask?.cancel()

        searchTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))

            guard !Task.isCancelled else { return }

            do {
                print("API call: searching with query='\(query)'")
                let results = try await OpenCodeAPIClient.shared.searchDirectories(query: query)
                let limitedResults = Array(results.prefix(3))
                print("API response: \(limitedResults.count) results")

                if !Task.isCancelled {
                    suggestions = limitedResults
                    isAutocompleteVisible = !limitedResults.isEmpty
                    print("Autocomplete visible: \(isAutocompleteVisible), suggestions: \(suggestions)")
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
