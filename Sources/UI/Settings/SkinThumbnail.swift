import SwiftUI

struct SkinThumbnail: View {
    let skin: SkinInfo
    let isSelected: Bool
    @State private var thumbnailImage: NSImage?

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
            isSelected ? .regular.tint(.accentColor.opacity(0.3)) : .regular,
            in: .rect(cornerRadius: 10, style: .continuous)
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(skin.displayName)\(isSelected ? "，已选中" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onAppear {
            thumbnailImage = SkinManager.shared.frame(for: skin.id, frameIndex: 0)
        }
    }
}
