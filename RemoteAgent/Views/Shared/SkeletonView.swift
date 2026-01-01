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
        HStack {
            if isUser {
                Spacer()
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                SkeletonView(
                    width: isUser ? 200 : 250,
                    height: 16,
                    cornerRadius: 12
                )
                
                if !isUser {
                    SkeletonView(
                        width: 180,
                        height: 16,
                        cornerRadius: 12
                    )
                    .opacity(0.7)
                }
            }
            .frame(maxWidth: isUser ? .infinity * 0.7 : .infinity * 0.8, alignment: isUser ? .trailing : .leading)
            
            if !isUser {
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

#Preview {
    VStack(spacing: 20) {
        SessionSkeletonView()
        
        Divider()
        
        VStack(spacing: 12) {
            MessageSkeletonView(isUser: true)
            MessageSkeletonView(isUser: false)
        }
    }
    .padding()
}