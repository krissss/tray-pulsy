import SwiftUI

struct SkinThumbnail: View {
    @Environment(AppState.self) private var appState
    let skin: SkinInfo
    let isSelected: Bool
    let pulsyConfigToken: String

    @State private var thumbnailImage: NSImage?
    @State private var animator: TrayAnimator?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image = thumbnailImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 32, height: 32)
            .padding(6)
            .glassEffect(.regular, in: .rect(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)

            Text(skin.displayName)
                .font(.caption2)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .glassEffect(
            isSelected ? .regular.tint(Color.accentColor) : .regular,
            in: .rect(cornerRadius: 10, style: .continuous)
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(skin.displayName)\(isSelected ? L10n.accSelected : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onAppear {
            updateAnimationState()
        }
        .onDisappear {
            stopAnimation()
        }
        .onChange(of: isSelected) {
            updateAnimationState()
        }
        .onChange(of: pulsyConfigToken) {
            guard isSelected, skin.id == "pulsy" else { return }
            startAnimation()
        }
    }

    private func updateAnimationState() {
        if isSelected {
            startAnimation()
        } else {
            stopAnimation()
            thumbnailImage = appState.skinManager.frame(for: skin.id, frameIndex: 0)
        }
    }

    private func startAnimation() {
        stopAnimation()
        let frames = appState.skinManager.frames(for: skin)
        guard !frames.isEmpty else {
            thumbnailImage = nil
            return
        }

        let animator = TrayAnimator(initialFrames: frames)
        animator.setFPSLimit(.fps20)
        animator.onFrameUpdate = { [weak animator] image in
            _ = animator
            MainActor.assumeIsolated {
                thumbnailImage = image
            }
        }
        animator.updateValue(50)
        animator.start()
        self.animator = animator
    }

    private func stopAnimation() {
        animator?.stop()
        animator = nil
    }
}
