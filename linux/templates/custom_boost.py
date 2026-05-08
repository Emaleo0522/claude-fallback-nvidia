"""
LiteLLM custom callback that prepends a "boost" system prompt to every
chat completion request before forwarding to the upstream model.

Loaded by the proxy via `litellm_settings.callbacks: ["custom_boost.booster"]`
in config.yaml.

Reads boost text from system_boost.md (sibling file). Reload requires
stop/start of the proxy.
"""
import sys
from pathlib import Path
from typing import Optional, Any, List, Dict

from litellm.integrations.custom_logger import CustomLogger

HERE = Path(__file__).parent
BOOST_PATH = HERE / "system_boost.md"
SEPARATOR = "\n\n---\n\n"
INJECTION_MARKER = "<!-- claude-fallback-nvidia:boost-injected -->"


def _load_boost() -> str:
    if not BOOST_PATH.exists():
        return ""
    return BOOST_PATH.read_text(encoding="utf-8").strip()


def _stderr(msg: str) -> None:
    """Plain stderr write — bypasses logging config so we always see it."""
    print(f"[boost] {msg}", file=sys.stderr, flush=True)


class SystemPromptBooster(CustomLogger):
    """
    Prepends a fixed boost text to the system message of every chat
    completion request handled by the proxy.

    Implements multiple LiteLLM hook variants because the version-specific
    dispatch is inconsistent. Whichever fires first injects, others no-op
    via the idempotency marker.
    """

    def __init__(self) -> None:
        super().__init__()
        self.boost = _load_boost()
        if self.boost:
            _stderr(f"loaded ({len(self.boost)} chars)")
        else:
            _stderr("WARNING boost text empty — no augmentation will be applied")

    # ────── Internal helper ─────────────────────────────────────────────────
    def _augment_messages(self, messages: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        if not self.boost or not isinstance(messages, list) or not messages:
            return messages

        first = messages[0] if messages else None
        if isinstance(first, dict) and first.get("role") == "system":
            existing = first.get("content", "")
            if isinstance(existing, str):
                if INJECTION_MARKER in existing:
                    return messages
                first["content"] = f"{self.boost}\n{INJECTION_MARKER}{SEPARATOR}{existing}"
            elif isinstance(existing, list):
                already = any(
                    isinstance(b, dict) and INJECTION_MARKER in str(b.get("text", ""))
                    for b in existing
                )
                if already:
                    return messages
                first["content"] = [
                    {"type": "text", "text": f"{self.boost}\n{INJECTION_MARKER}"}
                ] + existing
        else:
            messages.insert(0, {
                "role": "system",
                "content": f"{self.boost}\n{INJECTION_MARKER}",
            })
        return messages

    async def async_pre_call_hook(
        self,
        user_api_key_dict: Any,
        cache: Any,
        data: dict,
        call_type: str,
    ) -> Optional[dict]:
        if not self.boost or not isinstance(data, dict):
            return data

        # Anthropic /v1/messages path: system is a SEPARATE top-level field
        # (Anthropic Messages API spec), not part of messages[].
        if call_type == "anthropic_messages":
            existing = data.get("system", "")
            if isinstance(existing, str):
                if INJECTION_MARKER in existing:
                    return data
                data["system"] = (
                    f"{self.boost}\n{INJECTION_MARKER}{SEPARATOR}{existing}"
                    if existing else f"{self.boost}\n{INJECTION_MARKER}"
                )
            elif isinstance(existing, list):
                already = any(
                    isinstance(b, dict) and INJECTION_MARKER in str(b.get("text", ""))
                    for b in existing
                )
                if not already:
                    data["system"] = [
                        {"type": "text", "text": f"{self.boost}\n{INJECTION_MARKER}"}
                    ] + existing
            else:
                data["system"] = f"{self.boost}\n{INJECTION_MARKER}"
            return data

        # OpenAI /v1/chat/completions path: system is a message in messages[]
        if call_type in ("completion", "acompletion", "chat_completion"):
            messages = data.get("messages")
            if isinstance(messages, list):
                data["messages"] = self._augment_messages(messages)
        return data

    # NOTE: async_pre_request_hook also fires, but returning a dict from it
    # causes "multiple values for keyword argument 'messages'" because the
    # router merges its return value into kwargs. async_pre_call_hook above
    # already mutates `data["messages"]` in place, which is sufficient.


# Module-level instance referenced from config.yaml
booster = SystemPromptBooster()
