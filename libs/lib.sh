#!/bin/bash

link_to() {
  DST_PATH="${2}/$(basename "${1}")"
  SRC_PATH="$(realpath "${1}")"
  ln -snf "${SRC_PATH}" "${DST_PATH}"
}

export -f link_to

log_info() {
  printf '\033[2;36m%s\033[m\n' "$@"
}

log_notice() {
  printf '\033[1;36m%s\033[m\n' "$@"
}

log_warn() {
  printf '\033[1;33m%s\033[m\n' "$@"
}

deploy() {
  NAME=$1
  SRC=$2
  [ $# -ge 3 ] && DST=$3 || DST=$2
  DST_PATH="$(realpath "${HOME}/${DST}")"
  mkdir -p "${DST_PATH}"
  find "${SRC}" -depth 1 -type f -name "${NAME}" -print0 \
    | xargs -0 -n1 \
    | xargs -I {} bash -c "link_to {} ${DST_PATH}"
}

deploy_with_chmod() {
  NAME=$1
  SRC=$2
  [ $# -ge 3 ] && DST=$3 || DST=$2
  DST_PATH="${HOME}/${DST}"

  mkdir -p "${DST_PATH}"
  chmod 700 "${DST_PATH}"
  deploy "${NAME}" "${SRC}" "${DST}"
}
