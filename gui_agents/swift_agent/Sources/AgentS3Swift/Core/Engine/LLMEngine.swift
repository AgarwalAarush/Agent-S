import Foundation

/// Protocol defining the interface for LLM engines
protocol LLMEngine {
    /// Generate a response from the LLM
    /// - Parameters:
    ///   - messages: Array of messages in the conversation
    ///   - temperature: Temperature for generation (0.0-2.0)
    ///   - maxNewTokens: Maximum tokens to generate
    /// - Returns: Generated text response
    func generate(
        messages: [Message],
        temperature: Double,
        maxNewTokens: Int?
    ) async throws -> String
    
    /// Generate with thinking mode (for Claude models)
    /// - Parameters:
    ///   - messages: Array of messages in the conversation
    ///   - temperature: Temperature for generation
    ///   - maxNewTokens: Maximum tokens to generate
    /// - Returns: Generated response with thinking tokens
    func generateWithThinking(
        messages: [Message],
        temperature: Double,
        maxNewTokens: Int?
    ) async throws -> String
}
