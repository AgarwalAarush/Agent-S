# Quick Start Guide

## 1. Set Your API Key

```bash
export OPENAI_API_KEY="sk-your-key-here"
```

Or for Anthropic:

```bash
export ANTHROPIC_API_KEY="sk-ant-your-key-here"
```

## 2. Test the Agent

### Option A: Using the run script

```bash
cd gui_agents/swift_agent
./run.sh "Click on the Safari icon in the dock"
```

### Option B: Using Swift directly

```bash
cd gui_agents/swift_agent
swift run agent-s3 "Take a screenshot"
```

## 3. Example Instructions

Try these simple tasks:

```bash
# Click an icon
./run.sh "Click on the Finder icon in the dock"

# Open an app
./run.sh "Open Safari"

# Type something
./run.sh "Open TextEdit and type 'Hello World'"

# Take screenshot
./run.sh "Take a screenshot of the desktop"
```

## 4. Check Permissions

The agent needs two macOS permissions:

1. **Screen Recording**: 
   - System Settings → Privacy & Security → Screen Recording
   - Enable for Terminal
   - Restart Terminal

2. **Accessibility**:
   - System Settings → Privacy & Security → Accessibility  
   - Enable for Terminal
   - Restart Terminal

## Troubleshooting

### "Could not capture screenshot"
→ Grant Screen Recording permission and restart Terminal

### "API key not found"
→ Make sure you've exported OPENAI_API_KEY or ANTHROPIC_API_KEY

### Build errors
→ Make sure you're using Swift 5.9+: `swift --version`

### Permission errors
→ Restart Terminal after granting permissions

## Next Steps

- Read `SETUP.md` for detailed configuration
- Read `README.md` for architecture details
- Check the logs for debugging information

