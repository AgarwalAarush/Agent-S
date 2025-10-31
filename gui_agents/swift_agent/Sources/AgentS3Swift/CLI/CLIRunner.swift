import Foundation
import AppKit
import CoreGraphics

/// CLI runner for Agent S3
/// Main entry point for running the agent from command line
class CLIRunner {
    private var agent: AgentS3?
    private var paused = false
    private var instruction: String = ""
    private var scaledWidth: Int = 1000
    private var scaledHeight: Int = 1000
    
    /// Run the agent with command-line arguments
    /// - Parameter arguments: Command-line arguments
    func run(arguments: [String]) async throws {
        // Parse arguments (simplified for now)
        // In production, would use ArgumentParser or similar
        var engineParamsForGeneration: [String: Any] = [:]
        var engineParamsForGrounding: [String: Any] = [:]
        let platform = "darwin"
        let width = 1920
        let height = 1080
        let maxTrajectoryLength = 8
        let enableReflection = true
        let codeAgentBudget = 20
        
        // Parse arguments (simplified)
        // Would need proper argument parsing in production
        if arguments.count < 2 {
            print("Usage: \(arguments[0]) <instruction>")
            return
        }
        
        instruction = arguments[1]
        
        // Read API keys from environment
        let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        let anthropicKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        
        // Default to OpenAI if no key specified, check which one is available
        if openAIKey.isEmpty && anthropicKey.isEmpty {
            print("⚠️  ERROR: No API key found!")
            print("Please set one of:")
            print("  export OPENAI_API_KEY='your-key-here'")
            print("  export ANTHROPIC_API_KEY='your-key-here'")
            return
        }
        
        // Use OpenAI by default, or Anthropic if OpenAI not available
        let useOpenAI = !openAIKey.isEmpty
        
        if useOpenAI {
            engineParamsForGeneration = [
                "engine_type": "openai",
                "model": "gpt-5-nano-2025-08-07",
                "api_key": openAIKey
            ]

            engineParamsForGrounding = [
                "engine_type": "openai",
                "model": "gpt-5-nano-2025-08-07",
                "api_key": openAIKey,
                "grounding_width": 1000,
                "grounding_height": 1000
            ]
        } else {
            engineParamsForGeneration = [
                "engine_type": "anthropic",
                "model": "claude-sonnet-4-5-20250929",
                "api_key": anthropicKey,
                "temperature": 0.2,
                "top_p": 0.1
            ]

            engineParamsForGrounding = [
                "engine_type": "anthropic",
                "model": "claude-sonnet-4-5-20250929",
                "api_key": anthropicKey,
                "temperature": 0.2,
                "top_p": 0.1,
                "grounding_width": 1000,
                "grounding_height": 1000
            ]
        }
        
        print("✓ Using \(useOpenAI ? "OpenAI" : "Anthropic") API")
        
        // Scale screen dimensions
        let (scaledW, scaledH) = scaleScreenDimensions(width: width, height: height, maxDimSize: 1000)
        scaledWidth = scaledW
        scaledHeight = scaledH
        
        // Initialize agent
        do {
            agent = try AgentS3(
                engineParamsForGeneration: engineParamsForGeneration,
                engineParamsForGrounding: engineParamsForGrounding,
                platform: platform,
                width: width,
                height: height,
                maxTrajectoryLength: maxTrajectoryLength,
                enableReflection: enableReflection,
                codeAgentBudget: codeAgentBudget
            )
        } catch {
            print("Error initializing agent: \(error)")
            return
        }
        
        // Set up signal handler for pause/resume
        setupSignalHandler()
        
        // Run agent
        try await runAgent()
    }
    
    /// Scale screen dimensions to fit within max dimension
    /// - Parameters:
    ///   - width: Screen width
    ///   - height: Screen height
    ///   - maxDimSize: Maximum dimension size
    /// - Returns: Scaled (width, height)
    private func scaleScreenDimensions(width: Int, height: Int, maxDimSize: Int) -> (width: Int, height: Int) {
        let scaleFactor = min(Double(maxDimSize) / Double(width), Double(maxDimSize) / Double(height), 1.0)
        let safeWidth = Int(Double(width) * scaleFactor)
        let safeHeight = Int(Double(height) * scaleFactor)
        return (safeWidth, safeHeight)
    }
    
    /// Set up signal handler for pause/resume
    private func setupSignalHandler() {
        // macOS signal handling would use DispatchSource or similar
        // Simplified for now - would need proper signal handling
    }
    
    /// Main agent loop
    private func runAgent() async throws {
        guard let agent = agent else {
            return
        }
        
        var obs = Observation(screenshot: Data())
        var trajectory = "Task:\n\(instruction)"
        var subtaskTrajectory = ""
        
        for step in 0..<15 {
            // Handle pause
            while paused {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
            
            // Get screenshot
            guard let screenshotData = ImageUtils.captureScreenshot() else {
                print("Error: Could not capture screenshot")
                continue
            }
            
            // Resize screenshot
            guard let resizedData = ImageUtils.resizeImage(screenshotData, maxWidth: scaledWidth, maxHeight: scaledHeight) else {
                print("Error: Could not resize screenshot")
                continue
            }
            
            obs = Observation(screenshot: resizedData)
            
            // Handle pause
            while paused {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            
            print("\n🔄 Step \(step + 1)/15: Getting next action from agent...")
            
            // Get next action from agent
            let (info, actions) = try await agent.predict(instruction: instruction, observation: obs)
            
            // Handle action results
            guard let actionCode = actions.first else {
                print("No action returned")
                continue
            }
            
            // Check for done/fail/next/wait actions
            let actionUpper = actionCode.uppercased().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            if actionUpper == "DONE" || actionUpper.hasPrefix("DONE") {
                print("\n✅ Task completed!")
                break
            } else if actionUpper == "FAIL" || actionUpper.hasPrefix("FAIL") {
                print("\n❌ Task failed!")
                break
            } else if actionUpper == "NEXT" || actionUpper.hasPrefix("NEXT") {
                print("\n➡️  Moving to next step...")
                continue
            } else if actionUpper == "WAIT" || actionUpper.hasPrefix("WAIT") {
                print("\n⏸️  Waiting...")
                let waitTime = parseWaitTime(from: actionCode)
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                continue
            }
            
            // Handle pause before execution
            while paused {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            
            // Execute action
            print("EXECUTING CODE: \(actionCode)")
            
            // Execute action code using Grounding agent's executeActionCode
            do {
                try agent.groundingAgent.executeActionCode(actionCode)
            } catch {
                print("⚠️  Error executing action code: \(error)")
                // Continue anyway - don't crash
            }
            
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            
            // Update trajectory
            if let plan = info["plan"] as? String {
                trajectory += "\n\nStep \(step + 1):\n\(plan)"
            }
            if let execCode = info["exec_code"] as? String {
                subtaskTrajectory += "\nStep \(step + 1) Action:\n\(execCode)\n"
            }
        }
        
        print("\n📊 Final Trajectory:")
        print(trajectory)
    }
    
    /// Parse wait time from action code
    /// - Parameter code: Action code string
    /// - Returns: Wait time in seconds
    private func parseWaitTime(from code: String) -> Double {
        // Parse WAIT(seconds) format
        let pattern = #"WAIT\(([\d.]+)\)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: code, options: [], range: NSRange(code.startIndex..., in: code)),
           let timeRange = Range(match.range(at: 1), in: code),
           let time = Double(String(code[timeRange])) {
            return time
        }
        return 1.0 // Default wait time
    }
}
