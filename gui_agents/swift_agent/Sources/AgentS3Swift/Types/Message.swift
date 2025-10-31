import Foundation

/// Represents a message in the conversation history
struct Message: Codable {
    var role: String  // "system", "user", "assistant"
    var content: [ContentItem]
    
    init(role: String, content: [ContentItem]) {
        self.role = role
        self.content = content
    }
}

/// Represents content items in a message (text or image)
enum ContentItem: Codable {
    case text(String)
    case image(data: Data, mimeType: String, detail: String?)
    
    // Custom Codable implementation for OpenAI/Anthropic format
    enum CodingKeys: String, CodingKey {
        case type, text, imageURL = "image_url", imageURLValue = "url", source, mediaType = "media_type", data, detail
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "image_url":
            let imageContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .imageURL)
            let url = try imageContainer.decode(String.self, forKey: .imageURLValue)
            let detail = try? imageContainer.decode(String.self, forKey: .detail)
            // Parse data:image/png;base64,...
            if url.hasPrefix("data:"), let commaIndex = url.firstIndex(of: ",") {
                let dataString = String(url[url.index(after: commaIndex)...])
                if let data = Data(base64Encoded: dataString) {
                    let mimePart = String(url[..<commaIndex])
                    let mimeType = mimePart.contains("png") ? "image/png" : "image/jpeg"
                    self = .image(data: data, mimeType: mimeType, detail: detail)
                } else {
                    throw DecodingError.dataCorruptedError(forKey: .imageURLValue, in: imageContainer, debugDescription: "Invalid base64")
                }
            } else {
                throw DecodingError.dataCorruptedError(forKey: .imageURLValue, in: imageContainer, debugDescription: "Invalid image URL format")
            }
        case "image":
            let sourceContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .source)
            let mediaType = try sourceContainer.decode(String.self, forKey: .mediaType)
            let data = try sourceContainer.decode(Data.self, forKey: .data)
            self = .image(data: data, mimeType: mediaType, detail: nil)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let data, let mimeType, let detail):
            // For OpenAI format
            try container.encode("image_url", forKey: .type)
            var imageContainer = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .imageURL)
            let base64 = data.base64EncodedString()
            let url = "data:\(mimeType);base64,\(base64)"
            try imageContainer.encode(url, forKey: .imageURLValue)
            if let detail = detail {
                try imageContainer.encode(detail, forKey: .detail)
            }
        }
    }
}
