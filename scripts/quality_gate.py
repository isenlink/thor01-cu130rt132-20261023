#!/usr/bin/env python3
"""Minimal production quality gate for the Thor llama-server pair."""
import argparse
import base64
import json
import re
import struct
import time
import urllib.request
import zlib


def request(url: str, payload: dict, timeout: int = 600) -> dict:
    data = json.dumps(payload, ensure_ascii=False).encode()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)


def health(base: str) -> dict:
    with urllib.request.urlopen(base + "/health", timeout=10) as resp:
        return {"status": resp.status, "body": resp.read().decode()}


def completion(base: str, prompt: str, n_predict: int, timeout: int = 600) -> dict:
    raw = request(
        base + "/completion",
        {
            "prompt": prompt,
            "n_predict": n_predict,
            "temperature": 0,
            "top_k": 1,
            "seed": 42,
            "cache_prompt": False,
            "stream": False,
        },
        timeout,
    )
    return {
        "content": raw.get("content", ""),
        "timings": raw.get("timings", {}),
        "stop_type": raw.get("stop_type"),
    }


def chat(base: str, messages: list[dict], timeout: int = 600) -> dict:
    raw = request(
        base + "/v1/chat/completions",
        {
            "model": "ignored",
            "messages": messages,
            "max_tokens": 128,
            "temperature": 0,
            "top_k": 1,
            "seed": 42,
            "reasoning_effort": "none",
            "stream": False,
        },
        timeout,
    )
    choice = raw["choices"][0]["message"]
    return {
        "content": choice.get("content", ""),
        "reasoning_content": choice.get("reasoning_content", ""),
        "usage": raw.get("usage", {}),
        "timings": raw.get("timings", {}),
    }


def red_png_data_uri(size: int = 64) -> str:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    row = b"\x00" + b"\xff\x00\x00" * size
    raw = row * size
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    return "data:image/png;base64," + base64.b64encode(png).decode()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", required=True, help="board address or hostname")
    ap.add_argument("--out", required=True)
    ap.add_argument("--skip-image", action="store_true")
    args = ap.parse_args()

    base80 = f"http://{args.host}:8080"
    base82 = f"http://{args.host}:8082"
    result = {"timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "host": args.host, "tests": {}}
    failures = []

    def record(name: str, value, ok: bool, note: str = "") -> None:
        result["tests"][name] = {"ok": ok, "note": note, "value": value}
        if not ok:
            failures.append(name)

    for name, base in (("health_8080", base80), ("health_8082", base82)):
        try:
            h = health(base)
            record(name, h, h["status"] == 200 and '"ok"' in h["body"])
        except Exception as exc:
            record(name, repr(exc), False)

    try:
        v = chat(base80, [{"role": "user", "content": "1+1=? 只回答数字"}])
        record("8080_short", v, v["content"].strip() == "2")
    except Exception as exc:
        record("8080_short", repr(exc), False)

    try:
        v = chat(base80, [{"role": "user", "content": "复制以下随机数字串，只输出原串，不要解释，不要加空格：82947103655829174063829517402938"}])
        text = v["content"].replace(" ", "").replace("\n", "")
        record("8080_digit_copy", v, "82947103655829174063829517402938" in text)
    except Exception as exc:
        record("8080_digit_copy", repr(exc), False)

    try:
        v = chat(base80, [{"role": "user", "content": "只输出一行 JSON，不要 markdown：{\"answer\": 2, \"unit\": \"ok\"}"}])
        match = re.search(r"\{.*\}", v["content"], re.S)
        parsed = json.loads(match.group(0)) if match else None
        record("8080_json", v, parsed == {"answer": 2, "unit": "ok"})
    except Exception as exc:
        record("8080_json", repr(exc), False)

    try:
        v = chat(base82, [{"role": "user", "content": "1+1=? 只回答数字"}])
        record("8082_short", v, v["content"].strip() == "2")
    except Exception as exc:
        record("8082_short", repr(exc), False)

    if not args.skip_image:
        try:
            v = chat(
                base82,
                [
                    {
                        "role": "user",
                        "content": [
                            {"type": "text", "text": "这张图片是什么颜色？只回答颜色。"},
                            {"type": "image_url", "image_url": {"url": red_png_data_uri()}},
                        ],
                    }
                ],
            )
            record("8082_red_image", v, "红" in v["content"])
        except Exception as exc:
            record("8082_red_image", repr(exc), False)

    result["failures"] = failures
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(result, fh, ensure_ascii=False, indent=2)
    for name, item in result["tests"].items():
        print(name, "PASS" if item["ok"] else "FAIL")
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
