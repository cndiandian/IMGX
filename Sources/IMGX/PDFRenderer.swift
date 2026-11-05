import Foundation
import CoreGraphics

enum PDFError: LocalizedError {
    case unreadable, locked, invalidPage
    var errorDescription: String? {
        switch self {
        case .unreadable: L10n.text(.pdfUnreadable)
        case .locked: L10n.text(.pdfLocked)
        case .invalidPage: L10n.text(.pdfInvalidPage)
        }
    }
}

/// 每次只栅格化一页，默认 144 DPI；预览与导出共用相同的页面尺寸及变换。
enum PDFRenderer {
    static func document(at url: URL) throws -> CGPDFDocument {
        guard let document = CGPDFDocument(url as CFURL) else { throw PDFError.unreadable }
        guard document.isUnlocked else { throw PDFError.locked }
        guard document.numberOfPages > 0 else { throw PDFError.unreadable }
        return document
    }

    static func render(url: URL, pageNumber: Int, maximumDimension: Int? = nil) throws -> CGImage {
        let document = try document(at: url)
        guard pageNumber > 0, let page = document.page(at: pageNumber) else { throw PDFError.invalidPage }
        let box = page.getBoxRect(.cropBox).intersection(page.getBoxRect(.mediaBox))
        guard !box.isNull, box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else {
            throw PDFError.invalidPage
        }
        let rotated = abs(page.rotationAngle % 180) == 90
        let width = rotated ? box.height : box.width
        let height = rotated ? box.width : box.height
        var scale = 2.0
        if let maximumDimension { scale = min(scale, Double(maximumDimension) / max(width, height)) }
        let w = (width * scale).rounded(.up), h = (height * scale).rounded(.up)
        guard w.isFinite, h.isFinite, w >= 1, h >= 1,
              w <= Double(ImageSizing.maximumDimension), h <= Double(ImageSizing.maximumDimension),
              w * h <= Double(ImageSizing.maximumPixelCount) else { throw CodecError.imageTooLarge }
        guard let context = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8,
                                      bytesPerRow: Int(w) * 4, space: ImageCodec.colorSpace,
                                      bitmapInfo: ImageCodec.bitmapInfo) else { throw CodecError.decode }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        // Quartz 的页面适配变换不会主动放大内容，先显式应用栅格比例。
        context.scaleBy(x: w / width, y: h / height)
        let pageRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: pageRect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw CodecError.decode }
        return image
    }
}

struct ImportIdentity: Hashable {
    let url: URL
    let pageNumber: Int?
}
