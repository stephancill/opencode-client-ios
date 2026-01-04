import SwiftUI

struct AutocompleteView: View {
    let suggestions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button(action: {
                    onSelect(suggestion)
                }) {
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        Text(suggestion)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if suggestion != suggestions.last {
                    Divider()
                }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator, lineWidth: 0.5)
        )
    }
}