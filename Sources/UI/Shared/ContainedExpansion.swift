import SwiftUI

enum ContainedExpansionMotion {
    static func layoutAnimation(expanding: Bool) -> Animation {
        expanding
            ? .easeOut(duration: 0.18)
            : .easeInOut(duration: 0.24)
    }

    static func contentAnimation(expanding: Bool) -> Animation {
        expanding
            ? .easeOut(duration: 0.14).delay(0.03)
            : .easeOut(duration: 0.06)
    }

    static var controlAnimation: Animation {
        .easeInOut(duration: 0.14)
    }

    static let contentRemovalDelayNanoseconds: UInt64 = 260_000_000
}

struct ContainedExpansion<Content: View>: View {
    let isExpanded: Bool
    var topSpacing: CGFloat = 0
    @ViewBuilder let content: () -> Content
    @State private var measuredHeight: CGFloat = 0
    @State private var isRenderingContent = false
    @State private var removalTask: Task<Void, Never>?

    var body: some View {
        Group {
            if isExpanded || isRenderingContent {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: topSpacing)
                    content()
                }
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    measuredHeight = newHeight
                }
                .opacity(isExpanded ? 1 : 0)
                .animation(ContainedExpansionMotion.contentAnimation(expanding: isExpanded), value: isExpanded)
                .frame(height: isExpanded ? measuredHeight : 0, alignment: .top)
                .clipped()
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
            } else {
                Color.clear
                    .frame(height: 0)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: isExpanded, initial: true) { _, expanded in
            updateRenderingState(expanded: expanded)
        }
        .onDisappear {
            removalTask?.cancel()
            removalTask = nil
        }
    }

    private func updateRenderingState(expanded: Bool) {
        removalTask?.cancel()
        removalTask = nil

        if expanded {
            isRenderingContent = true
            return
        }

        guard isRenderingContent else { return }

        removalTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: ContainedExpansionMotion.contentRemovalDelayNanoseconds)
            guard !Task.isCancelled, !isExpanded else { return }
            isRenderingContent = false
        }
    }
}
