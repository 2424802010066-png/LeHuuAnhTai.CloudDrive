# LeHuuAnhTai.CloudDrive — Tự xây dựng và vận hành dịch vụ lưu trữ đám mây Nextcloud

Đồ án kết thúc học phần **Điện toán đám mây** — Trường Đại học Thủ Dầu Một, Viện Công nghệ số.
Sinh viên: **Lê Hữu Anh Tài – 2424802010066** · GVHD: ThS. Trần Nhật Nam.

Dịch vụ **SaaS** lưu trữ tệp (Nextcloud) chạy trên hạ tầng ảo hóa **VMware ESXi 8**, 3 VPS Ubuntu 24.04, công bố ra
Internet bằng **Cloudflare Tunnel**, quản trị qua **Tailscale**, giám sát bằng **Gatus** (cảnh báo Telegram), sao lưu
**restic** hằng đêm. Toàn bộ được dựng bằng mã: cloud-init + Ansible + Docker Compose.

```
Người dùng ──HTTPS──> Cloudflare ──Tunnel (kết nối RA)──> cloudflared ──> nginx ──> Nextcloud ──TLS──> PostgreSQL
Quản trị viên ──WireGuard (Tailscale)──> SSH 22 / HTTPS 443 / Gatus 8080        (không cổng nào mở từ Internet vào)
```

| VPS | Vai trò | IP (wan0 / svc0 / data0) |
|---|---|---|
| `vps-app-2424802010066` | Nextcloud 34, Redis, nginx, fail2ban, cloudflared dự phòng, sao lưu restic | .119.61 / .240.21 / .250.21 |
| `vps-data-2424802010066` | PostgreSQL 18 (TLS), rest-server append-only (kho sao lưu) | .119.62 / – / .250.22 |
| `vps-mon-2424802010066` | Gatus (status page, SLO, Telegram), cloudflared chính, bản sao lưu thứ 2, Ansible control node | .119.63 / .240.23 / .250.23 |

## Cấu trúc kho

```
infra/esxi/          Tầng ảo hóa: vps.json (bảng máy), esxi_mang_tuong_lua.sh (vùng mạng + tường lửa lớp 1),
                     tao_seed_vps.py (cloud-init + .vmx), dung_vps.sh (tạo, bật VPS)
ansible/             site.yml + 6 vai trò: common, docker, data, mon, app, cloudflared
  group_vars/        all.yml (biến chung), app/data/mon.yml (luật ufw từng máy, có lý do)
  secrets.example.yml   mẫu file bí mật (bản thật KHÔNG có trong kho)
scripts/tao_bi_mat.py   sinh bí mật ngẫu nhiên
docs/                SLA.md, HUONG_DAN_SU_DUNG.md, POSTMORTEM.md, tailscale-acl.hujson
```

## Dựng lại từ đầu

**Yêu cầu:** máy có VT-x, VMware Workstation (hoặc ESXi thật), ESXi 8 có datastore `ds-2424802010066`, vSwitch0 (NAT)
và `vSwitch-VPS` + port group `VPS-Net-2424802010066`; khóa SSH root của ESXi; Git Bash + Python 3 trên máy quản trị.

1. **Mạng 3 vùng + tường lửa lớp 1 trên ESXi**
   ```bash
   ssh root@<ESXi> "LAPTOP=<IP máy quản trị> sh -s" < infra/esxi/esxi_mang_tuong_lua.sh
   ```
2. **Sinh seed cloud-init và tạo 3 VPS** (đĩa nguồn = cloud image Ubuntu 24.04 dạng vmdk)
   ```bash
   ssh-keygen -t ed25519 -N '' -f deploy_ed25519 && cp deploy_ed25519.pub ansible/files/
   python infra/esxi/tao_seed_vps.py --ra _seed --hash-file hashes.json \
          --admin-pub ansible/files/anhtai.pub --deploy-pub ansible/files/deploy_ed25519.pub
   bash infra/esxi/dung_vps.sh _seed ubuntu-24.04-cloudimg.vmdk
   ```
3. **Chép kho + bí mật lên vps-mon (control node) và chạy Ansible**
   ```bash
   python3 scripts/tao_bi_mat.py > ansible/secrets.yml && chmod 600 ansible/secrets.yml
   sudo apt install ansible
   cd ansible && ansible-playbook site.yml
   ```
4. **VPN quản trị:** trên mỗi VPS `sudo tailscale up --hostname <tên-vps>` rồi duyệt trong trang quản trị Tailscale
   (ACL mẫu: `docs/tailscale-acl.hujson`); chạy lại `ansible-playbook site.yml --tags app` để xin chứng chỉ `tailscale cert`.
5. **Tên miền + Cloudflare Tunnel:** thêm tên miền vào Cloudflare, rồi trên máy quản trị:
   ```bash
   cloudflared tunnel login
   cloudflared tunnel create nextcloud-2424802010066
   cloudflared tunnel route dns nextcloud-2424802010066 cloud.<tên-miền>
   cloudflared tunnel route dns nextcloud-2424802010066 status.<tên-miền>
   ```
   Chép `<UUID>.json` vào `ansible/files/`, đặt `domain_ready: true` (group_vars/all.yml), `cloudflare_tunnel_id` (secrets.yml),
   chạy lại `ansible-playbook site.yml`.
6. **Người dùng:** `sudo nc-tao-nguoi-dung.sh` trên vps-app (đọc `ansible/roles/app/files/nguoi-dung.csv`;
   mật khẩu khởi tạo ngẫu nhiên nằm ở `/root/nguoi-dung-moi.csv`, quyền 0600).
7. **Kết thúc dựng:** đặt `lab_bootstrap: false` rồi chạy lại playbook để bỏ đường SSH tạm từ máy quản trị — từ đây SSH
   chỉ còn qua Tailscale.

## Vận hành

| Việc | Lệnh / lịch |
|---|---|
| Sao lưu hằng đêm (vps-app) | timer `nc-sao-luu.timer` 02:00 — `sudo /usr/local/sbin/nc-sao-luu.sh` |
| Diễn tập khôi phục | `sudo /usr/local/sbin/nc-khoi-phuc-thu.sh` (khôi phục ra thư mục + CSDL tạm, đối chiếu từng byte) |
| Chép bản sao sang vps-mon | timer `chep-ban-sao.timer` 02:40 (vps-data) |
| Dọn kho sao lưu | timer `don-sao-luu.timer` Chủ nhật 03:00 (vps-data, phía máy chủ vì kho append-only) |
| Cập nhật Nextcloud | timer `nc-cap-nhat.timer` Chủ nhật 02:30 |
| Giám sát | Gatus `http://vps-mon:8080` (qua VPN) / `https://status.<tên-miền>` |

## Bảo mật
- Không có mật khẩu, khóa, token nào trong kho: bí mật nằm ở `ansible/secrets.yml`, `.env` (0600) — đều trong `.gitignore`.
- Tường lửa 2 lớp: ESXi (mặc định DROP, quản trị chỉ từ máy quản trị) + ufw trên từng VPS (mặc định chặn, luật có lý do).
- SSH chỉ khóa, cấm root, `AllowUsers`; Fail2ban cho SSH và trang đăng nhập Nextcloud (chặn ở nginx theo IP thật).
- Docker publish cổng vượt qua ufw → dịch vụ mở ra mạng chạy `network_mode: host`, còn lại chỉ bind 127.0.0.1.

## Sử dụng AI
Đồ án có dùng trợ lý AI (Claude) để: tra cứu tài liệu chính thức, viết nháp mã Ansible/script, vẽ sơ đồ và soát lỗi báo
cáo. Mọi cấu hình đều được sinh viên chạy thử trên hệ thống thật, đọc hiểu và giải thích được khi vấn đáp.
