import SwiftUI

/// Displays a provider's icon — uses asset image when available, otherwise SF Symbol.
struct ProviderIconView: View {
    let provider: any TranslationProvider
    var font: Font = .callout
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let assetName = provider.iconAssetName {
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: provider.iconSystemName)
                    .font(font)
            }
        }
        .frame(width: size, height: size)
    }
}
