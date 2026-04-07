import SwiftUI

struct CachedDataBanner: View {
    let reason: CachedDataReason

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(CBFont.pixelFont(size: 8))
                    .foregroundStyle(titleColor)
                    .tracking(0.5)

                Spacer()

                Rectangle()
                    .fill(titleColor)
                    .frame(width: 8, height: 8)
            }

            Text(message)
                .font(CBFont.smallLabel)
                .foregroundStyle(CBColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CBColor.base.opacity(0.95))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var title: String {
        switch reason {
        case .authInvalid, .noToken:
            return "AUTH STALE"
        case .networkError:
            return "OFFLINE CACHE"
        case .serverError:
            return "SERVER STALE"
        case .rateLimited:
            return "RATE LIMITED"
        }
    }

    private var message: String {
        switch reason {
        case .authInvalid:
            return "Showing cached usage. Claude Code auth expired and ClaudeBat could not refresh."
        case .noToken:
            return "Showing cached usage. ClaudeBat could not read your Claude Code token."
        case .networkError:
            return "Showing cached usage. The last refresh failed because the network request did not complete."
        case .serverError:
            return "Showing cached usage. The usage endpoint returned an unexpected response."
        case .rateLimited:
            return "Showing cached usage. ClaudeBat hit the usage endpoint limit and is waiting before retrying."
        }
    }

    private var borderColor: Color {
        switch reason {
        case .authInvalid, .noToken:
            return CBColor.batteryCritical.opacity(0.7)
        case .networkError:
            return CBColor.batteryLow.opacity(0.7)
        case .serverError, .rateLimited:
            return CBColor.batteryMid.opacity(0.7)
        }
    }

    private var titleColor: Color {
        switch reason {
        case .authInvalid, .noToken:
            return CBColor.batteryCritical
        case .networkError:
            return CBColor.batteryLow
        case .serverError, .rateLimited:
            return CBColor.batteryMid
        }
    }
}
