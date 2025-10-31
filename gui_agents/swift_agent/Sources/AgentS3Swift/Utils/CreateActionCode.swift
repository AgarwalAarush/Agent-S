import Foundation

/// Helper to create action code from parsed action
/// Replaces Python's create_pyautogui_code which uses eval()
enum CreateActionCode {
    static func createActionCode(agent: OSWorldACI, code: String, obs: Observation) async throws -> String {
        // Assign screenshot for grounding
        agent.assignScreenshot(obs)

        // Parse code string to Action enum
        // First extract agent function from code
        print("DEBUG: CreateActionCode input code: '\(code)'")
        let functions = ActionParser.extractAgentFunctions(code)
        print("DEBUG: Extracted functions: \(functions)")
        guard let functionCall = functions.first else {
            print("DEBUG: No functions extracted")
            throw ActionParseError.invalidAction(code)
        }
        print("DEBUG: Parsing function call: '\(functionCall)'")
        guard let action = ActionParser.parseAction(functionCall) else {
            print("DEBUG: Failed to parse action from function call")
            throw ActionParseError.invalidAction(code)
        }
        print("DEBUG: Parsed action: \(action)")

        // Convert Action enum to executable code string
        let execCode = try await agent.createActionCode(action)
        print("DEBUG: Final executable code: '\(execCode)'")
        return execCode
    }
}

enum ActionParseError: Error {
    case invalidAction(String)
}
