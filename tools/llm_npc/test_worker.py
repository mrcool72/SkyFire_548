"""Unit tests for NPC dialogue transport and input/output boundaries."""

import io
import json
import os
import types
import unittest
from unittest.mock import Mock, patch

import worker


class WorkerTests(unittest.TestCase):
    def test_remote_plaintext_is_rejected(self):
        with self.assertRaises(ValueError):
            worker.validate_endpoint("http://example.com/v1/chat/completions")

    def test_local_http_is_allowed(self):
        self.assertEqual(
            worker.validate_endpoint("http://127.0.0.1:11434/v1/chat/completions"),
            "http://127.0.0.1:11434/v1/chat/completions",
        )

    def test_https_is_allowed(self):
        self.assertEqual(
            worker.validate_endpoint("https://llm.example.net/v1/chat/completions"),
            "https://llm.example.net/v1/chat/completions",
        )

    def test_sanitize_reply_removes_chat_markup_and_controls(self):
        self.assertEqual(worker.sanitize_reply("Hello|cff22FF00\nworld\x00"), "Hello cff22FF00 world")

    def test_sanitize_reply_truncates_utf8_safely(self):
        reply = worker.sanitize_reply("🐼" * 100)
        self.assertLessEqual(len(reply.encode("utf-8")), 220)
        self.assertNotIn("\ufffd", reply)

    def test_sanitize_empty_reply(self):
        self.assertEqual(worker.sanitize_reply("\r\n\t"), worker.FALLBACK)

    def test_chat_uses_message_content_and_never_tools(self):
        answer = {"choices": [{"message": {"content": "Greetings, traveler!"}}]}
        with patch("worker.urllib.request.urlopen", return_value=io.BytesIO(
            json.dumps(answer).encode("utf-8")
        )) as open_url:
            reply = worker.complete_chat(
                {"npc_name": "Lorewalker", "prompt": "What is Pandaria?"},
                url="http://localhost:11434/v1/chat/completions", model="test-model"
            )
        self.assertEqual(reply, "Greetings, traveler!")
        sent = json.loads(open_url.call_args.args[0].data)
        self.assertEqual(sent["model"], "test-model")
        self.assertIn("What is Pandaria?", sent["messages"][1]["content"])
        self.assertNotIn("tools", sent)
        self.assertIs(sent["stream"], False)

    def test_remote_mysql_requires_verified_tls(self):
        fake_mysql = types.SimpleNamespace(
            connect=Mock(), cursors=types.SimpleNamespace(DictCursor=object)
        )
        variables = {
            "SKYFIRE_LLM_DB_HOST": "db.example.net",
            "SKYFIRE_LLM_DB_USER": "limited",
        }
        with patch.dict("sys.modules", {"pymysql": fake_mysql}):
            with patch.dict(os.environ, variables, clear=True):
                with self.assertRaisesRegex(ValueError, "requires"):
                    worker.open_database()
        fake_mysql.connect.assert_not_called()

    def test_remote_mysql_uses_certificate_and_host_validation(self):
        fake_mysql = types.SimpleNamespace(
            connect=Mock(), cursors=types.SimpleNamespace(DictCursor=object)
        )
        variables = {
            "SKYFIRE_LLM_DB_HOST": "db.example.net",
            "SKYFIRE_LLM_DB_USER": "limited",
            "SKYFIRE_LLM_DB_SSL_CA": "C:/private/mysql-ca.pem",
        }
        with patch.dict("sys.modules", {"pymysql": fake_mysql}):
            with patch.dict(os.environ, variables, clear=True):
                worker.open_database()
        kwargs = fake_mysql.connect.call_args.kwargs
        self.assertEqual(kwargs["ssl_ca"], "C:/private/mysql-ca.pem")
        self.assertIs(kwargs["ssl_verify_cert"], True)
        self.assertIs(kwargs["ssl_verify_identity"], True)

    def test_finish_job_rejects_unexpected_status(self):
        with self.assertRaises(ValueError):
            worker.finish_job(None, 1, "reply", "delivered")


if __name__ == "__main__":
    unittest.main()
