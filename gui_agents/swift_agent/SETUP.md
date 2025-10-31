# Swift Agent S3 - Setup and Testing Guide

## Prerequisites

- macOS 13.0 or later
- Swift 5.9 or later
- Xcode 15.0 or later (for building)
- Screen Recording permission
- Accessibility permission

## Installation

### 1. Set Up API Keys

Create a `.env` file in the `gui_agents/swift_agent` directory:

```bash
# OpenAI API Key (for generation and grounding)
OPENAI_API_KEY=your_openai_api_key_here

# Anthropic API Key (optional, if using Claude)
ANTHROPIC_API_KEY=your_anthropic_api_key_here
```

Alternatively, export them as environment variables:

```bash
export OPENAI_API_KEY="your_openai_api_key_here"
export ANTHROPIC_API_KEY="your_anthropic_api_key_here"
```

### 2. Grant Permissions

#### Screen Recording Permission
1. System Settings → Privacy & Security → Screen Recording
2. Enable for Terminal (or your IDE)
3. Restart Terminal/IDE

#### Accessibility Permission
1. System Settings → Privacy & Security → Accessibility
2. Enable for Terminal (or your IDE)
3. Restart Terminal/IDE

### 3. Build the Package

```bash
cd gui_agents/swift_agent
swift build
```

### 4. Run the Agent

#### Basic Usage

```bash
swift run agent-s3 "Click on the login button"
```

#### With Custom Configuration

The CLI accepts arguments via command line:

```bash
swift run agent-s3 \
  --provider openai \
  --model gpt-4o \
  --ground_provider openai \
  --ground_model gpt-4o \
  --grounding_width 1000 \
  --grounding_height 1000 \
  "Open Safari and navigate to google.com"
```

## Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `OPENAI_API_KEY` | OpenAI API key | Yes (if using OpenAI) |
| `ANTHROPIC_API_KEY` | Anthropic API key | Yes (if using Anthropic) |

### API Provider Configuration

The agent uses two LLM instances:

1. **Generation Model**: Used by the Worker agent for planning and reflection
   - Default: OpenAI GPT-4o
   - Configurable via `--provider` and `--model` flags

2. **Grounding Model**: Used by the Grounding agent for coordinate generation
   - Default: OpenAI GPT-4o
   - Configurable via `--ground_provider` and `--ground_model` flags

## Testing

### 1. Simple Test

Run a simple task:

```bash
swift run agent-s3 "Take a screenshot"
```

### 2. Interactive Test

The agent runs for up to 15 steps. You can pause/resume using Ctrl+C:
- Press Ctrl+C once to pause
- Press Esc to resume
- Press Ctrl+C twice to quit

### 3. Verify Actions

Watch the terminal output for:
- `🔄 Step X/15: Getting next action from agent...`
- `EXECUTING CODE: ...`
- Action execution results

## Troubleshooting

### "Could not capture screenshot"
- Ensure Screen Recording permission is granted
- Restart Terminal after granting permission

### "Accessibility permission denied"
- Ensure Accessibility permission is granted
- Restart Terminal after granting permission

### "API key not found"
- Check `.env` file exists and contains `OPENAI_API_KEY`
- Or export environment variables before running

### Build Errors
- Ensure Swift 5.9+ is installed: `swift --version`
- Clean and rebuild: `swift package clean && swift build`

## Project Structure

```
swift_agent/
├── Sources/
│   └── AgentS3Swift/
│       └── main.swift          # Entry point
├── Agents/                     # Agent implementations
├── Core/                       # Core LLM infrastructure
├── Memory/                     # System prompts
├── Utils/                      # Utilities
├── CLI/                        # CLI components
├── Types/                      # Data types
├── Package.swift               # Swift Package manifest
└── SETUP.md                    # This file
```

## Next Steps

1. **Test Basic Actions**: Try simple click/type actions
2. **Test Code Agent**: Enable local environment for code execution
3. **Customize Prompts**: Modify `Memory/ProceduralMemory.swift`
4. **Add Logging**: Implement file-based logging (currently prints to console)

## Development Notes

- The implementation uses native Swift APIs instead of Python bindings
- Action execution happens via CGEvent (macOS native)
- Screenshots use CGWindowListCreateImage
- OCR uses Vision framework
- Code execution uses Process class for Python/Bash

