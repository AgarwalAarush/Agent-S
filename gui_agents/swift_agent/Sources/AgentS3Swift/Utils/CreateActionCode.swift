import Foundation

/// Helper to create action code from parsed action
/// Replaces Python's create_pyautogui_code which uses eval()
enum CreateActionCode {
    static func createActionCode(agent: OSWorldACI, code: String, obs: Observation) async throws -> String {
        // Assign screenshot for grounding
        agent.assignScreenshot(obs)
        
        // Parse code string to Action enum
        // First extract agent function from code
        let functions = ActionParser.extractAgentFunctions(code)
        guard let functionCall = functions.first,
              let action = ActionParser.parseAction(functionCall) else {
            throw ActionParseError.invalidAction(code)
        }
        
        // Convert Action enum to executable code string
        return try await agent.createActionCode(action)
    }
}

enum ActionParseError: Error {
    case invalidAction(String)
}
