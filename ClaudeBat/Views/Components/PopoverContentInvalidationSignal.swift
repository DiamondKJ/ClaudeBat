import SwiftUI

/// A stateless notification seam for final-root size changes.
/// The measured value is deliberately discarded; the sizing coordinator must
/// remeasure the current root when it drains the invalidation.
struct PopoverContentInvalidationSignal<Content: View>: View {
    let onContentInvalidated: @MainActor () -> Void
    @ViewBuilder let content: Content

    init(
        onContentInvalidated: @escaping @MainActor () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.onContentInvalidated = onContentInvalidated
        self.content = content()
    }

    var body: some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            reportIfValid(proxy.size)
                        }
                        .onChange(of: proxy.size) { _, newSize in
                            reportIfValid(newSize)
                        }
                }
            }
    }

    @MainActor
    private func reportIfValid(_ size: CGSize) {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else { return }
        onContentInvalidated()
    }
}
