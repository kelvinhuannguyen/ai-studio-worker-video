# Serverless VIDEO worker (RunPod · ComfyUI · mã nguồn mở)

Đây là **endpoint serverless thứ 2** — chuyên render video, tách khỏi endpoint ảnh
(`../runpod-worker`). App gọi nó qua `RUNPOD_VIDEO_ENDPOINT_ID`. $0 khi rảnh; chỉ tính tiền
GPU lúc render.

Pipeline: app gửi `{ input: { workflow, images } }` (graph ComfyUI do
[`webapp/lib/video/workflows.ts`](../webapp/lib/video/workflows.ts) dựng) → worker chạy →
trả MP4 (base64, hoặc URL nếu bật S3/R2 output).

## Engine & custom node
| Engine (app) | Node repo | Ghi chú |
|---|---|---|
| **Wan 2.2** (I2V/VACE) — mặc định | `kijai/ComfyUI-WanVideoWrapper` | Giữ nhân vật; hệ NSFW LoRA mạnh |
| **HunyuanVideo** (I2V/T2V) | `kijai/ComfyUI-HunyuanVideoWrapper` | Graph đã chạy thật (port từ AI STUDIO V2) |
| **LTX-2** | `Lightricks/ComfyUI-LTXVideo` | Audio native, clip dài tới ~20s |
| (mọi engine) | `Kosinkadink/ComfyUI-VideoHelperSuite` | `VHS_VideoCombine` ghép frame → MP4 |

## Cài đặt đầy đủ (model + endpoint)
👉 **Làm theo [`SETUP-VN.md`](SETUP-VN.md)** — hướng dẫn từng bước, đầy đủ.
Tải model bằng **[`download-models.sh`](download-models.sh)** (chạy trên pod có gắn volume):
tên file trong script khớp đúng hằng số ở đầu [`webapp/lib/video/workflows.ts`](../webapp/lib/video/workflows.ts).
Đặt dưới `/runpod-volume/models/{diffusion_models,vae,text_encoders}/`. TIER A ≈ 75GB (đủ render),
TIER B thêm Wan 2.2 MoE + LTX-2.3.

## Deploy (tóm tắt)
1. Push thư mục này lên 1 GitHub repo (vd `ai-studio-worker-video`).
2. RunPod → **Serverless → New Endpoint → Import từ GitHub** (build theo Dockerfile). GPU: 24GB
   đủ cho fp8 (Wan/Hunyuan 14B); LTX nhẹ hơn. 48GB (RTX 6000 Ada/A100) chạy thoải mái hơn.
3. Gắn **network volume** chứa models ở trên (mount `/runpod-volume`).
4. **Bật S3/R2 output** cho worker (env `BUCKET_ENDPOINT_URL`, `BUCKET_ACCESS_KEY_ID`,
   `BUCKET_SECRET_ACCESS_KEY`) để worker trả **URL** thay vì base64 (nhẹ & bền hơn). Không bật
   cũng chạy — app sẽ nhận base64 và (nếu có R2) tự đẩy lên R2.
5. Copy **Endpoint ID** → đặt `RUNPOD_VIDEO_ENDPOINT_ID` trong `webapp/.env.local` (cùng
   `RUNPOD_API_KEY` đang dùng cho ảnh). Restart `npm run dev`.

## ✅ Verify node (làm 1 lần) — QUAN TRỌNG
Graph **Hunyuan** port nguyên từ V2 (đã chạy). Graph **Wan 2.2 / LTX-2** theo mẫu wrapper chuẩn
— tên `class_type` hoặc tên file model của bản 2.2 / LTX-2 có thể khác trên worker của anh. Sau
khi endpoint sống, kiểm tra node thật:

```bash
curl https://<endpoint>-<id>.proxy.runpod.net/object_info | jq 'keys' | grep -iE "wan|hyvideo|ltx|vhs"
```

Đối chiếu với `class_type` trong `workflows.ts` và sửa cho khớp nếu lệch. Khi sai node, app
hiện lỗi `node_errors` rõ ràng (xem `runpodVideo.ts`), không render sai âm thầm.

## Lộ trình
- Pha 1 (nay): render 1 clip/cảnh.
- Pha 2: TTS tiếng Việt + lip-sync (MuseTalk/LipDub) + FFmpeg ghép cảnh + phụ đề + nhạc → MP4.
- Pha 3: hàng đợi job + "render tất cả cảnh" + agent tự lái.
