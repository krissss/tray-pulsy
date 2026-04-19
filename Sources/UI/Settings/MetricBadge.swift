import SwiftUI

struct MetricBadge: View {
    let icon: String
    let label: String
    let valueText: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(height: 22)
            Text(valueText)
                .font(.system(.title3, design: .rounded).monospacedDigit().bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 80)
    }
}
