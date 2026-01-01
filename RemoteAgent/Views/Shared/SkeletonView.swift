import SwiftUI

struct SkeletonView: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    
    init(width: CGFloat = .infinity, height: CGFloat = 20, cornerRadius: CGFloat = 4) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemGray5))
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.clear,
                                Color.white.opacity(0.3),
                                Color.clear
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .rotationEffect(.degrees(30))
                    .offset(x: -200)
                    .animation(
                        Animation.linear(duration: 1.5).repeatForever(autoreverses: false),
                        value: UUID().uuidString
                    )
            )
            .clipped()
    }
}

struct SessionSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonView(width: 200, height: 20)
            SkeletonView(width: 120, height: 14)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
    }
}

struct MessageSkeletonView: View {
    let isUser: Bool
    
    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            HStack {
                if isUser {
                    Spacer()
                }

                VStack(alignment: isUser ? .trailing : .leading) {
                    if !isUser {
                        // Assistant message skeleton
                        AssistantMessageSkeletonView()
                    } else {
                        // User message skeleton
                        UserMessageSkeletonView()
                    }
                }
                .padding()
                .background(isUser ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                .cornerRadius(12)

                if isUser {
                    Spacer()
                }
            }

            // Timestamp skeleton
            SkeletonView(width: 60, height: 12, cornerRadius: 3)
                .opacity(0.6)
        }
    }
}

struct AssistantMessageSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Agent name skeleton
            SkeletonView(width: 80, height: 12, cornerRadius: 3)
                .opacity(0.7)
            
            // Text content skeleton
            VStack(spacing: 4) {
                SkeletonView(width: 200, height: 16, cornerRadius: 3)
                SkeletonView(width: 180, height: 16, cornerRadius: 3)
                SkeletonView(width: 160, height: 16, cornerRadius: 3)
                    .opacity(0.8)
            }
            
            // Tool skeleton
            ToolSkeletonView()
            
            // Token/cost info skeleton
            HStack(spacing: 8) {
                SkeletonView(width: 16, height: 12, cornerRadius: 2)
                SkeletonView(width: 60, height: 12, cornerRadius: 3)
                
                SkeletonView(width: 16, height: 12, cornerRadius: 2)
                SkeletonView(width: 40, height: 12, cornerRadius: 3)
            }
            .opacity(0.6)
        }
    }
}

struct UserMessageSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Text content skeleton (usually shorter)
            VStack(spacing: 4) {
                SkeletonView(width: 160, height: 16, cornerRadius: 3)
                SkeletonView(width: 140, height: 16, cornerRadius: 3)
                    .opacity(0.8)
            }
        }
    }
}

struct ToolSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SkeletonView(width: 16, height: 16, cornerRadius: 2)
                
                VStack(alignment: .leading, spacing: 2) {
                    SkeletonView(width: 120, height: 14, cornerRadius: 3)
                    SkeletonView(width: 100, height: 12, cornerRadius: 3)
                        .opacity(0.7)
                }
                
                Spacer()
                
                // Status indicator skeleton
                HStack(spacing: 4) {
                    SkeletonView(width: 8, height: 8, cornerRadius: 4)
                    SkeletonView(width: 50, height: 12, cornerRadius: 3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
        }
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            SessionSkeletonView()
            
            Divider()
            
            VStack(spacing: 12) {
                MessageSkeletonView(isUser: true)
                MessageSkeletonView(isUser: false)
            }
            
            Divider()
            
            Text("Individual Components")
                .font(.headline)
            
            AssistantMessageSkeletonView()
            UserMessageSkeletonView()
            ToolSkeletonView()
        }
        .padding()
    }
}