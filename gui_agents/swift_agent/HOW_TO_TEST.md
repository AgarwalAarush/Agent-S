# How to Test and Run Swift Agent S3

## ✅ Everything is Implemented!

All core components are complete. Here's how to test and run:

## Step 1: Set Your API Key

```bash
export OPENAI_API_KEY="sk-your-openai-key-here"
```

Or for Anthropic:

```bash
export ANTHROPIC_API_KEY="sk-ant-your-anthropic-key-here"
```

**Where to get API keys:**
- OpenAI: https://platform.openai.com/api-keys
- Anthropic: https://console.anthropic.com/settings/keys

## Step 2: Grant macOS Permissions

The agent needs two permissions:

### Screen Recording
1. System Settings → Privacy & Security → Screen Recording
2. Enable for Terminal
3. **Restart Terminal**

### Accessibility  
1. System Settings → Privacy & Security → Accessibility
2. Enable for Terminal
3. **Restart Terminal**

## Step 3: Test Build

First, verify everything compiles:

```bash
cd gui_agents/swift_agent
./test_build.sh
```

Or manually:

```bash
cd gui_agents/swift_agent
swift build
```

## Step 4: Run the Agent

### Option A: Using the run script (easiest)

```bash
cd gui_agents/swift_agent
./run.sh "Click on the Safari icon in the dock"
```

### Option B: Using Swift directly

```bash
cd gui_agents/swift_agent
export OPENAI_API_KEY="sk-your-key-here"
swift run agent-s3 "Open Safari"
```

### Option C: Build then run

```bash
cd gui_agents/swift_agent
swift build
.build/debug/agent-s3 "Take a screenshot"
```

## Example Instructions to Test

Try these simple tasks:

```bash
# Simple click
./run.sh "Click on the Finder icon in the dock"

# Open an app
./run.sh "Open Safari"

# Type something
./run.sh "Open TextEdit, type 'Hello World' and press Enter"

# Screenshot
./run.sh "Take a screenshot"
```

## Expected Output

You should see:

```
✓ Using OpenAI API
🔨 Building Swift package...
🚀 Running agent with instruction: ...
🔄 Step 1/15: Getting next action from agent...
EXECUTING CODE: CLICK(960, 540, ...)
```

## Troubleshooting

### "OPENAI_API_KEY environment variable not set"
→ Make sure you exported the key:
```bash
export OPENAI_API_KEY="sk-your-key-here"
echo $OPENAI_API_KEY  # Should print your key
```

### "Could not capture screenshot"
→ Grant Screen Recording permission and **restart Terminal**

### "Build failed"
→ Check Swift version:
```bash
swift --version  # Should be 5.9+
```

### Permission errors
→ Grant Accessibility permission and **restart Terminal**

### Files not found errors
→ Make sure all files are in `Sources/AgentS3Swift/`:
```bash
cd gui_agents/swift_agent
# Move files if needed:
mkdir -p Sources/AgentS3Swift
cp -r Agents Core Utils CLI Types Memory Sources/AgentS3Swift/
```

## Project Structure

Make sure your structure looks like this:

```
swift_agent/
├── Sources/
│   └── AgentS3Swift/
│       ├── main.swift
│       ├── Agents/
│       ├── Core/
│       ├── Utils/
│       ├── CLI/
│       ├── Types/
│       └── Memory/
├── Package.swift
├── run.sh
├── test_build.sh
└── QUICK_START.md
```

## Next Steps

1. ✅ Set API key
2. ✅ Grant permissions  
3. ✅ Test build
4. ✅ Run simple test
5. 🎉 Start automating!

## Documentation

- `QUICK_START.md` - Quick reference
- `SETUP.md` - Detailed setup guide
- `README.md` - Architecture overview

