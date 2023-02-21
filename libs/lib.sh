#!/bin/bash

link_to() {
  DST_PATH="${2}/$(basename "${1}")"
  SRC_PATH="$(realpath "${1}")"
  ln -snf "${SRC_PATH}" "${DST_PATH}"
}

export -f link_to

deploy() {
  NAME=$1
  SRC=$2
  [ $# -ge 3 ] && DST=$3 || DST=$2
  DST_PATH="$(realpath "${HOME}/${DST}")"
  mkdir -p "${DSTPATH}"
  find "${SRC}" -depth 1 -type f -name "${NAME}" -print0 \
    | xargs -0 -n1 \
    | xargs -I {} bash -c "link_to {} ${DST_PATH}"
}

deploy_with_chmod() {
  NAME=$1
  SRC=$2
  [ $# -ge 3 ] && DST=$3 || DST=$2
  DSTPATH="${HOME}/${DST}"

  mkdir -p "${DSTPATH}"
  chmod 700 "${DSTPATH}"
  deploy "${NAME}" "${SRC}" "${DST}"
}
