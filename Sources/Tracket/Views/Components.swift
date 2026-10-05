import SwiftUI

struct Surface<Content: View>: View {
    private let content: Content
    private let padding: CGFloat

    init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.74))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(.white.opacity(0.08))
                    }
            }
    }
}

struct StagePill: View {
    let stage: ProjectStage

    var body: some View {
        Label(stage.title, systemImage: stage.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(stage.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(stage.tint.opacity(0.12), in: Capsule())
    }
}

struct MomentumRing: View {
    let score: Int
    var size: CGFloat = 116

    private var color: Color {
        switch score {
        case 75...: .green
        case 45...: TracketTheme.accent
        case 20...: .orange
        default: .red
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.13), lineWidth: 11)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(
                    AngularGradient(colors: [color.opacity(0.55), color], center: .center),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: size * 0.27, weight: .bold, design: .rounded))
                Text("momentum")
                    .font(.system(size: size * 0.09, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Momentum \(score) percent")
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let caption: String
    let symbol: String
    let tint: Color

    var body: some View {
        Surface(padding: 16) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text(value)
                        .font(.title2.bold())
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct ToolChip: View {
    let tool: DeveloperTool

    var body: some View {
        Label(tool.title, systemImage: tool.symbol)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
    }
}

struct ActivityRow: View {
    let activity: ProjectActivityEvent
    var context: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: activity.source.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(activity.source.tint)
                .frame(width: 30, height: 30)
                .background(activity.source.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(activity.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(activity.occurredAt.compactRelative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(activity.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let context {
                    Text(context)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(activity.source.tint)
                }
            }
        }
    }
}

extension Date {
    var compactRelative: String {
        RelativeDateTimeFormatter.tracket.localizedString(for: self, relativeTo: Date())
    }

    var compactDate: String {
        formatted(.dateTime.month(.abbreviated).day())
    }
}

private extension RelativeDateTimeFormatter {
    static let tracket: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
