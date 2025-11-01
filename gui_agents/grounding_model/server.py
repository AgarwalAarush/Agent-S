"""
FastAPI server for UI-TARS grounding model
Serves the ByteDance-Seed/UI-TARS-1.5-7B model locally on port 8080
Compatible with OpenAI API format for easy integration
"""

import os
import base64
import io
import time
from contextlib import asynccontextmanager
from typing import List, Dict, Any, Optional, Tuple
from PIL import Image
import torch

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import uvicorn
import re
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import transformers components
try:
    from transformers import (
        AutoProcessor, 
        AutoModelForVision2Seq,
        AutoModelForCausalLM,
        AutoTokenizer,
        AutoImageProcessor,
        AutoModel,
        BlipProcessor,
        BlipForConditionalGeneration
    )
    TRANSFORMERS_AVAILABLE = True
except ImportError:
    TRANSFORMERS_AVAILABLE = False
    logger.warning("transformers not available. Please install: pip install transformers")


# Configuration from environment
MODEL_NAME = os.getenv("GROUNDING_MODEL", "ByteDance-Seed/UI-TARS-1.5-7B")
DEVICE = os.getenv("DEVICE", "cuda" if torch.cuda.is_available() else "cpu")
PORT = int(os.getenv("PORT", "8080"))
HOST = os.getenv("HOST", "0.0.0.0")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    """Lifespan context manager for startup and shutdown events"""
    # Startup
    load_model()
    yield
    # Shutdown (cleanup if needed)


app = FastAPI(title="UI-TARS Grounding Model Server", lifespan=lifespan)

# Authentication Note:
# This server does NOT validate Authorization headers for local deployment.
# Clients (like Swift agent) may send "Authorization: Bearer {apiKey}" headers,
# but these are ignored by the server. For production deployment, implement
# proper authentication middleware using FastAPI's security utilities.

# Enable CORS for local development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# OpenAI-compatible error handler
@app.exception_handler(HTTPException)
async def openai_exception_handler(_request: Request, exc: HTTPException):
    """
    Convert FastAPI HTTPException to OpenAI-compatible error format.
    OpenAI format: {"error": {"message": "...", "type": "...", "code": ...}}
    """
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "message": exc.detail,
                "type": "invalid_request_error" if exc.status_code == 400 else "server_error",
                "code": exc.status_code
            }
        }
    )

# Global model variables
processor = None
tokenizer = None
model = None
model_type = None  # 'vision2seq', 'blip', 'auto', 'causal'


class ChatMessage(BaseModel):
    role: str
    content: List[Dict[str, Any]]


class ChatCompletionRequest(BaseModel):
    model: str
    messages: List[ChatMessage]
    temperature: Optional[float] = 0.0
    max_completion_tokens: Optional[int] = 128


class ChatCompletionResponse(BaseModel):
    id: str
    object: str = "chat.completion"
    created: int
    model: str
    choices: List[Dict[str, Any]]
    usage: Dict[str, Any]


def load_model():
    """Load the UI-TARS model and processor"""
    global processor, tokenizer, model, model_type
    
    if not TRANSFORMERS_AVAILABLE:
        raise RuntimeError("transformers library not available")

    logger.info(f"Loading model {MODEL_NAME} on device {DEVICE}...")
    
    try:
        # Try different model architectures
        # First, try Vision2Seq (common for vision-language models)
        try:
            processor = AutoProcessor.from_pretrained(MODEL_NAME)
            model = AutoModelForVision2Seq.from_pretrained(
                MODEL_NAME,
                torch_dtype=torch.float16 if DEVICE == "cuda" else torch.float32,
                device_map="auto" if DEVICE == "cuda" else None
            )
            model_type = "vision2seq"
            logger.info("Loaded as Vision2Seq model")
        except Exception as e1:
            # Try BLIP architecture
            try:
                processor = BlipProcessor.from_pretrained(MODEL_NAME)
                model = BlipForConditionalGeneration.from_pretrained(
                    MODEL_NAME,
                    torch_dtype=torch.float16 if DEVICE == "cuda" else torch.float32,
                    device_map="auto" if DEVICE == "cuda" else None
                )
                model_type = "blip"
                logger.info("Loaded as BLIP model")
            except Exception as e2:
                # Try standard AutoModel (for custom architectures)
                try:
                    image_processor = AutoImageProcessor.from_pretrained(MODEL_NAME)
                    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
                    model = AutoModel.from_pretrained(
                        MODEL_NAME,
                        torch_dtype=torch.float16 if DEVICE == "cuda" else torch.float32,
                        device_map="auto" if DEVICE == "cuda" else None
                    )
                    processor = image_processor
                    model_type = "auto"
                    logger.info("Loaded as AutoModel")
                except Exception as e3:
                    # Fallback to causal LM (text-only, but we'll try)
                    logger.warning(f"Vision2Seq failed ({e1}), BLIP failed ({e2}), AutoModel failed ({e3})")
                    logger.warning("Trying CausalLM as last resort (may not support images)")
                    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
                    model = AutoModelForCausalLM.from_pretrained(
                        MODEL_NAME,
                        torch_dtype=torch.float16 if DEVICE == "cuda" else torch.float32,
                        device_map="auto" if DEVICE == "cuda" else None
                    )
                    processor = tokenizer
                    model_type = "causal"
                    logger.warning("Loaded as CausalLM (image support may be limited)")
        
        if DEVICE == "cpu" and model_type != "auto":
            model = model.to(DEVICE)

        model.eval()
        logger.info(f"Model {MODEL_NAME} loaded successfully on {DEVICE}")
        
    except Exception as e:
        raise RuntimeError(f"Failed to load model: {e}")


def decode_image_from_base64(image_data: str) -> Image.Image:
    """Decode base64 image data"""
    # Handle data:image/png;base64, prefix
    if "," in image_data:
        image_data = image_data.split(",")[1]
    
    image_bytes = base64.b64decode(image_data)
    image = Image.open(io.BytesIO(image_bytes))
    return image.convert("RGB")


def extract_text_and_image(messages: List[ChatMessage]) -> Tuple[str, Optional[Image.Image]]:
    """Extract text prompt and image from OpenAI-format messages"""
    text_parts = []
    image = None
    
    # Process messages in order, looking for image in last user message
    for message in messages:
        if message.role == "user":
            for content_item in message.content:
                if isinstance(content_item, dict):
                    if content_item.get("type") == "text":
                        text_parts.append(content_item.get("text", ""))
                    elif content_item.get("type") == "image_url":
                        image_url = content_item.get("image_url", {})
                        if isinstance(image_url, dict):
                            url = image_url.get("url", "")
                            if url.startswith("data:"):
                                try:
                                    image = decode_image_from_base64(url)
                                except Exception as e:
                                    logger.warning(f"Failed to decode image: {e}")
    
    prompt = "\n".join(text_parts).strip()
    return prompt, image


async def generate_coordinates(
    prompt: str,
    image: Optional[Image.Image],
    temperature: float = 0.0,
    max_completion_tokens: int = 128
) -> str:
    """
    Generate coordinates using UI-TARS model

    Args:
        prompt: Text query describing what to find (client should include full instructions)
        image: Screenshot image
        temperature: Sampling temperature (default: 0.0 for deterministic output)
        max_completion_tokens: Maximum tokens to generate (default: 128, sufficient for coordinates)

    Returns:
        Response string containing coordinates
    """
    global processor, tokenizer, model, model_type

    if model is None:
        raise RuntimeError("Model not loaded")

    if image is None:
        raise ValueError("Image is required for grounding")

    try:
        # Handle different model types
        if model_type == "vision2seq" or model_type == "blip":
            # Vision-language models with processor
            # Use chat template for proper multi-modal formatting (required for Qwen2.5-VL)
            messages = [
                {
                    "role": "user",
                    "content": [
                        {"type": "image"},
                        {"type": "text", "text": prompt}
                    ]
                }
            ]

            # Apply chat template to insert vision tokens properly
            try:
                text = processor.apply_chat_template(
                    messages,
                    add_generation_prompt=True,
                    tokenize=False
                )

                # Process with formatted text and images
                inputs = processor(
                    text=[text],
                    images=[image],
                    return_tensors="pt",
                    padding=True
                )
            except (AttributeError, TypeError) as e:
                # Fallback for processors without apply_chat_template
                logger.warning(f"Processor doesn't support apply_chat_template ({e}), using direct processing")
                inputs = processor(
                    text=prompt,
                    images=image,
                    return_tensors="pt",
                    padding=True
                )

            # Move inputs to device
            inputs = {k: v.to(DEVICE) if isinstance(v, torch.Tensor) else v
                     for k, v in inputs.items()}

            # Generate response with client-specified parameters
            with torch.no_grad():
                outputs = model.generate(
                    **inputs,
                    max_new_tokens=max_completion_tokens,
                    temperature=temperature,
                    do_sample=temperature > 0.0,  # Only sample if temperature > 0
                    num_beams=1  # Greedy decoding for deterministic output
                )

            # Decode response
            response = processor.decode(outputs[0], skip_special_tokens=True)
                
        elif model_type == "auto":
            # Try to use processor for vision + tokenizer for text
            # This is model-specific and may need customization
            try:
                # Try processor with image
                image_inputs = processor(image, return_tensors="pt")
                text_inputs = tokenizer(full_prompt, return_tensors="pt")

                # Combine inputs (model-specific)
                inputs = {**image_inputs, **text_inputs}
                inputs = {k: v.to(DEVICE) if isinstance(v, torch.Tensor) else v
                         for k, v in inputs.items()}

                with torch.no_grad():
                    outputs = model.generate(
                        **inputs,
                        max_new_tokens=max_completion_tokens,
                        temperature=temperature,
                        do_sample=temperature > 0.0,
                        num_beams=1
                    )

                response = tokenizer.decode(outputs[0], skip_special_tokens=True)
            except Exception as e:
                raise RuntimeError(f"AutoModel processing failed: {e}")
                
        elif model_type == "causal":
            # Text-only model - this won't work well with images
            # But we'll try to process text only
            logger.warning("CausalLM model - image input ignored")
            inputs = tokenizer(full_prompt, return_tensors="pt")
            inputs = {k: v.to(DEVICE) for k, v in inputs.items()}

            with torch.no_grad():
                outputs = model.generate(
                    **inputs,
                    max_new_tokens=max_completion_tokens,
                    temperature=temperature,
                    do_sample=temperature > 0.0,
                    num_beams=1
                )

            response = tokenizer.decode(outputs[0], skip_special_tokens=True)
        else:
            raise RuntimeError(f"Unknown model type: {model_type}")

        # Log and validate the response
        response = response.strip()
        logger.info(f"Grounding model raw response: {response}")

        # Validate that response contains at least 2 numbers (for coordinate pair)
        numbers = re.findall(r'\d+', response)
        if len(numbers) < 2:
            logger.warning(f"Response validation: Expected at least 2 numbers for coordinates, found {len(numbers)}: {numbers}")
        else:
            logger.info(f"Response validation: Found {len(numbers)} numbers: {numbers[:2]} (using first 2 as coordinates)")

        return response
        
    except Exception as e:
        raise RuntimeError(f"Generation failed: {e}")


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "model": MODEL_NAME,
        "device": DEVICE,
        "model_loaded": model is not None,
        "model_type": model_type or "unknown"
    }


@app.post("/v1/chat/completions", response_model=ChatCompletionResponse)
async def chat_completions(request: ChatCompletionRequest):
    """
    OpenAI-compatible chat completions endpoint
    Accepts image + text and returns coordinates

    Note: Authorization header is ignored for local deployment.
    For production, implement proper authentication middleware.
    """
    try:
        # Extract text and image from messages
        prompt, image = extract_text_and_image(request.messages)

        if not prompt:
            raise HTTPException(status_code=400, detail="No text prompt provided")

        if image is None:
            raise HTTPException(status_code=400, detail="No image provided")

        # Generate coordinates with client-specified parameters
        response_text = await generate_coordinates(
            prompt,
            image,
            temperature=request.temperature,
            max_completion_tokens=request.max_completion_tokens
        )
        
        # Format response in OpenAI-compatible format
        response = {
            "id": f"chatcmpl-{int(time.time())}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": request.model,
            "choices": [
                {
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": response_text
                    },
                    "finish_reason": "stop"
                }
            ],
            "usage": {
                "prompt_tokens": len(prompt.split()),
                "completion_tokens": len(response_text.split()),
                "total_tokens": len(prompt.split()) + len(response_text.split())
            }
        }
        
        return response

    except ValueError as e:
        logger.error(f"Validation error: {e}")
        raise HTTPException(status_code=400, detail=str(e))
    except RuntimeError as e:
        logger.error(f"Runtime error: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    except Exception as e:
        logger.exception(f"Unexpected error in chat_completions: {e}")
        raise HTTPException(status_code=500, detail=f"Internal error: {str(e)}")


@app.post("/grounding/generate")
async def grounding_generate(
    prompt: str,
    image: str  # Base64 encoded image
):
    """
    Simple grounding endpoint (alternative to OpenAI format)
    """
    try:
        image_obj = decode_image_from_base64(image)
        response_text = await generate_coordinates(prompt, image_obj)

        # Extract coordinates from response
        numbers = re.findall(r'\d+', response_text)
        if len(numbers) >= 2:
            coordinates = [int(numbers[0]), int(numbers[1])]
        else:
            coordinates = None
        
        return {
            "response": response_text,
            "coordinates": coordinates
        }
    except Exception as e:
        logger.exception(f"Error in grounding_generate: {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    logger.info(f"Starting UI-TARS grounding model server on {HOST}:{PORT}")
    logger.info(f"Model: {MODEL_NAME}")
    logger.info(f"Device: {DEVICE}")
    uvicorn.run(app, host=HOST, port=PORT)

