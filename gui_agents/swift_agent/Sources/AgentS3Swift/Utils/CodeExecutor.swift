import Foundation

/// Code executor for running Python/Bash scripts
class CodeExecutor {
    
    /// Execute Python script
    /// - Parameters:
    ///   - code: Python code string to execute
    ///   - timeout: Timeout in seconds (default 30)
    /// - Returns: Execution result dictionary
    static func executePython(_ code: String, timeout: TimeInterval = 30) async -> [String: Any] {
        return await executeScript(command: "/usr/bin/python3", args: ["-c", code], timeout: timeout)
    }
    
    /// Execute Bash script
    /// - Parameters:
    ///   - code: Bash commands to execute
    ///   - timeout: Timeout in seconds (default 30)
    /// - Returns: Execution result dictionary
    static func executeBash(_ code: String, timeout: TimeInterval = 30) async -> [String: Any] {
        return await executeScript(command: "/bin/bash", args: ["-c", code], timeout: timeout)
    }
    
    /// Execute a script using Process
    /// - Parameters:
    ///   - command: Command to execute (e.g., /usr/bin/python3)
    ///   - args: Arguments to pass
    ///   - timeout: Timeout in seconds
    /// - Returns: Execution result dictionary
    private static func executeScript(command: String, args: [String], timeout: TimeInterval) async -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            
            // Wait for process with timeout
            var completed = false
            let deadline = Date(timeIntervalSinceNow: timeout)
            
            let task = Task {
                process.waitUntilExit()
                completed = true
            }
            
            // Check for timeout
            while !completed && Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
            
            if !completed {
                process.terminate()
                try? await Task.sleep(nanoseconds: 100_000_000)
                if process.isRunning {
                    process.terminate()
                }
                
                return [
                    "status": "timeout",
                    "returncode": -1,
                    "output": "",
                    "error": "Execution timed out after \(timeout) seconds"
                ]
            }
            
            // Read output
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: data, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            
            let status = process.terminationStatus == 0 ? "success" : "error"
            
            return [
                "status": status,
                "returncode": Int(process.terminationStatus),
                "output": output,
                "error": error
            ]
            
        } catch {
            return [
                "status": "error",
                "returncode": -1,
                "output": "",
                "error": error.localizedDescription
            ]
        }
    }
}

/// Helper to extract code block from action string
enum CodeUtils {
    static func extractCodeBlock(_ action: String) -> (codeType: String?, code: String?) {
        if action.contains("```python") {
            let parts = action.components(separatedBy: "```python")
            if parts.count > 1 {
                let codePart = parts[1].components(separatedBy: "```").first?.trimmingCharacters(in: .whitespacesAndNewlines)
                return ("python", codePart)
            }
        } else if action.contains("```bash") {
            let parts = action.components(separatedBy: "```bash")
            if parts.count > 1 {
                let codePart = parts[1].components(separatedBy: "```").first?.trimmingCharacters(in: .whitespacesAndNewlines)
                return ("bash", codePart)
            }
        } else if action.contains("```") {
            let parts = action.components(separatedBy: "```")
            if parts.count > 1 {
                let codePart = parts[1].components(separatedBy: "```").first?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (nil, codePart)
            }
        }
        
        return (nil, nil)
    }

    /// Format execution result into context string
    static func formatExecutionResult(_ result: [String: Any], stepCount: Int) -> String {
        guard !result.isEmpty else {
            return """
            Step \(stepCount + 1) Error:
            Error: No result returned from execution
            """
        }
        
        let status = result["status"] as? String ?? "unknown"
        let returnCode = result["returncode"] as? Int ?? result["return_code"] as? Int ?? -1
        let output = result["output"] as? String ?? ""
        let error = result["error"] as? String ?? ""
        
        var resultText = "Step \(stepCount + 1) Result:\n"
        resultText += "Status: \(status)\n"
        resultText += "Return Code: \(returnCode)\n"
        
        if !output.isEmpty {
            resultText += "Output:\n\(output)\n"
        }
        
        if !error.isEmpty {
            resultText += "Error:\n\(error)\n"
        }
        
        return resultText
    }
}
