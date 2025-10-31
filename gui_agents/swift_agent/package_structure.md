# Package Structure

The Swift Package Manager requires all source files to be under `Sources/AgentS3Swift/`.

**Current structure** (incorrect for SPM):
```
swift_agent/
├── Agents/
├── Core/
├── Utils/
├── CLI/
├── Types/
├── Memory/
└── Sources/
```

**Required structure** (for SPM):
```
swift_agent/
└── Sources/
    └── AgentS3Swift/
        ├── main.swift
        ├── Agents/
        ├── Core/
        ├── Utils/
        ├── CLI/
        ├── Types/
        └── Memory/
```

## Quick Fix

Run this command to move all files:

```bash
cd gui_agents/swift_agent
mkdir -p Sources/AgentS3Swift
mv Agents Core Utils CLI Types Memory Sources/AgentS3Swift/
```

Or manually copy each directory:
```bash
cp -r Agents Core Utils CLI Types Memory Sources/AgentS3Swift/
```

