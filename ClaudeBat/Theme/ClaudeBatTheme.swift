import SwiftUI

// MARK: - Colors

enum CBColor {
    // Primitives
    static let base = Color(red: 0x1A/255, green: 0x12/255, blue: 0x10/255)
    static let surface = Color(red: 0x2A/255, green: 0x20/255, blue: 0x18/255)
    static let elevated = Color(red: 0x3A/255, green: 0x30/255, blue: 0x28/255)
    static let accent = Color(red: 0xE8/255, green: 0x73/255, blue: 0x4A/255)

    // Text
    static let textPrimary = Color(red: 0xE6/255, green: 0xE8/255, blue: 0xEF/255)
    static let textSecondary = Color(red: 0x94/255, green: 0xA3/255, blue: 0xB8/255)
    static let textMuted = Color(red: 0x64/255, green: 0x74/255, blue: 0x8B/255)

    // Battery states
    static let batteryHigh = Color(red: 0x4A/255, green: 0xDE/255, blue: 0x80/255)
    static let batteryMid = Color(red: 0xFB/255, green: 0xBF/255, blue: 0x24/255)
    static let batteryLow = Color(red: 0xF8/255, green: 0x71/255, blue: 0x71/255)
    static let batteryCritical = Color(red: 0xEF/255, green: 0x44/255, blue: 0x44/255)

    // Semantic
    static let borderDefault = accent.opacity(0.08)
    static let borderStrong = accent.opacity(0.12)
    static let accentMuted = accent.opacity(0.08)
    static let focusRing = accent.opacity(0.30)

    /// Returns the battery color based on remaining percentage
    static func batteryColor(for remaining: Double) -> Color {
        switch remaining {
        case 60...100: return batteryHigh
        case 30..<60: return batteryMid
        case 10..<30: return batteryLow
        case 0..<10: return batteryCritical
        default: return accent
        }
    }
}

// MARK: - NSColor equivalents for AppKit

public enum CBNSColor {
    public static let base = NSColor(red: 0x1A/255, green: 0x12/255, blue: 0x10/255, alpha: 1)
    public static let surface = NSColor(red: 0x2A/255, green: 0x20/255, blue: 0x18/255, alpha: 1)
    public static let accent = NSColor(red: 0xE8/255, green: 0x73/255, blue: 0x4A/255, alpha: 1)
}

// MARK: - Typography

enum CBFont {
    /// Press Start 2P — pixel/brand font for numbers and titles
    static func pixelFont(size: CGFloat) -> Font {
        .custom("PressStart2P-Regular", size: size)
    }

    /// SF Pro — system UI font for labels and descriptions
    static func uiFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    // Named sizes from design system
    static let menuBarNumber = pixelFont(size: 11)
    static let displayNumber = pixelFont(size: 32)
    static let weeklyNumber = pixelFont(size: 16)
    static let modelNumber = pixelFont(size: 11)
    static let brandName = pixelFont(size: 11)
    static let heading = pixelFont(size: 20)
    static let subheading = pixelFont(size: 16)

    static let sectionHeader = uiFont(size: 12, weight: .medium)
    static let bodyText = uiFont(size: 13)
    static let smallLabel = uiFont(size: 11)
    static let tinyLabel = uiFont(size: 10, weight: .medium)
    static let modelLabel = uiFont(size: 12)
}

// MARK: - Spacing

enum CBSpacing {
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space6: CGFloat = 24
    static let space8: CGFloat = 32
    static let space12: CGFloat = 48
    static let space16: CGFloat = 64

    // Popup
    static let popupPadding: CGFloat = 20
    static let popupWidth: CGFloat = 320
    static let popupHeight: CGFloat = 392
}

// MARK: - Corner Radius

enum CBRadius {
    static let batteryBar: CGFloat = 4
    static let button: CGFloat = 6
    static let card: CGFloat = 8
    static let popup: CGFloat = 10
    static let pill: CGFloat = 9999
}

// MARK: - Font Registration

public enum FontRegistration {
    public static func registerFonts() {
        guard let fontURL = findFontURL() else {
            print("ClaudeBat: PressStart2P-Regular.ttf not found in any bundle")
            return
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) {
            // Already registered is fine
            let cfError = error?.takeRetainedValue()
            let code = cfError.map { CFErrorGetCode($0) } ?? 0
            if code != 105 { // 105 = already registered
                print("ClaudeBat: Failed to register font: \(cfError.debugDescription)")
            }
        }
    }

    /// Find the font without relying on Bundle.module (which fatalErrors if the
    /// SPM resource bundle isn't found — common in redistributed .app bundles).
    private static func findFontURL() -> URL? {
        let fontName = "PressStart2P-Regular"
        let bundleName = "ClaudeBat_ClaudeBatCore"

        // 1. Search for the SPM resource bundle in likely locations
        let searchRoots: [URL?] = [
            Bundle.main.resourceURL,                                          // .app/Contents/Resources/
            Bundle.main.bundleURL,                                            // .app/
            Bundle.main.executableURL?.deletingLastPathComponent(),            // next to binary (swift run)
        ]
        for root in searchRoots {
            guard let bundleDir = root?.appendingPathComponent(bundleName + ".bundle") else { continue }
            // Release .app: Contents/Resources/Font.ttf
            let nested = bundleDir.appendingPathComponent("Contents/Resources/\(fontName).ttf")
            if FileManager.default.fileExists(atPath: nested.path) { return nested }
            // Debug (swift run): Font.ttf at bundle root
            let flat = bundleDir.appendingPathComponent("\(fontName).ttf")
            if FileManager.default.fileExists(atPath: flat.path) { return flat }
        }

        // 2. Main bundle directly (e.g. font copied into Resources/)
        if let url = Bundle.main.url(forResource: fontName, withExtension: "ttf") {
            return url
        }

        return nil
    }
}
