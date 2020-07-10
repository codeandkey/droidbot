#!/bin/sh

# creates an MPD configuration for droidbot.

echo "pid_file \"$(pwd)/mpd.pid\"
db_file \"$(pwd)/mpd.db\"
state_file \"$(pwd)/mpdstate\"
playlist_directory \"$(pwd)/playlists\"
music_directory \"$(pwd)/sounds\"

audio_output {
    type \"fifo\"
    name \"FIFO\"
    path \"$(pwd)/mpd.fifo\"
    format \"24000:16:2\"
    mixer_type \"software\"
}" > $(dirname $0)/mpd.conf
