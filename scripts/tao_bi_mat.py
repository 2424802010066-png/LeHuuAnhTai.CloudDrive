"""Sinh file bí mật cho Ansible (ansible/secrets.yml) — mọi giá trị ngẫu nhiên, an toàn cho URL.
    python3 scripts/tao_bi_mat.py > ansible/secrets.yml && chmod 600 ansible/secrets.yml
Lê Hữu Anh Tài 2424802010066. File sinh ra KHÔNG được commit (.gitignore)."""
import secrets
import string

BANG = string.ascii_letters + string.digits


def ngau_nhien(n=32):
    return "".join(secrets.choice(BANG) for _ in range(n))


ten = ["pg_superuser_password", "nc_db_password", "redis_password", "nc_admin_password",
       "restic_password", "rest_server_password", "gatus_push_token"]
print("# BÍ MẬT — sinh bởi scripts/tao_bi_mat.py — KHÔNG commit, quyền 0600")
for t in ten:
    print(f'{t}: "{ngau_nhien(40 if t == "restic_password" else 32)}"')
print('telegram_token: ""')
print('telegram_chat_id: ""')
print('cloudflare_tunnel_id: ""')
