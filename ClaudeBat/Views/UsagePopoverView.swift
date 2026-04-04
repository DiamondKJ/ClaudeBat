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
        if viewModel.hasError {
            popupChrome {
                ErrorView(message: viewModel.errorMessage ?? "Unknown error")
            }
        } else if viewModel.usage == nil && viewModel.hasNoAuth {
            popupChrome {
                NoAuthView()
            }
        } else if let usage = viewModel.usage {
            if viewModel.isFullyMaxed {
                popupChrome {
                    GameOverView(usage: usage)
                }
            } else {
                popupChrome {
                    VStack(spacing: 0) {
                        NormalUsageView(usage: usage)
                        Spacer().frame(height: 12)
                        FreshnessIndicator(fetchedAt: viewModel.fetchedAt, freshness: viewModel.freshness)
                    }
                }
            }
        } else {
            LoadingRetroView()
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
