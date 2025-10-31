import Foundation

/// OpenAI API engine implementation
class OpenAIEngine: LLMEngine {
    private let model: String
    private let baseURL: URL?
    private let apiKey: String
    private let organization: String?
    private let temperature: Double?
    private let topP: Double?

    init(
        model: String,
        baseURL: URL? = nil,
        apiKey: String,
        organization: String? = nil,
        temperature: Double? = nil,
        topP: Double? = nil
    ) {
        self.model = model
        self.baseURL = baseURL ?? URL(string: "https://api.openai.com/v1")!
        self.apiKey = apiKey
        self.organization = organization
        self.temperature = temperature
        self.topP = topP
    }
    
    func generate(
        messages: [Message],
        temperature: Double,
        maxNewTokens: Int?
    ) async throws -> String {
        let actualTemperature = self.temperature ?? temperature

        var requestBody: [String: Any] = [
            "model": model,
            "messages": convertMessagesToOpenAIFormat(messages),
            "temperature": actualTemperature
        ]

        if let topP = self.topP {
            requestBody["top_p"] = topP
        }

        if let maxTokens = maxNewTokens {
            requestBody["max_completion_tokens"] = maxTokens
        }
        
        let response = try await makeRequest(
            endpoint: "/chat/completions",
            body: requestBody
        )
        
        guard let choices = response["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }
        
        return content
    }
    
    func generateWithThinking(
        messages: [Message],
        temperature: Double,
        maxNewTokens: Int?
    ) async throws -> String {
        // OpenAI doesn't support thinking mode like Claude
        return try await generate(messages: messages, temperature: temperature, maxNewTokens: maxNewTokens)
    }
    
    private func convertMessagesToOpenAIFormat(_ messages: [Message]) -> [[String: Any]] {
        return messages.map { message in
            var result: [String: Any] = [
                "role": message.role
            ]
            
            var content: [[String: Any]] = []
            for item in message.content {
                switch item {
                case .text(let text):
                    content.append([
                        "type": "text",
                        "text": text
                    ])
                case .image(let data, let mimeType, let detail):
                    let base64 = data.base64EncodedString()
                    var imageURLDict: [String: Any] = [
                        "url": "data:\(mimeType);base64,\(base64)"
                    ]
                    if let detail = detail {
                        imageURLDict["detail"] = detail
                    }
                    let imageContent: [String: Any] = [
                        "type": "image_url",
                        "image_url": imageURLDict
                    ]
                    content.append(imageContent)
                }
            }
            result["content"] = content
            return result
        }
    }
    
    private func makeRequest(endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        let url = baseURL!.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let org = organization {
            request.setValue(org, forHTTPHeaderField: "OpenAI-Organization")
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorData["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw LLMError.apiError(message)
            }
            throw LLMError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse
        }
        
        return json
    }
}

enum LLMError: Error {
    case invalidResponse
    case httpError(Int)
    case apiError(String)
}
