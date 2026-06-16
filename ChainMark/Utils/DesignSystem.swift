import SwiftUI

// MARK: - ChainMark Design System
/// Premium, cohesive design tokens to achieve the "Tesla of investigations" quality bar.
/// All visual constants live here — never hard-coded values in views.

enum AppColors {
    // MARK: - Core
    
    /// Primary brand color — yellow/gold for trust and warmth
    static let accent = Color(red: 0.95, green: 0.78, blue: 0.25)
    static let accentLight = Color(red: 1.0, green: 0.85, blue: 0.40)
    static let accentDark = Color(red: 0.75, green: 0.60, blue: 0.15)
    
    // MARK: - Backgrounds
    
    static let background = Color.black
    static let surface = Color.white.opacity(0.08)
    static let surfaceElevated = Color.white.opacity(0.12)
    static let surfaceDeep = Color(red: 0.08, green: 0.08, blue: 0.10)
    
    // MARK: - Text
    
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.7)
    static let tertiary = Color.white.opacity(0.45)
    static let disabled = Color.white.opacity(0.25)
    
    // MARK: - Status
    
    static let success = Color(red: 0.25, green: 0.78, blue: 0.45)
    static let warning = Color(red: 0.95, green: 0.78, blue: 0.25)
    static let error = Color(red: 0.90, green: 0.30, blue: 0.25)
    static let info = Color(red: 0.25, green: 0.60, blue: 0.95)
    
    // MARK: - GPS Quality
    
    static let gpsExcellent = Color.green
    static let gpsGood = Color(red: 0.60, green: 0.80, blue: 0.20)
    static let gpsFair = Color.orange
    static let gpsPoor = Color.red
    
    // MARK: - Seal Status
    
    static let sealed = Color(red: 0.25, green: 0.78, blue: 0.45)
    static let pending = Color(red: 0.95, green: 0.78, blue: 0.25)
    static let signed = Color(red: 0.40, green: 0.60, blue: 0.95)
    
    // MARK: - Borders
    
    static let border = Color.white.opacity(0.15)
    static let borderFocused = accent.opacity(0.5)
    
    // MARK: - Shadows
    
    static let shadowDark = Color.black.opacity(0.4)
    static let shadowAccent = accent.opacity(0.15)
}

enum AppTypography {
    // MARK: - Font Sizes
    
    static let caption2: CGFloat = 10
    static let caption: CGFloat = 11
    static let footnote: CGFloat = 12
    static let subheadline: CGFloat = 14
    static let callout: CGFloat = 15
    static let body: CGFloat = 16
    static let headline: CGFloat = 17
    static let title3: CGFloat = 20
    static let title2: CGFloat = 24
    static let title1: CGFloat = 28
    static let largeTitle: CGFloat = 34
    
    // MARK: - Font Weights
    
    static let regular: Font.Weight = .regular
    static let medium: Font.Weight = .medium
    static let semibold: Font.Weight = .semibold
    static let bold: Font.Weight = .bold
    
    // MARK: - Monospace (for hashes, GPS coordinates)
    
    static let monoSize: CGFloat = 11
    static let monoSmall: CGFloat = 9
}

enum AppSpacing {
    // MARK: - Spacing Scale (4-point grid)
    
    static let xxsmall: CGFloat = 2
    static let xsmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xlarge: CGFloat = 20
    static let xxlarge: CGFloat = 24
    static let xxxlarge: CGFloat = 32
    static let huge: CGFloat = 40
    
    // MARK: - Corner Radii
    
    static let radiusSmall: CGFloat = 6
    static let radiusMedium: CGFloat = 10
    static let radiusLarge: CGFloat = 12
    static let radiusXLarge: CGFloat = 16
    
    // MARK: - Padding
    
    static let paddingInline: CGFloat = 12
    static let paddingCard: CGFloat = 16
    static let paddingSection: CGFloat = 20
    static let paddingScreen: CGFloat = 16
}

// MARK: - Reusable View Modifiers

extension View {
    /// Card-style surface with rounded corners
    func cardStyle() -> some View {
        self
            .padding(AppSpacing.paddingCard)
            .background(AppColors.surface)
            .cornerRadius(AppSpacing.radiusLarge)
    }
    
    /// Subtle elevated card (used for active/sealed items)
    func cardStyleElevated() -> some View {
        self
            .padding(AppSpacing.paddingCard)
            .background(AppColors.surfaceElevated)
            .cornerRadius(AppSpacing.radiusLarge)
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.radiusLarge)
                    .stroke(AppColors.border, lineWidth: 0.5)
            )
    }
    
    /// Status badge styling
    func statusBadge(color: Color, text: String) -> some View {
        HStack(spacing: AppSpacing.xxsmall) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: AppTypography.caption2, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, AppSpacing.small)
        .padding(.vertical, AppSpacing.xsmall)
        .background(color.opacity(0.15))
        .cornerRadius(AppSpacing.radiusSmall)
    }
    
    /// Section header style
    func sectionHeader() -> some View {
        self
            .font(.system(size: AppTypography.subheadline, weight: .semibold))
            .foregroundColor(AppColors.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
    
    /// Detail row: label on left, value on right
    func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: AppTypography.caption))
                .foregroundColor(AppColors.tertiary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: AppTypography.subheadline))
                .foregroundColor(AppColors.primary)
            Spacer()
        }
    }
    
    /// Primary action button
    func primaryButton(color: Color = AppColors.accent) -> some View {
        self
            .font(.system(size: AppTypography.body, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color)
            .foregroundColor(.black)
            .cornerRadius(AppSpacing.radiusMedium)
    }
    
    /// Add haptic feedback on tap
    func hapticOnTap(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) -> some View {
        self.simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    let impact = UIImpactFeedbackGenerator(style: style)
                    impact.impactOccurred()
                }
        )
    }
    
    /// Accessibility label for evidence actions
    func evidenceAction(label: String, hint: String = "") -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)
    }
    
    /// Standard row background
    func rowBackground() -> some View {
        self
            .padding(AppSpacing.medium)
            .background(AppColors.surface)
            .cornerRadius(AppSpacing.radiusMedium)
    }
}

// MARK: - GPS Quality Helpers

extension Color {
    static func gpsQualityColor(accuracy: Double) -> Color {
        if accuracy <= 0 { return AppColors.warning }
        if accuracy <= 10 { return AppColors.gpsExcellent }
        if accuracy <= 50 { return AppColors.gpsGood }
        if accuracy <= 100 { return AppColors.gpsFair }
        return AppColors.gpsPoor
    }
}