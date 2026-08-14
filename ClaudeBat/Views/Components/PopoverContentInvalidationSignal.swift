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
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                guard size.width.isFinite,
                      size.height.isFinite,
                      size.width > 0,
                      size.height > 0 else { return }
                onContentInvalidated()
            }
    }
}
