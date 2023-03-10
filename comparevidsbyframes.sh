#!/bin/bash
set -e

# czkawka_cli config
filter="Lanczos3"
algorithm="Gradient"
hashsize=8
# "VeryHigh" "High" "Medium" "Small" "VerySmall" "Minimal"
similarity="VeryHigh"
czkawkaoptions="--minimal-file-size 1 --image-filter $filter --hash-alg $algorithm --hash-size $hashsize --similarity-preset $similarity"

# Help
information="\033[1;31m! By default this script runs RECURSIVE !\033[0m

It creates a folder where all fetched frames are stored. They are then compared by the czkawka_cli
program and as the final result the M3U playlist with all similar videos is created.
If the frames folder already exists the script will check that all stored frames have their 
corresponding video (if it were not deleted). If video is not found, frame will be deleted. 
If video exist, but don't have a frame, it will be generated.

\033[1;33mczkawka_cli\033[0m will be used with the following configuration:"

help() {
echo -e "
\033[1;33m$(basename "$0")\033[0m [-n] [-s n] -- a script to compare frames from the set point of videos to find
similar variations.

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
    -c=       --czkawka-config=        Pass your own czkawka_cli configuration instead of the default
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
      if [ ${i#*=} -eq ${i#*=} ] 2> /dev/null && [ ${i#*=} -ne 0 ];then
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
    -*|--*)
      echo "Unknown option $i"
      help
      exit 1
      ;;
    *)
      ;;
  esac
done

# Dependency check
depcheck() {
  for d in "$@";do
    if ! command -v $d &> /dev/null;then
      echo -e "\033[0;33m$d\033[0m could not be found"
      exit 1
    fi
  done
}

depcheck "czkawka_cli" "mediainfo" "ffmpeg"

# Information and prompt for confirmation
echo -e "
$information
$czkawkaoptions
"
read -r -p "Are you ready to proceed? y/N:" -N 1
if  ! { [ "$REPLY" == "y" ] || [ "$REPLY" == "Y" ]; };then
  echo -e '\r'
  exit
fi
echo -e '\r'

# Variable declarations
declare -i i=0
if [ ! $framefromsec ];then
  declare -i framefromsec=2
fi

homedir=~
maindir=~+
dirforframes="_frames"
if [ ! $usecache ];then dirforframes+="_from_${framefromsec}_sec";fi

# Create a frame folder or if it already exist, check the frames in it and list them in an array
if [ -d "$maindir/$dirforframes" ];then
  echo -e  "Updating an existing frames folder..."
  existingframes=()
  for f in "$maindir/$dirforframes/"*.png;do
    test=$(echo "$f" | sed -r "s/$dirforframes\///;s/%s%/\//g;s/\.frame\.png.*$//")
    if [ ! -f "$test" ];then
      rm "$f"
    else
      existingframes+=("$test")
    fi
  done
else
  mkdir "$dirforframes"
  declare -i firstrun=1
fi

# Folder exclusion mechanism
if [ -n "${ignore+set}" ];then
  ignorearg="-type d \("
  for j in "${ignore[@]}";do
    j=$(echo $j|sed 's/\/$//')
    ignorearg+=" -path \""$j"\" -o"
  done
  ignorearg=${ignorearg%-o}
  ignorearg+="\) -prune -o"
  findcommand="find $maindir/ $ignorearg $nonrecursive -type f -iname '*.mp4' -print0"
  readarray -d '' vidslist < <(eval $findcommand)
else
  readarray -d '' vidslist < <(find $maindir/ $nonrecursive -type f -iname '*.mp4' -print0)
fi
#echo ${#vidslist[@]}
#echo ${#existingframes[@]}

# Exclude existing frames from fetch mechanism
if [ $existingframes ];then
  readarray -d '' vidslist < <(comm -23z <(printf "%s\0" "${vidslist[@]}" | sort -z) <(printf "%s\0" "${existingframes[@]}" | sort -z) | sort -nz)
fi
declare -i totalvids=${#vidslist[@]}
echo -e '\033[1;33m'$totalvids videos to process.'\033[0m'

# Frame fetch mechanism
namingframes () {
  name=${1/$maindir/} 
  name=${name#*/}
  name=${name////%s%}
  framefile="./$dirforframes/$name.frame.png"
}

if [ ! $usecache ];then
  for v in "${vidslist[@]}";do
    namingframes "$v"
    if { [ $firstrun ] || [ ! -f "$framefile" ]; } && \
      [[ $(mediainfo --Output='Video;%Duration%' "$v") -gt "${framefromsec#-}000" ]];then
      if [ "$framefromsec" -gt 0 ];then time="-ss $framefromsec";else time="-sseof $framefromsec";fi
      ffmpeg $time -i "$v"  -hide_banner -loglevel error -frames:v 1 -q:v 2 "$framefile"
    fi
    i+=1
    echo -ne "  $(( i*100/totalvids ))%  Fetched $i frames from $totalvids videos.\r"
  done
else
  depcheck "ffmpegthumbnailer"
  for v in "${vidslist[@]}"; do
    namingframes "$v"
    filemd5=$(echo -n "file://$v" | md5sum)
    filemd5="${filemd5/ */}.png"
    pathtothumbnail="$homedir/.cache/thumbnails/normal/$filemd5"
    if [ ! -f "$pathtothumbnail" ];then
      ffmpegthumbnailer -t 20 -s 128 -f -i "$v" -o "$pathtothumbnail" 2> /dev/null || echo "File error: $v"
    fi 
    ln "$pathtothumbnail" "$framefile"
    i+=1
    echo -ne "  $(( i*100/totalvids ))%  Fetched $i thumbnails from $totalvids videos.\r"
  done
fi
echo -e ""
echo -e  "\033[1;33mFrame comparison with czkawka_cli:\033[0m"

# Pass data to czkawka_cli
czkawka_cli image --directories "$maindir/$dirforframes" $czkawkaoptions --file-to-save "./dupes.m3u"
sed -n -i "s/$dirforframes\///;s/%s%/\//g;s/\.frame\.png.*$//p" ./dupes.m3u
sed -i ' 1 s/.*/#EXTM3U\n&/' ./dupes.m3u
