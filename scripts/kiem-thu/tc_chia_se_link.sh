#!/usr/bin/env bash
# TC-CHIA-SE: kiểm thử chức năng cốt lõi "chia sẻ bằng link" của Nextcloud — Lê Hữu Anh Tài 2424802010066
# Chạy bằng root trên vps-app (từ control node: ansible app -b -m script -a scripts/kiem-thu/tc_chia_se_link.sh)
#   1) tài khoản thử sv01 tải một tệp lên (WebDAV)
#   2) tạo link chia sẻ công khai có MẬT KHẨU và HẠN DÙNG 7 ngày (OCS API)
#   3) người ngoài (không tài khoản) tải tệp qua link: thiếu mật khẩu -> bị từ chối, đúng mật khẩu -> nhận đúng nội dung
#   4) dọn dẹp: xóa link và tệp thử
# Mật khẩu (tài khoản, link) chỉ nằm trong biến của script, KHÔNG in ra màn hình.
set -euo pipefail
NC=http://192.168.240.21                       # nginx qua vùng dịch vụ, ĐÚNG đường connector cloudflared trên vps-app gọi vào
TEN_MIEN=$(docker exec -u www-data nextcloud php occ config:system:get overwrite.cli.url | sed 's#https://##')
U=sv01
P=$(awk -F';' -v u="$U" '$1==u{print $2}' /root/nguoi-dung-moi.csv)
[ -n "$P" ] || { echo "Không tìm thấy mật khẩu khởi tạo của $U"; exit 1; }
SPASS=$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-16)Aa9!
TEP=chia-se-thu-$(date +%H%M%S).txt
NOI_DUNG="Tệp thử chia sẻ — AnhTai Cloud Drive — MSSV 2424802010066 — $(date '+%F %T')"
c() { curl -s -H "Host: $TEN_MIEN" "$@"; }   # nginx chỉ tin IP connector -> tự gắn X-Forwarded-Proto: https

echo "== 1) $U tải tệp $TEP lên"
printf '%s\n' "$NOI_DUNG" > /tmp/$TEP
code=$(c -o /dev/null -w '%{http_code}' -u "$U:$P" -T /tmp/$TEP "$NC/remote.php/dav/files/$U/$TEP")
echo "   PUT WebDAV: HTTP $code (201 = đã tạo)"

echo "== 2) Tạo link công khai có mật khẩu, hết hạn sau 7 ngày"
HAN=$(date -d '+7 days' +%F)
kq=$(c -u "$U:$P" -H 'OCS-APIRequest: true' -X POST "$NC/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json" \
      --data-urlencode "path=/$TEP" -d shareType=3 --data-urlencode "password=$SPASS" -d "expireDate=$HAN")
ID=$(echo "$kq" | python3 -c 'import sys,json; print(json.load(sys.stdin)["ocs"]["data"]["id"])')
TOKEN=$(echo "$kq" | python3 -c 'import sys,json; print(json.load(sys.stdin)["ocs"]["data"]["token"])')
URL=$(echo "$kq" | python3 -c 'import sys,json; d=json.load(sys.stdin)["ocs"]["data"]; print(d["url"], "| het han:", d["expiration"][:10], "| co mat khau:", bool(d.get("password")))')
echo "   link: $URL"

echo "== 3) Người ngoài (không có tài khoản) tải tệp qua link"
code=$(c -o /dev/null -w '%{http_code}' "$NC/public.php/dav/files/$TOKEN")
echo "   không nhập mật khẩu : HTTP $code (mong đợi 401)"
code=$(c -o /tmp/tai-ve.txt -w '%{http_code}' -u "anonymous:$SPASS" "$NC/public.php/dav/files/$TOKEN")
echo "   đúng mật khẩu link   : HTTP $code (mong đợi 200)"
if cmp -s /tmp/$TEP /tmp/tai-ve.txt; then echo "   nội dung tải về KHỚP tệp gốc: \"$(cat /tmp/tai-ve.txt)\""; else echo "   nội dung KHÁC tệp gốc"; fi

echo "== 4) Dọn dẹp"
c -o /dev/null -u "$U:$P" -H 'OCS-APIRequest: true' -X DELETE "$NC/ocs/v2.php/apps/files_sharing/api/v1/shares/$ID"
code=$(c -o /dev/null -w '%{http_code}' -u "$U:$P" -X DELETE "$NC/remote.php/dav/files/$U/$TEP")
code2=$(c -o /dev/null -w '%{http_code}' -u "$U:$P" -H 'OCS-APIRequest: true' "$NC/ocs/v2.php/apps/files_sharing/api/v1/shares/$ID")
code3=$(c -o /dev/null -w '%{http_code}' -u "anonymous:$SPASS" "$NC/public.php/dav/files/$TOKEN")
echo "   xóa tệp: HTTP $code (204) | tra cứu link đã xóa: HTTP $code2 (404) | tải lại qua link: HTTP $code3 (không còn 200)"
rm -f /tmp/$TEP /tmp/tai-ve.txt
