import SwiftUI

struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(20)
            .glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
    }
}
