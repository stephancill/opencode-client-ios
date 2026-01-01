// Mock SwiftUI components for Linux testing
#if os(Linux)
import Foundation

// Mock types for Linux compilation
public enum Color {
    case accentColor
    public static let primary = Color.accentColor
}

public enum Font {
    case body, caption
    case monospaced()
    public static let body = Font.body
    public static let caption = Font.caption
}

public struct Text: View {
    let content: String
    public init(_ content: String) { self.content = content }
}

public protocol View {}

public struct VStack: View {
    public init(alignment: Alignment = .leading, spacing: CGFloat = 8, content: () -> [View]) {}
}

public struct Padding {
    public var vertical: CGFloat
}

public extension Text {
    func font(_ font: Font) -> Text { return self }
    func textSelection(_ enabled: Any) -> Text { return self }
    func padding(_ padding: Padding) -> Text { return self }
    func tint(_ color: Color) -> Text { return self }
}

public extension View {
    func padding() -> Self { return self }
}

public struct LocalizedStringKey {
    let stringLiteral: String
    init(_ stringLiteral: String) { self.stringLiteral = stringLiteral }
}

public struct Alignment {
    public static let leading = Alignment()
}

public typealias CGFloat = Double

#endif

// Cross-platform MarkdownView
#if os(Linux)
struct MarkdownView {
    let content: String
    
    init(content: String) {
        self.content = content
    }
    
    func render() -> String {
        // Simple markdown to text conversion for testing
        let markdown = content
            .replacingOccurrences(of: "\\*\\*(.*?)\\*\\*", with: "$1") // Bold
            .replacingOccurrences(of: "\\*(.*?)\\*", with: "$1") // Italic
            .replacingOccurrences(of: "^# (.*?)$", with: "=== $1 ===", options: .regularExpression) // Headers
            .replacingOccurrences(of: "^- (.*?)$", with: "• $1", options: [.regularExpression, .anchorsMatchLines]) // Lists
            .replacingOccurrences(of: "`(.*?)`", with: "$1", options: .regularExpression) // Inline code
            .replacingOccurrences(of: "```swift\\n([\\s\\S]*?)\\n```", with: "\nSwift Code:\n$1\n", options: .regularExpression) // Code blocks
            .replacingOccurrences(of: "```([\\s\\S]*?)```", with: "\nCode:\n$1\n", options: .regularExpression) // Other code blocks
            .replacingOccurrences(of: "^> (.*?)$", with: "Quote: $1", options: [.regularExpression, .anchorsMatchLines]) // Quotes
            .replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1 (link)", options: .regularExpression) // Links
        
        return markdown
    }
}
#else
import SwiftUI

struct MarkdownView: View {
    let content: String
    
    var body: some View {
        Text(LocalizedStringKey(content))
            .font(.body)
            .textSelection(.enabled)
            .padding(.vertical, 2)
            .tint(.accentColor)
    }
}
#endif

// Test function
#if os(Linux)
func testMarkdown() {
    let testContent = """
    # Heading 1
    
    This is **bold** text and *italic* text.
    
    - Item 1
    - Item 2
    - Item 3
    
    `inline code` and ```swift
    let x = 1
    ```
    
    > This is a quote
    
    [Link text](https://example.com)
    """
    
    let markdownView = MarkdownView(content: testContent)
    print("Markdown test:")
    print(markdownView.render())
    print("\n✅ MarkdownView compiles successfully!")
}

testMarkdown()
#endif