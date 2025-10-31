import Foundation

/// Code Agent for executing Python/Bash code with a budget of steps
class CodeAgent {
    private var engineParams: [String: Any]
    private var budget: Int
    private var agent: LLMAgent?
    
    init(engineParams: [String: Any], budget: Int = 20) throws {
        self.engineParams = engineParams
        self.budget = budget
        reset()
    }
    
    func reset() {
        var params = engineParams
        params["system_prompt"] = ProceduralMemory.CODE_AGENT_PROMPT
        do {
            self.agent = try LLMAgent(engineParams: params)
        } catch {
            print("Error initializing CodeAgent: \(error)")
        }
    }
    
    /// Execute code for the given task with a budget of steps
    /// - Parameters:
    ///   - taskInstruction: Task instruction to execute
    ///   - screenshot: Screenshot data for context
    ///   - envController: Environment controller (optional, for now simplified)
    /// - Returns: Execution result dictionary
    func execute(taskInstruction: String, screenshot: Data, envController: Any? = nil) async throws -> [String: Any] {
        print("\n🚀 STARTING CODE EXECUTION")
        print("=" + String(repeating: "=", count: 60))
        print("Task: \(taskInstruction)")
        print("Budget: \(budget) steps")
        print("=" + String(repeating: "=", count: 60))
        
        reset()
        
        guard let agent = agent else {
            throw CodeAgentError.agentNotInitialized
        }
        
        // Add initial task instruction and screenshot context
        let context = "Task: \(taskInstruction)\n\nCurrent screenshot is provided for context."
        agent.addMessage(
            textContent: context,
            imageContent: screenshot,
            role: "user"
        )
        
        var stepCount = 0
        var executionHistory: [[String: Any]] = []
        var completionReason: String?
        
        while stepCount < budget {
            print("\nStep \(stepCount + 1)/\(budget)")
            
            // Get assistant response
            let response = await LLMUtils.callLLMSafe(agent, temperature: 1.0)
            
            // Print to terminal for visibility
            print("\n🤖 CODING AGENT RESPONSE - Step \(stepCount + 1)/\(budget)")
            print("=" + String(repeating: "=", count: 60))
            print(response)
            print("=" + String(repeating: "=", count: 60))
            
            if response.isEmpty {
                throw CodeAgentError.emptyResponse(step: stepCount + 1)
            }
            
            // Parse response
            let (thoughts, action) = LLMUtils.splitThinkingResponse(response)
            
            executionHistory.append([
                "step": stepCount + 1,
                "action": action,
                "thoughts": thoughts
            ])
            
            // Check for completion signals
            let actionUpper = action.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if actionUpper == "DONE" {
                print("\n✅ TASK COMPLETED - Step \(stepCount + 1)")
                print("=" + String(repeating: "=", count: 60))
                print("Agent signaled task completion")
                print("=" + String(repeating: "=", count: 60))
                completionReason = "DONE"
                break
            } else if actionUpper == "FAIL" {
                print("\n❌ TASK FAILED - Step \(stepCount + 1)")
                print("=" + String(repeating: "=", count: 60))
                print("Agent signaled task failure")
                print("=" + String(repeating: "=", count: 60))
                completionReason = "FAIL"
                break
            }
            
            // Extract and execute code
            let (codeType, code) = CodeUtils.extractCodeBlock(action)
            
            var result: [String: Any]
            if let code = code, let codeType = codeType {
                // Execute code
                if codeType == "python" {
                    result = await CodeExecutor.executePython(code)
                } else if codeType == "bash" {
                    result = await CodeExecutor.executeBash(code)
                } else {
                    result = [
                        "status": "error",
                        "error": "Unknown code type: \(codeType)"
                    ]
                }
                
                // Print execution result
                print("\n⚡ CODE EXECUTION RESULT - Step \(stepCount + 1)")
                print("-" + String(repeating: "-", count: 50))
                if let status = result["status"] as? String {
                    print("Status: \(status)")
                }
                if let output = result["output"] as? String, !output.isEmpty {
                    print("Output:\n\(output)")
                }
                if let error = result["error"] as? String, !error.isEmpty {
                    print("Error:\n\(error)")
                }
                print("-" + String(repeating: "-", count: 50))
            } else {
                print("\n⚠️  NO CODE BLOCK FOUND - Step \(stepCount + 1)")
                print("-" + String(repeating: "-", count: 50))
                print("Action did not contain executable code")
                print("-" + String(repeating: "-", count: 50))
                
                result = [
                    "status": "skipped",
                    "message": "No code block found"
                ]
            }
            
            // Add assistant response to history
            agent.addMessage(textContent: response, role: "assistant")
            
            // Add execution result to history
            let resultContext = CodeUtils.formatExecutionResult(result, stepCount: stepCount)
            agent.addMessage(textContent: resultContext, role: "user")
            
            stepCount += 1
        }
        
        // Handle budget exhaustion
        if completionReason == nil {
            print("\n⏰ BUDGET EXHAUSTED - \(stepCount) steps completed")
            print("=" + String(repeating: "=", count: 60))
            print("Maximum budget of \(budget) steps reached")
            print("=" + String(repeating: "=", count: 60))
            completionReason = "BUDGET_EXHAUSTED_AFTER_\(stepCount)_STEPS"
        }
        
        // Generate final summary
        let summary = await generateSummary(executionHistory: executionHistory, taskInstruction: taskInstruction)
        
        let finalResult: [String: Any] = [
            "task_instruction": taskInstruction,
            "completion_reason": completionReason ?? "UNKNOWN",
            "summary": summary,
            "execution_history": executionHistory,
            "steps_executed": stepCount,
            "budget": budget
        ]
        
        return finalResult
    }
    
    /// Generate summary of code execution session
    private func generateSummary(executionHistory: [[String: Any]], taskInstruction: String) async -> String {
        if executionHistory.isEmpty {
            return "No actions were executed."
        }
        
        // Build execution context
        var executionContext = "Task: \(taskInstruction)\n\nExecution Steps:\n"
        
        for step in executionHistory {
            let stepNum = step["step"] as? Int ?? 0
            let thoughts = step["thoughts"] as? String ?? ""
            let action = step["action"] as? String ?? ""
            
            executionContext += "\nStep \(stepNum):\n"
            if !thoughts.isEmpty {
                executionContext += "Thoughts: \(thoughts)\n"
            }
            executionContext += "Code: \(action)\n"
        }
        
        // Create summary prompt
        let summaryPrompt = """
        \(executionContext)
        
        Please provide a concise summary of the code execution session. Focus on:
        
        1. The code logic implemented at each step
        2. The outputs and results produced by each code execution
        3. The progression of the solution approach
        
        Do not make judgments about success or failure. Simply describe what was attempted and what resulted.
        
        Keep the summary under 150 words and use clear, factual language.
        """
        
        // Generate summary using LLM
        do {
            var summaryParams = engineParams
            summaryParams["system_prompt"] = ProceduralMemory.CODE_SUMMARY_AGENT_PROMPT
            let summaryAgent = try LLMAgent(engineParams: summaryParams)
            summaryAgent.addMessage(textContent: summaryPrompt, role: "user")
            let summary = await LLMUtils.callLLMSafe(summaryAgent, temperature: 1.0)
            
            if summary.isEmpty {
                return "Summary generation failed - no response from LLM"
            }
            
            return summary
        } catch {
            return "Summary generation failed: \(error.localizedDescription)"
        }
    }
}

enum CodeAgentError: Error {
    case agentNotInitialized
    case emptyResponse(step: Int)
}
