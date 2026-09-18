#!/bin/sh
# Encode the Seedance 2.5 raw clips (docs/design/mascot-animations/raw, 640x640)
# into the small, silent, gapless loops bundled with the iOS app.
#   mascot-<char>-<phase>.mp4        480x480 full figure (large indicators)
#   mascot-<char>-thinking-small.mp4 144x144 head crop (inline indicators)
#   mascot-<char>-poster[-small].jpg first frame of the encoded thinking loop
#                                    (Reduce Motion / paused / before first frame)
# Seedance returns close to, but not exactly, to the start frame, so the last
# 0.25 s is blended toward the first frame to hide the loop point. H.264 so the same files play in the HTML review
# gallery and in AVPlayer.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RAW="$ROOT/docs/design/mascot-animations/raw"
OUT="$ROOT/ios/CraftStudio/Resources/Mascot"
mkdir -p "$OUT"
FADE=0.25

# Head-and-shoulders crops in the 640x640 source (w:h:x:y), chosen so the
# thinking orb stays in frame.
crop_for() { case "$1" in dragon) echo "300:300:150:0" ;; panda) echo "280:280:180:0" ;; esac; }

# encode <input> <output> <frame filter> <crf>
# Frame 0 (the original art) stays the first frame. Over the last $FADE seconds
# the clip blends toward that exact frame, reaching it one frame after the end.
encode() {
  duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$1")
  start=$(echo "$duration - $FADE" | bc -l)
  frames=$(mktemp -d)
  ffmpeg -v error -y -i "$1" -vf "fps=24,$3" -frames:v 1 "$frames/first.png"
  # The blend only takes effect reliably when rendered to image frames, so the
  # loop is rendered losslessly first and encoded afterwards.
  ffmpeg -v error -y -i "$1" -loop 1 -framerate 24 -i "$frames/first.png" -filter_complex \
    "[0:v]fps=24,$3,format=yuv444p[v];[1:v]format=yuv444p[f];[v][f]blend=all_expr='A+(B-A)*clip((T-$start)/$FADE,0,1)':shortest=1" \
    -vsync 0 "$frames/f%03d.png"
  ffmpeg -v error -y -framerate 24 -i "$frames/f%03d.png" -pix_fmt yuv420p \
    -c:v libx264 -preset veryslow -profile:v high -crf "$4" -an -movflags +faststart "$2"
  rm -rf "$frames"
}

for char in dragon panda; do
  for phase in thinking concept model; do
    encode "$RAW/$char-$phase.mp4" "$OUT/mascot-$char-$phase.mp4" "scale=480:480:flags=lanczos" 27
  done
  encode "$RAW/$char-thinking.mp4" "$OUT/mascot-$char-thinking-small.mp4" \
    "crop=$(crop_for $char),scale=144:144:flags=lanczos" 26
  ffmpeg -v error -y -i "$OUT/mascot-$char-thinking.mp4" -frames:v 1 -q:v 4 "$OUT/mascot-$char-poster.jpg"
  ffmpeg -v error -y -i "$OUT/mascot-$char-thinking-small.mp4" -frames:v 1 -q:v 3 "$OUT/mascot-$char-poster-small.jpg"
done
ls -l "$OUT"
