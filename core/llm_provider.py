"""LLM provider abstraction for OpenAI and Gemini (using new google-genai SDK)."""

from __future__ import annotations

import time
from typing import Any

import numpy as np

from config import LLMConfig
from core.models import LLMCallLog


class LLMProvider:
    """Unified interface for OpenAI and Gemini APIs."""

    def __init__(self, config: LLMConfig):
        self.config = config
        self.provider = config.provider
        self._openai_client = None
        self._genai_client = None

    def _get_openai_client(self):
        if self._openai_client is None:
            from openai import OpenAI
            self._openai_client = OpenAI(api_key=self.config.openai_api_key)
        return self._openai_client

    def _get_genai_client(self):
        if self._genai_client is None:
            from google import genai
            self._genai_client = genai.Client(api_key=self.config.gemini_api_key)
        return self._genai_client

    @property
    def fast_model(self) -> str:
        if self.provider == "openai":
            return self.config.openai_fast_model
        return self.config.gemini_fast_model

    @property
    def strong_model(self) -> str:
        if self.provider == "openai":
            return self.config.openai_strong_model
        return self.config.gemini_strong_model

    @property
    def deep_model(self) -> str:
        if self.provider == "openai":
            return self.config.openai_deep_model
        return self.config.gemini_deep_model

    def chat(
        self,
        messages: list[dict[str, str]],
        model: str | None = None,
        temperature: float = 0.0,
        json_mode: bool = False,
        stage: str = "unknown",
    ) -> tuple[str, LLMCallLog]:
        """Send a chat completion request. Returns (response_text, call_log)."""
        model = model or self.strong_model
        start = time.time()

        if self.provider == "openai":
            result, tokens_in, tokens_out = self._chat_openai(
                messages, model, temperature, json_mode
            )
        else:
            result, tokens_in, tokens_out = self._chat_gemini(
                messages, model, temperature, json_mode
            )

        latency_ms = int((time.time() - start) * 1000)
        log = LLMCallLog(
            stage=stage,
            model=model,
            tokens_in=tokens_in,
            tokens_out=tokens_out,
            latency_ms=latency_ms,
        )
        return result, log

    def _chat_openai(
        self,
        messages: list[dict[str, str]],
        model: str,
        temperature: float,
        json_mode: bool,
    ) -> tuple[str, int, int]:
        client = self._get_openai_client()
        kwargs: dict[str, Any] = {
            "model": model,
            "messages": messages,
            "temperature": temperature,
        }
        if json_mode:
            kwargs["response_format"] = {"type": "json_object"}

        resp = client.chat.completions.create(**kwargs)
        text = resp.choices[0].message.content or ""
        return text, resp.usage.prompt_tokens, resp.usage.completion_tokens

    def _chat_gemini(
        self,
        messages: list[dict[str, str]],
        model: str,
        temperature: float,
        json_mode: bool,
    ) -> tuple[str, int, int]:
        from google.genai import types

        client = self._get_genai_client()

        # Separate system instruction from conversation
        system_text = ""
        contents = []
        for msg in messages:
            if msg["role"] == "system":
                system_text = msg["content"]
            elif msg["role"] == "user":
                contents.append(types.Content(role="user", parts=[types.Part(text=msg["content"])]))
            elif msg["role"] == "assistant":
                contents.append(types.Content(role="model", parts=[types.Part(text=msg["content"])]))

        config_kwargs: dict[str, Any] = {"temperature": temperature}
        if json_mode:
            config_kwargs["response_mime_type"] = "application/json"
        if system_text:
            config_kwargs["system_instruction"] = system_text

        gen_config = types.GenerateContentConfig(**config_kwargs)

        resp = client.models.generate_content(
            model=model,
            contents=contents,
            config=gen_config,
        )
        text = resp.text or ""

        # Token counts from usage metadata
        tokens_in = 0
        tokens_out = 0
        if resp.usage_metadata:
            tokens_in = resp.usage_metadata.prompt_token_count or 0
            tokens_out = resp.usage_metadata.candidates_token_count or 0
        else:
            tokens_in = sum(len(m["content"]) // 4 for m in messages)
            tokens_out = len(text) // 4

        return text, tokens_in, tokens_out

    def embed(self, texts: list[str]) -> list[list[float]]:
        """Get embeddings for a list of texts."""
        if self.provider == "openai":
            return self._embed_openai(texts)
        return self._embed_gemini(texts)

    def _embed_openai(self, texts: list[str]) -> list[list[float]]:
        client = self._get_openai_client()
        all_embeddings = []
        for i in range(0, len(texts), 100):
            batch = texts[i : i + 100]
            resp = client.embeddings.create(
                model=self.config.openai_embedding_model,
                input=batch,
            )
            all_embeddings.extend([d.embedding for d in resp.data])
        return all_embeddings

    def _embed_gemini(self, texts: list[str]) -> list[list[float]]:
        client = self._get_genai_client()
        model_name = self.config.gemini_embedding_model

        all_embeddings = []
        # Gemini embed API: process one at a time for reliability
        for i in range(0, len(texts), 20):
            batch = texts[i : i + 20]
            for text in batch:
                resp = client.models.embed_content(
                    model=model_name,
                    contents=text,
                )
                all_embeddings.append(resp.embeddings[0].values)
        return all_embeddings

    def embed_single(self, text: str) -> list[float]:
        """Embed a single text."""
        return self.embed([text])[0]

    def list_embedding_models(self) -> list[str]:
        """List available embedding models (useful for debugging)."""
        if self.provider == "gemini":
            client = self._get_genai_client()
            models = []
            for m in client.models.list():
                if "embedContent" in (m.supported_actions or []):
                    models.append(m.name)
            return models
        return [self.config.openai_embedding_model]


def cosine_similarity(a: list[float], b: list[float]) -> float:
    """Compute cosine similarity between two vectors."""
    a_arr = np.array(a)
    b_arr = np.array(b)
    dot = np.dot(a_arr, b_arr)
    norm = np.linalg.norm(a_arr) * np.linalg.norm(b_arr)
    if norm == 0:
        return 0.0
    return float(dot / norm)
