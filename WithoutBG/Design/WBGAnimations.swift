import SwiftUI

/// Fade-in + slight upward translate on appear (mirrors `animate-fade-in-up`).
struct FadeInUpModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.35)) { appeared = true }
            }
    }
}

extension View {
    func fadeInUp() -> some View {
        modifier(FadeInUpModifier())
    }
}
