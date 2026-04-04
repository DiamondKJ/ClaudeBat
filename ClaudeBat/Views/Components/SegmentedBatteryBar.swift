import SwiftUI

enum BatteryBarSize {
    case compact    // Menu bar: 10 segments, 2px wide, 9px tall
    case `default`  // Popup session: 20 segments, 12px wide, 16px tall
    case medium     // Popup weekly: 15 segments, 10px wide, 12px tall
    case mini       // Model breakdown: 10 segments, 12px wide, 8px tall

    var segmentCount: Int {
        switch self {
        case .compact: return 10
        case .default: return 20
        case .medium: return 15
        case .mini: return 10
        }
    }

    var segmentWidth: CGFloat {
        switch self {
        case .compact: return 2
        case .default: return 12
        case .medium: return 10
        case .mini: return 12
        }
    }

    var segmentHeight: CGFloat {
        switch self {
        case .compact: return 9
        case .default: return 16
        case .medium: return 12
        case .mini: return 8
        }
    }

    var borderWidth: CGFloat {
        switch self {
        case .compact: return 1
        case .default: return 3
        case .medium: return 2
        case .mini: return 2
        }
    }

    var padding: CGFloat {
        switch self {
        case .compact: return 2
        case .default: return 3
        case .medium: return 2
        case .mini: return 2
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .compact: return 2
        default: return 0
        }
    }

    var segmentRadius: CGFloat {
        switch self {
        case .compact: return 1
        default: return 0
        }
    }
}

struct SegmentedBatteryBar: View {
    let percentage: Double // 0-100 remaining
    var size: BatteryBarSize = .default
    var fillColor: Color? = nil
    var borderColor: Color? = nil
    var showBorder: Bool = true

    /// Number of fully filled segments
    private var fullSegments: Int {
        Int(percentage / 100.0 * Double(size.segmentCount))
    }

    /// Fractional fill (0.0–1.0) for the partially filled segment
    private var partialFill: CGFloat {
        let exact = percentage / 100.0 * Double(size.segmentCount)
        return CGFloat(exact - Double(fullSegments))
    }

    /// Default fill: use battery state color based on percentage
    private var resolvedFillColor: Color {
        fillColor ?? CBColor.batteryColor(for: percentage)
    }

    private var resolvedBorderColor: Color {
        borderColor ?? CBColor.borderStrong
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<size.segmentCount, id: \.self) { index in
                if index < fullSegments {
                    // Fully filled
                    RoundedRectangle(cornerRadius: size.segmentRadius)
                        .fill(resolvedFillColor)
                        .frame(width: size.segmentWidth, height: size.segmentHeight)
                } else if index == fullSegments && partialFill > 0 {
                    // Partially filled — clip the fill from the leading edge
                    RoundedRectangle(cornerRadius: size.segmentRadius)
                        .fill(CBColor.elevated.opacity(0.3))
                        .frame(width: size.segmentWidth, height: size.segmentHeight)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: size.segmentRadius)
                                .fill(resolvedFillColor)
                                .frame(width: size.segmentWidth * partialFill)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: size.segmentRadius))
                } else {
                    // Empty
                    RoundedRectangle(cornerRadius: size.segmentRadius)
                        .fill(CBColor.elevated.opacity(0.3))
                        .frame(width: size.segmentWidth, height: size.segmentHeight)
                }
            }
        }
        .padding(size.padding)
        .background(CBColor.base)
        .overlay(
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .stroke(
                    showBorder ? resolvedBorderColor : .clear,
                    lineWidth: size.borderWidth
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius))
    }
}

// MARK: - Menu Bar Battery (with cap)

struct MenuBarBattery: View {
    let percentage: Double

    private var fillColor: Color {
        CBColor.batteryColor(for: percentage)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Body
            SegmentedBatteryBar(
                percentage: percentage,
                size: .compact,
                fillColor: fillColor,
                showBorder: false
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(CBColor.accent, lineWidth: 1)
            )

            // Cap
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 1.5,
                topTrailingRadius: 1.5
            )
            .fill(CBColor.accent)
            .frame(width: 2, height: 5)
        }
    }
}
