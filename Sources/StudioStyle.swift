import SwiftUI

enum Studio {
    // C · 暖木棋室. These are explicit sRGB tokens so light surfaces remain
    // consistent even when the operating system uses a dark appearance.
    // Legacy names stay source-compatible with the existing learning screens.
    static let ink = Color(red: 68 / 255, green: 42 / 255, blue: 30 / 255)
    static let muted = Color(red: 116 / 255, green: 94 / 255, blue: 75 / 255)
    static let rail = Color(red: 247 / 255, green: 239 / 255, blue: 225 / 255)
    static let paper = Color(red: 244 / 255, green: 235 / 255, blue: 219 / 255)
    static let white = Color(red: 255 / 255, green: 250 / 255, blue: 240 / 255)
    static let cream = Color(red: 239 / 255, green: 226 / 255, blue: 206 / 255)
    static let line = Color(red: 223 / 255, green: 206 / 255, blue: 181 / 255)
    static let accent = Color(red: 182 / 255, green: 75 / 255, blue: 38 / 255)
    static let green = accent
    // Darkened ochre / teal / plum retain readable light Top 1/2/3 numerals.
    static let gold = Color(red: 138 / 255, green: 88 / 255, blue: 12 / 255)
    static let cyan = Color(red: 35 / 255, green: 102 / 255, blue: 106 / 255)
    static let purple = Color(red: 105 / 255, green: 81 / 255, blue: 121 / 255)
    static let red = Color(red: 156 / 255, green: 45 / 255, blue: 28 / 255)
    static let success = Color(red: 71 / 255, green: 107 / 255, blue: 63 / 255)
    static let onAccent = Color(red: 255 / 255, green: 250 / 255, blue: 241 / 255)
    static let surfaceRaised = Color(red: 253 / 255, green: 247 / 255, blue: 235 / 255)
    static let shadow = Color(red: 97 / 255, green: 61 / 255, blue: 28 / 255)
    static let cornerRadius: CGFloat = 10

    static func symbol(_ stage: LearningStage) -> String {
        switch stage {
        case .foundation: return "shield.lefthalf.filled"
        case .opening: return "arrow.triangle.branch"
        case .tactics: return "scope"
        case .endgame: return "flag.checkered"
        case .strategy: return "point.topleft.down.to.point.bottomright.curvepath"
        }
    }
    static func color(_ stage: LearningStage) -> Color {
        switch stage {
        case .foundation: return success
        case .opening: return accent
        case .tactics: return red
        case .endgame: return gold
        case .strategy: return purple
        }
    }
    static func stageName(_ stage: LearningStage) -> String {
        switch stage {
        case .foundation: return "基础补漏"
        case .opening: return "布局与中局衔接"
        case .tactics: return "计算与攻防"
        case .endgame: return "残局转化与胜和"
        case .strategy: return "形势判断与计划"
        }
    }
}

struct StudioButtonStyle: ButtonStyle {
    var primary = false
    var compact = false
    var destructive = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .padding(.horizontal, compact ? 12 : 18).padding(.vertical, compact ? 8 : 11)
            .frame(minHeight: compact ? 34 : 40)
            .contentShape(Rectangle())
            .foregroundColor(primary ? Studio.onAccent : destructive ? Studio.red : Studio.ink)
            .background(primary ? (destructive ? Studio.red : Studio.accent) : Studio.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: Studio.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Studio.cornerRadius)
                .strokeBorder(primary ? Color.clear : contrast == .increased ? Studio.muted : Studio.line.opacity(0.8), lineWidth: 0.75)
                .allowsHitTesting(false))
            .shadow(color: Studio.shadow.opacity(enabled ? primary ? 0.14 : 0.08 : 0), radius: 3, y: 2)
            .opacity(enabled ? configuration.isPressed ? 0.82 : 1 : 0.45)
    }
}

/// Plain labels still need a rectangular hit target: a clear background alone
/// can leave spaces between icons and text untappable. Press feedback is instant,
/// without scaling the target beneath a moving pointer.
struct StudioQuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle())
            .opacity(enabled ? configuration.isPressed ? 0.65 : 1 : 0.45)
    }
}

struct StudioIconButton: View {
    let symbol: String
    let label: String
    var active = false
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                .foregroundColor(active ? Studio.green : Studio.muted)
                .background(active || hovering ? Studio.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(StudioQuietButtonStyle()).help(label).accessibilityLabel(label)
            .onHover { hovering = $0 }
    }
}

struct StudioTag: View {
    let text: String
    var color: Color = Studio.green
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium))
            .foregroundColor(color).padding(.horizontal, 8).padding(.vertical, 5)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
    }
}

struct StudioProgress: View {
    let value: Double
    var color: Color = Studio.green
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Studio.line)
                Capsule().fill(color).frame(width: max(0, geo.size.width * min(1, max(0, value))))
            }
        }.frame(height: 4)
            .accessibilityLabel("进度").accessibilityValue("\(Int(min(1, max(0, value)) * 100))%")
    }
}

struct StudioEmpty: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light))
                .foregroundColor(Studio.green).frame(width: 74, height: 74)
                .background(Studio.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            Text(title).font(.system(size: 20, weight: .semibold))
            Text(detail).font(.system(size: 13)).foregroundColor(Studio.muted)
                .multilineTextAlignment(.center).lineSpacing(5).frame(maxWidth: 360)
        }.frame(maxWidth: .infinity).padding(.vertical, 48)
    }
}

extension View {
    func studioSurface(_ padding: CGFloat = 20) -> some View {
        self.padding(padding).background(Studio.white, in: RoundedRectangle(cornerRadius: Studio.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Studio.cornerRadius).strokeBorder(Studio.line.opacity(0.5), lineWidth: 0.65).allowsHitTesting(false))
            .shadow(color: Studio.shadow.opacity(0.055), radius: 5, y: 2)
    }
}
