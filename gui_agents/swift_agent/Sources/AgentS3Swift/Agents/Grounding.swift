import Foundation
import CoreGraphics
import AppKit

/// Base ACI class for agent computer interface
class ACI {
    var notes: [String] = []
}

/// Protocol for agent actions
protocol AgentActionProtocol {
    static var isAgentAction: Bool { get }
}

/// OSWorld ACI - Grounding agent that translates descriptions to coordinates and executes actions
class OSWorldACI: ACI {
    private let platform: String
    private let width: Int
    private let height: Int
    
    // LLM agents
    private var groundingModel: LLMAgent
    private var textSpanAgent: LLMAgent
    private var codeAgent: CodeAgent?
    
    // Configuration
    private let engineParamsForGrounding: [String: Any]
    private var currentTaskInstruction: String?
    
    // Current observation
    private var obs: Observation?
    
    // Coordinates for actions
    private var coords1: [Int]?
    private var coords2: [Int]?
    
    init(
        platform: String,
        engineParamsForGeneration: [String: Any],
        engineParamsForGrounding: [String: Any],
        width: Int = 1920,
        height: Int = 1080,
        codeAgentBudget: Int = 20,
        codeAgentEngineParams: [String: Any]? = nil,
        codeAgent: CodeAgent? = nil
    ) throws {
        self.platform = platform
        self.width = width
        self.height = height
        self.engineParamsForGrounding = engineParamsForGrounding
        
        // Initialize grounding model
        self.groundingModel = try LLMAgent(engineParams: engineParamsForGrounding)
        
        // Initialize text span agent (uses generation engine)
        let textSpanParams = engineParamsForGeneration
        // TODO: Add PHRASE_TO_WORD_COORDS_PROMPT to system prompt
        self.textSpanAgent = try LLMAgent(engineParams: textSpanParams)
        
        // Initialize code agent if provided
        if let codeAgent = codeAgent {
            self.codeAgent = codeAgent
        } else if codeAgentEngineParams != nil || (engineParamsForGeneration as [String: Any]?) != nil {
            // Initialize code agent if params provided
            // Will be initialized later when needed
        }
        
        super.init()
    }
    
    /// Assign screenshot observation
    func assignScreenshot(_ obs: Observation) {
        self.obs = obs
    }
    
    /// Set task instruction for code agent
    func setTaskInstruction(_ instruction: String) {
        self.currentTaskInstruction = instruction
    }
    
    /// Generate coordinates from description using grounding model
    /// - Parameter refExpr: Description of element to click
    /// - Returns: Coordinates [x, y]
    func generateCoords(_ refExpr: String) async throws -> [Int] {
        guard let obs = obs else {
            throw GroundingError.noObservation
        }
        
        groundingModel.reset()
        
        let prompt = "Query:\(refExpr)\nOutput only the coordinate of one point in your response.\n"
        groundingModel.addMessage(
            textContent: prompt,
            imageContent: obs.screenshot,
            putTextLast: true
        )
        
        let response = await LLMUtils.callLLMSafe(groundingModel)
        print("RAW GROUNDING MODEL RESPONSE: \(response)")
        
        // Extract coordinates using regex
        let pattern = #"\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            throw GroundingError.invalidCoordinateResponse
        }
        
        let matches = regex.matches(in: response, options: [], range: NSRange(response.startIndex..., in: response))
        guard matches.count >= 2 else {
            throw GroundingError.invalidCoordinateResponse
        }
        
        let firstRange = matches[0].range
        let secondRange = matches[1].range
        
        guard let firstValue = Int(String(response[Range(firstRange, in: response)!])),
              let secondValue = Int(String(response[Range(secondRange, in: response)!])) else {
            throw GroundingError.invalidCoordinateResponse
        }
        
        return [firstValue, secondValue]
    }
    
    /// Get OCR elements from screenshot
    /// - Returns: Tuple of (OCR table string, OCR elements array)
    func getOCRElements() async throws -> (table: String, elements: [OCRElement]) {
        guard let obs = obs else {
            throw GroundingError.noObservation
        }
        
        let elements = try await ImageUtils.performOCR(obs.screenshot)
        let table = ImageUtils.generateOCRTable(elements)
        
        return (table: table, elements: elements)
    }
    
    /// Generate text coordinates from phrase using OCR + LLM
    /// - Parameters:
    ///   - phrase: Text phrase to find
    ///   - alignment: "start", "end", or "" for center
    /// - Returns: Coordinates [x, y]
    func generateTextCoords(phrase: String, alignment: String = "") async throws -> [Int] {
        guard let obs = obs else {
            throw GroundingError.noObservation
        }
        
        let (ocrTable, ocrElements) = try await getOCRElements()
        
        var alignmentPrompt = ""
        if alignment == "start" {
            alignmentPrompt = "**Important**: Output the word id of the FIRST word in the provided phrase.\n"
        } else if alignment == "end" {
            alignmentPrompt = "**Important**: Output the word id of the LAST word in the provided phrase.\n"
        }
        
        textSpanAgent.reset()
        textSpanAgent.addMessage(
            textContent: alignmentPrompt + "Phrase: \(phrase)\n\(ocrTable)",
            role: "user"
        )
        textSpanAgent.addMessage(
            textContent: "Screenshot:\n",
            imageContent: obs.screenshot,
            role: "user"
        )
        
        let response = await LLMUtils.callLLMSafe(textSpanAgent)
        print("TEXT SPAN AGENT RESPONSE: \(response)")
        
        // Extract word ID
        let pattern = #"\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            throw GroundingError.invalidCoordinateResponse
        }
        
        let matches = regex.matches(in: response, options: [], range: NSRange(response.startIndex..., in: response))
        let textID = matches.isEmpty ? 0 : (Int(String(response[Range(matches.last!.range, in: response)!])) ?? 0)
        
        guard textID < ocrElements.count else {
            throw GroundingError.invalidWordID
        }
        
        let element = ocrElements[textID]
        
        // Compute coordinates based on alignment
        let coords: [Int]
        switch alignment {
        case "start":
            coords = [element.left, element.top + (element.height / 2)]
        case "end":
            coords = [element.left + element.width, element.top + (element.height / 2)]
        default:
            coords = [element.left + (element.width / 2), element.top + (element.height / 2)]
        }
        
        return coords
    }
    
    /// Resize coordinates from grounding model dimensions to screen dimensions
    /// - Parameter coordinates: Coordinates in grounding model space
    /// - Returns: Coordinates in screen space
    func resizeCoordinates(_ coordinates: [Int]) -> [Int] {
        guard coordinates.count >= 2 else {
            return coordinates
        }
        
        guard let groundingWidth = engineParamsForGrounding["grounding_width"] as? Int,
              let groundingHeight = engineParamsForGrounding["grounding_height"] as? Int else {
            // Default to 1000x1000 (UI-TARS default)
            let defaultSize = 1000
            return [
                Int(round(Double(coordinates[0]) * Double(width) / Double(defaultSize))),
                Int(round(Double(coordinates[1]) * Double(height) / Double(defaultSize)))
            ]
        }
        
        return [
            Int(round(Double(coordinates[0]) * Double(width) / Double(groundingWidth))),
            Int(round(Double(coordinates[1]) * Double(height) / Double(groundingHeight)))
        ]
    }
    
    /// Assign coordinates for actions (called before action generation)
    /// Similar to Python's assign_coordinates
    func assignCoordinates(plan: String, obs: Observation) async throws {
        self.obs = obs
        self.coords1 = nil
        self.coords2 = nil
        
        // Parse the plan code
        let code = LLMUtils.parseCodeFromString(plan)
        let functions = LLMUtils.extractAgentFunctions(code)
        
        guard let functionCall = functions.first else {
            return
        }
        
        guard let action = ActionParser.parseAction(functionCall) else {
            return
        }
        
        // Assign coordinates based on action type
        switch action {
        case .click(let description, _, _, _):
            self.coords1 = try await generateCoords(description)
        case .type(let description, _, _, _):
            if let desc = description {
                self.coords1 = try await generateCoords(desc)
            }
        case .scroll(let description, _, _):
            self.coords1 = try await generateCoords(description)
        case .dragAndDrop(let startDesc, let endDesc, _):
            self.coords1 = try await generateCoords(startDesc)
            self.coords2 = try await generateCoords(endDesc)
        case .highlightTextSpan(let startPhrase, let endPhrase, _):
            self.coords1 = try await generateTextCoords(phrase: startPhrase, alignment: "start")
            self.coords2 = try await generateTextCoords(phrase: endPhrase, alignment: "end")
        default:
            break
        }
    }
    
    /// Create executable action code from Action enum
    /// This replaces eval() by converting Action to execution commands
    /// - Parameter action: Action enum to convert
    /// - Returns: Executable code string
    func createActionCode(_ action: AgentAction) async throws -> String {
        switch action {
        case .click(let description, let numClicks, let buttonType, let holdKeys):
            let coords = try await generateCoords(description)
            let resizedCoords = resizeCoordinates(coords)
            let x = resizedCoords[0]
            let y = resizedCoords[1]
            
            var command = ""
            
            // Hold modifier keys (will be handled separately)
            for _ in holdKeys {
                // Keys will be held during click
            }
            
            // Generate click command
            command += "CLICK(\(x), \(y), clicks=\(numClicks), button=\(buttonType))"
            
            return command
            
        case .type(let description, let text, let overwrite, let enter):
            var command = ""
            
            if let desc = description {
                let coords = try await generateCoords(desc)
                let resizedCoords = resizeCoordinates(coords)
                command += "CLICK(\(resizedCoords[0]), \(resizedCoords[1])); "
            }
            
            if overwrite {
                let modifier = platform == "darwin" ? "command" : "ctrl"
                command += "HOTKEY(\(modifier), 'a'); BACKSPACE(); "
            }
            
            // Handle Unicode vs ASCII
            let hasUnicode = text.unicodeScalars.contains { $0.value > 127 }
            if hasUnicode {
                // Use clipboard for Unicode
                command += "CLIPBOARD_SET(\(text.quoted)); HOTKEY(\(platform == "darwin" ? "command" : "ctrl"), 'v'); "
            } else {
                command += "TYPE(\(text.quoted)); "
            }
            
            if enter {
                command += "PRESS_ENTER(); "
            }
            
            return command
            
        case .scroll(let description, let clicks, let shift):
            let coords = try await generateCoords(description)
            let resizedCoords = resizeCoordinates(coords)
            let x = resizedCoords[0]
            let y = resizedCoords[1]
            
            if shift {
                return "SCROLL_H(\(x), \(y), clicks=\(clicks))"
            } else {
                return "SCROLL_V(\(x), \(y), clicks=\(clicks))"
            }
            
        case .dragAndDrop(let startDesc, let endDesc, _):
            let startCoords = try await generateCoords(startDesc)
            let endCoords = try await generateCoords(endDesc)
            let startResized = resizeCoordinates(startCoords)
            let endResized = resizeCoordinates(endCoords)
            
            return "DRAG(\(startResized[0]), \(startResized[1]), \(endResized[0]), \(endResized[1]))"
            
        case .highlightTextSpan(let startPhrase, let endPhrase, let button):
            let startCoords = try await generateTextCoords(phrase: startPhrase, alignment: "start")
            let endCoords = try await generateTextCoords(phrase: endPhrase, alignment: "end")
            
            return "HIGHLIGHT(\(startCoords[0]), \(startCoords[1]), \(endCoords[0]), \(endCoords[1]), button=\(button))"
            
        case .hotkey(let keys):
            print("DEBUG: Creating hotkey action code with keys: \(keys)")
            let code = "HOTKEY(\(keys.map { $0.quoted }.joined(separator: ", ")))"
            print("DEBUG: Generated hotkey code: \(code)")
            return code
            
        case .holdAndPress(let holdKeys, let pressKeys):
            var command = ""
            for key in holdKeys {
                command += "KEY_DOWN(\(key.quoted)); "
            }
            for key in pressKeys {
                command += "PRESS(\(key.quoted)); "
            }
            for key in holdKeys.reversed() {
                command += "KEY_UP(\(key.quoted)); "
            }
            return command
            
        case .wait(let time):
            return "WAIT(\(time))"
            
        case .done:
            return "DONE"
            
        case .fail:
            return "FAIL"
            
        case .callCodeAgent(let task):
            return "CALL_CODE_AGENT(task: \(task?.quoted ?? "nil"))"
            
        case .switchApplications(let appCode):
            if platform == "darwin" {
                return "HOTKEY('command', 'space'); WAIT(0.5); TYPE(\(appCode.quoted)); PRESS_ENTER(); WAIT(1.0)"
            } else if platform == "linux" {
                return "UBUNTU_SWITCH_APP(\(appCode.quoted))"
            } else {
                return "HOTKEY('win', 'd'); WAIT(0.5); TYPE(\(appCode.quoted)); PRESS_ENTER(); WAIT(1.0)"
            }
            
        case .open(let appOrFilename):
            if platform == "darwin" {
                return "HOTKEY('command', 'space'); WAIT(0.5); TYPE(\(appOrFilename.quoted)); PRESS_ENTER(); WAIT(1.0)"
            } else if platform == "linux" {
                return "HOTKEY('win'); WAIT(0.5); TYPE(\(appOrFilename.quoted)); WAIT(1.0); PRESS_ENTER(); WAIT(0.5)"
            } else {
                return "HOTKEY('win'); WAIT(0.5); TYPE(\(appOrFilename.quoted)); WAIT(1.0); PRESS_ENTER(); WAIT(0.5)"
            }
            
        case .saveToKnowledge(let text):
            notes.append(contentsOf: text)
            return "WAIT"
            
        case .setCellValues(_, let appName, let sheetName):
            // Complex LibreOffice integration
            return "SET_CELL_VALUES(\(appName.quoted), \(sheetName.quoted))"
        }
    }
    
    /// Execute action code (interprets the command strings)
    /// - Parameter code: Action code string
    func executeActionCode(_ code: String) throws {
        // Parse and execute the action code
        // This interprets the command strings generated by createActionCode

        // Handle compound commands (separated by semicolons)
        let commands = code.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }

        for command in commands {
            if command.isEmpty {
                continue
            }

            if command.hasPrefix("CLICK(") {
                try executeClickCode(command)
            } else if command.hasPrefix("TYPE(") {
                try executeTypeCode(command)
            } else if command.hasPrefix("HOTKEY(") {
                try executeHotkeyCode(command)
            } else if command.hasPrefix("CLIPBOARD_SET(") {
                try executeClipboardSetCode(command)
            } else if command.hasPrefix("WAIT(") {
                try executeWaitCode(command)
            } else if command.hasPrefix("PRESS_ENTER(") {
                CGEventExecutor.pressEnter()
            } else if command.hasPrefix("BACKSPACE(") {
                CGEventExecutor.pressBackspace()
            } else if command.hasPrefix("SCROLL_V(") {
                try executeScrollCode(command, horizontal: false)
            } else if command.hasPrefix("SCROLL_H(") {
                try executeScrollCode(command, horizontal: true)
            } else if command.hasPrefix("DRAG(") {
                try executeDragCode(command)
            } else if command == "DONE" {
                // Done - handled by caller
            } else if command == "FAIL" {
                // Fail - handled by caller
            } else if command == "WAIT" {
                Thread.sleep(forTimeInterval: 1.0)
            } else {
                print("⚠️  Unknown command: \(command)")
            }
        }
    }
    
    private func executeClickCode(_ code: String) throws {
        // Parse CLICK(x, y, clicks=1, button="left")
        // Extract coordinates and execute
        let pattern = #"CLICK\((\d+),\s*(\d+)(?:,\s*clicks=(\d+))?(?:,\s*button=(\w+))?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: code, options: [], range: NSRange(code.startIndex..., in: code)),
              let xRange = Range(match.range(at: 1), in: code),
              let yRange = Range(match.range(at: 2), in: code),
              let x = Int(String(code[xRange])),
              let y = Int(String(code[yRange])) else {
            throw GroundingError.invalidActionCode
        }
        
        let clicks = match.numberOfRanges > 3 && match.range(at: 3).location != NSNotFound
            ? (Int(String(code[Range(match.range(at: 3), in: code)!])) ?? 1)
            : 1
        
        let button = match.numberOfRanges > 4 && match.range(at: 4).location != NSNotFound
            ? String(code[Range(match.range(at: 4), in: code)!])
            : "left"
        
        let point = CGPoint(x: Double(x), y: Double(y))
        CGEventExecutor.click(point: point, numClicks: clicks, buttonType: button)
    }
    
    private func executeTypeCode(_ code: String) throws {
        // Parse TYPE("text")
        let pattern = #"TYPE\("([^"]+)"\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: code, options: [], range: NSRange(code.startIndex..., in: code)),
              let textRange = Range(match.range(at: 1), in: code) else {
            throw GroundingError.invalidActionCode
        }
        
        let text = String(code[textRange])
        CGEventExecutor.typeText(text)
    }
    
    private func executeHotkeyCode(_ code: String) throws {
        // Parse HOTKEY('key1', 'key2', ...) or HOTKEY("key1", "key2", ...)
        // Extract all key arguments
        let pattern = #"HOTKEY\((.*)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: code, options: [], range: NSRange(code.startIndex..., in: code)),
              let argsRange = Range(match.range(at: 1), in: code) else {
            throw GroundingError.invalidActionCode
        }
        
        let argsString = String(code[argsRange])
        // Parse quoted strings (either single or double quotes)
        let keyPattern = #"['"]([^'"]+)['"]"#
        guard let keyRegex = try? NSRegularExpression(pattern: keyPattern) else {
            throw GroundingError.invalidActionCode
        }
        
        let matches = keyRegex.matches(in: argsString, options: [], range: NSRange(argsString.startIndex..., in: argsString))
        var keys: [String] = []
        
        for match in matches {
            if let keyRange = Range(match.range(at: 1), in: argsString) {
                keys.append(String(argsString[keyRange]))
            }
        }
        
        guard !keys.isEmpty else {
            throw GroundingError.invalidActionCode
        }
        
        CGEventExecutor.hotkey(keys: keys)
    }
    
    private func executeClipboardSetCode(_ code: String) throws {
        // Parse CLIPBOARD_SET("text")
        let pattern = #"CLIPBOARD_SET\("([^"]+)"\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: code, options: [], range: NSRange(code.startIndex..., in: code)),
              let textRange = Range(match.range(at: 1), in: code) else {
            throw GroundingError.invalidActionCode
        }
        
        let text = String(code[textRange])
        CGEventExecutor.setClipboard(text)
    }
    
    private func executeWaitCode(_ code: String) throws {
        // Parse WAIT(seconds)
        let pattern = #"WAIT\(([\d.]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: code, options: [], range: NSRange(code.startIndex..., in: code)),
              let timeRange = Range(match.range(at: 1), in: code),
              let time = Double(String(code[timeRange])) else {
            throw GroundingError.invalidActionCode
        }

        Thread.sleep(forTimeInterval: time)
    }

    private func executeScrollCode(_ code: String, horizontal: Bool) throws {
        // Parse SCROLL_V(x, y, clicks=N) or SCROLL_H(x, y, clicks=N)
        let pattern = #"SCROLL_[VH]\((\d+),\s*(\d+)(?:,\s*clicks=(-?\d+))?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: code, options: [], range: NSRange(code.startIndex..., in: code)),
              let xRange = Range(match.range(at: 1), in: code),
              let yRange = Range(match.range(at: 2), in: code),
              let x = Int(String(code[xRange])),
              let y = Int(String(code[yRange])) else {
            throw GroundingError.invalidActionCode
        }

        let clicks = match.numberOfRanges > 3 && match.range(at: 3).location != NSNotFound
            ? (Int(String(code[Range(match.range(at: 3), in: code)!])) ?? 10)
            : 10

        let point = CGPoint(x: Double(x), y: Double(y))
        CGEventExecutor.scroll(at: point, clicks: clicks, shift: horizontal)
    }

    private func executeDragCode(_ code: String) throws {
        // Parse DRAG(x1, y1, x2, y2)
        let pattern = #"DRAG\((\d+),\s*(\d+),\s*(\d+),\s*(\d+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: code, options: [], range: NSRange(code.startIndex..., in: code)),
              let x1Range = Range(match.range(at: 1), in: code),
              let y1Range = Range(match.range(at: 2), in: code),
              let x2Range = Range(match.range(at: 3), in: code),
              let y2Range = Range(match.range(at: 4), in: code),
              let x1 = Int(String(code[x1Range])),
              let y1 = Int(String(code[y1Range])),
              let x2 = Int(String(code[x2Range])),
              let y2 = Int(String(code[y2Range])) else {
            throw GroundingError.invalidActionCode
        }

        let startPoint = CGPoint(x: Double(x1), y: Double(y1))
        let endPoint = CGPoint(x: Double(x2), y: Double(y2))
        CGEventExecutor.drag(from: startPoint, to: endPoint)
    }
}

enum GroundingError: Error {
    case noObservation
    case invalidCoordinateResponse
    case invalidWordID
    case invalidActionCode
}

extension String {
    var quoted: String {
        return "\"\(self)\""
    }
}
