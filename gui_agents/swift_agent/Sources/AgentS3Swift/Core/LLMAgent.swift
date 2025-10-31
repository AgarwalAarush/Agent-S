import Foundation

/// LLM Agent wrapper that manages conversation history and provides a unified interface
class LLMAgent {
    private var engine: LLMEngine
    var messages: [Message] = []
    var systemPrompt: String = "You are a helpful assistant."
    
    init(engine: LLMEngine, systemPrompt: String? = nil) {
        self.engine = engine
        if let prompt = systemPrompt {
            self.systemPrompt = prompt
        }
        reset()
    }
    
    convenience init(engineParams: [String: Any]) throws {
        guard let engineType = engineParams["engine_type"] as? String else {
            throw LLMError.invalidConfiguration("engine_type is required")
        }
        
        let engine: LLMEngine
        
        switch engineType {
        case "openai":
            guard let model = engineParams["model"] as? String,
                  let apiKey = engineParams["api_key"] as? String else {
                throw LLMError.invalidConfiguration("OpenAI requires model and api_key")
            }
            let baseURL = (engineParams["base_url"] as? String).flatMap { URL(string: $0) }
            let organization = engineParams["organization"] as? String
            let temperature = engineParams["temperature"] as? Double
            let topP = engineParams["top_p"] as? Double
            engine = OpenAIEngine(
                model: model,
                baseURL: baseURL,
                apiKey: apiKey,
                organization: organization,
                temperature: temperature,
                topP: topP
            )
        case "anthropic":
            guard let model = engineParams["model"] as? String,
                  let apiKey = engineParams["api_key"] as? String else {
                throw LLMError.invalidConfiguration("Anthropic requires model and api_key")
            }
            let baseURL = (engineParams["base_url"] as? String).flatMap { URL(string: $0) }
            let temperature = engineParams["temperature"] as? Double
            let topP = engineParams["top_p"] as? Double
            let thinking = engineParams["thinking"] as? Bool ?? false
            engine = AnthropicEngine(
                model: model,
                baseURL: baseURL,
                apiKey: apiKey,
                temperature: temperature,
                topP: topP,
                thinking: thinking
            )
        default:
            throw LLMError.invalidConfiguration("Unsupported engine type: \(engineType)")
        }
        
        let systemPrompt = engineParams["system_prompt"] as? String
        self.init(engine: engine, systemPrompt: systemPrompt)
    }
    
    func reset() {
        messages = [
            Message(
                role: "system",
                content: [.text(systemPrompt)]
            )
        ]
    }
    
    func addSystemPrompt(_ prompt: String) {
        systemPrompt = prompt
        if messages.isEmpty {
            messages.append(Message(role: "system", content: [.text(prompt)]))
        } else {
            messages[0] = Message(role: "system", content: [.text(prompt)])
        }
    }
    
    func addMessage(
        textContent: String,
        imageContent: Data? = nil,
        role: String? = nil,
        imageDetail: String = "high",
        putTextLast: Bool = false
    ) {
        // Infer role from previous message if not provided
        let inferredRole: String
        if let role = role {
            inferredRole = role
        } else if messages.isEmpty {
            inferredRole = "user"
        } else {
            switch messages[messages.count - 1].role {
            case "system":
                inferredRole = "user"
            case "user":
                inferredRole = "assistant"
            case "assistant":
                inferredRole = "user"
            default:
                inferredRole = "user"
            }
        }
        
        var content: [ContentItem] = []
        
        // Add image first if not putTextLast
        if let image = imageContent, !putTextLast {
            content.append(.image(data: image, mimeType: "image/png", detail: imageDetail))
        }
        
        // Add text
        content.append(.text(textContent))
        
        // Add image last if putTextLast
        if let image = imageContent, putTextLast {
            content.append(.image(data: image, mimeType: "image/png", detail: imageDetail))
        }
        
        messages.append(Message(role: inferredRole, content: content))
    }
    
    func removeMessage(at index: Int) {
        if index < messages.count {
            messages.remove(at: index)
        }
    }
    
    func getResponse(
        temperature: Double = 1.0,
        maxNewTokens: Int? = nil,
        useThinking: Bool = false
    ) async throws -> String {
        if useThinking {
            return try await engine.generateWithThinking(
                messages: messages,
                temperature: temperature,
                maxNewTokens: maxNewTokens
            )
        }
        return try await engine.generate(
            messages: messages,
            temperature: temperature,
            maxNewTokens: maxNewTokens
        )
    }
    
    func encodeImage(_ imageContent: Any) -> String {
        if let path = imageContent as? String {
            // Read from file
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                return ""
            }
            return data.base64EncodedString()
        } else if let data = imageContent as? Data {
            return data.base64EncodedString()
        }
        return ""
    }
}

extension LLMError {
    static func invalidConfiguration(_ message: String) -> LLMError {
        return .apiError("Configuration error: \(message)")
    }
}
