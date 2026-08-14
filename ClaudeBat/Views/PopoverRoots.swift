import SwiftUI

/// Natural-height chrome for the normal usage screen.
struct NormalPopoverRoot<Content: View>: View {
    let onClose: () -> Void
    @ViewBuilder let content: Content

    init(onClose: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(onClose: onClose)
            Spacer().frame(height: 20)
            content
        }
        .padding(CBPopoverMetrics.padding)
        .frame(width: CBPopoverMetrics.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(CBColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: CBRadius.popup))
    }
}

/// Minimum-height chrome for error/reconnect/offline and Game Over screens.
/// Banner/footer presence is explicit so their declared 12-point gaps are not
/// guessed from the child's measured height.
struct HeaderBaselinePopoverRoot<Banner: View, StateContent: View, Footer: View>: View {
    let onClose: () -> Void
    let hasBanner: Bool
    let hasFooter: Bool
    @ViewBuilder let banner: Banner
    @ViewBuilder let stateContent: StateContent
    @ViewBuilder let footer: Footer

    init(
        onClose: @escaping () -> Void,
        hasBanner: Bool,
        hasFooter: Bool,
        @ViewBuilder banner: () -> Banner,
        @ViewBuilder stateContent: () -> StateContent,
        @ViewBuilder footer: () -> Footer
    ) {
        self.onClose = onClose
        self.hasBanner = hasBanner
        self.hasFooter = hasFooter
        self.banner = banner()
        self.stateContent = stateContent()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(onClose: onClose)
            Spacer().frame(height: 20)

            if hasBanner {
                banner
                Spacer().frame(height: 12)
            }

            stateContent
                .frame(maxHeight: .infinity)

            if hasFooter {
                Spacer().frame(height: 12)
                footer
            }
        }
        .padding(CBPopoverMetrics.padding)
        .frame(width: CBPopoverMetrics.width)
        .frame(minHeight: CBPopoverMetrics.baselineHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background(CBColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: CBRadius.popup))
    }
}

/// Loading/recovery keep their existing base-colored, headerless composition.
/// The state view owns its existing 20-point horizontal inset.
struct StandaloneBaselinePopoverRoot<StateContent: View>: View {
    @ViewBuilder let stateContent: StateContent

    init(@ViewBuilder stateContent: () -> StateContent) {
        self.stateContent = stateContent()
    }

    var body: some View {
        stateContent
            .frame(width: CBPopoverMetrics.width)
            .frame(minHeight: CBPopoverMetrics.baselineHeight)
            .fixedSize(horizontal: false, vertical: true)
            .background(CBColor.base)
            .clipShape(RoundedRectangle(cornerRadius: CBRadius.popup))
    }
}
