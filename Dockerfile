# Custom RunPod serverless VIDEO worker = worker-comfyui + open-source video nodes.
# This is the SECOND serverless endpoint (separate from the image worker in ../runpod-worker).
# Point webapp/.env.local → RUNPOD_VIDEO_ENDPOINT_ID at this endpoint's id.
# Video weights live on a network volume at /runpod-volume/models/...
# Deploy: push to a GitHub repo → RunPod builds on commit; attach the network volume.

FROM runpod/worker-comfyui:5.8.5-base

# Video custom nodes:
#   WanVideoWrapper      → Wan 2.2 I2V + VACE (default engine; character consistency)
#   HunyuanVideoWrapper  → HunyuanVideo I2V/T2V (proven graph, ported from AI STUDIO V2)
#   ComfyUI-LTXVideo     → LTX-2 (native audio, clips up to ~20s)
#   VideoHelperSuite     → VHS_VideoCombine (decoded frames → MP4)
RUN cd /comfyui/custom_nodes \
    && git clone --depth 1 https://github.com/kijai/ComfyUI-WanVideoWrapper.git \
    && git clone --depth 1 https://github.com/kijai/ComfyUI-HunyuanVideoWrapper.git \
    && git clone --depth 1 https://github.com/Lightricks/ComfyUI-LTXVideo.git \
    && git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git \
    && for d in ComfyUI-WanVideoWrapper ComfyUI-HunyuanVideoWrapper ComfyUI-LTXVideo ComfyUI-VideoHelperSuite; do \
         if [ -f "$d/requirements.txt" ]; then pip install --no-cache-dir -r "$d/requirements.txt" || true; fi; \
       done

# worker-comfyui auto-maps checkpoints/loras/vae/unet/clip from the volume, but the video
# wrappers also read from diffusion_models / text_encoders. Point those at the volume too
# (symlinks resolve at runtime when the network volume is mounted).
RUN for f in diffusion_models text_encoders; do \
      rm -rf /comfyui/models/$f && ln -s /runpod-volume/models/$f /comfyui/models/$f; \
    done
