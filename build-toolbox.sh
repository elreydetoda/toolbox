#!/bin/bash

# https://elrey.casa/bash/scripting/harden
set "-${-//[sc]/}eu${DEBUG:+xv}o" pipefail


function prep(){

  toolbox rm -f "${toolbox_name}" || true

  # pulling if image isn't local
  if [[ -n "${CONREG}" ]] ; then
    podman pull "${container_image}"
  fi

  toolbox -y create -c "${toolbox_name}" --image "${container_image}"

}

function configure(){

  # can't do that with toolbox run yet, as we need to install sudo first
  podman start "${toolbox_name}"
  podman exec -it "${toolbox_name}" sh -exc '
  # go-faster apt/dpkg
  echo force-unsafe-io > /etc/dpkg/dpkg.cfg.d/unsafe-io

  apt-get update
  apt-get install -y libnss-myhostname sudo eatmydata libcap2-bin

  # allow sudo with empty password
  sed -i "s/nullok_secure/nullok/" /etc/pam.d/common-auth
  '

  # shellcheck disable=SC2016
  toolbox run --container "${toolbox_name}" sh -exc '
  # otherwise installing systemd fails
  sudo umount /var/log/journal

  # useful hostname
  . /etc/os-release
  echo "${ID}-${VERSION_ID:-sid}" | sudo tee /etc/hostname
  sudo hostname -F /etc/hostname

  sudo eatmydata apt-get -y dist-upgrade

  # development tools
  sudo eatmydata apt-get install -y --no-install-recommends build-essential git-buildpackage libwww-perl less vim lintian debhelper manpages-dev git dput pristine-tar bash-completion wget gnupg ubuntu-dev-tools python3-debian fakeroot libdistro-info-perl

  # autopkgtest
  sudo eatmydata apt-get install -y --no-install-recommends autopkgtest qemu-system-x86 qemu-utils genisoimage
  '

}


function main(){
  DISTRO="${1}"
  RELEASE="${2:-latest}"
  CONREG="${3-docker.io/}"
  container_image="${CONREG}${DISTRO}:${RELEASE}"
  toolbox_name="${4:-${DISTRO}-${RELEASE}}"

  prep
  configure

  toolbox enter --container "${toolbox_name}"

}

# https://elrey.casa/bash/scripting/main
if [[ "${0}" = "${BASH_SOURCE[0]:-bash}" ]] ; then
  main "${@}"
fi