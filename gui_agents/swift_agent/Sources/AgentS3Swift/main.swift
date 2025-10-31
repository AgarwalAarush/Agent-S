import Foundation

// Main entry point - imports all modules
// Note: In a real Swift package, these would be separate modules
// For now, we'll consolidate everything into one target

let runner = CLIRunner()

// Read API key from environment
let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""

if openAIKey.isEmpty {
    print("⚠️  ERROR: OPENAI_API_KEY environment variable not set")
    print("\nPlease set your OpenAI API key:")
    print("  export OPENAI_API_KEY='your-api-key-here'")
    print("\nOr create a .env file (see SETUP.md)")
    exit(1)
}

Task {
    do {
        try await runner.run(arguments: CommandLine.arguments)
    } catch {
        print("❌ Error: \(error)")
        exit(1)
    }
}

RunLoop.main.run()
