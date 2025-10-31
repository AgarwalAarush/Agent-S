import Foundation

/// Format validation functions for LLM responses
enum Formatters {
    /// Check if response contains exactly one agent action
    static func singleActionCheck(_ response: String) -> Bool {
        let code = LLMUtils.parseCodeFromString(response)
        let functions = LLMUtils.extractAgentFunctions(code)
        return functions.count == 1
    }

    /// Format checker for single action requirement
    struct SingleActionFormatter {
        static func check(_ response: String) -> (success: Bool, feedback: String) {
            let success = singleActionCheck(response)
            let feedback = success ? "" : "Incorrect code: There must be a single agent action in the code response."
            return (success: success, feedback: feedback)
        }
    }

    /// Format checker for valid code execution
    struct CodeValidFormatter {
        let agent: Any // Grounding agent (will be properly typed later)
        let obs: Observation
        
        func check(_ response: String) -> (success: Bool, feedback: String) {
            let code = LLMUtils.parseCodeFromString(response)
            
            // Try to parse the action
            let functions = LLMUtils.extractAgentFunctions(code)
            guard let functionCall = functions.first else {
                return (success: false, feedback: "No agent function found in code")
            }
            
            // Try to parse into Action enum
            guard ActionParser.parseAction(functionCall) != nil else {
                return (success: false, feedback: "Incorrect code: The agent action must be a valid function and use valid parameters from the docstring list.")
            }
            
            return (success: true, feedback: "")
        }
    }

    /// Format checker for thoughts/answer tags
    struct ThoughtsAnswerTagFormatter {
        static func check(_ response: String) -> (success: Bool, feedback: String) {
            let (thoughts, answer) = LLMUtils.splitThinkingResponse(response)
            let success = !thoughts.isEmpty || !answer.isEmpty
            let feedback = success ? "" : "Incorrect response: The response must contain both <thoughts>...</thoughts> and <answer>...</answer> tags."
            return (success: success, feedback: feedback)
        }
    }

    /// Format checker for integer answer requirement
    struct IntegerAnswerFormatter {
        static func check(_ response: String) -> (success: Bool, feedback: String) {
            let (_, answer) = LLMUtils.splitThinkingResponse(response)
            let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            let success = Int(trimmed) != nil
            let feedback = success ? "" : "Incorrect response: The <answer>...</answer> tag must contain a single integer."
            return (success: success, feedback: feedback)
        }
    }

    /// Call LLM with format validation and retry logic
    /// - Parameters:
    ///   - generator: LLM agent to call
    ///   - formatCheckers: Array of format validation functions
    ///   - temperature: Temperature for generation
    ///   - useThinking: Whether to use thinking mode
    ///   - messages: Optional custom messages
    /// - Returns: Formatted response string
    static func callLLMFormatted(
        _ generator: LLMAgent,
        formatCheckers: [(String) -> (success: Bool, feedback: String)],
        temperature: Double = 1.0,
        useThinking: Bool = false,
        messages: [Message]? = nil
    ) async -> String {
        let maxRetries = 3
        var attempt = 0
        var response = ""
        
        var workingMessages = messages ?? generator.messages
        
        while attempt < maxRetries {
            response = await LLMUtils.callLLMSafe(
                generator,
                temperature: temperature,
                useThinking: useThinking,
                messages: workingMessages
            )
            
            // Check all format checkers
            var feedbackMessages: [String] = []
            for checker in formatCheckers {
                let (success, feedback) = checker(response)
                if !success {
                    feedbackMessages.append(feedback)
                }
            }
            
            if feedbackMessages.isEmpty {
                // Format is correct
                break
            }
            
            // Format error - add feedback to conversation
            workingMessages.append(Message(
                role: "assistant",
                content: [.text(response)]
            ))
            
            let delimiter = "\n- "
            let formattingFeedback = "- \(feedbackMessages.joined(separator: delimiter))"
            
            let feedbackPrompt = """
            Your previous response was not formatted correctly. You must respond again to replace your previous response. Do not make reference to this message while fixing the response. Please address the following issues below to improve the previous response:
            \(formattingFeedback)
            """
            
            workingMessages.append(Message(
                role: "user",
                content: [.text(feedbackPrompt)]
            ))
            
            attempt += 1
            if attempt < maxRetries {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
        
        return response
    }
}
