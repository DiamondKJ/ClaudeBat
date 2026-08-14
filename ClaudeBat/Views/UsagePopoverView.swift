import SwiftUI

@MainActor
public struct UsagePopoverView: View {
    @Bindable var viewModel: UsageViewModel
    let onCloseRequested: @MainActor () -> Void
    let onContentInvalidated: @MainActor () -> Void

    public init(
        viewModel: UsageViewModel,
        onCloseRequested: @escaping @MainActor () -> Void = {},
        onContentInvalidated: @escaping @MainActor () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.onCloseRequested = onCloseRequested
        self.onContentInvalidated = onContentInvalidated
    }

    public var body: some View {
        PopoverContentInvalidationSignal(
            onContentInvalidated: onContentInvalidated
        ) {
            liveContent
        }
    }

    @ViewBuilder
    private var liveContent: some View {
        switch viewModel.popoverScreen {
        case .error:
            headerBaseline {
                ErrorView(message: viewModel.errorMessage ?? "Unknown error")
            }
        case .reconnectClaude:
            headerBaseline {
                NoAuthView(mode: viewModel.authPrompt == .reconnect ? .reconnect : .setup)
            }
        case .offline:
            headerBaseline {
                ErrorView(titleOverride: "No Internet", message: viewModel.offlineErrorMessage)
            }
        case .recovering:
            StandaloneBaselinePopoverRoot {
                LoadingRetroView(title: "SYNCING", message: viewModel.recoveryMessage)
            }
        case .usage:
            if let usage = viewModel.usage {
                if viewModel.isDepleted {
                    gameOverRoot(usage: usage)
                } else {
                    normalUsageRoot(usage: usage)
                }
            }
        case .loading:
            StandaloneBaselinePopoverRoot {
                LoadingRetroView(title: "LOADING")
            }
        }
    }

    private func normalUsageRoot(usage: UsageResponse) -> some View {
        NormalPopoverRoot(onClose: onCloseRequested) {
            VStack(spacing: 0) {
                if viewModel.shouldShowCachedBanner,
                   let reason = viewModel.cachedDataReason {
                    CachedDataBanner(reason: reason)
                    Spacer().frame(height: 12)
                }

                NormalUsageView(usage: usage)
                Spacer().frame(height: CBPopoverMetrics.lowerSectionSpacing)
                FreshnessIndicator(
                    fetchedAt: viewModel.fetchedAt,
                    freshness: viewModel.freshness
                )
            }
        }
    }

    private func gameOverRoot(usage: UsageResponse) -> some View {
        HeaderBaselinePopoverRoot(
            onClose: onCloseRequested,
            hasBanner: viewModel.shouldShowCachedBanner && viewModel.cachedDataReason != nil,
            hasFooter: true,
            banner: {
                if let reason = viewModel.cachedDataReason {
                    CachedDataBanner(reason: reason)
                }
            },
            stateContent: {
                GameOverView(usage: usage)
            },
            footer: {
                FreshnessIndicator(
                    fetchedAt: viewModel.fetchedAt,
                    freshness: viewModel.freshness
                )
            }
        )
    }

    private func headerBaseline<Content: View>(
        @ViewBuilder stateContent: () -> Content
    ) -> some View {
        HeaderBaselinePopoverRoot(
            onClose: onCloseRequested,
            hasBanner: false,
            hasFooter: false,
            banner: { EmptyView() },
            stateContent: stateContent,
            footer: { EmptyView() }
        )
    }
}
