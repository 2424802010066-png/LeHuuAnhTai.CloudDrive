#!/usr/bin/env bash
# Kiểm tra sức khỏe máy mỗi phút: đĩa, RAM, unit systemd lỗi + các kiểm tra riêng
# trong /etc/kiem-tra.d/*.sh (mỗi script in "khoa-gatus" ... tự đẩy). Lê Hữu Anh Tài - 2424802010066
set -u
. /etc/gatus-push.env
loi=""
# 1) Đĩa: phân vùng nào trên 85% là báo lỗi
while read -r pct mnt; do
  p=${pct%\%}; [ "$p" -ge 85 ] && loi+="dia ${mnt} ${pct}; "
done < <(df --output=pcent,target -x tmpfs -x devtmpfs -x overlay -x squashfs | tail -n +2)
# 2) RAM khả dụng dưới 5%
ram=$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf "%d", 100-(a*100/t)}' /proc/meminfo)
[ "$ram" -ge 95 ] && loi+="RAM ${ram}%; "
# 3) Unit systemd bị lỗi
failed=$(systemctl --failed --no-legend --plain | awk '{print $1}' | paste -sd, -)
[ -n "$failed" ] && loi+="unit loi: ${failed}; "
if [ -z "$loi" ]; then /usr/local/bin/push-gatus.sh "$GATUS_KEY_MAY" true
else /usr/local/bin/push-gatus.sh "$GATUS_KEY_MAY" false "$loi"; fi
# 4) Kiểm tra riêng của từng máy (CSDL, rest-server...)
for f in /etc/kiem-tra.d/*.sh; do [ -x "$f" ] && "$f"; done
exit 0
