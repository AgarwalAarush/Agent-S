# 🚀 Quick Start - Swift Agent S3

## ✅ Everything is Implemented!

All components are complete. Here's how to test and run:

## Step 1: Set Your API Key

```bash
export OPENAI_API_KEY="sk-your-openai-key-here"
```

**OR** for Anthropic:

```bash
export ANTHROPIC_API_KEY="sk-ant-your-anthropic-key-here"
```

**Where to get API keys:**
- OpenAI: https://platform.openai.com/api-keys
- Anthropic: https://console.anthropic.com/settings/keys

## Step 2: Grant macOS Permissions

1. **Screen Recording Permission**
   - System Settings → Privacy & Security → Screen Recording
   - Enable for Terminal
   - **Restart Terminal**

2. **Accessibility Permission**
   - System Settings → Privacy & Security → Accessibility
   - Enable for Terminal
   - **Restart Terminal**

## Step 3: Test Build

```bash
./test_build.sh
```

Or manually:

```bash
swift build
```

## Step 4: Run!

### Easiest way:

```bash
./run.sh "Click on the Safari icon in the dock"
```

### Or directly with Swift:

```bash
export OPENAI_API_KEY="sk-your-key-here"
swift run agent-s3 "Open Safari"
```

## Example Instructions

Try these:

```bash
# Simple click
./run.sh "Click on the Finder icon"

# Open an app
./run.sh "Open Safari"

# Type something
./run.sh "Open TextEdit and type 'Hello World'"
```

## Troubleshooting

### "API key not found"
→ Export your API key:
```bash
export OPENAI_API_KEY="sk-your-key-here"
echo $OPENAI_API_KEY  # Verify it's set
```

### "Could not capture screenshot"
→ Grant Screen Recording permission and **restart Terminal**

### "Build failed"
→ Check Swift version: `swift --version` (need 5.9+)

### "Permission denied"
→ Grant Accessibility permission and **restart Terminal**

## File Structure

Make sure all files are in `Sources/AgentS3Swift/`:

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
└── run.sh
```

If files are missing, run:

```bash
mkdir -p Sources/AgentS3Swift
cp -r Agents Core Utils CLI Types Memory Sources/AgentS3Swift/
```

## Next Steps

1. ✅ Set API key (`export OPENAI_API_KEY="sk-..."`)
2. ✅ Grant permissions (Screen Recording + Accessibility)
3. ✅ Test build (`./test_build.sh`)
4. ✅ Run! (`./run.sh "your instruction"`)

## Documentation

- `QUICK_START.md` - Quick reference
- `HOW_TO_TEST.md` - Detailed testing guide
- `SETUP.md` - Full setup instructions
- `README.md` - Architecture overview

