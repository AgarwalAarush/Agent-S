import Foundation

/// Parser to convert LLM string responses to structured Action enum
/// Replaces eval() by parsing and validating action calls
class ActionParser {
    
    /// Extract code block from markdown-formatted response
    /// - Parameter inputString: LLM response string potentially containing code blocks
    /// - Returns: The last code block found, or empty string if none
    static func parseCodeFromString(_ inputString: String) -> String {
        let trimmed = inputString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Match ```python code``` or ```code``` (non-greedy)
        let pattern = #"```(?:\w+\s+)?(.*?)```"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return ""
        }
        
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = regex.matches(in: trimmed, options: [], range: range)
        
        guard let lastMatch = matches.last,
              let matchRange = Range(lastMatch.range(at: 1), in: trimmed) else {
            return ""
        }
        
        return String(trimmed[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Extract all agent function calls from code
    /// - Parameter code: Code string to search
    /// - Returns: Array of agent function call strings
    static func extractAgentFunctions(_ code: String) -> [String] {
        // Match agent.xxx(...)
        let pattern = #"agent\.\w+\(\s*.*?\)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        
        let range = NSRange(code.startIndex..., in: code)
        let matches = regex.matches(in: code, options: [], range: range)
        
        return matches.compactMap { match in
            guard let matchRange = Range(match.range, in: code) else { return nil }
            return String(code[matchRange])
        }
    }
    
    /// Parse a single agent function call string to Action enum
    /// - Parameter functionCall: String like "agent.click('description', 1, 'left')"
    /// - Returns: Parsed Action enum, or nil if parsing fails
    static func parseAction(_ functionCall: String) -> AgentAction? {
        // Extract function name and arguments
        let pattern = #"agent\.(\w+)\((.*)\)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: functionCall, options: [], range: NSRange(functionCall.startIndex..., in: functionCall)),
              let nameRange = Range(match.range(at: 1), in: functionCall),
              let argsRange = Range(match.range(at: 2), in: functionCall) else {
            return nil
        }
        
        let functionName = String(functionCall[nameRange])
        let argsString = String(functionCall[argsRange])
        let args = parseArguments(argsString)
        
        switch functionName {
        case "click":
            guard args.count >= 1 else { return nil }
            let description = parseStringLiteral(args[0])
            let numClicks = args.count > 1 ? parseInteger(args[1]) ?? 1 : 1
            let buttonType = args.count > 2 ? parseStringLiteral(args[2]) ?? "left" : "left"
            let holdKeys = args.count > 3 ? parseStringArray(args[3]) ?? [] : []
            return .click(description: description, numClicks: numClicks, buttonType: buttonType, holdKeys: holdKeys)
            
        case "type":
            let description = args.count > 0 && args[0] != "None" ? parseStringLiteral(args[0]) : nil
            let text = args.count > 1 ? parseStringLiteral(args[1]) ?? "" : ""
            let overwrite = args.count > 2 ? parseBoolean(args[2]) ?? false : false
            let enter = args.count > 3 ? parseBoolean(args[3]) ?? false : false
            return .type(description: description, text: text, overwrite: overwrite, enter: enter)
            
        case "scroll":
            guard args.count >= 2 else { return nil }
            let description = parseStringLiteral(args[0])
            let clicks = parseInteger(args[1]) ?? 0
            let shift = args.count > 2 ? parseBoolean(args[2]) ?? false : false
            return .scroll(description: description, clicks: clicks, shift: shift)
            
        case "drag_and_drop":
            guard args.count >= 2 else { return nil }
            let startDescription = parseStringLiteral(args[0])
            let endDescription = parseStringLiteral(args[1])
            let holdKeys = args.count > 2 ? parseStringArray(args[2]) ?? [] : []
            return .dragAndDrop(startDescription: startDescription, endDescription: endDescription, holdKeys: holdKeys)
            
        case "highlight_text_span":
            guard args.count >= 2 else { return nil }
            let startPhrase = parseStringLiteral(args[0])
            let endPhrase = parseStringLiteral(args[1])
            let button = args.count > 2 ? parseStringLiteral(args[2]) ?? "left" : "left"
            return .highlightTextSpan(startPhrase: startPhrase, endPhrase: endPhrase, button: button)
            
        case "hotkey":
            guard args.count >= 1 else { return nil }
            let keys = parseStringArray(args[0]) ?? []
            return .hotkey(keys: keys)
            
        case "hold_and_press":
            guard args.count >= 2 else { return nil }
            let holdKeys = parseStringArray(args[0]) ?? []
            let pressKeys = parseStringArray(args[1]) ?? []
            return .holdAndPress(holdKeys: holdKeys, pressKeys: pressKeys)
            
        case "wait":
            guard args.count >= 1 else { return nil }
            let time = parseDouble(args[0]) ?? 0.0
            return .wait(time: time)
            
        case "done":
            return .done
            
        case "fail":
            return .fail
            
        case "call_code_agent":
            let task = args.count > 0 && args[0] != "None" ? parseStringLiteral(args[0]) : nil
            return .callCodeAgent(task: task)
            
        case "switch_applications":
            guard args.count >= 1 else { return nil }
            let appCode = parseStringLiteral(args[0])
            return .switchApplications(appCode: appCode)
            
        case "open":
            guard args.count >= 1 else { return nil }
            let appOrFilename = parseStringLiteral(args[0])
            return .open(appOrFilename: appOrFilename)
            
        case "save_to_knowledge":
            guard args.count >= 1 else { return nil }
            let text = parseStringArray(args[0]) ?? []
            return .saveToKnowledge(text: text)
            
        case "set_cell_values":
            // Complex parsing for dict arguments - simplified for now
            guard args.count >= 3 else { return nil }
            // This would need more sophisticated parsing for dict/any types
            return nil // Placeholder - implement if needed
            
        default:
            return nil
        }
    }
    
    // MARK: - Argument Parsing Helpers
    
    private static func parseArguments(_ argsString: String) -> [String] {
        var args: [String] = []
        var current = ""
        var depth = 0
        var inString = false
        var stringChar: Character?
        
        for char in argsString {
            if !inString && (char == "'" || char == "\"") {
                inString = true
                stringChar = char
                current.append(char)
            } else if inString && char == stringChar {
                inString = false
                stringChar = nil
                current.append(char)
            } else if !inString && char == "(" {
                depth += 1
                current.append(char)
            } else if !inString && char == ")" {
                depth -= 1
                current.append(char)
            } else if !inString && depth == 0 && char == "," {
                args.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        
        if !current.isEmpty {
            args.append(current.trimmingCharacters(in: .whitespaces))
        }
        
        return args
    }
    
    private static func parseStringLiteral(_ arg: String) -> String {
        let trimmed = arg.trimmingCharacters(in: .whitespaces)
        
        // Remove quotes if present
        if (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) ||
           (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) {
            let startIndex = trimmed.index(after: trimmed.startIndex)
            let endIndex = trimmed.index(before: trimmed.endIndex)
            return String(trimmed[startIndex..<endIndex])
        }
        
        return trimmed
    }
    
    private static func parseInteger(_ arg: String) -> Int? {
        return Int(arg.trimmingCharacters(in: .whitespaces))
    }
    
    private static func parseDouble(_ arg: String) -> Double? {
        return Double(arg.trimmingCharacters(in: .whitespaces))
    }
    
    private static func parseBoolean(_ arg: String) -> Bool? {
        let trimmed = arg.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed == "true" || trimmed == "True" {
            return true
        } else if trimmed == "false" || trimmed == "False" {
            return false
        }
        return nil
    }
    
    private static func parseStringArray(_ arg: String) -> [String]? {
        let trimmed = arg.trimmingCharacters(in: .whitespaces)
        
        // Handle list format: ['key1', 'key2'] or ["key1", "key2"]
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            let content = String(trimmed.dropFirst().dropLast())
            let items = parseArguments(content)
            return items.map { parseStringLiteral($0) }
        }
        
        return nil
    }
}
