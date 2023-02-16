# comparevidsbyframes
A simple bash script that extract a single frame from each found video and compare it in the Czkawka_cli program.
Czkawka_cli is an excellent program created by Rafał Mikrut (https://github.com/qarmin).
This program already has the feature of comparing similar videos by calculating the hash from the video file. Unfotunately, even small visual differences between videos (e.g. "b" video is slightly shorter than "a") can result in large differences in hashes. But if we know our videos may have a very simillar beginnig, there is no need to hash the entire video, and hashing screenshots from the same timestamp may be more reliable.
Here's what this script does: It fetches screenshots of the set timestamp of all your mp4 files, pass them to czkawka_cli for comparison, and finally creates an m3u playlist where all similliar videos should by placed side-by-side.
