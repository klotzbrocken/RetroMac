import SwiftUI

// MARK: - Card

struct RMCard<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    var headerAction: AnyView? = nil
    var bodyPadding: CGFloat = RMSpacing.card
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = title {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(-0.05)
                            .foregroundColor(.rmTextPrimary)
                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(.rmSecondary)
                                .foregroundColor(.rmTextSecondary)
                                .lineSpacing(1.35)
                        }
                    }
                    Spacer()
                    if let action = headerAction {
                        action
                    }
                }
                .padding(.horizontal, RMSpacing.card)
                .padding(.top, 13)
                .padding(.bottom, 12)

                Rectangle()
                    .fill(Color.rmDivider)
                    .frame(height: 1)
            }

            content()
                .padding(bodyPadding)
        }
        .background(Color.rmSurface)
        .clipShape(RoundedRectangle(cornerRadius: RMRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: RMRadius.card)
                .stroke(Color.rmBorder, lineWidth: 1)
        )
        .rmCardShadow()
    }
}

// MARK: - Row

struct RMRow<Control: View>: View {
    var label: String
    var hint: String? = nil
    var isLast: Bool = false
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.rmBody)
                        .foregroundColor(.rmTextPrimary)
                        .lineSpacing(1.35)
                    if let hint = hint {
                        Text(hint)
                            .font(.rmSecondary)
                            .foregroundColor(.rmTextSecondary)
                            .lineSpacing(1.45)
                    }
                }
                Spacer(minLength: 12)
                control()
                    .frame(minHeight: 22)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, RMSpacing.card)

            if !isLast {
                Rectangle()
                    .fill(Color.rmDivider)
                    .frame(height: 1)
                    .padding(.horizontal, RMSpacing.card)
            }
        }
    }
}

// MARK: - Chip

enum RMChipTone {
    case neutral, on, warn, danger, info
}

struct RMChip: View {
    var text: String
    var tone: RMChipTone = .neutral
    var showDot: Bool = true

    private var bgColor: Color {
        switch tone {
        case .neutral: return Color(red: 0.933, green: 0.941, blue: 0.953)
        case .on: return .rmAccentSoft
        case .warn: return Color(red: 0.992, green: 0.953, blue: 0.875)
        case .danger: return Color(red: 0.992, green: 0.914, blue: 0.898)
        case .info: return Color(red: 0.894, green: 0.933, blue: 0.992)
        }
    }

    private var fgColor: Color {
        switch tone {
        case .neutral: return .rmTextSecondary
        case .on: return .rmAccentText
        case .warn: return Color(red: 0.655, green: 0.427, blue: 0.063)
        case .danger: return Color(red: 0.659, green: 0.200, blue: 0.102)
        case .info: return Color(red: 0.114, green: 0.298, blue: 0.698)
        }
    }

    private var dotColor: Color {
        switch tone {
        case .neutral: return .rmTextTertiary
        case .on: return .rmAccent
        case .warn: return Color(red: 0.878, green: 0.620, blue: 0.169)
        case .danger: return .rmDanger
        case .info: return .rmInfo
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if showDot {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(fgColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(bgColor)
        .clipShape(Capsule())
    }
}

// MARK: - Section Header

struct RMSectionHeaderView: View {
    var title: String
    var hint: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: RMSpacing.lg) {
            Text(title.uppercased())
                .font(.rmSectionHeader)
                .tracking(0.5)
                .foregroundColor(.rmTextSecondary)

            Rectangle()
                .fill(Color.rmDivider)
                .frame(height: 1)

            if let hint = hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundColor(.rmTextTertiary)
            }
        }
        .padding(.vertical, 4)
        .padding(.bottom, RMSpacing.lg)
    }
}

// MARK: - KeyCap

struct RMKeyCap: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.rmMono(size: 11.5, weight: .medium))
            .foregroundColor(.rmTextPrimary)
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 6)
            .background(
                LinearGradient(
                    colors: [Color.white, Color(red: 0.941, green: 0.949, blue: 0.965)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: RMRadius.keyCap))
            .overlay(
                RoundedRectangle(cornerRadius: RMRadius.keyCap)
                    .stroke(Color.rmBorderStrong, lineWidth: 1)
            )
            .overlay(
                Rectangle()
                    .fill(Color.rmBorderStrong)
                    .frame(height: 0.5)
                    .offset(y: 0.5),
                alignment: .bottom
            )
            .shadow(color: Color.black.opacity(0.06), radius: 0, x: 0, y: 1)
    }
}

// MARK: - Hotkey Chip (multiple KeyCaps with + between)

struct RMHotkeyChip: View {
    var keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                if index > 0 {
                    Text("+")
                        .font(.system(size: 10))
                        .foregroundColor(.rmTextTertiary)
                }
                RMKeyCap(text: key)
            }
        }
    }
}

// MARK: - Button Styles

struct RMPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.227, green: 0.702, blue: 0.420),
                        Color(red: 0.169, green: 0.600, blue: 0.353)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: RMRadius.button))
            .overlay(
                RoundedRectangle(cornerRadius: RMRadius.button)
                    .stroke(Color(red: 0.133, green: 0.502, blue: 0.298), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct RMDefaultButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(.rmTextPrimary)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                LinearGradient(
                    colors: [Color.white, Color(red: 0.965, green: 0.969, blue: 0.976)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: RMRadius.button))
            .overlay(
                RoundedRectangle(cornerRadius: RMRadius.button)
                    .stroke(Color.rmBorderStrong, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 0, x: 0, y: 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct RMGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(.rmTextSecondary)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct RMDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(.rmDanger)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                LinearGradient(
                    colors: [Color.white, Color(red: 0.965, green: 0.969, blue: 0.976)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: RMRadius.button))
            .overlay(
                RoundedRectangle(cornerRadius: RMRadius.button)
                    .stroke(Color.rmBorderStrong, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 0, x: 0, y: 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
