#!/bin/bash
set -e

# czkawka_cli config
filter="Lanczos3"
algorithm="Gradient"
hashsize=8
# "VeryHigh" "High" "Medium" "Small" "VerySmall" "Minimal"
similarity="VeryHigh"
czkawkaoptions="--minimal-file-size 1 --image-filter $filter --hash-alg $algorithm \
--hash-size $hashsize --similarity-preset $similarity"

# Help
information="
This script creates a folder where all fetched frames are stored. They are then compared by the czkawka_cli
program and as the final result the M3U playlist with all similar videos is created.
If the frames folder already exists the script will check that all stored frames have their 
corresponding video (if it were not deleted). If video is not found, frame will be deleted. 
If video exist, but don't have a frame, it will be generated.

\033[1;33mczkawka_cli\033[0m will be used with the following configuration:"

help() {
echo -e "\
\033[1;33m$(basename "$0")\033[0m [-n] [-s=<INT> / -t] [-c=<STRING>] [-i=<TXTFILE>] [<PATH>] 
A script to compare frames from the set point of videos to find similar variations.

Dependencies: \033[1;33mffmpeg\033[0m, \033[1;33mmediainfo\033[0m and \033[1;33mczkawka_cli\033[0m
Optional:     \033[1;33mffmpegthumbnailer\033[0m is required for the '-t' option to work 
$information
$czkawkaoptions

\033[1;33mOptions\033[0m:
    -h        --help                   Show this text
    -n        --non-recursive          Don't search for videos in other folders
    -t        --use-thumbnails         Use thumbnails cached by the KDE Dolphin
    -s=n      --frame-from-sec=n       Fetch a frame n seconds from the beginning of the video 
                                       or from the end if n is negative.
                                       [by default, the script will take frame from the 2nd second]
    -c=       --czkawka-config=        Pass your own czkawka_cli configuration
    -i=       --ignore-locations=      Ignore files in locations listed in the passed txt file
"
}

# Script arguments
for i in "$@"; do
  case $i in
    -h|--help)
      help
      exit
      ;;
    -n|--non-recursive)
      nonrecursive="-maxdepth 1"
      shift
      ;;
    -t|--use-thumbs)
      usecache=1
      shift
      ;;
    -s=*|--frame-from-sec=*)
      if [ "${i#*=}" -eq "${i#*=}" ] 2> /dev/null && [ "${i#*=}" -ne 0 ];then
        declare -i framefromsec=${i#*=}
      else
        echo "Incorrect input. It should be integer different from 0"
        help
        exit 1
      fi
      shift
      ;;
    -c=*|--czkawka-config=*)
      czkawkaoptions=${i#*=}
      shift
      ;;
    -i=*|--ignore-locations=*)
      if [ -f "${i#*=}" ] && [[ "${i#*=}" == *".txt" ]]; then
        readarray -t ignore < "${i#*=}"
      else
        echo "${i#*=} - file doesn't exist or is not a txt file"
        exit 1
      fi
      shift
      ;;
    -*)
      echo "Unknown option $i"
      help
      exit 1
      ;;
    *)
      if [ -d "$i" ];then
        cd "$i"
      else
        echo "Unknown input: $i"
        help
        exit 1
      fi
      ;;
  esac
done

# Information
echo -e "\
$information
$czkawkaoptions

Script will work from this point: \033[1;33m$PWD\033[0m"
if [ -z "$nonrecursive" ];then echo -e "\033[1;31m! RECURSIVE !\033[0m";fi
if [ -n "$usecache" ] && ! command -v "dolphin" &> /dev/null ;then 
echo -e "
It seems that you use a different file manager than KDE Dolphin.
Dolphin stores thumbnails in ${HOME}/.cache/thumbnails/<medium|large|x-large|xx-large>
as a PNG files named after a hashed URI version of their video path.
The script searches these directories, creates missing thumnails, and link them all to the /_frames
directory. Sript uses this conversion method to match existing thumbnais created by Dolphin:
ffmpegthumbnailer -t 20 -s 128 -f -i <input> -o <output>
Before proceeding, make sure your file manager behaves in a similar way!
"
fi

# Dependency check
depcheck() {
  for d in "$@";do
    if ! command -v "$d" &> /dev/null;then
      echo -e "\033[0;33m$d\033[0m could not be found"
      exit 3
    fi
  done
}

depcheck "czkawka_cli" "ffmpeg" "mediainfo"
if [ -n "$usecache" ];then depcheck "ffmpegthumbnailer";fi

# Prompt for confirmation
read -r -p "Are you ready to proceed? y/N:" -N 1
if  ! { [ "$REPLY" == "y" ] || [ "$REPLY" == "Y" ]; };then
  echo -e '\r'
  exit
fi
echo -e '\r'

# Variable declarations
if [ -z "$framefromsec" ];then
  declare -i framefromsec=2
fi

cachedir="$HOME/.cache/thumbnails"
dirforframes="_frames"
if [ -z "$usecache" ];then 
  dirforframes+="_from_${framefromsec}_sec"
  format="jpg"
else
  format="png"
fi
if [ "$framefromsec" -gt 0 ];then time="-ss ${framefromsec}";else time="-sseof ${framefromsec}";fi


# Create a frame folder 
if [ ! -d "$PWD/$dirforframes" ];then
  mkdir "$dirforframes"
  declare -i firstrun=1
fi

# Folder exclusion mechanism
if [ -n "${ignore}" ];then
  ignorearg="-type d \("
  for j in "${ignore[@]}";do
    j=$(echo $j|sed 's/\/$//')
    ignorearg+=" -path \""$j"\" -o"
  done
  ignorearg=${ignorearg%-o}
  ignorearg+="\) -prune -o"
  findcommand="find \""$PWD"/\" $ignorearg $nonrecursive -type f -iname '*.mp4' -print0"
  readarray -d '' vidslist < <(eval $findcommand)
else
  readarray -d '' vidslist < <(find "$PWD/" $nonrecursive -type f -iname '*.mp4' -print0)
fi

#echo "V1:${#vidslist[@]}"

# Frames cleanup mechanism: remove orphans and exclude existing frames from the fetch mechanism
if [ -z "$firstrun" ];then
  echo -e  "Updating an existing frames folder..."
  readarray -d '' existingframes < <(find "$PWD/$dirforframes/" -type f -print0)
  readarray -d '' filesforexistingframes < <(printf "%s\0" "${existingframes[@]}" | \
    sed -E "s|${dirforframes}\/||g;s|%s%|\/|g;s|\.frame\.${format}\x0|\x0|g")
  readarray -d '' differrences < <(comm -3z \
    <(printf "%s\0" "${vidslist[@]}" | sort -z) \
    <(printf "%s\0" "${filesforexistingframes[@]}" | sort -z))
  readarray -d '' removedfiles < <(printf "%s\0" "${differrences[@]}" | \
    awk -F"\t" 'BEGIN{RS="\0";ORS="\0"} $2{ print $2; }')
  readarray -d '' framestoremove < <(printf "%s\0" "${removedfiles[@]}" | \
    sed -E "s|${PWD}\/||g;s|\/|%s%|g;s|\.mp4\x0|\.mp4\.frame\.${format}\x0|g")
  readarray -d '' vidslist < <(printf "%s\0" "${differrences[@]}" | \
    awk -F"\t" 'BEGIN{RS="\0";ORS="\0"} $1{ print $1; }')
  cd "${PWD}/${dirforframes}"
  if [ -n "${framestoremove}" ];then
    for r in "${framestoremove[@]}";do rm "$r";done
  fi
  cd ..
fi
declare -i totalvids=${#vidslist[@]}
echo -e '\033[1;33m'$totalvids videos to process.'\033[0m'

#echo "EF:${#existingframes[@]}"
#echo "RV:${#removedfiles[@]}"
#echo "V2:${#vidslist[@]}"
#read

# Frame fetch mechanism

readarray -d '' namesofframes < <(printf "%s\0" "${vidslist[@]}" | \
  sed -E "s|${PWD}\/||g;s|\/|%s%|g;s|\.mp4\x0|\.mp4\.frame\.${format}\x0|g")
#readarray -d '' pathesofframes < <(printf "${PWD}/${dirforframes}/%s\0" "${namesofframes[@]}" )

if [ -z "$usecache" ];then
  for v in "${!vidslist[@]}";do
    pathtoframe="${PWD}/${dirforframes}/${namesofframes[$v]}"
    #d=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration \
    #  -of default=noprint_wrappers=1:nokey=1 "${vidslist[$v]}" | sed -E "s|\..*$||")
    #if [[ "$d" -ge "${framefromsec#-}" ]];then
    if [[ $(mediainfo --Output='Video;%Duration%' "${vidslist[$v]}") -gt "${framefromsec#-}000" ]];then
      ffmpeg $time -i "${vidslist[$v]}"  -hide_banner -loglevel error -frames:v 1 -q:v 2 \
        -vf scale=w=128:h=128:force_original_aspect_ratio=decrease "$pathtoframe"
    fi
    echo -ne "  $(( (v+1)*100/totalvids ))%  Fetched $(( v+1 )) frames from $totalvids videos.\r"
  done
else
  readarray -d '' md5list < <(printf "file://%s\0" "${vidslist[@]}" | \
    perl -0 -MURI::file -MDigest::MD5=md5_hex -lpe '$_ = md5_hex $_' | \
    sed -E "s|\x0|\.png\x0|g")
  for v in "${!vidslist[@]}"; do
    pathtoframe="${PWD}/${dirforframes}/${namesofframes[$v]}"
    pathtothumbnail=
    pathtothumbnail=$(find "$cachedir" -name "${md5list[$v]}" -print -quit)
    if [ -z "$pathtothumbnail" ];then
      pathtothumbnail="$cachedir/normal/${md5list[$v]}"
      ffmpegthumbnailer -t 20 -s 128 -f -i "${vidslist[$v]}" -o "$pathtothumbnail" 2> /dev/null || \
        echo "File error: ${vidslist[$v]}"
    fi 
    ln "$pathtothumbnail" "$pathtoframe"
    echo -ne "  $(( (v+1)*100/totalvids ))%  Fetched $(( v+1 )) thumbnails from $totalvids videos.\r"
  done
fi
echo -e ""
echo -e  "\033[1;33mFrame comparison with czkawka_cli:\033[0m"

# Pass data to czkawka_cli
czkawka_cli image --directories "$PWD/$dirforframes" $czkawkaoptions --file-to-save "./dupes.m3u"
sed -n -i "s/$dirforframes\///;s/%s%/\//g;s/\.frame\.${format}.*$//p" ./dupes.m3u
sed -i ' 1 s/.*/#EXTM3U\n&/' ./dupes.m3u
