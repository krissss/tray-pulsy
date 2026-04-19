import SwiftUI

struct MetricRow: View {
    let icon: String
    let name: String
    let value: Double
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(value, specifier: "%.1f")%")
                    if let detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: min(value / 100.0, 1.0))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value, format: .number.precision(.fractionLength(0)))
                    .font(.system(.caption2, design: .rounded).monospacedDigit().bold())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 36, height: 36)
        }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 10, style: .continuous))
    }
}
