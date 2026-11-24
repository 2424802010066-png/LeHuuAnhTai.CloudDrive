#!/bin/sh
# Chạy TRÊN ESXi (ssh root@192.168.119.50 sh -s < esxi_mang_tuong_lua.sh)
# Tầng ảo hóa — mạng 3 vùng + TƯỜNG LỬA LỚP 1 — Lê Hữu Anh Tài 2424802010066
set -e
LAPTOP=${LAPTOP:-192.168.119.1}     # máy quản trị vật lý (VMnet8) — nơi duy nhất được vào quản trị ESXi

echo "== 1) Vùng DỮ LIỆU: vSwitch-Data KHÔNG có uplink -> không có đường ra/vào mạng vật lý"
esxcli network vswitch standard list -v vSwitch-Data >/dev/null 2>&1 || esxcli network vswitch standard add -v vSwitch-Data
esxcli network vswitch standard portgroup list | grep -q 'Data-Net-2424802010066' || \
  esxcli network vswitch standard portgroup add -p Data-Net-2424802010066 -v vSwitch-Data

echo "== 2) Chính sách an ninh lớp 2 trên mọi vSwitch (chặn nghe lén, giả MAC)"
for vs in vSwitch0 vSwitch-VPS vSwitch-Data; do
  esxcli network vswitch standard policy security set -v "$vs" \
    --allow-promiscuous=false --allow-mac-change=false --allow-forged-transmits=false
done

echo "== 3) Tường lửa ESXi: dịch vụ quản trị (SSH, Host Client 443/80) chỉ nhận từ máy quản trị $LAPTOP"
for rs in sshServer vSphereClient webAccess; do
  esxcli network firewall ruleset set -r "$rs" -e true -a false
  esxcli network firewall ruleset allowedip list -r "$rs" | grep -q "$LAPTOP" || \
    esxcli network firewall ruleset allowedip add -r "$rs" -i "$LAPTOP"
done
echo "   Tắt các dịch vụ không dùng (CIM/SLP, SNMP)"
for rs in CIMSLP CIMHttpServer CIMHttpsServer snmp; do
  esxcli network firewall ruleset set -r "$rs" -e false 2>/dev/null || true
done
/etc/init.d/slpd stop >/dev/null 2>&1 || true
chkconfig slpd off 2>/dev/null || true
esxcli network firewall set --enabled true --default-action false
esxcli network firewall refresh

echo "== 4) Tự khởi động VPS khi ESXi khởi động (thứ tự: data -> app -> mon)"
vim-cmd hostsvc/autostartmanager/enable_autostart true >/dev/null
i=1
for ten in vps-data-2424802010066 vps-app-2424802010066 vps-mon-2424802010066; do
  id=$(vim-cmd vmsvc/getallvms | awk -v t="$ten" '$2==t{print $1}')
  [ -n "$id" ] && vim-cmd hostsvc/autostartmanager/update_autostartentry "$id" PowerOn 60 $i guestShutdown 60 systemDefault >/dev/null
  i=$((i+1))
done

echo "== KẾT QUẢ"
esxcli network vswitch standard list | grep -E 'Name:|Uplinks|Portgroups'
esxcli network firewall ruleset list | grep -E 'sshServer|vSphereClient|webAccess|CIM|snmp'
esxcli network firewall ruleset allowedip list | grep -E 'sshServer|vSphereClient|webAccess'
