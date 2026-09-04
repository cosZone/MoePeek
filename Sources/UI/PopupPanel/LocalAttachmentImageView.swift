import ImageIO
import SwiftUI

/// Displays a captured source image. Decoding and downsampling run off the main thread so a
/// large pasted image never stalls the popup.
struct LocalAttachmentImageView: View {
    let data: Data
    let label: String
    @State private var decoded: DecodedImage?

    var body: some View {
        Group {
            if let decoded {
                Image(decoded.cgImage, scale: 1, label: Text(label))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: CGFloat(decoded.cgImage.width), maxHeight: 320, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 120, height: 60)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .task(id: data) {
            decoded = await Task.detached(priority: .utility) {
                DecodedImage(data: data, maxPixelSize: 1600)
            }.value
        }
    }
}

/// `CGImage` is immutable, so sharing one across isolation domains is safe.
struct DecodedImage: @unchecked Sendable {
    let cgImage: CGImage

    init?(data: Data, maxPixelSize: Int) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        cgImage = image
    }
}
