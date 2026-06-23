#!/usr/bin/env python3
# Patch worker-comfyui's handler.py so it ALSO returns VIDEO outputs.
#
# worker-comfyui only collects the "images" output key. VHS_VideoCombine (and animated/video
# nodes) emit their MP4/WebP under "gifs" / "videos" → the worker logs "unhandled output keys"
# and returns 0 images, so the rendered video never comes back.
#
# Fix: right before the existing image-processing loop, merge any "gifs"/"videos" items into the
# "images" list. They share the same shape ({filename, subfolder, type}), so the MP4 then gets
# base64-returned (or S3-uploaded if BUCKET_ENDPOINT_URL is set) exactly like an image. The app
# (lib/video/runpodVideo.ts mapWorkerVideo) recognises a .mp4 filename and re-hosts to R2.
#
# NOTE: handler.py is ADDed to / in runpod/worker-comfyui (Dockerfile: WORKDIR /; ADD ... handler.py ./).
# Use FIXED candidate paths — do NOT recursive-glob the filesystem (that OOM-killed the build).
import sys

candidates = ["/handler.py", "/src/handler.py", "/app/handler.py", "/comfyui/handler.py"]
target = None
for p in candidates:
    try:
        s = open(p, encoding="utf-8").read()
    except Exception:
        continue
    if "for node_id, node_output in outputs.items():" in s and '"images" in node_output' in s:
        target = p
        break

if not target:
    print("PATCH WARNING: worker-comfyui handler.py not found — video output NOT patched")
    sys.exit(0)  # don't fail the image build

s = open(target, encoding="utf-8").read()
if "_vkey" in s:
    print(f"PATCH: video-output support already present in {target}")
    sys.exit(0)

needle = "        for node_id, node_output in outputs.items():\n"
inject = (
    "        for node_id, node_output in outputs.items():\n"
    '            for _vkey in ("gifs", "videos"):\n'
    "                if _vkey in node_output:\n"
    '                    node_output.setdefault("images", []).extend(node_output[_vkey])\n'
)
if needle not in s:
    print(f"PATCH WARNING: anchor not found in {target} — handler layout changed?")
    sys.exit(0)

open(target, "w", encoding="utf-8").write(s.replace(needle, inject, 1))
print(f"PATCH: applied video-output support to {target}")
