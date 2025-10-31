import Foundation

/// Worker agent that generates next actions based on observations
class Worker: BaseModule {
    private var temperature: Double
    private var useThinking: Bool
    private var groundingAgent: OSWorldACI
    private var maxTrajectoryLength: Int
    private var enableReflection: Bool
    
    private var generatorAgent: LLMAgent?
    private var reflectionAgent: LLMAgent?
    private var turnCount: Int = 0
    private var workerHistory: [String] = []
    private var reflections: [String] = []
    private var screenshotInputs: [Data] = []
    
    init(
        workerEngineParams: [String: Any],
        groundingAgent: OSWorldACI,
        platform: String = "darwin",
        maxTrajectoryLength: Int = 8,
        enableReflection: Bool = true
    ) throws {
        let temperature = workerEngineParams["temperature"] as? Double ?? 1.0
        let model = workerEngineParams["model"] as? String ?? ""
        let useThinking = [
            "claude-opus-4-20250514",
            "claude-sonnet-4-20250514",
            "claude-3-7-sonnet-20250219",
            "claude-sonnet-4-5-20250929"
        ].contains(model)
        
        self.temperature = temperature
        self.useThinking = useThinking
        self.groundingAgent = groundingAgent
        self.maxTrajectoryLength = maxTrajectoryLength
        self.enableReflection = enableReflection
        
        super.init(engineParams: workerEngineParams, platform: platform)
        
        reset()
    }
    
    func reset() {
        var skippedActions: [String] = []
        
        if platform != "linux" {
            skippedActions.append("set_cell_values")
        }
        
        // Hide code agent action if not available
        // (simplified for now - would need to check for env/controller)
        
        let sysPrompt = ProceduralMemory.constructSimpleWorkerProceduralMemory(
            agentClass: OSWorldACI.self,
            skippedActions: skippedActions,
            platform: platform
        ).replacingOccurrences(of: "CURRENT_OS", with: platform)
        
        do {
            self.generatorAgent = try createAgent(systemPrompt: sysPrompt, engineParams: nil)
            self.reflectionAgent = try createAgent(systemPrompt: ProceduralMemory.REFLECTION_ON_TRAJECTORY, engineParams: nil)
        } catch {
            print("Error initializing Worker agents: \(error)")
        }
        
        self.turnCount = 0
        self.workerHistory = []
        self.reflections = []
        self.screenshotInputs = []
    }
    
    /// Flush messages to fit within context limits
    func flushMessages() {
        guard let generatorAgent = generatorAgent,
              let reflectionAgent = reflectionAgent else {
            return
        }
        
        let engineType = engineParams["engine_type"] as? String ?? ""
        
        // Flush strategy for long-context models: keep all text, only keep latest images
        if ["anthropic", "openai", "gemini"].contains(engineType) {
            let maxImages = maxTrajectoryLength
            for agent in [generatorAgent, reflectionAgent] {
                var imgCount = 0
                // Iterate messages in reverse to remove oldest images first
                var messagesToKeep: [Message] = []
                for message in agent.messages.reversed() {
                    var contentToKeep: [ContentItem] = []
                    for item in message.content {
                        switch item {
                        case .image:
                            imgCount += 1
                            if imgCount <= maxImages {
                                contentToKeep.append(item)
                            }
                        case .text:
                            contentToKeep.append(item)
                        }
                    }
                    if !contentToKeep.isEmpty {
                        messagesToKeep.insert(Message(role: message.role, content: contentToKeep), at: 0)
                    }
                }
                agent.messages = messagesToKeep
            }
        } else {
            // Flush strategy for non-long-context models: drop full turns
            // Generator messages are alternating [user, assistant], so 2 per round
            if generatorAgent.messages.count > 2 * maxTrajectoryLength + 1 {
                generatorAgent.messages.remove(at: 1)
                generatorAgent.messages.remove(at: 1)
            }
            // Reflection messages are all [(user text, user image)], so 1 per round
            if reflectionAgent.messages.count > maxTrajectoryLength + 1 {
                reflectionAgent.messages.remove(at: 1)
            }
        }
    }
    
    /// Generate reflection on trajectory
    /// - Parameters:
    ///   - instruction: Task instruction
    ///   - obs: Current observation
    /// - Returns: Tuple of (reflection text, reflection thoughts)
    func generateReflection(instruction: String, obs: Observation) async -> (reflection: String?, thoughts: String?) {
        guard enableReflection, let reflectionAgent = reflectionAgent else {
            return (nil, nil)
        }
        
        if turnCount == 0 {
            // Initial message
            let textContent = """
            Task Description: \(instruction)
            Current Trajectory below:
            """
            let updatedSysPrompt = reflectionAgent.systemPrompt + "\n" + textContent
            reflectionAgent.addSystemPrompt(updatedSysPrompt)
            reflectionAgent.addMessage(
                textContent: "The initial screen is provided. No action has been taken yet.",
                imageContent: obs.screenshot,
                role: "user"
            )
            return (nil, nil)
        } else {
            // Add latest action
            reflectionAgent.addMessage(
                textContent: workerHistory.last ?? "",
                imageContent: obs.screenshot,
                role: "user"
            )
            
            let fullReflection = await LLMUtils.callLLMSafe(
                reflectionAgent,
                temperature: temperature,
                useThinking: useThinking
            )
            
            let (thoughts, reflection) = LLMUtils.splitThinkingResponse(fullReflection)
            reflections.append(reflection)
            
            print("REFLECTION THOUGHTS: \(thoughts)")
            print("REFLECTION: \(reflection)")
            
            return (reflection, thoughts)
        }
    }
    
    /// Generate next action based on observation
    /// - Parameters:
    ///   - instruction: Task instruction
    ///   - obs: Current observation
    /// - Returns: Tuple of (executor info, actions list)
    func generateNextAction(instruction: String, obs: Observation) async throws -> ([String: Any], [String]) {
        guard let generatorAgent = generatorAgent else {
            throw WorkerError.agentNotInitialized
        }
        
        groundingAgent.assignScreenshot(obs)
        groundingAgent.setTaskInstruction(instruction)
        
        var generatorMessage = turnCount > 0 ? "" : "The initial screen is provided. No action has been taken yet."
        
        // Load task into system prompt
        if turnCount == 0 {
            let promptWithInstructions = generatorAgent.systemPrompt.replacingOccurrences(of: "TASK_DESCRIPTION", with: instruction)
            generatorAgent.addSystemPrompt(promptWithInstructions)
        }
        
        // Get per-step reflection
        let (reflection, reflectionThoughts) = await generateReflection(instruction: instruction, obs: obs)
        if let reflection = reflection {
            generatorMessage += "REFLECTION: You may use this reflection on the previous action and overall trajectory:\n\(reflection)\n"
        }
        
        // Get grounding agent's knowledge base buffer
        generatorMessage += "\nCurrent Text Buffer = [\(groundingAgent.notes.joined(separator: ","))]\n"
        
        // Add code agent result from previous step if available
        if let codeAgentResult = groundingAgent.lastCodeAgentResult {
            generatorMessage += "\nCODE AGENT RESULT:\n"
            generatorMessage += "Task/Subtask Instruction: \(codeAgentResult["task_instruction"] as? String ?? "")\n"
            generatorMessage += "Steps Completed: \(codeAgentResult["steps_executed"] as? Int ?? 0)\n"
            generatorMessage += "Max Steps: \(codeAgentResult["budget"] as? Int ?? 0)\n"
            generatorMessage += "Completion Reason: \(codeAgentResult["completion_reason"] as? String ?? "")\n"
            generatorMessage += "Summary: \(codeAgentResult["summary"] as? String ?? "")\n"
            
            if let executionHistory = codeAgentResult["execution_history"] as? [[String: Any]] {
                generatorMessage += "Execution History:\n"
                for (i, step) in executionHistory.enumerated() {
                    let action = step["action"] as? String ?? ""
                    
                    // Format code snippets
                    if action.contains("```python") {
                        let parts = action.components(separatedBy: "```python")
                        if parts.count > 1 {
                            let codePart = parts[1].components(separatedBy: "```").first ?? ""
                            generatorMessage += "Step \(i + 1): \n```python\n\(codePart)\n```\n"
                        }
                    } else if action.contains("```bash") {
                        let parts = action.components(separatedBy: "```bash")
                        if parts.count > 1 {
                            let codePart = parts[1].components(separatedBy: "```").first ?? ""
                            generatorMessage += "Step \(i + 1): \n```bash\n\(codePart)\n```\n"
                        }
                    } else {
                        generatorMessage += "Step \(i + 1): \n\(action)\n"
                    }
                }
            }
            generatorMessage += "\n"
            
            // Reset code agent result after adding to context
            groundingAgent.lastCodeAgentResult = nil
        }
        
        // Finalize generator message
        generatorAgent.addMessage(
            textContent: generatorMessage,
            imageContent: obs.screenshot,
            role: "user"
        )
        
        // Generate plan and next action with format validation
        let formatCheckers: [(String) -> (success: Bool, feedback: String)] = [
            Formatters.SingleActionFormatter.check,
            { [self] response in
                Formatters.CodeValidFormatter(agent: self.groundingAgent, obs: obs).check(response)
            }
        ]
        
        let plan = await Formatters.callLLMFormatted(
            generatorAgent,
            formatCheckers: formatCheckers,
            temperature: temperature,
            useThinking: useThinking
        )
        
        workerHistory.append(plan)
        generatorAgent.addMessage(textContent: plan, role: "assistant")
        print("PLAN:\n\(plan)")
        
        // Extract next action from plan
        let planCode = LLMUtils.parseCodeFromString(plan)
        guard !planCode.isEmpty else {
            throw WorkerError.emptyPlanCode
        }
        
        var execCode: String
        do {
            execCode = try await CreateActionCode.createActionCode(agent: groundingAgent, code: planCode, obs: obs)
        } catch {
            print("Could not evaluate plan code: \(planCode)\nError: \(error)")
            // Skip turn if code cannot be evaluated
            execCode = "WAIT(1.333)"
        }
        
        let executorInfo: [String: Any] = [
            "plan": plan,
            "plan_code": planCode,
            "exec_code": execCode,
            "reflection": reflection ?? "",
            "reflection_thoughts": reflectionThoughts ?? "",
            "code_agent_output": groundingAgent.lastCodeAgentResult as Any
        ]
        
        turnCount += 1
        screenshotInputs.append(obs.screenshot)
        flushMessages()
        
        return (executorInfo, [execCode])
    }
}

enum WorkerError: Error {
    case agentNotInitialized
    case emptyPlanCode
}

extension OSWorldACI {
    var lastCodeAgentResult: [String: Any]? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.lastCodeAgentResult) as? [String: Any]
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.lastCodeAgentResult, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

private struct AssociatedKeys {
    static var lastCodeAgentResult = "lastCodeAgentResult"
}

#if canImport(ObjectiveC)
import ObjectiveC
#endif
