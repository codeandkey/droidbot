#!/bin/bash

root=$(dirname $0)
filename=$4

echo "Downloading from youtube source."
youtube-dl -q --postprocessor-args "-ss $2 -t 0:0:$3" -o "$root/$filename" "$1" || exit 1

echo "Converting and trimming."
ffmpeg -loglevel error -i $root/$filename.* "$root/../sounds/$filename.mp3" 2>&1 >/dev/null || exit 2

rm -f $root/$filename*

echo "Grab succeeded: $filename"
