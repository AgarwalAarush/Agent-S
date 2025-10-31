import Foundation

/// Main AgentS3 class that orchestrates Worker and Grounding agents
class AgentS3 {
    private var executor: Worker
    var groundingAgent: OSWorldACI { get { _groundingAgent } }
    private var _groundingAgent: OSWorldACI
    
    init(
        engineParamsForGeneration: [String: Any],
        engineParamsForGrounding: [String: Any],
        platform: String = "darwin",
        width: Int = 1920,
        height: Int = 1080,
        maxTrajectoryLength: Int = 8,
        enableReflection: Bool = true,
        codeAgentBudget: Int = 20,
        codeAgentEngineParams: [String: Any]? = nil
    ) throws {
        // Initialize grounding agent
        _groundingAgent = try OSWorldACI(
            platform: platform,
            engineParamsForGeneration: engineParamsForGeneration,
            engineParamsForGrounding: engineParamsForGrounding,
            width: width,
            height: height,
            codeAgentBudget: codeAgentBudget,
            codeAgentEngineParams: codeAgentEngineParams
        )
        
        // Initialize worker agent
        executor = try Worker(
            workerEngineParams: engineParamsForGeneration,
            groundingAgent: _groundingAgent,
            platform: platform,
            maxTrajectoryLength: maxTrajectoryLength,
            enableReflection: enableReflection
        )
    }
    
    /// Reset agent state
    func reset() {
        executor.reset()
        // Grounding agent reset would be handled by OSWorldACI
    }
    
    /// Predict next action based on instruction and observation
    /// - Parameters:
    ///   - instruction: Task instruction
    ///   - observation: Current observation with screenshot
    /// - Returns: Tuple of (info dictionary, actions list)
    func predict(instruction: String, observation: Observation) async throws -> ([String: Any], [String]) {
        let (info, actions) = try await executor.generateNextAction(
            instruction: instruction,
            obs: observation
        )
        return (info, actions)
    }
}
