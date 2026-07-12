import SwiftUI

@MainActor
public struct UsagePopoverView: View {
    @Bindable var viewModel: UsageViewModel
    let onPreferredHeightChange: ((CGFloat) -> Void)?

    public init(viewModel: UsageViewModel, onPreferredHeightChange: ((CGFloat) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onPreferredHeightChange = onPreferredHeightChange
    }

    @Environment(\.dismiss) private var dismiss

    // Measured natural height of the usage screen — its content varies (model
    // breakdown rows, cached banner, game over), so a fixed constant either
    // clips or leaves dead space that gets centered into ugly gaps.
    @State private var measuredUsageHeight: CGFloat?

    public var body: some View {
        liveContent
            .onAppear {
                onPreferredHeightChange?(preferredHeight)
            }
            .onChange(of: preferredHeight) { _, newValue in
                onPreferredHeightChange?(newValue)
            }
    }

    private var preferredHeight: CGFloat {
        switch viewModel.popoverScreen {
        case .usage:
            return measuredUsageHeight
                ?? (viewModel.shouldShowCachedBanner ? CBSpacing.popupHeightWithBanner : CBSpacing.popupHeight)
        default:
            return CBSpacing.popupHeight
        }
    }

    @ViewBuilder
    private var liveContent: some View {
        switch viewModel.popoverScreen {
        case .error:
            popupChrome {
                ErrorView(message: viewModel.errorMessage ?? "Unknown error")
            }
        case .reconnectClaude:
            popupChrome {
                NoAuthView(mode: viewModel.authPrompt == .reconnect ? .reconnect : .setup)
            }
        case .offline:
            popupChrome {
                ErrorView(titleOverride: "No Internet", message: viewModel.offlineErrorMessage)
            }
        case .recovering:
            LoadingRetroView(title: "SYNCING", message: viewModel.recoveryMessage)
                .frame(width: CBSpacing.popupWidth, height: preferredHeight)
                .background(CBColor.base)
                .clipShape(RoundedRectangle(cornerRadius: CBRadius.popup))
        case .usage:
            if let usage = viewModel.usage {
                popupChrome(fitsContent: true) {
                    VStack(spacing: 0) {
                        if viewModel.shouldShowCachedBanner, let reason = viewModel.cachedDataReason {
                            CachedDataBanner(reason: reason)
                            Spacer().frame(height: 12)
                        }

                        if viewModel.isDepleted {
                            GameOverView(usage: usage)
                        } else {
                            NormalUsageView(usage: usage)
                        }
                        Spacer().frame(height: 12)
                        FreshnessIndicator(fetchedAt: viewModel.fetchedAt, freshness: viewModel.freshness)
                    }
                }
            }
        case .loading:
            LoadingRetroView(title: "LOADING")
                .frame(width: CBSpacing.popupWidth, height: preferredHeight)
                .background(CBColor.base)
                .clipShape(RoundedRectangle(cornerRadius: CBRadius.popup))
        }
    }

    /// `fitsContent: true` lets the chrome hug its content and reports the
    /// measured height back through `preferredHeight` so the NSPopover resizes
    /// to fit; `false` keeps the fixed-height layout with vertically centered
    /// content (error/reconnect/offline screens).
    @ViewBuilder
    private func popupChrome<Content: View>(fitsContent: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            PopoverHeader {
                dismiss()
            }
            .padding(.bottom, 20)

            if fitsContent {
                content()
            } else {
                content()
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(CBSpacing.popupPadding)
        .frame(width: CBSpacing.popupWidth)
        .frame(height: fitsContent ? nil : preferredHeight)
        .background(CBColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: CBRadius.popup))
        .background {
            if fitsContent {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { recordMeasuredHeight(proxy.size.height) }
                        .onChange(of: proxy.size.height) { _, newHeight in
                            recordMeasuredHeight(newHeight)
                        }
                }
            }
        }
    }

    /// Ignore sub-point measurement changes: resizing the popover perturbs
    /// layout enough to re-fire the GeometryReader, and feeding jitter back
    /// into `preferredHeight` -> NSPopover.contentSize -> layout creates an
    /// infinite main-thread loop (froze the app at the v1.0.14 reset boundary).
    private func recordMeasuredHeight(_ newHeight: CGFloat) {
        guard let current = measuredUsageHeight else {
            measuredUsageHeight = newHeight
            return
        }
        if abs(current - newHeight) > 0.5 {
            measuredUsageHeight = newHeight
        }
    }
}
