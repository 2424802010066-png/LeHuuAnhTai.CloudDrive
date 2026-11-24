#!/usr/bin/env bash
# Tạo 3 VPS trên ESXi từ cloud image Ubuntu 24.04 + seed cloud-init — chạy trong Git Bash trên laptop.
#   bash infra/esxi/dung_vps.sh <thu-muc-seed> <cloudimg-vps-src.vmdk (dạng 2GB sparse)>
# Lê Hữu Anh Tài 2424802010066
set -euo pipefail
SEED=${1:?thu muc seed}; SRC=${2:?vmdk nguon}
K=${ESXI_KEYDIR:-/c/VMs/DoAnVPS/ssh}
ESXI=${ESXI:-root@192.168.119.50}
SSHO=(-i "$K/id_rsa_esxi" -o IdentitiesOnly=yes -o UserKnownHostsFile="$K/known_hosts" -o BatchMode=yes -o LogLevel=ERROR)
DSR=/vmfs/volumes/ds-2424802010066
SRCDIR=$(dirname "$SRC"); SRCBASE=$(basename "$SRC" .vmdk)

echo "== Tải đĩa nguồn (cloud image) lên datastore một lần"
ssh "${SSHO[@]}" "$ESXI" "mkdir -p $DSR/_src"
if ! ssh "${SSHO[@]}" "$ESXI" "test -f $DSR/_src/$SRCBASE.vmdk"; then
  scp -q "${SSHO[@]}" "$SRCDIR/$SRCBASE"*.vmdk "$ESXI:$DSR/_src/"
fi

for d in "$SEED"/vps-*; do
  TEN=$(basename "$d")
  echo "== $TEN"
  ssh "${SSHO[@]}" "$ESXI" "mkdir -p $DSR/$TEN"
  scp -q "${SSHO[@]}" "$d/seed-cidata.iso" "$d/$TEN.vmx" "$ESXI:$DSR/$TEN/"
  OSGB=$(python -I -X utf8 -c "import json,sys;c=json.load(open(sys.argv[1],encoding='utf-8'));print([v['os_gb'] for v in c['vps'] if v['ten']==sys.argv[2]][0])" "$(dirname "$0")/vps.json" "$TEN")
  THEM=$(python -I -X utf8 -c "import json,sys;c=json.load(open(sys.argv[1],encoding='utf-8'));print(' '.join(str(x) for v in c['vps'] if v['ten']==sys.argv[2] for x in v['dia_them_gb']))" "$(dirname "$0")/vps.json" "$TEN")
  ssh "${SSHO[@]}" "$ESXI" sh -s <<EOF
set -e
cd $DSR/$TEN
vmkload_mod multiextent >/dev/null 2>&1 || true
[ -f $TEN.vmdk ] || vmkfstools -i $DSR/_src/$SRCBASE.vmdk -d thin $TEN.vmdk >/dev/null
vmkfstools -X ${OSGB}G $TEN.vmdk >/dev/null 2>&1 || true
i=1
for gb in $THEM; do
  [ -f ${TEN}_\$i.vmdk ] || vmkfstools -c \${gb}G -d thin ${TEN}_\$i.vmdk >/dev/null
  i=\$((i+1))
done
vim-cmd vmsvc/getallvms | grep -q " $TEN " || vim-cmd solo/registervm $DSR/$TEN/$TEN.vmx >/dev/null
ls -la $DSR/$TEN | grep -E 'vmdk|iso|vmx$'
EOF
done

echo "== Bật các VPS (data trước)"
for TEN in vps-data-2424802010066 vps-app-2424802010066 vps-mon-2424802010066; do
  ssh "${SSHO[@]}" "$ESXI" "id=\$(vim-cmd vmsvc/getallvms | awk '\$2==\"$TEN\"{print \$1}'); vim-cmd vmsvc/power.getstate \$id | grep -q 'Powered on' || vim-cmd vmsvc/power.on \$id"
done
ssh "${SSHO[@]}" "$ESXI" "vim-cmd vmsvc/getallvms"
