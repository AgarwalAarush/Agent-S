import Foundation

/// Anthropic API engine implementation
class AnthropicEngine: LLMEngine {
    private let model: String
    private let baseURL: URL?
    private let apiKey: String
    private let temperature: Double?
    private let topP: Double?
    private let thinking: Bool

    init(
        model: String,
        baseURL: URL? = nil,
        apiKey: String,
        temperature: Double? = nil,
        topP: Double? = nil,
        thinking: Bool = false
    ) {
        self.model = model
        self.baseURL = baseURL ?? URL(string: "https://api.anthropic.com/v1")!
        self.apiKey = apiKey
        self.temperature = temperature
        self.topP = topP
        self.thinking = thinking
    }
    
    func generate(
        messages: [Message],
        temperature: Double,
        maxNewTokens: Int?
    ) async throws -> String {
        let actualTemperature = self.temperature ?? temperature
        
        if thinking {
            return try await generateWithThinking(messages: messages, temperature: actualTemperature, maxNewTokens: maxNewTokens)
        }
        
        // Separate system message from user/assistant messages
        var systemMessage: String?
        var conversationMessages: [Message] = []
        
        for message in messages {
            if message.role == "system" {
                if let textItem = message.content.first(where: { 
                    if case .text = $0 { return true }
                    return false
                }) {
                    if case .text(let text) = textItem {
                        systemMessage = text
                    }
                }
            } else {
                conversationMessages.append(message)
            }
        }
        
        var requestBody: [String: Any] = [
            "model": model,
            "messages": convertMessagesToAnthropicFormat(conversationMessages),
            "max_tokens": maxNewTokens ?? 4096,
            "temperature": actualTemperature
        ]

        if let topP = self.topP {
            requestBody["top_p"] = topP
        }

        if let system = systemMessage {
            requestBody["system"] = system
        }
        
        let response = try await makeRequest(
            endpoint: "/messages",
            body: requestBody
        )
        
        guard let content = response["content"] as? [[String: Any]],
              let firstContent = content.first,
              let type = firstContent["type"] as? String,
              type == "text",
              let text = firstContent["text"] as? String else {
            throw LLMError.invalidResponse
        }
        
        return text
    }
    
    func generateWithThinking(
        messages: [Message],
        temperature: Double,
        maxNewTokens: Int?
    ) async throws -> String {
        // Separate system message
        var systemMessage: String?
        var conversationMessages: [Message] = []
        
        for message in messages {
            if message.role == "system" {
                if let textItem = message.content.first(where: { 
                    if case .text = $0 { return true }
                    return false
                }) {
                    if case .text(let text) = textItem {
                        systemMessage = text
                    }
                }
            } else {
                conversationMessages.append(message)
            }
        }
        
        var requestBody: [String: Any] = [
            "model": model,
            "messages": convertMessagesToAnthropicFormat(conversationMessages),
            "max_tokens": 8192,
            "temperature": temperature,
            "thinking": [
                "type": "enabled",
                "budget_tokens": 4096
            ]
        ]

        if let topP = self.topP {
            requestBody["top_p"] = topP
        }

        if let system = systemMessage {
            requestBody["system"] = system
        }
        
        let response = try await makeRequest(
            endpoint: "/messages",
            body: requestBody
        )
        
        guard let content = response["content"] as? [[String: Any]],
              content.count >= 2 else {
            throw LLMError.invalidResponse
        }
        
        // First item is thinking, second is answer
        guard content.count >= 2,
              let thinkingContent = content.first,
              let thinkingType = thinkingContent["type"] as? String,
              thinkingType == "thinking",
              let thinking = thinkingContent["text"] as? String else {
            throw LLMError.invalidResponse
        }
        
        let answerContent = content[1]
        guard let answerType = answerContent["type"] as? String,
              answerType == "text",
              let answer = answerContent["text"] as? String else {
            throw LLMError.invalidResponse
        }
        
        // Return formatted with thinking tokens
        return "<thoughts>\n\(thinking)\n</thoughts>\n\n<answer>\n\(answer)\n</answer>\n"
    }
    
    private func convertMessagesToAnthropicFormat(_ messages: [Message]) -> [[String: Any]] {
        return messages.map { message in
            var content: [[String: Any]] = []
            
            for item in message.content {
                switch item {
                case .text(let text):
                    content.append([
                        "type": "text",
                        "text": text
                    ])
                case .image(let data, _, _):
                    content.append([
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/png",
                            "data": data.base64EncodedString()
                        ]
                    ])
                }
            }
            
            return [
                "role": message.role == "assistant" ? "assistant" : "user",
                "content": content
            ]
        }
    }
    
    private func makeRequest(endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        let url = baseURL!.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
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
