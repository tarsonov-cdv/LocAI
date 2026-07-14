import SwiftUI

/// Shared low-overhead visual language for the whole app using static
/// SwiftUI materials and standard controls.
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
        .staticBlurPanel(cornerRadius: 18, tint: tint)
    }
}

/// Standard action button wrapper used across the app.
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
        .standardActionStyle(prominent: prominent)
        .disabled(isDisabled)
    }
}

/// Page header used at the top of each tab.
struct GlassHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
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
        .staticBlurPanel(cornerRadius: 20)
    }
}

struct StaticBackdrop: View {
    var body: some View {
        platformBackground
            .ignoresSafeArea()
    }

    private var platformBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }
}

extension View {
    func staticBlurPanel(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    if let tint {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.08))
                    }
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        }
    }

    @ViewBuilder
    func standardActionStyle(prominent: Bool) -> some View {
        if prominent {
            self
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
