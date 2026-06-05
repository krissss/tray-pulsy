import Defaults
import SwiftUI

struct SkinThumbnail: View {
    @Environment(AppState.self) private var appState
    @Default(.reverseAnimationSpeed) private var reverseAnimationSpeed
    @Default(.skinAnimationSpeed) private var skinAnimationSpeed
    let skin: SkinInfo
    let isSelected: Bool
    let previewLoad: Double
    let pulsyConfigToken: String

    @State private var thumbnailImage: NSImage?
    @State private var animator: TrayAnimator?

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .topTrailing) {
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
                .frame(width: 34, height: 34)
                .padding(7)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.secondary.opacity(isSelected ? 0.09 : 0.055))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.28) : .secondary.opacity(0.08), lineWidth: 1)
                }
                .accessibilityHidden(true)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .background {
                            Circle()
                                .fill(.background)
                                .frame(width: 10, height: 10)
                        }
                        .offset(x: 3, y: -3)
                        .accessibilityHidden(true)
                }
            }

            Text(skin.displayName)
                .font(.caption2.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 84)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.11) : .secondary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.34) : .secondary.opacity(0.07), lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: 10, style: .continuous))
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(skin.displayName)\(isSelected ? L10n.accSelected : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
        .onChange(of: previewLoad) {
            updatePreviewLoad()
        }
        .onChange(of: pulsyConfigToken) {
            guard skin.id == "pulsy" else { return }
            startAnimation()
        }
        .onChange(of: reverseAnimationSpeed) {
            animator?.setReverseAnimationSpeed(reverseAnimationSpeed)
        }
        .onChange(of: skinAnimationSpeed) {
            animator?.setSkinAnimationSpeed(skinAnimationSpeed)
        }
    }

    private func startAnimation() {
        stopAnimation()
        let frames = previewFrames()
        guard !frames.isEmpty else {
            thumbnailImage = nil
            return
        }

        thumbnailImage = frames.first
        guard frames.count > 1 else { return }

        let animator = TrayAnimator(initialFrames: frames)
        animator.setFPSLimit(.fps20)
        animator.setReverseAnimationSpeed(reverseAnimationSpeed)
        animator.setSkinAnimationSpeed(skinAnimationSpeed)
        animator.onFrameUpdate = { [weak animator] image in
            _ = animator
            MainActor.assumeIsolated {
                thumbnailImage = image
            }
        }
        animator.updateValue(previewLoad)
        animator.start()
        self.animator = animator
    }

    private func updatePreviewLoad() {
        if skin.id == "pulsy" {
            let frames = previewFrames()
            animator?.updateFrames(frames)
            if animator == nil {
                thumbnailImage = frames.first
            }
        }
        animator?.updateValue(previewLoad)
    }

    private func previewFrames() -> [NSImage] {
        if skin.id == "pulsy" {
            return PulsySkinRenderer.generateFrames(
                value: CGFloat(previewLoad),
                config: SkinManager.currentPulsyConfig()
            )
        }
        return appState.skinManager.frames(for: skin)
    }

    private func stopAnimation() {
        animator?.stop()
        animator = nil
    }
}
