"""Behavioral checks for Transformers chat-template tokenization."""

from __future__ import annotations

import unittest
from collections import UserDict
from typing import Any

from adapters.common import ConversationTurn
from adapters.transformers_python import _tokenize_prompt


class PromptTokenizationTests(unittest.TestCase):
    def test_chat_template_mapping_is_used_without_fallback(self) -> None:
        class Tokenizer:
            chat_template = "template"

            def apply_chat_template(self, messages: Any, **kwargs: Any) -> Any:
                self.messages = messages
                return UserDict({"input_ids": [42], "attention_mask": [1]})

            def __call__(self, text: str, **kwargs: Any) -> Any:
                raise AssertionError("chat-template result must not use fallback")

        tokenizer = Tokenizer()
        result = _tokenize_prompt(tokenizer, [ConversationTurn("user", "hello")])
        self.assertEqual(result, {"input_ids": [42], "attention_mask": [1]})
        self.assertEqual(tokenizer.messages, [{"role": "user", "content": "hello"}])


if __name__ == "__main__":
    unittest.main()
