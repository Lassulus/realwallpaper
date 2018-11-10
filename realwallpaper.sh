#! /bin/sh
set -euf

if [ -z "${working_dir+x}" ];then
  echo "please set working_dir"
  exit 23
fi

if [ -z "${nightmap_url+x}" ];then
  echo "please set nightmap_url"
  exit 23
fi

if [ -z "${daymap_url+x}" ];then
  echo "please set daymap_url"
  exit 23
fi

if [ -z "${cloudmap_url+x}" ];then
  echo "please set cloudmap_url"
  exit 23
fi

if [ -z "${marker_url+x}" ];then
  echo "please set marker_url"
  exit 23
fi

# usage: getimg FILENAME URL
fetch() {
  echo "fetch $1"
  curl -LsS -z "$1" -o "$1" "$2"
}

# usage: check_type FILENAME TYPE
check_type() {
  if ! file -ib "$1" | grep -q "^$2/"; then
    echo "$1 is not of type $2" >&2
    rm "$1"
    return 1
  fi
}

# usage: image_size FILENAME
image_size() {
  identify "$1" | awk '{print$3}'
}

# usage: make_mask DST SRC MASK
make_layer() {
  if needs_rebuild "$@"; then
    echo "make $1 (apply mask)" >&2
    convert "$2" "$3" -alpha off -compose copy_opacity -composite "$1"
  fi
}

# usage: flatten DST HILAYER LOLAYER
flatten() {
  if needs_rebuild "$@"; then
    echo "make $1 (flatten)" >&2
    composite "$2" "$3" "$1"
  fi
}

# usage: needs_rebuild DST SRC...
needs_rebuild() {
  a="$1"
  shift
  if ! test -e "$a"; then
    #echo "  $a does not exist" >&2
    result=0
  else
    result=1
    for b; do
      if test "$b" -nt "$a"; then
        #echo "  $b is newer than $a" >&2
        result=0
      fi
    done
  fi
  #case $result in
  #  0) echo "$a needs rebuild" >&2;;
  #esac
  return $result
}

main() {
  cd $working_dir

  # fetch source images in parallel
  fetch nightmap-raw.jpg \
    $nightmap_url &
  fetch daymap-raw.png \
    $daymap_url &
  fetch clouds-raw.jpg \
    $cloudmap_url &
  fetch marker.json \
    $marker_url &
  wait

  check_type nightmap-raw.jpg image
  check_type daymap-raw.png image
  check_type clouds-raw.jpg image

  in_size=2048x1024
  xplanet_out_size=1466x1200
  out_geometry=1366x768+100+160

  nightsnow_color='#0c1a49'  # nightmap

  for raw in \
      nightmap-raw.jpg \
      daymap-raw.png \
      clouds-raw.jpg \
      ;
  do
    normal=''${raw%-raw.*}.png
    if needs_rebuild $normal $raw; then
      echo "make $normal; normalize $raw" >&2
      convert $raw -scale $in_size $normal
    fi
  done

  # create nightmap-fullsnow
  if needs_rebuild nightmap-fullsnow.png; then
    convert -size $in_size xc:$nightsnow_color nightmap-fullsnow.png
  fi

  # extract daymap-snowmask from daymap-final
  if needs_rebuild daymap-snowmask.png daymap.png; then
    convert daymap.png -threshold 95% daymap-snowmask.png
  fi

  # extract nightmap-lightmask from nightmap
  if needs_rebuild nightmap-lightmask.png nightmap.png; then
    convert nightmap.png -threshold 25% nightmap-lightmask.png
  fi

  # create layers
  make_layer nightmap-snowlayer.png nightmap-fullsnow.png daymap-snowmask.png
  make_layer nightmap-lightlayer.png nightmap.png nightmap-lightmask.png

  # apply layers
  flatten nightmap-lightsnowlayer.png \
    nightmap-lightlayer.png \
    nightmap-snowlayer.png

  flatten nightmap-final.png \
    nightmap-lightsnowlayer.png \
    nightmap.png
    # nightmap-old.png

  # create marker file from json
  if [ -s marker.json ]; then
    jq -r 'to_entries[] | @json "\(.value.latitude) \(.value.longitude)"' marker.json > marker_file
  fi

  # make all unmodified files as final
  for normal in \
      daymap.png \
      clouds.png \
      ;
  do
    final=''${normal%.png}-final.png
    needs_rebuild $final &&
      ln $normal $final
  done

  map=daymap-final.png
  night_map=nightmap-final.png
  cloud_map=clouds-final.png
  gcloud_map=gcloud-cloudmask.png

  # create xplanet output
  cat >xplanet.config <<EOF
[earth]
"Earth"
map=$map
night_map=$night_map
cloud_map=$cloud_map
cloud_threshold=10
shade=15
EOF

  cat >xplanet-krebs.config <<EOF
[earth]
"Earth"
map=$map
night_map=$night_map
cloud_map=$cloud_map
cloud_threshold=10
marker_file=marker_file
shade=15
EOF

  # rebuild every time to update shadow
  xplanet --num_times 1 --geometry $xplanet_out_size \
    --output xplanet-output.png --projection merc \
    -config xplanet.config

  xplanet --num_times 1 --geometry $xplanet_out_size \
    --output xplanet-krebs-output.png --projection merc \
    -config xplanet-krebs.config

  # trim xplanet output
  if needs_rebuild realwallpaper.png xplanet-output.png; then
    convert xplanet-output.png -crop $out_geometry \
      realwallpaper.png
  fi

  if needs_rebuild realwallpaper-krebs.png xplanet-krebs-output.png; then
    convert xplanet-krebs-output.png -crop $out_geometry \
      realwallpaper-krebs.png
  fi

}

main "$@"

