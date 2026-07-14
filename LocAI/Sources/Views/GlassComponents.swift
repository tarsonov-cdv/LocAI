import SwiftUI

/// Shared visual language for the whole app - real Liquid Glass via
/// `.glassEffect()` / `GlassEffectContainer` (macOS 26 / iOS 26 SDK),
/// not an imitation. Falls back gracefully on older OS versions.

/// A rounded glass "card" wrapping arbitrary content - the workhorse
/// container used across Chat/Models/Settings/Tuning instead of the old
/// ttk.LabelFrame boxes.
struct GlassCard<Content: View>: View {
    var title: String? = nil
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(16)
        .glassEffect(
            tint.map { Glass.regular.tint($0) } ?? Glass.regular,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }
}

/// A pill-shaped glass button for primary actions (Send, Download, Start
/// tuning, ...). Uses the system `.glass`/`.glassProminent` button styles
/// so it matches native controls exactly rather than a hand-drawn look.
struct GlassActionButton: View {
    let title: String
    var systemImage: String? = nil
    var prominent: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(.glass)
        .tint(prominent ? Color.accentColor : nil)
        .disabled(isDisabled)
    }
}

/// Page header used at the top of each tab - big glass title bar.
struct GlassHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.largeTitle.bold())
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }
}

/// Full-window animated backdrop the glass cards sit above. Liquid Glass
/// is a *translucency* effect - it needs varied color/light behind it to
/// read as "glass" rather than flat frosted gray, so we paint soft
/// drifting color blobs behind the whole app.
struct LiquidBackdrop: View {
    @State private var animate = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let blobs: [(Color, CGFloat, CGFloat, CGFloat)] = [
                    (.indigo, 0.30 + 0.05 * CGFloat(sin(t * 0.05)), 0.25, 0.55),
                    (.purple, 0.70 + 0.05 * CGFloat(cos(t * 0.04)), 0.65, 0.5),
                    (.teal,   0.45 + 0.06 * CGFloat(sin(t * 0.03 + 2)), 0.85, 0.45),
                ]
                for (color, relX, relY, relRadius) in blobs {
                    let center = CGPoint(x: size.width * relX, y: size.height * relY)
                    let radius = size.width * relRadius
                    let gradient = Gradient(colors: [color.opacity(0.55), color.opacity(0.0)])
                    context.fill(
                        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                        with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
                    )
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}
