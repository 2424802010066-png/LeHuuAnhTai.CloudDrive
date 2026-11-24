#!/usr/bin/env bash
# Đẩy kết quả một phép kiểm tra vào "external endpoint" của Gatus.
#   push-gatus.sh <khoa-da-urlencode> <true|false> [mo-ta-loi] [thoi-gian vd 3s]
# Lê Hữu Anh Tài - 2424802010066
set -u
. /etc/gatus-push.env
key="$1"; ok="$2"; err="${3:-}"; dur="${4:-}"
q="success=${ok}"
[ -n "$err" ] && q+="&error=$(jq -rn --arg s "$err" '$s|@uri')"
[ -n "$dur" ] && q+="&duration=${dur}"
curl -fsS -m 10 -X POST -H "Authorization: Bearer ${GATUS_TOKEN}" \
     "${GATUS_URL}/api/v1/endpoints/${key}/external?${q}" >/dev/null
