import Foundation

/// Base module class for agent components
class BaseModule {
    var engineParams: [String: Any]
    var platform: String
    
    init(engineParams: [String: Any], platform: String) {
        self.engineParams = engineParams
        self.platform = platform
    }
    
    func createAgent(systemPrompt: String? = nil, engineParams: [String: Any]? = nil) throws -> LLMAgent {
        let params = engineParams ?? self.engineParams
        if let prompt = systemPrompt {
            var finalParams = params
            finalParams["system_prompt"] = prompt
            return try LLMAgent(engineParams: finalParams)
        }
        return try LLMAgent(engineParams: params)
    }
}
