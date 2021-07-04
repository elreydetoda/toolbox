#!/usr/bin/env bash

# https://elrey.casa/bash/scripting/harden
set -${-//[sc]/}eu${DEBUG:+xv}o pipefail

function prep_container(){

  container_id="$(buildah from docker.io/kalilinux/kali-rolling:latest)"

  for label in "${labels[@]}" ; do
    buildah config --label "${label}" "${container_id}"
  done
  buildah config --env DEBIAN_FRONTEND=noninteractive "${container_id}"

}

function build_system(){
  # update cache
  "${buildah_run_cmd[@]}" apt-get update
  # upgrade system
  "${buildah_run_cmd[@]}" apt-get dist-upgrade -y \
    -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confnew'
  # install packages
  "${buildah_run_cmd[@]}" apt-get install -y "${pkgs[@]}"
  # fixing sudo permission
  "${buildah_run_cmd[@]}" sed -i -e 's/ ALL$/ NOPASSWD:ALL/' /etc/sudoers
  "${buildah_run_cmd[@]}" bash -c "echo VARIANT_ID=container | tee -a /etc/os-release"
  for filez in "${create_files[@]}" ; do
    printf 'creating file: %s\n' "${filez}"
    "${buildah_run_cmd[@]}" touch "${filez}"
  done
}

function wrapping_it_up(){
  buildah config --cmd '/bin/sh' "${container_id}"
  buildah config --env DEBIAN_FRONTEND- "${container_id}"
}

function cleanup(){
  "${buildah_run_cmd[@]}" apt-get autoremove -y
  "${buildah_run_cmd[@]}" apt-get autoclean -y
  "${buildah_run_cmd[@]}" rm -rf /var/lib/apt/lists/*
}

function main(){
  curlz=( "curl" "-fsSL" )
  RELEASE='latest'
  DISTRO='kalilinux/kali-rolling'
  CONREG="${1-docker.io/}"
  toolbox_name='kalilinux-toolbox'
  # curl command came from:
  # https://github.com/elreydetoda/packer-kali_linux/blob/cbf4285872c7edf8fe452195a628a0b43c7610b1/scripts/new-kali.sh#L134
  toolbox_version="$(
    # getting the current release of kali
    "${curlz[@]}" 'https://cdimage.kali.org/current/' |
      # only getting the iso lines
      sed -n "/href=\".*.iso\"/p" |
      # printing out the names of the isos
      awk -F'["]' '{print $8}' |
      # greping out only the version number
      grep -oP '\d{4}\.\d([a-z]|)' |
      # uniq'ing the version
      sort -u
  )"
  container_image="${CONREG}${DISTRO}:${RELEASE}"
  container_id=''
  labels=(
    'com.github.containers.toolbox="true"'
    "name=${toolbox_name}"
    "version=${toolbox_version}"
    'usage="This image is meant to be used with the toolbox command"'
    "summary='Base image for creating kali linux ${toolbox_version} containers'"
    'maintainer="Alex R <toolbox-social-contact@elrey741.33mail.com>'
  )

  # got packages from here:
  # https://github.com/containers/toolbox/blob/a6d31c6cd22dc05987e21df8b9d50f403a4a47b8/images/ubuntu/19.04/extra-packages
  pkgs=(
    'bash-completion'
    'git'
    'keyutils'
    'libcap2-bin'
    'lsof'
    'man-db'
    'mlocate'
    'mtr'
    'rsync'
    'sudo'
    'tcpdump'
    'time'
    'traceroute'
    'tree'
    'unzip'
    'wget'
    'zip'
  )
  create_files=(
    '/etc/machine-id'
    '/etc/localtime'
  )
  buildah_run_cmd=(
    'buildah' 'run'
  )
  prep_container
  buildah_run_cmd+=( "${container_id}" '--' )

  printf 'building: %s\nversion: %s\n%s\n\n' \
    "${container_image}" \
    "$("${buildah_run_cmd[@]}" bash -c 'grep "^VERSION=" /etc/os-release | cut -d "\"" -f 2')" \
    "$(buildah images --format="{{.ID}}" --no-trunc "${container_image}")"

  build_system
  cleanup
  wrapping_it_up

  buildah commit --format docker "${container_id}" "${toolbox_name}"
  buildah rm "${container_id}"
}

# https://elrey.casa/bash/scripting/main
if [[ "${0}" = "${BASH_SOURCE[0]:-bash}" ]] ; then
  main "${@}"
fi