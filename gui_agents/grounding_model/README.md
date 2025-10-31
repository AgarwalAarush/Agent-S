# UI-TARS Grounding Model Server

Local Python backend server for running the UI-TARS-1.5-7B grounding model from Hugging Face.

## Overview

This server provides a local endpoint (default: `http://localhost:8080`) that serves the UI-TARS vision-language model for grounding UI elements. It accepts screenshots and text queries and returns coordinates.

## Setup

### 1. Create Conda Environment

```bash
cd grounding_model
./setup.sh
```

Or manually:
```bash
conda create -n grounding_model python=3.10 -y
conda activate grounding_model
```

### 2. Install Dependencies

```bash
pip install -r requirements.txt
```

**Note**: For GPU support, make sure you have the appropriate PyTorch CUDA version installed. Check [PyTorch website](https://pytorch.org/) for your system.

### 3. Configure Environment

Copy `.env.example` to `.env` and update as needed:

```bash
cp .env.example .env
```

Edit `.env` to set:
- `GROUNDING_MODEL`: Model name (default: `ByteDance-Seed/UI-TARS-1.5-7B`)
- `DEVICE`: `cuda` or `cpu` (default: `cuda` if available, else `cpu`)
- `PORT`: Server port (default: `8080`)
- `GROUNDING_URL`: Backend URL for Agent S (default: `http://localhost:8080`)

### 4. Run the Server

```bash
# Make sure conda environment is activated
conda activate grounding_model
python server.py
```

Or use the run script:

```bash
./run.sh
```

Or with uvicorn directly:

```bash
conda activate grounding_model
uvicorn server:app --host 0.0.0.0 --port 8080
```

The server will:
1. Load the UI-TARS model from Hugging Face (first run will download the model)
2. Start serving on `http://localhost:8080`

## API Endpoints

### Health Check

```bash
curl http://localhost:8080/health
```

Returns:
```json
{
  "status": "healthy",
  "model": "ByteDance-Seed/UI-TARS-1.5-7B",
  "device": "cuda",
  "model_loaded": true
}
```

### OpenAI-Compatible Chat Completions

**Endpoint**: `POST /v1/chat/completions`

**Request Format** (OpenAI-compatible):
```json
{
  "model": "ByteDance-Seed/UI-TARS-1.5-7B",
  "messages": [
    {
      "role": "user",
      "content": [
        {
          "type": "text",
          "text": "Query: click the button\nOutput only the coordinate of one point in your response."
        },
        {
          "type": "image_url",
          "image_url": {
            "url": "data:image/png;base64,..."
          }
        }
      ]
    }
  ],
  "temperature": 0.0
}
```

**Response Format**:
```json
{
  "id": "chatcmpl-...",
  "object": "chat.completion",
  "created": 1234567890,
  "model": "ByteDance-Seed/UI-TARS-1.5-7B",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "x y coordinates here"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 2,
    "total_tokens": 12
  }
}
```

### Simple Grounding Endpoint

**Endpoint**: `POST /grounding/generate`

**Request**:
- `prompt`: Text query (e.g., "click the button")
- `image`: Base64-encoded image

**Response**:
```json
{
  "response": "x y coordinates here",
  "coordinates": [100, 200]
}
```

## Integration with Agent S

### For Swift Agent

Update the `engineParamsForGrounding` in your Swift code to use the local server:

```swift
engineParamsForGrounding = [
    "engine_type": "openai",
    "model": "ByteDance-Seed/UI-TARS-1.5-7B",
    "api_key": "dummy",  // Not used for local server
    "base_url": "http://localhost:8080/v1",
    "grounding_width": 1920,
    "grounding_height": 1080
]
```

### Command Line Usage

When running Agent S, use:

```bash
agent_s \
    --provider openai \
    --model gpt-5-2025-08-07 \
    --ground_provider huggingface \
    --ground_url http://localhost:8080 \
    --ground_model ByteDance-Seed/UI-TARS-1.5-7B \
    --grounding_width 1920 \
    --grounding_height 1080
```

## Environment Variables

The server reads from `.env` file:

- `GROUNDING_MODEL`: Hugging Face model identifier (default: `ByteDance-Seed/UI-TARS-1.5-7B`)
- `DEVICE`: Device to run on - `cuda` or `cpu` (auto-detects if not set)
- `HOST`: Server host (default: `0.0.0.0`)
- `PORT`: Server port (default: `8080`)
- `GROUNDING_URL`: Backend URL that Agent S should use (default: `http://localhost:8080`)

## Troubleshooting

### Model Download

On first run, the model will be downloaded from Hugging Face (several GB). Ensure you have:
- Sufficient disk space
- Stable internet connection
- Optional: Set `HF_TOKEN` environment variable if model requires authentication

### GPU Issues

If you have CUDA installed but getting CPU usage:
- Check: `python -c "import torch; print(torch.cuda.is_available())"`
- Verify CUDA version matches PyTorch version
- Try: `DEVICE=cpu` in `.env` to force CPU mode

### Memory Issues

If running out of memory:
- Use CPU mode: `DEVICE=cpu` in `.env`
- Reduce batch size in server code
- Consider using model quantization (requires `bitsandbytes`)

### Port Already in Use

If port 8080 is in use:
- Change `PORT` in `.env` to another port (e.g., `8081`)
- Update `GROUNDING_URL` accordingly
- Restart the server

## Notes

- The model loads on server startup, which may take 30-60 seconds
- First inference may be slower (model warmup)
- GPU is recommended for faster inference
- The server is designed for local use; for production, add authentication and rate limiting

