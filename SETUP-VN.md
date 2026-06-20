# Hướng dẫn dựng RunPod Serverless VIDEO + tải đầy đủ mô hình

Mục tiêu: có **endpoint serverless thứ 2** chuyên render video (Wan / Hunyuan / LTX), $0 khi rảnh,
để tab **🎥 Video** render clip thật. Đây là endpoint RIÊNG, tách khỏi endpoint ảnh
(`53iuufo2fhz59y`) — vì model video rất nặng.

```
webapp (tab 🎥) ──/api/video/render──► RunPod VIDEO endpoint (worker-comfyui + WanVideo/HyVideo/LTX nodes)
                                              └── network volume: /runpod-volume/models/{diffusion_models,vae,text_encoders}
```

> ⏱ Tổng thời gian: ~30–60' (phần lớn là chờ tải ~75GB model). Chi phí xem mục 9.

---

## Bước 1 — Đẩy worker image lên GitHub
Worker = `runpod-worker-video/Dockerfile` (đã có sẵn: worker-comfyui + WanVideoWrapper +
HunyuanVideoWrapper + ComfyUI-LTXVideo + VideoHelperSuite).

1. Tạo repo GitHub mới, ví dụ `kelvinhuannguyen/ai-studio-worker-video`.
2. Đẩy **nội dung thư mục `runpod-worker-video/`** lên (ít nhất là `Dockerfile`):
   ```bash
   cd "C:/VIBECODE OPEN SOURCE/AI IMAGE/runpod-worker-video"
   git init && git add Dockerfile README.md SETUP-VN.md download-models.sh
   git commit -m "video worker"
   git branch -M main
   git remote add origin https://github.com/kelvinhuannguyen/ai-studio-worker-video.git
   git push -u origin main
   ```

---

## Bước 2 — Network volume + tải model

### 2a. Tạo / chọn volume
- RunPod → **Storage → Network Volume → New**. Khuyến nghị **250GB** (đủ TIER A+B), chọn
  **region có GPU 24–48GB** (vd `EU-RO-1` như volume ảnh của anh). Đặt tên `ai-studio-video`.
- (Hoặc dùng lại volume `ai-studio` 150GB nếu chỉ tải TIER A ~75GB — nhưng nó đã có ~27GB model ảnh,
  còn ~120GB, vẫn đủ TIER A. Tách riêng vẫn sạch hơn.)

### 2b. Spin 1 pod tạm để tải (rẻ)
- RunPod → **Pods → Deploy** → GPU rẻ bất kỳ (vd RTX 3090/A4000) hoặc CPU pod → **gắn network
  volume vừa tạo** (mount mặc định `/workspace`).
- Vào **Connect → Direct TCP** (⚠️ dùng `ssh root@<IP> -p <PORT>`, KHÔNG dùng proxy `ssh.runpod.io`
  — proxy băm nát lệnh dài).

### 2c. Chạy script tải
Trên pod:
```bash
cd /workspace
# lấy script từ repo vừa push (hoặc paste tay):
wget https://raw.githubusercontent.com/kelvinhuannguyen/ai-studio-worker-video/main/download-models.sh
chmod +x download-models.sh

# chạy nền để khỏi rớt khi mất SSH:
tmux new -s dl                  # (nếu không có tmux: nohup ./download-models.sh > dl.log 2>&1 &)
./download-models.sh            # TIER A (~75GB) — đủ để render
# ./download-models.sh all      # + TIER B (Wan 2.2 MoE + LTX-2.3, thêm ~60GB)
# Ctrl+B rồi D để thoát tmux; `tmux attach -t dl` để xem lại
```
Script đặt file đúng thư mục: `diffusion_models/`, `vae/`, `text_encoders/` (khớp `workflows.ts`).
Xong thì **Terminate pod tạm** (volume vẫn giữ model).

---

## Bước 3 — Tạo serverless endpoint

### 3a. Tạo endpoint từ image GitHub
- RunPod → **Serverless → New Endpoint**.
- **Source**: GitHub repo `ai-studio-worker-video` (RunPod tự build theo Dockerfile, ~10–15').
- **GPU**: 24GB chạy được fp8 (Wan/Hunyuan 14B, hơi sát); **48GB (RTX 6000 Ada / A40 / L40S)
  thoải mái hơn** — nên chọn 48GB cho video.
- **Workers**: Min `0`, Max `1–2`, **FlashBoot ON**, Idle timeout `5s`.
- **Container disk**: ~20GB (chỉ chứa code, model nằm ở volume).

### 3b. Gắn network volume (qua REST API)
UI tạo endpoint thường KHÔNG có chỗ gắn volume → dùng API (giống lúc làm endpoint ảnh):
```bash
curl -X PATCH https://rest.runpod.io/v1/endpoints/<ENDPOINT_ID> \
  -H "Authorization: Bearer <RUNPOD_API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"networkVolumeId":"<VOLUME_ID>"}'
```
(`<ENDPOINT_ID>` lấy ở trang endpoint; `<VOLUME_ID>` ở trang Storage; `RUNPOD_API_KEY` trong
`webapp/.env.local`.) Sau khi gắn, endpoint **rollout lại** — đợi xong mới test.

### 3c. (tùy) Bật S3/R2 output cho worker
Để worker trả **URL** thay vì base64 (nhẹ + bền). Thêm env vào endpoint:
`BUCKET_ENDPOINT_URL` = R2 endpoint, `BUCKET_ACCESS_KEY_ID`, `BUCKET_SECRET_ACCESS_KEY`
(dùng creds R2 sẵn trong `.env.local`). Không bật cũng chạy — app nhận base64 và (nếu có R2) tự đẩy lên.

---

## Bước 4 — Nối vào app
Trong `webapp/.env.local` (đã có sẵn dòng trống):
```
RUNPOD_VIDEO_ENDPOINT_ID=<ENDPOINT_ID>
```
Restart dev (`preview_stop` + `preview_start`, hoặc Ctrl+C rồi `npm run dev`) để nạp env mới.

---

## Bước 5 — Verify node + render thử (QUAN TRỌNG)
Graph **Hunyuan** đã chuẩn (port từ V2). Graph **Wan/LTX** là mẫu → kiểm tra node thật:
```bash
curl https://api.runpod.ai/v2/<ENDPOINT_ID>/health -H "Authorization: Bearer <KEY>"
# Khi có worker chạy, xem node đã cài (qua 1 job /runsync gọi /object_info, hoặc log ComfyUI)
```
**Thứ tự test khôn ngoan** (trong tab 🎥 Video):
1. Chọn engine **HunyuanVideo · ảnh→video** (graph chắc chạy) → tạo storyboard 1 cảnh → **Render clip**.
   Lần đầu cold-start ~2–3' + render vài phút. Có clip = endpoint OK.
2. Rồi thử **Wan 2.1→2.2** (mặc định). Nếu báo `node_errors`/`model not found` → so tên file/node
   với `webapp/lib/video/workflows.ts` và sửa hằng số cho khớp `/object_info`.

---

## Nâng lên Wan 2.2 MoE (tùy chọn, chất lượng cao hơn)
Wan 2.2 A14B = **MoE 2 chuyên gia HIGH + LOW** (mỗi ~15GB) → cần graph **2 model-loader** + sampler
chia theo timestep, KHÁC graph 1-loader hiện tại.
1. `./download-models.sh all` (tải HIGH + LOW).
2. Mở **workflow Wan 2.2 I2V chính chủ** của Kijai (ComfyUI-WanVideoWrapper → `example_workflows`)
   để lấy đúng sơ đồ 2-expert, rồi cập nhật `buildWanI2V` trong `workflows.ts` theo đó
   (2× `WanVideoModelLoader` high/low + boundary). Hoặc giữ Wan 2.1 (đã rất tốt).

---

## 8. Bảng model (TIER A = lõi, B = nâng cao)
| File | Repo HuggingFace | Thư mục | ~GB | Dùng cho |
|---|---|---|---|---|
| hunyuan_video_I2V_fp8_e4m3fn | Kijai/HunyuanVideo_comfy | diffusion_models | 13 | Hunyuan I2V |
| hunyuan_video_720_cfgdistill_fp8_e4m3fn | Kijai/HunyuanVideo_comfy | diffusion_models | 13 | Hunyuan T2V |
| hunyuan_video_vae_bf16 | Kijai/HunyuanVideo_comfy | vae | 0.5 | Hunyuan |
| Wan2_1-I2V-14B-720P_fp8_e4m3fn | Kijai/WanVideo_comfy | diffusion_models | 17 | **Wan I2V (mặc định)** |
| Wan2_1-T2V-14B_fp8_e4m3fn | Kijai/WanVideo_comfy | diffusion_models | 17 | Wan VACE base |
| Wan2_1-VACE_module_14B_fp8_e4m3fn | Kijai/WanVideo_comfy | diffusion_models | ~3 | Wan VACE |
| umt5-xxl-enc-bf16 | Kijai/WanVideo_comfy | text_encoders | 11 | Wan encoder |
| Wan2_1_VAE_bf16 | Kijai/WanVideo_comfy | vae | 0.5 | Wan |
| **B:** Wan2_2-I2V-A14B-HIGH/LOW_fp8_e4m3fn_scaled_KJ | Kijai/WanVideo_comfy_fp8_scaled (`/I2V`) | diffusion_models | 15+15 | Wan 2.2 MoE |
| **B:** ltx-2.3-22b-dev-fp8 | Lightricks/LTX-2.3-fp8 | diffusion_models | 29 | LTX-2 |
| **B:** gemma_3_12B_it_fp8_scaled | (ComfyUI Manager / awesome-ltx2) | text_encoders | ~12 | LTX-2 encoder |

TIER A ≈ **75GB** · A+B ≈ **135GB**.

## 9. Chi phí ước tính
- Volume 250GB: ~**$17.5/tháng** (cố định). Dùng lại `ai-studio` thì $0 thêm (chỉ tải TIER A).
- Render: serverless $0 khi rảnh; lúc chạy ~**$0.0005–0.001/giây GPU** (48GB). 1 clip 5s ≈ vài phút
  GPU ≈ **$0.1–0.3/clip** (cold-start lần đầu tốn hơn).
- Pod tạm để tải: ~$0.2–0.4/giờ × ~1–2 giờ.

## 10. Lỗi thường gặp
- **`model not found` / `node_errors`** → tên file/thư mục lệch hằng số `workflows.ts`, hoặc node
  wrapper tên khác → so với `/object_info`, sửa cho khớp. (Bài học: đổi config rồi đợi **rollout xong** mới test, kẻo trúng worker cũ.)
- **Worker mãi "loading"** → thiếu model trên volume / sai region (endpoint khác region volume).
- **Hunyuan T2V đòi text encoder** → node `DownloadAndLoadHyVideoTextEncoder` tự tải lúc chạy, cần
  worker có internet (mặc định có).
- **OOM trên 24GB** → đổi GPU 48GB, hoặc giảm `durationSec`/khung 9:16 480p.
