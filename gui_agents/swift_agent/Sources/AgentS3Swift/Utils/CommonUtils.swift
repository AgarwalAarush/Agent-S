import Foundation

/// Utility functions for LLM calls, parsing, and formatting
enum LLMUtils {
    /// Call LLM safely with retry logic
    /// - Parameters:
    ///   - agent: LLM agent to call
    ///   - temperature: Temperature for generation
    ///   - useThinking: Whether to use thinking mode (for Claude)
    ///   - messages: Optional custom messages (defaults to agent's messages)
    /// - Returns: Generated response string
    static func callLLMSafe(
    _ agent: LLMAgent,
    temperature: Double = 1.0,
    useThinking: Bool = false,
    messages: [Message]? = nil
) async -> String {
    let maxRetries = 3
    var attempt = 0
    var response = ""
    
    while attempt < maxRetries {
        do {
            if let customMessages = messages {
                // Temporarily use custom messages
                let originalMessages = agent.messages
                agent.messages = customMessages
                response = try await agent.getResponse(
                    temperature: temperature,
                    useThinking: useThinking
                )
                agent.messages = originalMessages
            } else {
                response = try await agent.getResponse(
                    temperature: temperature,
                    useThinking: useThinking
                )
            }
            
            if !response.isEmpty {
                print("Response success!")
                break
            }
        } catch {
            attempt += 1
            print("Attempt \(attempt) failed: \(error)")
            if attempt < maxRetries {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            } else {
                print("Max retries reached. Handling failure.")
            }
        }
    }
    
    return response
}

    /// Split thinking response into thoughts and answer
    /// - Parameter fullResponse: Full response string with <thoughts> and <answer> tags
    /// - Returns: Tuple of (thoughts, answer)
    static func splitThinkingResponse(_ fullResponse: String) -> (thoughts: String, answer: String) {
        var thoughts = ""
        var answer = ""
        
        // Extract thoughts section
        if let thoughtsStart = fullResponse.range(of: "<thoughts>"),
           let thoughtsEnd = fullResponse.range(of: "</thoughts>", range: thoughtsStart.upperBound..<fullResponse.endIndex) {
            thoughts = String(fullResponse[thoughtsStart.upperBound..<thoughtsEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Extract answer section
        if let answerStart = fullResponse.range(of: "<answer>"),
           let answerEnd = fullResponse.range(of: "</answer>", range: answerStart.upperBound..<fullResponse.endIndex) {
            answer = String(fullResponse[answerStart.upperBound..<answerEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // If no tags found, treat entire response as answer
        if thoughts.isEmpty && answer.isEmpty {
            answer = fullResponse
        }
        
        return (thoughts: thoughts, answer: answer)
    }

    /// Parse code block from markdown-formatted string
    /// Delegates to ActionParser.parseCodeFromString
    static func parseCodeFromString(_ inputString: String) -> String {
        return ActionParser.parseCodeFromString(inputString)
    }

    /// Extract all agent function calls from code
    /// Delegates to ActionParser.extractAgentFunctions
    static func extractAgentFunctions(_ code: String) -> [String] {
        return ActionParser.extractAgentFunctions(code)
    }
}
