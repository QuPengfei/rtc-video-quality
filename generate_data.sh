#!/bin/bash

function help_and_exit() {
  >&2 echo Usage: ./generate_data.sh ENCODER BITRATE_KBPS FPS file.WIDTH_HEIGHT.yuv
  exit 1
}

function libvpx() {
  COMMON_PARAMS="--lag-in-frames=0 --error-resilient=1 --kf-min-dist=3000 --kf-max-dist=3000 --static-thresh=1 --end-usage=cbr --undershoot-pct=100 --overshoot-pct=15 --buf-sz=1000 --buf-initial-sz=500 --buf-optimal-sz=600 --max-intra-rate=900 --resize-allowed=0 --drop-frame=0 --passes=1 --rt --noise-sensitivity=0"
  if [ "$VPX_CODEC" = "vp8" ]; then
    CODEC_PARAMS="--codec=vp8 --cpu-used=-6 --min-q=2 --max-q=56 --screen-content-mode=0 --threads=4"
  else
    # VP9
    CODEC_PARAMS="--codec=vp9 --cpu-used=7 --min-q=2 --max-q=52 --aq-mode=3 --threads=8"
  fi
  ENCODED_FILE="$OUT_DIR/out.webm"
  set -x
  libvpx/vpxenc $CODEC_PARAMS $COMMON_PARAMS --fps=$FPS/1 --target-bitrate=$BITRATE_KBPS --width=$WIDTH --height=$HEIGHT -o "$ENCODED_FILE" "$FILE"
  { set +x; } 2>/dev/null
}

function play_mplayer() {
  mplayer -demuxer rawvideo -rawvideo w=$WIDTH:h=$HEIGHT:fps=$FPS:format=i420 "$FILE"
  exit 0 # Do not continue with SSIM/PSNR comparison.
}

function libvpx_tl() {
  THREADS=4
  if [ "$VPX_CODEC" = "vp8" ]; then
    # TODO(pbos): Account for low resolutions (use CPU=4)
    CODEC_CPU=6
  else
    # VP9
    # TODO(pbos): Account for low resolutions (use CPU=5)
    CODEC_CPU=7
  fi
  ENCODED_FILE="$OUT_DIR/out"
  # TODO(pbos): Add support for non-hardcoded lower-layer bitrates.
  if [ "$TEMPORAL_LAYERS" = "2" ]; then
    LAYER_STRATEGY=8
    BITRATES="1300 $BITRATE_KBPS"
  elif [ "$TEMPORAL_LAYERS" = "3" ]; then
    LAYER_STRATEGY=10
    BITRATES="800 1300 $BITRATE_KBPS"
  else
    >&2 echo Incorrect temporal layers.
    exit 1
  fi
  set -x
  libvpx/examples/vpx_temporal_svc_encoder "$FILE" "$ENCODED_FILE" $VPX_CODEC $WIDTH $HEIGHT 1 $FPS $CODEC_CPU 0 $THREADS $LAYER_STRATEGY $BITRATES
  { set +x; } 2>/dev/null
  # TODO(pbos): Support lower layers for SSIM/PSNR too.
  ENCODED_FILE=${ENCODED_FILE}_`expr $TEMPORAL_LAYERS "-" 1`.ivf
}

ENCODER="$1"
if [ "$ENCODER" = "libvpx-vp8" ]; then
  ENCODER_COMMAND=libvpx
  VPX_CODEC=vp8
  OUT_DIR=out/$ENCODER
elif [ "$ENCODER" = "libvpx-vp9" ]; then
  ENCODER_COMMAND=libvpx
  VPX_CODEC=vp9
  OUT_DIR=out/$ENCODER
elif [ "$ENCODER" = "libvpx-vp8-1sl2tl" ]; then
  ENCODER_COMMAND=libvpx_tl
  VPX_CODEC=vp8
  TEMPORAL_LAYERS=2
  OUT_DIR=out/$ENCODER
elif [ "$ENCODER" = "libvpx-vp9-1sl2tl" ]; then
  ENCODER_COMMAND=libvpx_tl
  VPX_CODEC=vp9
  TEMPORAL_LAYERS=2
  OUT_DIR=out/$ENCODER
elif [ "$ENCODER" = "libvpx-vp8-1sl3tl" ]; then
  ENCODER_COMMAND=libvpx_tl
  VPX_CODEC=vp8
  TEMPORAL_LAYERS=3
  OUT_DIR=out/$ENCODER
elif [ "$ENCODER" = "libvpx-vp9-1sl3tl" ]; then
  ENCODER_COMMAND=libvpx_tl
  VPX_CODEC=vp9
  TEMPORAL_LAYERS=3
  OUT_DIR=out/$ENCODER
#TODO(pbos): Add support for more encoders here, libva/ffmpeg/etc.
elif [ "$ENCODER" = "play" ]; then
  ENCODER_COMMAND=play_mplayer
  OUT_DIR=""
else
  >&2 echo Unknown encoder: "'$ENCODER'"
  help_and_exit
fi

# Uncomment for a verbose mode:
BITRATE_KBPS="$2"

if [ ! "$BITRATE_KBPS" ]; then
  help_and_exit
fi

FPS="$3"

if [ ! "$FPS" ]; then
  help_and_exit
fi

FILE="$4"
[[ "$FILE" =~ ([0-9]+)_([0-9]+).yuv$ ]] || { >&2 echo File needs to contain WIDTH_HEIGHT.yuv; help_and_exit; }
WIDTH=${BASH_REMATCH[1]}
HEIGHT=${BASH_REMATCH[2]}
OUT_FILE="out.${WIDTH}_${HEIGHT}.yuv"

if [ "$OUT_DIR" ]; then
  if [ -d "$OUT_DIR" ]; then
    rm -r "$OUT_DIR"
  fi
  mkdir -p "$OUT_DIR"
fi

START_TIME=$(date +%s.%N)
$ENCODER_COMMAND
END_TIME=$(date +%s.%N)
ENCODE_SEC=$(bc <<< "($END_TIME - $START_TIME)")

libvpx/vpxdec --i420 --codec=$VPX_CODEC -o "$OUT_DIR/$OUT_FILE" "$ENCODED_FILE"

libvpx/tools/tiny_ssim "$FILE" "$OUT_DIR/$OUT_FILE" ${WIDTH}x${HEIGHT} > "$OUT_DIR/results.txt"
RESULTS=`cat $OUT_DIR/results.txt`
echo
echo "$FILE" "(${WIDTH}x${HEIGHT}@$FPS)" "->" "$ENCODED_FILE" "->" "$OUT_DIR/$OUT_FILE"
echo
echo Encoder: $ENCODER
echo Codec: $VPX_CODEC
echo "$RESULTS"
[[ "$RESULTS" =~ Nframes:\ ([0-9]+) ]] || { >&2 echo HOLY WHAT BORK BORK; exit 1; }
FRAMES=${BASH_REMATCH[1]}
echo Target bitrate: `expr $BITRATE_KBPS "*" 1000`
BITRATE_USED=$(expr `wc -c < "$ENCODED_FILE"` "*" 8 "*" $FPS "/" $FRAMES)
echo Bitrate: $BITRATE_USED
echo BitrateUtilization: $(bc <<< "scale=2; $BITRATE_USED/($BITRATE_KBPS * 1000)")
echo EncodeMs: $(bc <<< "scale=0; $ENCODE_SEC * 1000")
echo EncodeTimeUsed: $(bc <<< "scale=2; $ENCODE_SEC / ($FRAMES / $FPS)")