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
            .glassEffect(.regular, in: .rect(cornerRadius: 8, style: .continuous))

            Text(skin.displayName)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .glassEffect(
            isSelected ? .regular.tint(.accentColor.opacity(0.3)) : .regular,
            in: .rect(cornerRadius: 10, style: .continuous)
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
