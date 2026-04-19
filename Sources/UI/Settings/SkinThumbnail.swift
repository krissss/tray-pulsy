import SwiftUI
import Defaults

struct SkinThumbnail: View {
    let skin: SkinInfo
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let frame = SkinManager.shared.frame(for: skin.id, frameIndex: 0) {
                    Image(nsImage: frame)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 36, height: 36)
            .padding(8)
            .background(.regularMaterial, in: .rect(cornerRadius: 8, style: .continuous))

            Text(skin.displayName)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : .clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1.5)
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
