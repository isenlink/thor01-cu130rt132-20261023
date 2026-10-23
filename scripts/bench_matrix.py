#!/usr/bin/env python3
"""Deterministic llama-server benchmark matrix (no prefix cache).

Uses /completion so the server-reported timings are available. Each request
sets cache_prompt=false, temperature=0, top_k=1 and a fixed seed.
"""
import argparse
import hashlib
import json
import time
import urllib.request


def make_text(target_words: int) -> str:
    sentence = (
        "The quick brown fox jumps over the lazy dog while seven engineers "
        "measure throughput, latency, memory and correctness on the same board. "
    )
    words = sentence.split()
    out = []
    while len(out) < target_words:
        out.extend(words)
    return " ".join(out[:target_words])


def cases() -> list[dict]:
    decode_prompt = "请只回答一个数字：1+1=?"
    p2k = (
        "Read the following text and answer with one word: which animal is mentioned? "
        "Answer only the animal name.\n\n" + make_text(1800)
    )
    p8k = (
        "Read the following text and answer with one word: which animal is mentioned? "
        "Answer only the animal name.\n\n" + make_text(7050)
    )
    return [
        {
            "name": "decode128",
            "prompt": decode_prompt,
            "n_predict": 128,
            "ignore_eos": True,
        },
        {
            "name": "prefill2k",
            "prompt": p2k,
            "n_predict": 16,
            "ignore_eos": False,
        },
        {
            "name": "prefill8k",
            "prompt": p8k,
            "n_predict": 16,
            "ignore_eos": False,
        },
    ]


def post(url: str, payload: dict, timeout: int) -> tuple[float, dict]:
    data = json.dumps(payload, ensure_ascii=False).encode()
    req = urllib.request.Request(
        url + "/completion", data=data, headers={"Content-Type": "application/json"}
    )
    t0 = time.monotonic()
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = json.load(resp)
    return time.monotonic() - t0, raw


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--timeout", type=int, default=1800)
    args = ap.parse_args()

    result = {"tag": args.tag, "base_url": args.base_url, "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "tests": {}}
    for case in cases():
        payload = {
            "prompt": case["prompt"],
            "n_predict": case["n_predict"],
            "ignore_eos": case["ignore_eos"],
            "temperature": 0,
            "top_k": 1,
            "seed": 42,
            "cache_prompt": False,
            "stream": False,
        }
        wall, raw = post(args.base_url, payload, args.timeout)
        timings = raw.get("timings", {})
        result["tests"][case["name"]] = {
            "prompt_sha256": hashlib.sha256(case["prompt"].encode()).hexdigest(),
            "request": {k: v for k, v in payload.items() if k != "prompt"},
            "wall_s": wall,
            "content": raw.get("content"),
            "stop_type": raw.get("stop_type"),
            "usage": raw.get("usage"),
            "timings": timings,
        }
        print(
            f"{case['name']}: prompt_n={timings.get('prompt_n')} "
            f"prompt_ms={timings.get('prompt_ms')} "
            f"predicted_n={timings.get('predicted_n')} "
            f"decode_tps={timings.get('predicted_per_second')} wall={wall:.3f}s"
        )
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(result, fh, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
