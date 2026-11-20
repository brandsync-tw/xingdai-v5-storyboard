#!/usr/bin/env bash
set -euo pipefail
mkdir -p site/assets work/source work/cuts
fetch() {
  local name="$1" url="$2"
  echo "Downloading $name"
  curl --fail --location --retry 5 --retry-delay 2 --connect-timeout 20 --max-time 150 --silent --show-error "$url" -o "work/source/$name.mp4"
  test "$(wc -c < "work/source/$name.mp4")" -gt 100000
  ffprobe -v error -show_entries format=duration -of csv=p=0 "work/source/$name.mp4" | grep -Eq '[0-9]'
}
fetch s01 'https://v3b.fal.media/files/b/0ab2f4bc/irSxdqJdNCX6AouWBOhun_video.mp4'
fetch office 'https://v3b.fal.media/files/b/0ab2f711/HmJo1NYAjXX3DkKGQDiXg_video.mp4'
fetch shop 'https://v3b.fal.media/files/b/0ab2f717/qSrqTtFs8N_NheaeshqHU_video.mp4'
fetch freelance 'https://v3b.fal.media/files/b/0ab2f706/Zkc-nMpKDABsS48_s-lTU_video.mp4'
fetch paper 'https://v3b.fal.media/files/b/0ab3389f/_fbClyti3zUclA5QZDrhS_video.mp4'
fetch writing 'https://v3b.fal.media/files/b/0ab338a3/k0HCYTS-IuxCPvY0kwPXf_video.mp4'
fetch laptop 'https://v3b.fal.media/files/b/0ab338a6/dtbjjxlcuczHixoGvVzgj_video.mp4'
fetch pickup 'https://v3b.fal.media/files/b/0ab31e3e/yyzDgfGx7-1WgfreFLJeC_video.mp4'
fetch standup 'https://v3b.fal.media/files/b/0ab31e82/vuNbL04R_OT-T6e3i80Cu_video.mp4'
fetch phone 'https://v3b.fal.media/files/b/0ab3389c/ujxhq_Zq9o9A0ERZY8wmg_video.mp4'
fetch tote 'https://v3b.fal.media/files/b/0ab338ad/o3lgdBgzXVfzEDVlLkYd0_video.mp4'
fetch closing 'https://v3b.fal.media/files/b/0ab2fb0f/_67sWIMzqk03u_M8UHiCm_video.mp4'
fetch original_with_voice 'https://v3b.fal.media/files/b/0ab2fc87/LmxpaCExrjb9nl8p9UsUK_combined_output.mp4'

ffmpeg -hide_banner -loglevel error -y -i work/source/original_with_voice.mp4 -vn -ac 2 -ar 48000 -c:a pcm_s16le work/source/gemini_voice.wav
voice_duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 work/source/gemini_voice.wav)
python3 - "$voice_duration" <<'PY'
import sys
d=float(sys.argv[1])
assert 30.55 <= d <= 30.75, f"Original voice duration unexpected: {d}"
PY

# Each segment has an exact integer number of frames. Sum = 735 frames (30.625 s at 24 fps).
# Original 30.64 s narration supplies the final 15 ms of mux duration.
make_cut() {
  local index="$1" name="$2" start="$3" frames="$4"
  ffmpeg -hide_banner -loglevel error -y -ss "$start" -i "work/source/$name.mp4" \
    -vf "scale=720:1280:force_original_aspect_ratio=decrease,pad=720:1280:(ow-iw)/2:(oh-ih)/2:color=0xfffcf6,fps=24,setsar=1,format=yuv420p" \
    -frames:v "$frames" -an -c:v libx264 -preset veryfast -crf 20 -g 48 -pix_fmt yuv420p \
    -video_track_timescale 12288 "work/cuts/$(printf '%02d' "$index").mp4"
}
make_cut 1 s01 0 120
make_cut 2 office 0.30 35
make_cut 3 shop 0.50 29
make_cut 4 freelance 0.20 31
make_cut 5 paper 0.12 55
make_cut 6 writing 0.10 53
make_cut 7 laptop 0.20 66
make_cut 8 pickup 0.60 54
make_cut 9 standup 0.30 57
make_cut 10 phone 0.20 67
make_cut 11 tote 0.45 38
make_cut 12 closing 0.35 70

# Approved optimized logo: use original transparent PNG on clean warm-white canvas.
test -s site/assets/optimized-logo.png
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "color=c=0xfffcf6:s=720x1280:r=24" -loop 1 -i site/assets/optimized-logo.png \
  -filter_complex "[1:v]scale=650:650,format=rgba,fade=t=in:st=0:d=0.30:alpha=1[lg];[0:v][lg]overlay=(W-w)/2:(H-h)/2:shortest=1,format=yuv420p[v]" \
  -map "[v]" -frames:v 60 -an -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -video_track_timescale 12288 work/cuts/13.mp4

: > work/cuts/concat.txt
for i in $(seq -w 1 13); do printf "file '%s.mp4'\n" "$i" >> work/cuts/concat.txt; done
(cd work/cuts && ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i concat.txt -c copy ../video_only.mp4)

ffmpeg -hide_banner -loglevel error -y -i work/video_only.mp4 -i work/source/gemini_voice.wav \
  -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -ar 48000 \
  -t 30.64 -movflags +faststart site/assets/XingDai_V5_Full_NoSubtitles.mp4

python3 - <<'PY'
import json,subprocess,os
p="site/assets/XingDai_V5_Full_NoSubtitles.mp4"
info=json.loads(subprocess.check_output(["ffprobe","-v","error","-show_streams","-show_format","-of","json",p]))
dur=float(info["format"]["duration"])
vs=[s for s in info["streams"] if s["codec_type"]=="video"]
au=[s for s in info["streams"] if s["codec_type"]=="audio"]
assert 30.55<=dur<=30.75, f"Duration error: {dur}"
assert len(vs)==1 and len(au)==1, "Video/audio stream missing"
assert vs[0]["width"]==720 and vs[0]["height"]==1280, "Wrong dimensions"
assert os.path.getsize(p)>1000000, "Output unexpectedly small"
print(f"VERIFIED: {p}, duration={dur:.3f}s, 720x1280, audio+video, size={os.path.getsize(p)}")
PY
ffmpeg -hide_banner -loglevel error -i site/assets/XingDai_V5_Full_NoSubtitles.mp4 -f null - </dev/null

# Thumbnail of the finished movie for the public page.
ffmpeg -hide_banner -loglevel error -y -ss 16.9 -i site/assets/XingDai_V5_Full_NoSubtitles.mp4 -frames:v 1 -q:v 3 site/assets/V5-final-preview.jpg
