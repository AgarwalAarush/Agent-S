import Foundation
import AppKit
import CoreGraphics
import Vision

/// Image utilities for screenshots, OCR, and image processing
class ImageUtils {
    
    /// Capture screenshot of the main display
    /// - Returns: Screenshot as PNG Data, or nil on failure
    static func captureScreenshot() -> Data? {
        let mainDisplayID = CGMainDisplayID()
        
        guard let image = CGWindowListCreateImage(
            .zero,
            .optionOnScreenBelowWindow,
            kCGNullWindowID,
            .bestResolution
        ) else {
            return nil
        }
        
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        return pngData
    }
    
    /// Resize image to fit within max dimensions while maintaining aspect ratio
    /// - Parameters:
    ///   - imageData: Source image data
    ///   - maxWidth: Maximum width
    ///   - maxHeight: Maximum height
    /// - Returns: Resized image data, or original if no resizing needed
    static func resizeImage(_ imageData: Data, maxWidth: Int, maxHeight: Int) -> Data? {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return imageData
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Calculate scale factor
        let scaleFactor = min(
            Double(maxWidth) / Double(width),
            Double(maxHeight) / Double(height),
            1.0
        )
        
        if scaleFactor >= 1.0 {
            return imageData  // No resize needed
        }
        
        let newWidth = Int(Double(width) * scaleFactor)
        let newHeight = Int(Double(height) * scaleFactor)
        
        // Create resized image
        guard let colorSpace = cgImage.colorSpace,
              let context = CGContext(
                  data: nil,
                  width: newWidth,
                  height: newHeight,
                  bitsPerComponent: cgImage.bitsPerComponent,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: cgImage.bitmapInfo.rawValue
              ) else {
            return imageData
        }
        
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        
        guard let resizedCGImage = context.makeImage() else {
            return imageData
        }
        
        let resizedImage = NSBitmapImageRep(cgImage: resizedCGImage)
        return resizedImage.representation(using: .png, properties: [:])
    }
    
    /// Perform OCR on image and return text elements with bounding boxes
    /// - Parameter imageData: Image data to process
    /// - Returns: Array of OCRElement with text and bounding boxes
    static func performOCR(_ imageData: Data) async throws -> [OCRElement] {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageError.invalidImageData
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                var elements: [OCRElement] = []
                var ocrID = 0
                
                for observation in observations {
                    guard let topCandidate = observation.topCandidates(1).first else {
                        continue
                    }
                    
                    let text = topCandidate.string
                    let boundingBox = observation.boundingBox
                    
                    // Convert normalized bounding box to image coordinates
                    let imageWidth = CGFloat(cgImage.width)
                    let imageHeight = CGFloat(cgImage.height)
                    
                    let rect = VNImageRectForNormalizedRect(
                        boundingBox,
                        Int(imageWidth),
                        Int(imageHeight)
                    )
                    
                    let element = OCRElement(
                        id: ocrID,
                        text: text,
                        boundingBox: rect,
                        left: Int(rect.origin.x),
                        top: Int(rect.origin.y),
                        width: Int(rect.width),
                        height: Int(rect.height)
                    )
                    
                    elements.append(element)
                    ocrID += 1
                }
                
                continuation.resume(returning: elements)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Generate OCR table string for LLM consumption
    /// - Parameter elements: OCR elements to format
    /// - Returns: Formatted table string
    static func generateOCRTable(_ elements: [OCRElement]) -> String {
        var table = "Text Table:\nWord id\tText\n"
        
        for element in elements {
            // Clean text: remove leading/trailing non-alphabetic characters but keep punctuation
            let cleaned = cleanText(element.text)
            if !cleaned.isEmpty {
                table += "\(element.id)\t\(cleaned)\n"
            }
        }
        
        return table
    }
    
    /// Clean text by removing leading/trailing non-alphabetic characters but keeping punctuation
    private static func cleanText(_ text: String) -> String {
        // Remove leading/trailing non-alphabetic characters except spaces and punctuation
        let pattern = "^[^a-zA-Z\\s.,!?;:\\-\\+]+|[^a-zA-Z\\s.,!?;:\\-\\+]+$"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
    
    /// Encode image data to base64 string
    /// - Parameter imageData: Image data to encode
    /// - Returns: Base64 encoded string
    static func encodeImageToBase64(_ imageData: Data) -> String {
        return imageData.base64EncodedString()
    }
    
    /// Compress image to WebP format
    /// - Parameter imageData: Source image data
    /// - Returns: Compressed WebP data, or original if compression fails
    static func compressImage(_ imageData: Data) -> Data {
        // WebP compression requires additional libraries
        // For now, return original data
        // TODO: Add WebP support if needed
        return imageData
    }
}

/// OCR element representing a recognized text region
struct OCRElement {
    let id: Int
    let text: String
    let boundingBox: CGRect
    let left: Int
    let top: Int
    let width: Int
    let height: Int
    
    /// Calculate center point of the element
    var center: CGPoint {
        return CGPoint(
            x: Double(left) + Double(width) / 2.0,
            y: Double(top) + Double(height) / 2.0
        )
    }
}

enum ImageError: Error {
    case invalidImageData
    case ocrFailed
}
