import Foundation

/// Structured action enum representing all possible agent actions
/// Replaces the need for eval() by providing type-safe action representation
enum AgentAction {
    case click(description: String, numClicks: Int, buttonType: String, holdKeys: [String])
    case type(description: String?, text: String, overwrite: Bool, enter: Bool)
    case scroll(description: String, clicks: Int, shift: Bool)
    case dragAndDrop(startDescription: String, endDescription: String, holdKeys: [String])
    case highlightTextSpan(startPhrase: String, endPhrase: String, button: String)
    case hotkey(keys: [String])
    case holdAndPress(holdKeys: [String], pressKeys: [String])
    case wait(time: Double)
    case done
    case fail
    case callCodeAgent(task: String?)
    case switchApplications(appCode: String)
    case open(appOrFilename: String)
    case saveToKnowledge(text: [String])
    case setCellValues(cellValues: [String: Any], appName: String, sheetName: String)
    
    /// Action name for logging/debugging
    var name: String {
        switch self {
        case .click: return "click"
        case .type: return "type"
        case .scroll: return "scroll"
        case .dragAndDrop: return "dragAndDrop"
        case .highlightTextSpan: return "highlightTextSpan"
        case .hotkey: return "hotkey"
        case .holdAndPress: return "holdAndPress"
        case .wait: return "wait"
        case .done: return "done"
        case .fail: return "fail"
        case .callCodeAgent: return "callCodeAgent"
        case .switchApplications: return "switchApplications"
        case .open: return "open"
        case .saveToKnowledge: return "saveToKnowledge"
        case .setCellValues: return "setCellValues"
        }
    }
}
