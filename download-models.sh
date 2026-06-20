#!/usr/bin/env bash
# Tải TOÀN BỘ mô hình video cho serverless worker (chạy TRÊN pod RunPod có gắn network volume).
# Network volume mount ở /workspace khi là POD (và /runpod-volume khi serverless — CÙNG 1 volume).
# Tên file ở đây PHẢI khớp hằng số trong webapp/lib/video/workflows.ts.
#
# Cách chạy:
#   chmod +x download-models.sh
#   ./download-models.sh            # tải TIER A (lõi, đủ để render: Hunyuan + Wan 2.1 + VACE)
#   ./download-models.sh all        # tải cả TIER B (Wan 2.2 MoE + LTX-2.3 — nâng cao)
#
# wget -c = nối lại nếu rớt mạng. File to (13–17GB) nên để chạy nền: `tmux` hoặc `nohup`.

set -u
MODELS="${MODELS:-/workspace/models}"   # đổi sang /runpod-volume/models nếu chạy ở chỗ khác
DIFF="$MODELS/diffusion_models"
VAE="$MODELS/vae"
TENC="$MODELS/text_encoders"
mkdir -p "$DIFF" "$VAE" "$TENC"
FAILED=""

dl () { # dl <url> <dest_path> — wget -c: resume nếu dở, "nothing to do" nếu đã đủ size
  echo "⬇  $(basename "$2")"
  if wget -c --tries=10 --retry-connrefused --waitretry=15 --timeout=60 -q --show-progress -O "$2" "$1"; then
    echo "   ✓ $(du -h "$2" 2>/dev/null | cut -f1)"
  else
    echo "   ✗ LỖI tải: $1"; FAILED="$FAILED $(basename "$2")"
  fi
}

HF=https://huggingface.co
WAN=$HF/Kijai/WanVideo_comfy/resolve/main
HY=$HF/Kijai/HunyuanVideo_comfy/resolve/main

echo "== TIER A — lõi (Hunyuan + Wan 2.1 I2V + VACE + encoder/vae) =="

# HunyuanVideo (graph port nguyên từ V2 — đã chạy thật, đường ngắn nhất ra clip đầu tiên)
dl "$HY/hunyuan_video_I2V_fp8_e4m3fn.safetensors"        "$DIFF/hunyuan_video_I2V_fp8_e4m3fn.safetensors"          # ~13GB
dl "$HY/hunyuan_video_720_cfgdistill_fp8_e4m3fn.safetensors" "$DIFF/hunyuan_video_720_cfgdistill_fp8_e4m3fn.safetensors" # ~13GB
dl "$HY/hunyuan_video_vae_bf16.safetensors"              "$VAE/hunyuan_video_vae_bf16.safetensors"                  # ~0.5GB

# Wan 2.1 I2V 14B 720p = MẶC ĐỊNH engine wan22-i2v (1 file, chạy với graph hiện tại)
dl "$WAN/Wan2_1-I2V-14B-720P_fp8_e4m3fn.safetensors"     "$DIFF/Wan2_1-I2V-14B-720P_fp8_e4m3fn.safetensors"         # ~17GB

# Wan VACE (đa nhân vật): base T2V 14B + VACE module
dl "$WAN/Wan2_1-T2V-14B_fp8_e4m3fn.safetensors"          "$DIFF/Wan2_1-T2V-14B_fp8_e4m3fn.safetensors"              # ~17GB
dl "$WAN/Wan2_1-VACE_module_14B_fp8_e4m3fn.safetensors"  "$DIFF/Wan2_1-VACE_module_14B_fp8_e4m3fn.safetensors"      # ~ (nếu 404, xem tên đúng ở trang Kijai/WanVideo_comfy)

# Encoder + VAE cho Wan
dl "$WAN/umt5-xxl-enc-bf16.safetensors"                  "$TENC/umt5-xxl-enc-bf16.safetensors"                      # ~11GB
dl "$WAN/Wan2_1_VAE_bf16.safetensors"                    "$VAE/Wan2_1_VAE_bf16.safetensors"                         # ~0.5GB

# (HunyuanVideo text encoder = node DownloadAndLoadHyVideoTextEncoder TỰ tải lúc chạy lần đầu
#  vào HF cache — cần worker có internet. Không tải ở đây.)

if [ "$1" = "all" ]; then
  echo "== TIER B — nâng cao (Wan 2.2 MoE + LTX-2.3) — cần verify graph =="
  WAN22=$HF/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/I2V
  LTX=$HF/Lightricks/LTX-2.3-fp8/resolve/main

  # Wan 2.2 I2V A14B — MoE: cần CẢ HAI (HIGH + LOW). Dùng với graph 2-loader (SETUP-VN.md).
  dl "$WAN22/Wan2_2-I2V-A14B-HIGH_fp8_e4m3fn_scaled_KJ.safetensors" "$DIFF/Wan2_2-I2V-A14B-HIGH_fp8_e4m3fn_scaled_KJ.safetensors" # ~15GB
  dl "$WAN22/Wan2_2-I2V-A14B-LOW_fp8_e4m3fn_scaled_KJ.safetensors"  "$DIFF/Wan2_2-I2V-A14B-LOW_fp8_e4m3fn_scaled_KJ.safetensors"  # ~15GB

  # LTX-2.3 (audio native, ~20s) + gemma text encoder. Node graph khác template → import workflow chính chủ.
  dl "$LTX/ltx-2.3-22b-dev-fp8.safetensors"               "$DIFF/ltx-2.3-22b-dev-fp8.safetensors"                    # ~29GB
  echo "ℹ  gemma_3_12B_it_fp8_scaled.safetensors cho LTX-2: tải qua ComfyUI Manager hoặc repo trong github.com/wildminder/awesome-ltx2 → đặt vào $TENC/"
fi

echo ""
if [ -n "$FAILED" ]; then echo "⚠ Lỗi tải:$FAILED — chạy lại script để resume."; else echo "✅ Tất cả OK."; fi
echo "Dung lượng:"; du -sh "$DIFF" "$VAE" "$TENC" 2>/dev/null || true
echo "Model đã tải:"; ls -lh "$DIFF" "$VAE" "$TENC"
