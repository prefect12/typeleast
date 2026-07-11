#!/usr/bin/env python3
"""Replay PCM16 mono 24 kHz audio through OpenAI Realtime without printing transcripts."""

import argparse
import asyncio
import base64
import json
import os
import statistics
import time

import websockets


async def run_once(audio: bytes) -> dict:
    started = time.monotonic()
    commit_at = None
    metrics = {
        "ready_ms": None,
        "first_delta_ms": None,
        "completed_ms": None,
        "commit_to_completed_ms": None,
        "delta_before_commit": False,
        "completed": False,
        "delta_count": 0,
    }
    headers = {"Authorization": f"Bearer {os.environ['OPENAI_API_KEY']}"}
    connect_parameters = (
        {"additional_headers": headers}
        if "additional_headers" in websockets.connect.__init__.__code__.co_varnames
        else {"extra_headers": headers}
    )

    async with websockets.connect(
        "wss://api.openai.com/v1/realtime?intent=transcription",
        **connect_parameters,
    ) as socket:
        while True:
            event = json.loads(await asyncio.wait_for(socket.recv(), timeout=8))
            if event.get("type") == "session.created":
                break

        await socket.send(json.dumps({
            "type": "session.update",
            "session": {
                "type": "transcription",
                "audio": {"input": {
                    "format": {"type": "audio/pcm", "rate": 24_000},
                    "transcription": {"model": "gpt-realtime-whisper", "delay": "minimal"},
                    "turn_detection": None,
                }},
            },
        }))

        while True:
            event = json.loads(await asyncio.wait_for(socket.recv(), timeout=8))
            if event.get("type") == "session.updated":
                metrics["ready_ms"] = round((time.monotonic() - started) * 1_000)
                break
            if event.get("type") == "error":
                raise RuntimeError(event.get("error", {}).get("message", "session error"))

        async def receive_events() -> None:
            while True:
                event = json.loads(await socket.recv())
                event_type = event.get("type", "")
                now = time.monotonic()
                if event_type.endswith(".delta"):
                    metrics["delta_count"] += 1
                    if metrics["first_delta_ms"] is None:
                        metrics["first_delta_ms"] = round((now - started) * 1_000)
                        metrics["delta_before_commit"] = commit_at is None
                elif event_type.endswith(".completed"):
                    metrics["completed_ms"] = round((now - started) * 1_000)
                    metrics["completed"] = True
                    return
                elif event_type in ("error", "conversation.item.input_audio_transcription.failed"):
                    raise RuntimeError(event.get("error", {}).get("message", "transcription error"))

        receive_task = asyncio.create_task(receive_events())
        for offset in range(0, len(audio), 4_800):
            chunk = audio[offset:offset + 4_800]
            await socket.send(json.dumps({
                "type": "input_audio_buffer.append",
                "audio": base64.b64encode(chunk).decode(),
            }))
            await asyncio.sleep(0.1)

        await asyncio.sleep(0.35)
        commit_at = time.monotonic()
        await socket.send(json.dumps({"type": "input_audio_buffer.commit"}))
        await asyncio.wait_for(receive_task, timeout=8)
        metrics["commit_to_completed_ms"] = round((time.monotonic() - commit_at) * 1_000)
        return metrics


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pcm_file")
    parser.add_argument("--repeat", type=int, default=1)
    arguments = parser.parse_args()
    if not os.environ.get("OPENAI_API_KEY"):
        raise SystemExit("OPENAI_API_KEY is required")
    audio = open(arguments.pcm_file, "rb").read()

    results = []
    for index in range(arguments.repeat):
        result = await run_once(audio)
        result["run"] = index + 1
        results.append(result)
        print(json.dumps(result, sort_keys=True), flush=True)

    completed = [item for item in results if item["completed"]]
    first_delta_values = [
        item["first_delta_ms"] for item in results if item["first_delta_ms"] is not None
    ]
    summary = {
        "runs": len(results),
        "completed": len(completed),
        "delta_before_commit": sum(bool(item["delta_before_commit"]) for item in results),
        "median_first_delta_ms": round(statistics.median(first_delta_values)) if first_delta_values else None,
        "median_commit_to_completed_ms": round(statistics.median(
            item["commit_to_completed_ms"] for item in completed
        )),
    }
    print(json.dumps({"summary": summary}, sort_keys=True), flush=True)
    if len(completed) != len(results):
        raise SystemExit(1)


if __name__ == "__main__":
    asyncio.run(main())
