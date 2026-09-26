import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(PDFKit)
import PDFKit
#endif

public extension DocumentTranscoder {
    func importRTF(_ data: Data, fileName: String) throws -> EditorDocument {
        #if canImport(AppKit)
        let attributedString = try NSAttributedString(data: data, options: [:], documentAttributes: nil)
        return importPlainText(attributedString.string, fileName: fileName, isMarkdown: false)
        #else
        throw TranscoderError.unsupportedImportFormat(.rtf)
        #endif
    }

    func exportRTF(_ document: EditorDocument) throws -> Data {
        #if canImport(AppKit)
        let attributedString = NSAttributedString(string: document.plainText())
        return try attributedString.data(from: NSRange(location: 0, length: attributedString.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        #else
        throw TranscoderError.unsupportedExportFormat(.rtf)
        #endif
    }

    func importPDF(_ data: Data, fileName: String) throws -> EditorDocument {
        #if canImport(PDFKit)
        guard let pdfDocument = PDFDocument(data: data) else {
            throw TranscoderError.unsupportedImportFormat(.pdf)
        }

        let text = (0..<pdfDocument.pageCount)
            .compactMap { pdfDocument.page(at: $0)?.string }
            .joined(separator: "\n")
        return importPlainText(text, fileName: fileName, isMarkdown: false)
        #else
        throw TranscoderError.unsupportedImportFormat(.pdf)
        #endif
    }

    func exportPDF(_ document: EditorDocument) throws -> Data {
        #if canImport(AppKit) && canImport(PDFKit)
        let attributedString = NSAttributedString(string: document.plainText())
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let textView = NSTextView(frame: bounds)
        textView.textStorage?.setAttributedString(attributedString)
        let pdfData = textView.dataWithPDF(inside: bounds)
        return pdfData
        #else
        throw TranscoderError.unsupportedExportFormat(.pdf)
        #endif
    }
}
