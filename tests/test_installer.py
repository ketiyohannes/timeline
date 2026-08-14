#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path


root = Path(__file__).resolve().parent.parent
installer = root / "bin" / "install-hooks"

with tempfile.TemporaryDirectory(prefix="timeline-installer-") as directory:
    config = Path(directory) / "hooks.json"
    config.write_text(
        json.dumps(
            {
                "hooks": {
                    "UserPromptSubmit": [
                        {
                            "hooks": [
                                {
                                    "type": "command",
                                    "command": "/old/codex-timeline-hook UserPromptSubmit # codex-timeline",
                                }
                            ]
                        }
                    ],
                    "Stop": [
                        {
                            "hooks": [
                                {"type": "command", "command": "/existing/hook stop"}
                            ]
                        }
                    ]
                }
            }
        ),
        encoding="utf-8",
    )

    subprocess.run([sys.executable, str(installer), "--config", str(config)], check=True)
    value = json.loads(config.read_text(encoding="utf-8"))
    assert len(value["hooks"]["Stop"]) == 2
    assert len(value["hooks"]["PostToolUse"]) == 1
    assert len(value["hooks"]["UserPromptSubmit"]) == 1
    upgraded = value["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"]
    assert "timeline-hook" in upgraded and "# timeline" in upgraded

    subprocess.run([sys.executable, str(installer), "--config", str(config)], check=True)
    value = json.loads(config.read_text(encoding="utf-8"))
    assert len(value["hooks"]["Stop"]) == 2, "reinstall must be idempotent"

    subprocess.run(
        [sys.executable, str(installer), "--config", str(config), "--uninstall"],
        check=True,
    )
    value = json.loads(config.read_text(encoding="utf-8"))
    assert list(value["hooks"]) == ["Stop"]
    assert value["hooks"]["Stop"][0]["hooks"][0]["command"] == "/existing/hook stop"

print("installer test passed")
