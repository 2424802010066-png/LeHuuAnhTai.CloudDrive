"""Sinh cloud-init (NoCloud) + file .vmx cho các VPS trong vps.json — Lê Hữu Anh Tài 2424802010066.

    python -I -X utf8 infra/esxi/tao_seed_vps.py --ra C:/VMs/DoAnNhom/_seed \
        --hash-file C:/VMs/DoAnVPS/.secrets/hashes.json \
        --admin-pub ansible/files/anhtai.pub --deploy-pub ansible/files/deploy_ed25519.pub

Mỗi VPS có: hostname chứa MSSV, IP TĨNH cho từng card (chọn theo MAC, đổi tên card thành
wan0/svc0/data0), user quản trị "anhtai" (sudo, chỉ khóa SSH; mật khẩu sudo là bản băm do
user tự nhập) và user dịch vụ "deploy" cho Ansible. Không có bí mật dạng rõ trong seed.
"""
import argparse
import json
import pathlib
import shutil
import subprocess

GOC = pathlib.Path(__file__).resolve().parent
MKISOFS = r"C:\Program Files\VMware\VMware Workstation\mkisofs.exe"


def user_data(v, hash_anhtai, admin_pub, deploy_pub):
    return f"""#cloud-config
hostname: {v['ten']}
fqdn: {v['ten']}.lab.local
manage_etc_hosts: true
timezone: Asia/Ho_Chi_Minh
users:
  - name: anhtai
    gecos: Le Huu Anh Tai - 2424802010066
    groups: [sudo, adm]
    shell: /bin/bash
    lock_passwd: false
    passwd: "{hash_anhtai}"
    ssh_authorized_keys:
      - {admin_pub}
  - name: deploy
    gecos: Ansible service account
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - {deploy_pub}
disable_root: true
ssh_pwauth: false
write_files:
  - path: /etc/sudoers.d/80-deploy
    permissions: "0440"
    content: |
      deploy ALL=(ALL) NOPASSWD:ALL
final_message: "{v['ten']} san sang sau $UPTIME giay"
"""


def network_config(v, cfg):
    dong = ["version: 2", "ethernets:"]
    for n in v["nic"]:
        dong += [f"  {n['ten']}:",
                 "    match:",
                 f"      macaddress: \"{n['mac']}\"",
                 f"    set-name: {n['ten']}",
                 "    dhcp4: false",
                 "    dhcp6: false",
                 f"    addresses: [{n['ip']}]"]
        if n.get("gw"):
            dong += ["    routes:",
                     "      - to: default",
                     f"        via: {cfg['gateway']}",
                     "    nameservers:",
                     f"      addresses: [{', '.join(cfg['dns'])}]"]
    return "\n".join(dong) + "\n"


def vmx(v, cfg):
    ds = f"/vmfs/volumes/{cfg['datastore']}/{v['ten']}"
    d = [
        '.encoding = "UTF-8"', 'config.version = "8"', 'virtualHW.version = "21"',
        f'displayName = "{v["ten"]}"',
        f'annotation = "{v["vai_tro"]} - Le Huu Anh Tai - MSSV 2424802010066"',
        'guestOS = "ubuntu-64"', 'firmware = "bios"',
        f'numvcpus = "{v["vcpu"]}"', f'cpuid.coresPerSocket = "{v["vcpu"]}"', f'memSize = "{v["ram_mb"]}"',
        'pciBridge0.present = "TRUE"',
    ]
    for b in (4, 5, 6, 7):
        d += [f'pciBridge{b}.present = "TRUE"', f'pciBridge{b}.virtualDev = "pcieRootPort"', f'pciBridge{b}.functions = "8"']
    d += ['scsi0.present = "TRUE"', 'scsi0.virtualDev = "pvscsi"',
          'scsi0:0.present = "TRUE"', 'scsi0:0.deviceType = "scsi-hardDisk"', f'scsi0:0.fileName = "{v["ten"]}.vmdk"']
    for i, _ in enumerate(v["dia_them_gb"], start=1):
        d += [f'scsi0:{i}.present = "TRUE"', f'scsi0:{i}.deviceType = "scsi-hardDisk"',
              f'scsi0:{i}.fileName = "{v["ten"]}_{i}.vmdk"']
    d += ['sata0.present = "TRUE"', 'sata0:0.present = "TRUE"', 'sata0:0.deviceType = "cdrom-image"',
          f'sata0:0.fileName = "{ds}/seed-cidata.iso"', 'sata0:0.startConnected = "TRUE"']
    for i, n in enumerate(v["nic"]):
        d += [f'ethernet{i}.present = "TRUE"', f'ethernet{i}.virtualDev = "vmxnet3"',
              f'ethernet{i}.networkName = "{cfg["portgroups"][n["mang"]]}"',
              f'ethernet{i}.addressType = "static"', f'ethernet{i}.address = "{n["mac"]}"',
              f'ethernet{i}.startConnected = "TRUE"']
    d += ['tools.syncTime = "FALSE"', 'tools.upgrade.policy = "manual"']
    return "\n".join(d) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ra", required=True)
    ap.add_argument("--hash-file", required=True)
    ap.add_argument("--admin-pub", required=True)
    ap.add_argument("--deploy-pub", required=True)
    a = ap.parse_args()
    cfg = json.loads((GOC / "vps.json").read_text(encoding="utf-8"))
    h = json.loads(pathlib.Path(a.hash_file).read_text(encoding="utf-8"))["vps_anhtai"]
    admin_pub = pathlib.Path(a.admin_pub).read_text().strip()
    deploy_pub = pathlib.Path(a.deploy_pub).read_text().strip()
    ra = pathlib.Path(a.ra)
    for v in cfg["vps"]:
        thu_muc = ra / v["ten"]
        if thu_muc.exists():
            shutil.rmtree(thu_muc)
        cd = thu_muc / "cd"
        cd.mkdir(parents=True)
        tep = {
            "user-data": user_data(v, h, admin_pub, deploy_pub),
            "meta-data": f"instance-id: {v['ten']}-01\nlocal-hostname: {v['ten']}\n",
            "network-config": network_config(v, cfg),
        }
        for ten, nd in tep.items():
            (cd / ten).write_bytes(nd.encode("utf-8"))
        subprocess.run([MKISOFS, "-quiet", "-V", "cidata", "-J", "-r", "-o", str(thu_muc / "seed-cidata.iso"), str(cd)],
                       check=True)
        (thu_muc / f"{v['ten']}.vmx").write_bytes(vmx(v, cfg).encode("utf-8"))
        print(f"{v['ten']}: seed + vmx -> {thu_muc}")


if __name__ == "__main__":
    main()
