import SwiftUI

public struct UsagePopoverView: View {
    @Bindable var viewModel: UsageViewModel

    public init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
    }

    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        liveContent
            .onAppear { viewModel.onPopoverOpen() }
            .onDisappear { viewModel.onPopoverClose() }
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
                .frame(width: CBSpacing.popupWidth, height: CBSpacing.popupHeight)
                .background(CBColor.base)
                .clipShape(RoundedRectangle(cornerRadius: CBRadius.popup))
        case .usage:
            if let usage = viewModel.usage {
                popupChrome {
                    VStack(spacing: 0) {
                        if viewModel.shouldShowCachedBanner, let reason = viewModel.cachedDataReason {
                            CachedDataBanner(reason: reason)
                            Spacer().frame(height: 12)
                        }

                        if viewModel.isFullyMaxed {
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
                .frame(width: CBSpacing.popupWidth, height: CBSpacing.popupHeight)
                .background(CBColor.base)
                .clipShape(RoundedRectangle(cornerRadius: CBRadius.popup))
        }
    }

    @ViewBuilder
    private func popupChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            PopoverHeader {
                dismiss()
            }
            .padding(.bottom, 20)

            content()
                .frame(maxHeight: .infinity)
        }
        .padding(CBSpacing.popupPadding)
        .frame(width: CBSpacing.popupWidth, height: CBSpacing.popupHeight)
        .background(CBColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: CBRadius.popup))
    }
}
