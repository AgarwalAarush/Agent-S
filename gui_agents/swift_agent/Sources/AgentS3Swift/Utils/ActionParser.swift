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
        var functions: [String] = []

        // Find all occurrences of "agent." followed by a function name
        let pattern = #"agent\.(\w+)\("#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let range = NSRange(code.startIndex..., in: code)
        let matches = regex.matches(in: code, options: [], range: range)

        for match in matches {
            guard let matchRange = Range(match.range, in: code) else { continue }

            // Start from the beginning of "agent.xxx("
            let startIndex = matchRange.lowerBound

            // Find the matching closing parenthesis by counting depth
            var depth = 0
            var foundStart = false
            var endIndex = startIndex

            for (index, char) in code[startIndex...].enumerated() {
                let currentIndex = code.index(startIndex, offsetBy: index)

                if char == "(" {
                    depth += 1
                    foundStart = true
                } else if char == ")" {
                    depth -= 1
                    if depth == 0 && foundStart {
                        endIndex = code.index(currentIndex, offsetBy: 1)
                        break
                    }
                }
            }

            if depth == 0 && foundStart {
                let functionCall = String(code[startIndex..<endIndex])
                functions.append(functionCall)
            }
        }

        return functions
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
        let (args, kwargs) = parseArguments(argsString)

        switch functionName {
        case "click":
            // Support both positional and keyword arguments
            let description: String
            if let desc = kwargs["description"] {
                description = parseStringLiteral(desc)
            } else if args.count >= 1 {
                description = parseStringLiteral(args[0])
            } else {
                return nil
            }

            let numClicks = kwargs["numClicks"].flatMap { parseInteger($0) }
                ?? (args.count > 1 ? parseInteger(args[1]) : nil) ?? 1
            let buttonType = kwargs["buttonType"].flatMap { parseStringLiteral($0) }
                ?? (args.count > 2 ? parseStringLiteral(args[2]) : nil) ?? "left"
            let holdKeys = kwargs["holdKeys"].flatMap { parseStringArray($0) }
                ?? (args.count > 3 ? parseStringArray(args[3]) : nil) ?? []
            return .click(description: description, numClicks: numClicks, buttonType: buttonType, holdKeys: holdKeys)

        case "type":
            // Support both positional and keyword arguments
            let description: String?
            if let desc = kwargs["description"] {
                description = desc != "None" ? parseStringLiteral(desc) : nil
            } else if args.count > 0 && args[0] != "None" {
                description = parseStringLiteral(args[0])
            } else {
                description = nil
            }

            let text = kwargs["text"].flatMap { parseStringLiteral($0) }
                ?? (args.count > 1 ? parseStringLiteral(args[1]) : nil) ?? ""
            let overwrite = kwargs["overwrite"].flatMap { parseBoolean($0) }
                ?? (args.count > 2 ? parseBoolean(args[2]) : nil) ?? false
            let enter = kwargs["enter"].flatMap { parseBoolean($0) }
                ?? (args.count > 3 ? parseBoolean(args[3]) : nil) ?? false
            return .type(description: description, text: text, overwrite: overwrite, enter: enter)
            
        case "scroll":
            let description: String
            if let desc = kwargs["description"] {
                description = parseStringLiteral(desc)
            } else if args.count >= 1 {
                description = parseStringLiteral(args[0])
            } else {
                return nil
            }

            let clicks: Int
            if let c = kwargs["clicks"].flatMap({ parseInteger($0) }) {
                clicks = c
            } else if args.count >= 2, let c = parseInteger(args[1]) {
                clicks = c
            } else {
                return nil
            }

            let shift = kwargs["shift"].flatMap { parseBoolean($0) }
                ?? (args.count > 2 ? parseBoolean(args[2]) : nil) ?? false
            return .scroll(description: description, clicks: clicks, shift: shift)

        case "drag_and_drop":
            let startDescription: String
            let endDescription: String

            if let start = kwargs["startDescription"] ?? kwargs["start_description"] {
                startDescription = parseStringLiteral(start)
            } else if args.count >= 1 {
                startDescription = parseStringLiteral(args[0])
            } else {
                return nil
            }

            if let end = kwargs["endDescription"] ?? kwargs["end_description"] {
                endDescription = parseStringLiteral(end)
            } else if args.count >= 2 {
                endDescription = parseStringLiteral(args[1])
            } else {
                return nil
            }

            let holdKeys = kwargs["holdKeys"].flatMap { parseStringArray($0) }
                ?? (args.count > 2 ? parseStringArray(args[2]) : nil) ?? []
            return .dragAndDrop(startDescription: startDescription, endDescription: endDescription, holdKeys: holdKeys)

        case "highlight_text_span":
            let startPhrase: String
            let endPhrase: String

            if let start = kwargs["startPhrase"] ?? kwargs["start_phrase"] {
                startPhrase = parseStringLiteral(start)
            } else if args.count >= 1 {
                startPhrase = parseStringLiteral(args[0])
            } else {
                return nil
            }

            if let end = kwargs["endPhrase"] ?? kwargs["end_phrase"] {
                endPhrase = parseStringLiteral(end)
            } else if args.count >= 2 {
                endPhrase = parseStringLiteral(args[1])
            } else {
                return nil
            }

            let button = kwargs["button"].flatMap { parseStringLiteral($0) }
                ?? (args.count > 2 ? parseStringLiteral(args[2]) : nil) ?? "left"
            return .highlightTextSpan(startPhrase: startPhrase, endPhrase: endPhrase, button: button)

        case "hotkey":
            print("DEBUG: Parsing hotkey action, args: \(args), kwargs: \(kwargs)")
            let keys: [String]
            if let keysArg = kwargs["keys"] {
                keys = parseStringArray(keysArg) ?? []
                print("DEBUG: Parsed keys from kwargs: \(keys)")
            } else if args.count >= 1 {
                keys = parseStringArray(args[0]) ?? []
                print("DEBUG: Parsed keys from positional: \(keys)")
            } else {
                print("DEBUG: No args for hotkey")
                return nil
            }
            return .hotkey(keys: keys)

        case "hold_and_press":
            let holdKeys: [String]
            let pressKeys: [String]

            if let hold = kwargs["holdKeys"] ?? kwargs["hold_keys"] {
                holdKeys = parseStringArray(hold) ?? []
            } else if args.count >= 1 {
                holdKeys = parseStringArray(args[0]) ?? []
            } else {
                return nil
            }

            if let press = kwargs["pressKeys"] ?? kwargs["press_keys"] {
                pressKeys = parseStringArray(press) ?? []
            } else if args.count >= 2 {
                pressKeys = parseStringArray(args[1]) ?? []
            } else {
                return nil
            }
            return .holdAndPress(holdKeys: holdKeys, pressKeys: pressKeys)

        case "wait":
            let time: Double
            if let t = kwargs["time"].flatMap({ parseDouble($0) }) {
                time = t
            } else if args.count >= 1, let t = parseDouble(args[0]) {
                time = t
            } else {
                return nil
            }
            return .wait(time: time)
            
        case "done":
            return .done
            
        case "fail":
            return .fail
            
        case "call_code_agent":
            let task: String?
            if let t = kwargs["task"] {
                task = t != "None" ? parseStringLiteral(t) : nil
            } else if args.count > 0 && args[0] != "None" {
                task = parseStringLiteral(args[0])
            } else {
                task = nil
            }
            return .callCodeAgent(task: task)

        case "switch_applications":
            let appCode: String
            if let code = kwargs["appCode"] ?? kwargs["app_code"] {
                appCode = parseStringLiteral(code)
            } else if args.count >= 1 {
                appCode = parseStringLiteral(args[0])
            } else {
                return nil
            }
            return .switchApplications(appCode: appCode)

        case "open":
            let appOrFilename: String
            if let app = kwargs["appOrFilename"] ?? kwargs["app_or_filename"] {
                appOrFilename = parseStringLiteral(app)
            } else if args.count >= 1 {
                appOrFilename = parseStringLiteral(args[0])
            } else {
                return nil
            }
            return .open(appOrFilename: appOrFilename)

        case "save_to_knowledge":
            let text: [String]
            if let t = kwargs["text"] {
                text = parseStringArray(t) ?? []
            } else if args.count >= 1 {
                text = parseStringArray(args[0]) ?? []
            } else {
                return nil
            }
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

    private static func parseArguments(_ argsString: String) -> (positional: [String], kwargs: [String: String]) {
        var positionalArgs: [String] = []
        var kwargs: [String: String] = [:]
        var current = ""
        var parenDepth = 0
        var bracketDepth = 0
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
                parenDepth += 1
                current.append(char)
            } else if !inString && char == ")" {
                parenDepth -= 1
                current.append(char)
            } else if !inString && char == "[" {
                bracketDepth += 1
                current.append(char)
            } else if !inString && char == "]" {
                bracketDepth -= 1
                current.append(char)
            } else if !inString && parenDepth == 0 && bracketDepth == 0 && char == "," {
                let arg = current.trimmingCharacters(in: .whitespaces)
                if !arg.isEmpty {
                    parseArgument(arg, positional: &positionalArgs, kwargs: &kwargs)
                }
                current = ""
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            let arg = current.trimmingCharacters(in: .whitespaces)
            parseArgument(arg, positional: &positionalArgs, kwargs: &kwargs)
        }

        return (positional: positionalArgs, kwargs: kwargs)
    }

    private static func parseArgument(_ arg: String, positional: inout [String], kwargs: inout [String: String]) {
        // Check if this is a keyword argument (key=value)
        // Need to find first '=' that's not inside quotes
        var inString = false
        var stringChar: Character?
        var equalsIndex: String.Index?

        for (index, char) in zip(arg.indices, arg) {
            if !inString && (char == "'" || char == "\"") {
                inString = true
                stringChar = char
            } else if inString && char == stringChar {
                inString = false
                stringChar = nil
            } else if !inString && char == "=" && equalsIndex == nil {
                equalsIndex = index
                break
            }
        }

        if let eqIndex = equalsIndex {
            // Keyword argument
            let key = String(arg[..<eqIndex]).trimmingCharacters(in: .whitespaces)
            let valueStart = arg.index(after: eqIndex)
            let value = String(arg[valueStart...]).trimmingCharacters(in: .whitespaces)
            kwargs[key] = value
        } else {
            // Positional argument
            positional.append(arg)
        }
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
        let trimmed = arg.trimmingCharacters(in: .whitespaces)
        // Handle Python-style True/False (capital T/F) and lowercase variants
        if trimmed == "True" || trimmed == "true" {
            return true
        } else if trimmed == "False" || trimmed == "false" {
            return false
        }
        return nil
    }
    
    private static func parseStringArray(_ arg: String) -> [String]? {
        let trimmed = arg.trimmingCharacters(in: .whitespaces)

        // Handle list format: ['key1', 'key2'] or ["key1", "key2"]
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            let content = String(trimmed.dropFirst().dropLast())
            let (items, _) = parseArguments(content)
            return items.map { parseStringLiteral($0) }
        }

        return nil
    }
}
