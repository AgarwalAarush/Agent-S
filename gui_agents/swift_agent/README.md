# Swift Agent S3 Implementation

This is a Swift port of the Python Agent S3 codebase, implementing a GUI automation agent that can interact with desktop applications using visual grounding and LLM-based action generation.

## Architecture

The Swift implementation follows the same architecture as the Python version but uses native Swift APIs:

- **Core LLM Infrastructure**: URLSession-based HTTP clients for OpenAI and Anthropic APIs
- **Action System**: Structured Action enum replacing Python's eval() with type-safe parsing
- **Grounding Agent**: Visual grounding using LLM + Vision framework for OCR
- **Worker Agent**: Message management, reflection, and format validation
- **Code Agent**: Process-based Python/Bash execution
- **CLI Runner**: Command-line interface for running the agent

## Key Differences from Python

1. **eval() Replacement**: Uses structured Action enum and ActionParser instead of dynamic code evaluation
2. **Screenshots**: CGWindowListCreateImage instead of pyautogui
3. **OCR**: Vision framework instead of pytesseract
4. **Action Execution**: CGEvent instead of pyautogui
5. **Code Execution**: Process class instead of exec()
6. **HTTP/JSON**: URLSession + Codable instead of requests/json

## Directory Structure

```
gui_agents/swift_agent/
├── Agents/
│   ├── AgentS.swift           # Main agent class
│   ├── Worker.swift           # Worker agent
│   ├── Grounding.swift         # OSWorldACI equivalent
│   └── CodeAgent.swift        # Code execution agent
├── Core/
│   ├── LLMAgent.swift         # LLM wrapper
│   ├── BaseModule.swift       # Base module class
│   └── Engine/
│       ├── LLMEngine.swift     # Protocol
│       ├── OpenAIEngine.swift  # OpenAI implementation
│       └── AnthropicEngine.swift # Anthropic implementation
├── Memory/
│   └── ProceduralMemory.swift  # System prompts
├── Utils/
│   ├── CommonUtils.swift       # LLM calls, parsing
│   ├── Formatters.swift        # Format validation
│   ├── ActionParser.swift      # Action parsing
│   ├── ImageUtils.swift        # Screenshot, OCR
│   ├── CGEventExecutor.swift   # CGEvent execution
│   ├── CodeExecutor.swift      # Process execution
│   └── CreateActionCode.swift  # Action code creation
├── CLI/
│   └── CLIRunner.swift         # CLI entry point
└── Types/
    ├── Action.swift            # Action enum
    ├── Message.swift           # Message types
    ├── Observation.swift       # Observation structure
    └── AgentResponse.swift     # Response types
```

## Usage

```swift
let agent = try AgentS3(
    engineParamsForGeneration: generationParams,
    engineParamsForGrounding: groundingParams,
    platform: "darwin"
)

let obs = Observation(screenshot: screenshotData)
let (info, actions) = try await agent.predict(
    instruction: "Click on the login button",
    observation: obs
)
```

## Requirements

- macOS (for CGEvent and Vision framework)
- Swift 5.9+
- Screen recording permission (required for screenshot capture)
- Accessibility permission (required for CGEvent automation)

## Status

All core components have been implemented:
- ✅ Core LLM infrastructure
- ✅ Action parsing and execution
- ✅ Grounding agent with visual grounding
- ✅ Worker agent with reflection
- ✅ Code agent with Process execution
- ✅ CLI runner
- ✅ Procedural memory system prompts

## Next Steps

1. Add comprehensive error handling
2. Implement full argument parsing in CLI
3. Add unit tests
4. Add integration tests
5. Implement remaining action types
6. Add proper signal handling for pause/resume
7. Complete CGEvent executor implementation

