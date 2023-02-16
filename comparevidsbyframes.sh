#!/bin/bash
set -e

# czkawka_cli config
filter="Lanczos3"
algorithm="Gradient"
hashsize=8
# "VeryHigh" "High" "Medium" "Small" "VerySmall" "Minimal"
similarity="VeryHigh"
czkawkaoptions="--minimal-file-size 1 --image-filter $filter --hash-alg $algorithm --hash-size $hashsize --similarity-preset $similarity"

information="\033[1;31m! By default this script runs RECURSIVE !\033[0m

It creates a folder where all fetched frames are stored. They are then compared by the czkawka_cli
program and as the final result the M3U playlist with all similar videos is created.
If the frames folder already exists, the fetch process will be omitted and the script will check that
all stored frames have their corresponding video (if it were not deleted). If not, frame 
will be deleted.

\033[1;33mczkawka_cli\033[0m will be used with the following configuration:"

help() {
echo -e "
\033[1;33m$(basename "$0")\033[0m [-n] [-s n] -- a script to compare frames from the beginning of videos to find
similar variations.

There are two dependencies: \033[1;33mmediainfo\033[0m (it's optional) and \033[1;33mczkawka_cli\033[0m

$information
$czkawkaoptions

\033[1;33mOptions\033[0m:
    -h        --help                   Show this text
    -n        --non-recursive          Don't search for videos in other folders
    -s=n      --frame-from-sec=n       Fetch a frame n seconds from the beginning of the video.
                                       n must be an integer between 1 and 9.
                                       [by default, the script will take frame from the 2nd second]
    -c=       --czkawka-config         Pass your own czkawka_cli configuration instead of the default
"

#    -t=T  --frame-from-time=T         Fetch frame from specified time stamp.
#                                      Time stamp format is "NN:NN:NN".
#                                      -s and -t options can't be passed together.

}

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
    -s=*|--frame-from-sec=*)
      if [ ${i#*=} -eq ${i#*=} ] 2> /dev/null && [ ${i#*=} -ge 1 ] && [ ${i#*=} -le 9 ];then
        declare -i framefromsec=${i#*=}
      else
        echo "Incorrect input. It should be integer between 1 and 9"
        help
        exit 1
      fi
      shift
      ;;
    -c=*|--czkawka-config=*)
      czkawkaoptions=${i#*=}
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

if ! command -v czkawka_cli &> /dev/null
then
    echo -e "\033[0;33mczkawka_cli\033[0m could not be found"
    exit 1
fi

echo -e "
$information
$czkawkaoptions
"
read -p "Are you ready to proceed? y/N:" -N 1
if  ! ( [ $REPLY == "y" ] || [ $REPLY == "Y" ] );then
  echo -e '\r'
  exit
fi
echo -e '\r'

declare -i i=0
if [ ! $framefromsec ];then
  declare -i framefromsec=2
fi
time="00:00:0$framefromsec"
maindir=~+
dirforframes="frames_from_${framefromsec}_sec"

if [ ! -d "$maindir/$dirforframes" ];then
mkdir "$dirforframes"

readarray -d '' vidslist < <(find ~+ $nonrecursive -type f -iname "*.mp4" -print0)
echo -e '\033[1;33m'${#vidslist[@]} videos to process.'\033[0m'
declare -i totalvids=${#vidslist[@]}

for v in "${vidslist[@]}"
do
#you can comment out if statement if you don't have mediainfo installed, but the whole process will take much longer time
  if [[ $(mediainfo --Output='Video;%Duration%' "$v") -gt "${framefromsec}000" ]];then
    name=${v/$maindir/} 
    name=${name#*/}
    name=${name////%s%}
    ffmpeg -ss "$time" -i "$v"  -hide_banner -loglevel error -frames:v 1 -q:v 2 "./$dirforframes/$name.frame.jpg"
    #mv -t "./$dirforframes" "$v.frame.jpg" 2> /dev/null || :
  fi
  i+=1
  echo -ne "  $(( i*100/totalvids ))%  Fetched $i frames from $totalvids videos.\r"
done
echo -e ""
else
  echo -e  "Updating an existing frames folder..."
  for f in "$maindir/$dirforframes/"*.jpg
  do
  test=$(echo "$f" | sed -r "s/$dirforframes\///;s/%s%/\//g;s/\.frame\.jpg.*$//")
   if [ ! -f "$test" ];then
     rm "$f"
   fi
  done
fi

 echo -e  "\033[1;33mFrame comparison with czkawka_cli:\033[0m"

czkawka_cli image --directories "$maindir/$dirforframes" $czkawkaoptions --file-to-save "./dupes.m3u"
sed -n -i "s/$dirforframes\///;s/%s%/\//g;s/\.frame\.jpg.*$//p" ./dupes.m3u
sed -i ' 1 s/.*/#EXTM3U\n&/' ./dupes.m3u
