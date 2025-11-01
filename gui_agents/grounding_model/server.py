"""
FastAPI proxy for the grounding model that forwards OpenAI-format requests
to a local backend and normalises the responses.
"""

import os
import re
import time
import logging
from typing import Any, Dict, List, Optional, Union

from fastapi import FastAPI, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from openai import OpenAI, OpenAIError
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
DEFAULT_MODEL = os.getenv("GROUNDING_MODEL", "tgi")
BASE_URL = os.getenv("GROUNDING_BASE_URL", "http://localhost:8080/v1")
API_KEY = os.getenv("GROUNDING_API_KEY", os.getenv("OPENAI_API_KEY", "dummy"))
DEFAULT_MAX_TOKENS = int(os.getenv("GROUNDING_MAX_TOKENS", "400"))


def add_box_token(input_string: str) -> str:
    """
    Insert <|box_start|> / <|box_end|> tokens around coordinate arguments so
    the backend model receives boxed coordinates.
    """
    if "Action: " in input_string and "start_box=" in input_string:
        prefix = input_string.split("Action: ")[0] + "Action: "
        actions = input_string.split("Action: ")[1:]
        processed: List[str] = []
        for action in actions:
            action = action.strip()
            matches = re.findall(r"(start_box|end_box)='\((\d+),\s*(\d+)\)'", action)
            updated = action
            for coord_type, x_val, y_val in matches:
                needle = f"{coord_type}='({x_val},{y_val})'"
                replacement = (
                    f"{coord_type}='<|box_start|>({x_val},{y_val})<|box_end|>'"
                )
                updated = updated.replace(needle, replacement)
            processed.append(updated)
        return prefix + "\n\n".join(processed)
    return input_string


MessageContent = Union[str, List[Dict[str, Any]]]


class ChatMessage(BaseModel):
    role: str
    content: MessageContent


class ChatCompletionRequest(BaseModel):
    model: Optional[str] = None
    messages: List[ChatMessage]
    temperature: Optional[float] = 0.0
    max_completion_tokens: Optional[int] = None
    max_tokens: Optional[int] = None


client: Optional[OpenAI] = None


def get_client() -> OpenAI:
    global client
    if client is None:
        client = OpenAI(base_url=BASE_URL, api_key=API_KEY)
        logger.info("Initialised OpenAI client with base_url=%s", BASE_URL)
    return client


def ensure_data_url(image: str) -> str:
    return image if image.startswith("data:") else f"data:image/png;base64,{image}"


def prepare_messages(messages: List[ChatMessage]) -> List[Dict[str, Any]]:
    prepared: List[Dict[str, Any]] = []
    for message in messages:
        item: Dict[str, Any] = {"role": message.role}
        content = message.content
        if isinstance(content, list):
            parts: List[Any] = []
            for part in content:
                if not isinstance(part, dict):
                    parts.append(part)
                    continue
                updated = dict(part)
                text_value = updated.get("text")
                if (
                    isinstance(text_value, str)
                    and message.role == "assistant"
                ):
                    updated["text"] = add_box_token(text_value)
                parts.append(updated)
            item["content"] = parts
        elif isinstance(content, str) and message.role == "assistant":
            item["content"] = add_box_token(content)
        else:
            item["content"] = content
        prepared.append(item)
    return prepared


def extract_response_text(completion: Any) -> str:
    if not getattr(completion, "choices", []):
        return ""
    choice = completion.choices[0]
    message = getattr(choice, "message", choice.get("message") if isinstance(choice, dict) else None)
    if message is None:
        return ""
    content = getattr(message, "content", message.get("content") if isinstance(message, dict) else None)
    if isinstance(content, list):
        texts: List[str] = []
        for part in content:
            if isinstance(part, dict):
                if "text" in part and isinstance(part["text"], str):
                    texts.append(part["text"])
                elif "value" in part and isinstance(part["value"], str):
                    texts.append(part["value"])
        return "\n".join(texts).strip()
    if isinstance(content, str):
        return content.strip()
    return ""


async def request_chat_completion(
    messages: List[Dict[str, Any]],
    model: Optional[str],
    temperature: Optional[float],
    max_tokens: Optional[int],
) -> Any:
    payload: Dict[str, Any] = {
        "model": model or DEFAULT_MODEL,
        "messages": messages,
    }
    if temperature is not None:
        payload["temperature"] = temperature
    effective_max_tokens = max_tokens or DEFAULT_MAX_TOKENS
    if effective_max_tokens is not None:
        payload["max_tokens"] = effective_max_tokens

    try:
        completion = await run_in_threadpool(
            get_client().chat.completions.create,
            **payload,
        )
        return completion
    except OpenAIError as exc:
        logger.error("OpenAI backend error: %s", exc)
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    except Exception as exc:
        logger.exception("Unexpected backend error")
        raise HTTPException(status_code=500, detail=str(exc)) from exc


app = FastAPI(title="Grounding Model Proxy")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(HTTPException)
async def openai_exception_handler(_request: Request, exc: HTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "message": exc.detail,
                "type": "invalid_request_error"
                if exc.status_code == 400
                else "server_error",
                "code": exc.status_code,
            }
        },
    )


@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "model": DEFAULT_MODEL,
        "base_url": BASE_URL,
    }


@app.post("/v1/chat/completions")
async def chat_completions(request: ChatCompletionRequest):
    messages = prepare_messages(request.messages)
    completion = await request_chat_completion(
        messages=messages,
        model=request.model,
        temperature=request.temperature,
        max_tokens=request.max_tokens or request.max_completion_tokens,
    )
    result = completion.model_dump() if hasattr(completion, "model_dump") else completion
    if isinstance(result, dict):
        result.setdefault("id", f"chatcmpl-{int(time.time())}")
        result.setdefault("object", "chat.completion")
        result.setdefault("created", int(time.time()))
    return result


@app.post("/grounding/generate")
async def grounding_generate(prompt: str, image: str):
    messages = [
        {
            "role": "user",
            "content": [
                {"type": "text", "text": prompt},
                {"type": "image_url", "image_url": {"url": ensure_data_url(image)}},
            ],
        }
    ]
    completion = await request_chat_completion(
        messages=messages,
        model=DEFAULT_MODEL,
        temperature=0.0,
        max_tokens=DEFAULT_MAX_TOKENS,
    )
    response_text = extract_response_text(completion)
    numbers = re.findall(r"\d+", response_text)
    coordinates = [int(numbers[0]), int(numbers[1])] if len(numbers) >= 2 else None
    return {
        "response": response_text,
        "coordinates": coordinates,
    }


if __name__ == "__main__":
    import uvicorn

    logger.info("Starting grounding proxy on %s", BASE_URL)
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
