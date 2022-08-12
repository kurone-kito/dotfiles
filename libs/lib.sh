#!/bin/sh

deploy() {
  NAME=$1
  SRC=$2
  [ $# -ge 3 ] && DST=$3 || DST=$2
  DSTPATH="${HOME}/${DST}"
  mkdir -p "${DSTPATH}"
  find "${SRC}" -depth 1 -type f -name "${NAME}" -print0 \
    | xargs -0 -n1 basename \
    | xargs -I {} ln -snf \
      "$(realpath "$(pwd)/${SRC}/{}")" \
      "$(realpath "${DSTPATH}/{}")"
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
