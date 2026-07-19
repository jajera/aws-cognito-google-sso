#!/usr/bin/env bash
# Assemble a walkthrough video from docs/images screenshots.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SLIDES="$ROOT/docs/videos/slides"
OUT="$ROOT/docs/videos/cognito-google-sso-walkthrough.mp4"
FONT="/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONTB="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
W=1920
H=1080
BG="0x0B1220"
ACCENT="0xFF9900"
REPO="github.com/jajera/aws-cognito-google-sso"
FOOTER_H=56
# Content area under caption bar — images fit inside without stretching
MAX_W=1840
MAX_H=920
CAPTION_H=88

rm -rf "$SLIDES"
mkdir -p "$SLIDES"

make_card() {
  local file="$1" duration="$2" title="$3" subtitle="$4"
  local title_file="$file.title.txt"
  local sub_file="$file.sub.txt"
  printf '%s' "$title" >"$title_file"
  printf '%s' "$subtitle" >"$sub_file"
  ffmpeg -y -hide_banner -loglevel error \
    -f lavfi -i "color=c=${BG}:s=${W}x${H}:d=${duration}" \
    -vf "drawtext=fontfile=${FONTB}:textfile=${title_file}:fontcolor=white:fontsize=64:x=(w-text_w)/2:y=h*0.38,\
drawtext=fontfile=${FONT}:textfile=${sub_file}:fontcolor=0xC5D0E0:fontsize=34:x=(w-text_w)/2:y=h*0.52,\
drawbox=x=0:y=0:w=iw:h=8:color=${ACCENT}:t=fill,\
drawbox=x=0:y=ih-${FOOTER_H}:w=iw:h=${FOOTER_H}:color=0x111827:t=fill,\
drawtext=fontfile=${FONT}:text='${REPO}':fontcolor=0x9FB2CC:fontsize=26:x=(w-text_w)/2:y=h-${FOOTER_H}+15" \
    -c:v libx264 -pix_fmt yuv420p -r 30 "$file"
}

# Fit screenshot into frame preserving aspect ratio (letterbox/pillarbox, never stretch)
make_shot() {
  local src="$1" file="$2" duration="$3" caption="$4"
  local cap_file="$file.cap.txt"
  printf '%s' "$caption" >"$cap_file"
  ffmpeg -y -hide_banner -loglevel error \
    -loop 1 -t "$duration" -i "$src" \
    -f lavfi -t "$duration" -i "color=c=${BG}:s=${W}x${H}" \
    -filter_complex "[0:v]scale=${MAX_W}:${MAX_H}:force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1[img];\
[1:v][img]overlay=(W-w)/2:${CAPTION_H}+(${MAX_H}-h)/2[base];\
[base]drawbox=x=0:y=0:w=iw:h=${CAPTION_H}:color=0x111827:t=fill,\
drawtext=fontfile=${FONTB}:textfile=${cap_file}:fontcolor=white:fontsize=34:x=48:y=26,\
drawbox=x=0:y=0:w=iw:h=6:color=${ACCENT}:t=fill,\
drawbox=x=0:y=ih-${FOOTER_H}:w=iw:h=${FOOTER_H}:color=0x111827:t=fill,\
drawtext=fontfile=${FONT}:text='${REPO}':fontcolor=0x9FB2CC:fontsize=26:x=(w-text_w)/2:y=h-${FOOTER_H}+15" \
    -c:v libx264 -pix_fmt yuv420p -r 30 "$file"
}

echo "Rendering title cards..."
make_card "$SLIDES/01-title.mp4" 4 \
  "Amazon Cognito Google SSO" \
  "Terraform walkthrough with PKCE demo app"

make_card "$SLIDES/02-agenda.mp4" 5 \
  "What this demo shows" \
  "Hosted app · Google federation · Cognito allowlist"

echo "Rendering architecture + screenshots (aspect preserved)..."
make_shot "$ROOT/docs/images/cognito-google-sso-architecture.png" "$SLIDES/03-architecture.mp4" 8 \
  "Architecture — CloudFront, Cognito, Google, optional allowlist Lambda"

make_shot "$ROOT/docs/images/demo-sign-in-page.png" "$SLIDES/04-signin.mp4" 4 \
  "1. CloudFront demo app — Sign in with Google"

make_shot "$ROOT/docs/images/google-oauth-client.png" "$SLIDES/05-oauth.mp4" 6 \
  "2. Google OAuth client — Cognito origin + redirect URI"

make_shot "$ROOT/docs/images/google-account-chooser.png" "$SLIDES/06-chooser.mp4" 4 \
  "3. Google account chooser"

make_shot "$ROOT/docs/images/google-consent-screen.png" "$SLIDES/07-consent.mp4" 5 \
  "4. Google consent — Cognito requests email"

make_shot "$ROOT/docs/images/demo-signed-in-workspace.png" "$SLIDES/08-workspace.mp4" 5 \
  "5. Allowed user — protected workspace + ID token claims"

make_shot "$ROOT/docs/images/cognito-federated-user.png" "$SLIDES/09-cognito-user.mp4" 5 \
  "6. Cognito Users — federated Google profile created"

make_card "$SLIDES/10-allowlist-note.mp4" 6 \
  "Authorization is in Cognito" \
  "Google verifies identity — Cognito pre-sign-up enforces the email allowlist"

make_shot "$ROOT/docs/images/demo-sign-in-denied.png" "$SLIDES/11-denied.mp4" 5 \
  "7. Email not on allowlist — Cognito rejects — app shows generic error"

make_card "$SLIDES/12-end.mp4" 5 \
  "Full steps are in the README" \
  "${REPO}"

echo "Concatenating..."
list="$SLIDES/concat.txt"
: > "$list"
for f in "$SLIDES"/[0-9]*.mp4; do
  printf "file '%s'\n" "$f" >> "$list"
done

SILENT="$SLIDES/_video.mp4"
ffmpeg -y -hide_banner -loglevel error -f concat -safe 0 -i "$list" \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$SILENT"

# Background music:
# 1) If docs/videos/music.mp3 (or .m4a/.wav) exists, use it (drop in any royalty-free track).
# 2) Otherwise synthesize a soft, copyright-free ambient pad with ffmpeg.
DUR=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$SILENT")
MUSIC=""
for cand in "$ROOT/docs/videos/music.mp3" "$ROOT/docs/videos/music.m4a" "$ROOT/docs/videos/music.wav"; do
  [ -f "$cand" ] && MUSIC="$cand" && break
done

if [ -z "$MUSIC" ]; then
  echo "No music file found — synthesizing ambient track..."
  MUSIC="$SLIDES/_music.wav"
  # Gentle Amaj-ish pad: layered low-volume sines with tremolo, slow chord swells.
  ffmpeg -y -hide_banner -loglevel error \
    -f lavfi -i "sine=frequency=110:duration=${DUR}" \
    -f lavfi -i "sine=frequency=164.81:duration=${DUR}" \
    -f lavfi -i "sine=frequency=220:duration=${DUR}" \
    -f lavfi -i "sine=frequency=277.18:duration=${DUR}" \
    -filter_complex "[0:a]volume=0.18[a0];[1:a]volume=0.12[a1];[2:a]volume=0.10[a2];[3:a]volume=0.08[a3];\
[a0][a1][a2][a3]amix=inputs=4:normalize=0,tremolo=f=0.15:d=0.6,\
aecho=0.8:0.7:600:0.25,lowpass=f=1200,afade=t=in:st=0:d=3,afade=t=out:st=$(awk "BEGIN{print ${DUR}-3}"):d=3[aout]" \
    -map "[aout]" -ac 2 -ar 44100 "$MUSIC"
fi

echo "Muxing music..."
ffmpeg -y -hide_banner -loglevel error \
  -i "$SILENT" -stream_loop -1 -i "$MUSIC" \
  -filter_complex "[1:a]volume=0.5[m]" \
  -map 0:v -map "[m]" -shortest \
  -c:v copy -c:a aac -b:a 192k -movflags +faststart "$OUT"

secs=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT" | cut -d. -f1)
size=$(du -h "$OUT" | cut -f1)
echo "Wrote $OUT (${secs}s, ${size})"

# Drop intermediate slide clips; keep only the final mp4 in docs/videos/
rm -rf "$SLIDES"
