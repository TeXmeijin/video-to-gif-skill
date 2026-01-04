#!/bin/bash
# merge_videos_to_gif.sh - Merge multiple videos into a single GIF
# Usage: ./merge_videos_to_gif.sh -o output.gif [-w 800] [-h 338] [-f 8] [-c 128] [-l 80] video1.mov:speed1 video2.mov:speed2 ...
# Example: ./merge_videos_to_gif.sh -o demo.gif -w 800 -h 338 first.mov:2 second.mov:4.75 third.mov:4.75

set -e

# Default values
WIDTH=800
HEIGHT=338
FPS=8
COLORS=128
LOSSY=80
OUTPUT=""
TMPDIR=$(mktemp -d)

cleanup() {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

usage() {
    echo "Usage: $0 -o output.gif [options] video1:speed1 video2:speed2 ..."
    echo ""
    echo "Options:"
    echo "  -o FILE    Output GIF file (required)"
    echo "  -w WIDTH   Output width (default: 800)"
    echo "  -h HEIGHT  Output height (default: 338)"
    echo "  -f FPS     Frames per second (default: 8)"
    echo "  -c COLORS  Max colors for GIF (default: 128)"
    echo "  -l LOSSY   Lossy compression level 0-200 (default: 80)"
    echo ""
    echo "Video format: path/to/video.mov:speed_multiplier"
    echo "  speed_multiplier: 1 = original speed, 2 = 2x faster, 0.5 = half speed"
    echo ""
    echo "Example:"
    echo "  $0 -o demo.gif -w 800 -h 338 first.mov:2 second.mov:4.75 third.mov:4.75"
    exit 1
}

# Parse options
while getopts "o:w:h:f:c:l:" opt; do
    case $opt in
        o) OUTPUT="$OPTARG" ;;
        w) WIDTH="$OPTARG" ;;
        h) HEIGHT="$OPTARG" ;;
        f) FPS="$OPTARG" ;;
        c) COLORS="$OPTARG" ;;
        l) LOSSY="$OPTARG" ;;
        *) usage ;;
    esac
done
shift $((OPTIND-1))

# Check required arguments
if [ -z "$OUTPUT" ] || [ $# -eq 0 ]; then
    usage
fi

# Check dependencies
for cmd in ffmpeg gifsicle; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is required but not installed."
        echo "Install with: brew install $cmd"
        exit 1
    fi
done

echo "=== Video to GIF Converter ==="
echo "Output: $OUTPUT"
echo "Resolution: ${WIDTH}x${HEIGHT}"
echo "FPS: $FPS, Colors: $COLORS, Lossy: $LOSSY"
echo ""

# Process each video
CONCAT_LIST="$TMPDIR/concat.txt"
> "$CONCAT_LIST"
PART_NUM=0

for arg in "$@"; do
    VIDEO="${arg%:*}"
    SPEED="${arg#*:}"

    if [ ! -f "$VIDEO" ]; then
        echo "Error: Video file not found: $VIDEO"
        exit 1
    fi

    if [ -z "$SPEED" ] || [ "$SPEED" = "$VIDEO" ]; then
        SPEED=1
    fi

    PART_NUM=$((PART_NUM + 1))
    PART_FILE="$TMPDIR/part${PART_NUM}.mp4"

    echo "Processing: $VIDEO (speed: ${SPEED}x)"

    # Scale and speed up video
    ffmpeg -y -i "$VIDEO" \
        -vf "scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=decrease,pad=${WIDTH}:${HEIGHT}:(ow-iw)/2:(oh-ih)/2:black,setpts=PTS/${SPEED}" \
        -c:v libx264 -crf 18 -an \
        "$PART_FILE" 2>/dev/null

    echo "file '$PART_FILE'" >> "$CONCAT_LIST"
done

echo ""
echo "Merging videos..."
MERGED="$TMPDIR/merged.mp4"
ffmpeg -y -f concat -safe 0 -i "$CONCAT_LIST" -c copy "$MERGED" 2>/dev/null

# Get duration
DURATION=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of csv=p=0 "$MERGED")
echo "Total duration: ${DURATION}s"

echo ""
echo "Generating GIF..."
PALETTE="$TMPDIR/palette.png"
RAW_GIF="$TMPDIR/raw.gif"

# Generate palette
ffmpeg -y -i "$MERGED" \
    -vf "fps=${FPS},palettegen=max_colors=${COLORS}" \
    "$PALETTE" 2>/dev/null

# Generate GIF with palette
ffmpeg -y -i "$MERGED" -i "$PALETTE" \
    -filter_complex "fps=${FPS}[v];[v][1:v]paletteuse=dither=bayer:bayer_scale=3" \
    "$RAW_GIF" 2>/dev/null

echo ""
echo "Compressing GIF..."
gifsicle -O3 --colors "$COLORS" --lossy="$LOSSY" "$RAW_GIF" -o "$OUTPUT" 2>/dev/null || cp "$RAW_GIF" "$OUTPUT"

# Report results
SIZE=$(ls -la "$OUTPUT" | awk '{print $5}')
SIZE_KB=$((SIZE / 1024))
echo ""
echo "=== Done ==="
echo "Output: $OUTPUT"
echo "Size: ${SIZE_KB} KB"
