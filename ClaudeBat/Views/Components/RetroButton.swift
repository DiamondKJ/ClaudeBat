import SwiftUI

/// 8-bit styled button with stepped pixel border
struct RetroButton: View {
    let title: String
    var action: () -> Void

    @State private var isPressed = false

    private let fillColor = CBColor.accent
    private let borderColor = Color(red: 0xF0/255, green: 0xA0/255, blue: 0x78/255)
    private let textColor = CBColor.base

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CBFont.pixelFont(size: 11))
                .foregroundStyle(textColor)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(fillColor)
                .overlay(
                    // Stepped pixel border effect
                    ZStack {
                        // Top border (wider)
                        Rectangle()
                            .fill(borderColor)
                            .frame(height: 2)
                            .padding(.horizontal, -2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .offset(y: -2)

                        // Bottom border (wider)
                        Rectangle()
                            .fill(borderColor)
                            .frame(height: 2)
                            .padding(.horizontal, -2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .offset(y: 2)

                        // Left border (taller)
                        Rectangle()
                            .fill(borderColor)
                            .frame(width: 2)
                            .padding(.vertical, -2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .offset(x: -2)

                        // Right border (taller)
                        Rectangle()
                            .fill(borderColor)
                            .frame(width: 2)
                            .padding(.vertical, -2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                            .offset(x: 2)
                    }
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.easeOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}
