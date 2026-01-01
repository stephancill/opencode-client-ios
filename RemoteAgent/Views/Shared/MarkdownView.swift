import SwiftUI

struct MarkdownView: View {
    let content: String
    
    var body: some View {
        Text(LocalizedStringKey(content))
            .font(.body)
            .textSelection(.enabled)
            .padding(.vertical, 2)
            .tint(.accentColor) // For link coloring
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        MarkdownView(content: "# Heading 1\n\nThis is **bold** text and *italic* text.\n\n- Item 1\n- Item 2\n- Item 3\n\n`inline code` and ```swift\nlet x = 1\n```")
        
        MarkdownView(content: "## Code Example\n\nHere's a function:\n\n```swift\nfunc greet(name: String) {\n    print(\"Hello, \\(name)!\")\n}\n```\n\n> This is a quote\n\n[Link text](https://example.com)")
    }
    .padding()
}