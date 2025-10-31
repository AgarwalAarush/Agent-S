import Foundation

/// Response structure from agent predictions
struct AgentResponse {
    var info: [String: Any]
    var actions: [String]  // Executable action strings
    
    init(info: [String: Any] = [:], actions: [String] = []) {
        self.info = info
        self.actions = actions
    }
}
