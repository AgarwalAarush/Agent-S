# Integration Guide for Agent S

## Quick Start

### 1. Setup and Run the Grounding Model Server

```bash
cd grounding_model
./setup.sh          # First time only
./run.sh            # Start the server
```

The server will be available at: **http://localhost:8080**

### 2. Environment Configuration

The `.env` file in `grounding_model/` contains:

```bash
GROUNDING_URL=http://localhost:8080
PORT=8080
```

**Important**: This `GROUNDING_URL` is what Agent S needs to know to connect to the local backend.

### 3. For Swift Agent Integration

In your Swift code, update the `engineParamsForGrounding` to point to the local server:

```swift
engineParamsForGrounding = [
    "engine_type": "openai",           // Use OpenAI-compatible format
    "model": "ui-tars-1.5-7b",        // Model name (for reference)
    "api_key": "dummy",               // Not needed for local server
    "base_url": "http://localhost:8080/v1",  // ← This is the key setting
    "grounding_width": 1920,
    "grounding_height": 1080
]
```

### 4. Command Line Usage

When running Agent S from command line:

```bash
agent_s \
    --provider openai \
    --model gpt-5-2025-08-07 \
    --ground_provider huggingface \
    --ground_url http://localhost:8080 \      # ← Backend URL
    --ground_model ui-tars-1.5-7b \
    --grounding_width 1920 \
    --grounding_height 1080
```

## API Endpoints

### Health Check
```bash
curl http://localhost:8080/health
```

### OpenAI-Compatible Endpoint
```bash
POST http://localhost:8080/v1/chat/completions
```

This endpoint accepts OpenAI-format requests with:
- `messages`: Array of message objects
- Each message can contain:
  - `type: "text"` - Text prompt
  - `type: "image_url"` - Base64-encoded image

### Simple Grounding Endpoint
```bash
POST http://localhost:8080/grounding/generate
```

Parameters:
- `prompt`: Text query string
- `image`: Base64-encoded image string

## Configuration Summary

| Setting | Value | Description |
|---------|-------|-------------|
| **GROUNDING_URL** | `http://localhost:8080` | URL for Agent S to connect to |
| **PORT** | `8080` | Server port (change if needed) |
| **MODEL** | `ui-tars-1.5-7b` | Hugging Face model identifier |
| **DEVICE** | `cuda` or `cpu` | Device to run inference on |

## Notes

1. **First Run**: The model will be downloaded from Hugging Face (~several GB). This happens automatically on first run.

2. **Model Loading**: The server loads the model on startup, which takes 30-60 seconds.

3. **GPU vs CPU**: 
   - Set `DEVICE=cuda` in `.env` for GPU (much faster)
   - Set `DEVICE=cpu` in `.env` for CPU (slower but works)

4. **Port Conflicts**: If port 8080 is in use, change `PORT` in `.env` and update `GROUNDING_URL` accordingly.

5. **OpenAI Compatibility**: The server implements OpenAI-compatible API, so it works with the OpenAI engine type by setting `base_url`.

## Troubleshooting

### Server won't start
- Check if port 8080 is available: `lsof -i :8080`
- Verify dependencies: `pip install -r requirements.txt`

### Model won't load
- Check internet connection (for first download)
- Verify GPU/CPU setup matches `.env` configuration
- Check disk space (model is several GB)

### Agent S can't connect
- Verify server is running: `curl http://localhost:8080/health`
- Check `base_url` in Swift code matches `GROUNDING_URL` in `.env`
- Ensure no firewall blocking localhost:8080

