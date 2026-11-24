# Hậu kiểm sự cố (postmortem): vps-data bị tắt, Nextcloud gián đoạn 3 phút 40 giây

Dịch vụ: AnhTai Cloud Drive (Nextcloud) · Người viết: Lê Hữu Anh Tài – MSSV 2424802010066 · Ngày: 25/11/2026
Hình thức: **diễn tập sự cố có chủ đích** (game day) lúc 00:10, khi chưa có người dùng thật. Bản hậu kiểm viết theo
lối **không quy lỗi cho cá nhân** (blameless): tìm lỗ hổng của hệ thống và quy trình, không tìm người để trách.

Nhật ký gốc (máy đo trên laptop, ghi mỗi khi một phép kiểm tra đổi trạng thái):
[`dien-tap/2026-11-25_tat-vps-data.log`](dien-tap/2026-11-25_tat-vps-data.log). Giờ trong log Gatus là UTC, ở đây đã đổi sang giờ Việt Nam (UTC+7).

## 1. Tóm tắt

| | |
|---|---|
| Kịch bản | Quản trị viên định tắt VPS cũ của bài 2 (`vps-2424802010066`) nhưng tắt nhầm máy dữ liệu `vps-data-2424802010066` (PostgreSQL + kho sao lưu) |
| Tác động | Nextcloud không dùng được (trang treo > 10 s rồi lỗi) trong **≈ 3 phút 40 giây** (00:10:26 → 00:14:06). Không mất dữ liệu |
| Phát hiện | Cảnh báo Telegram đầu tiên lúc **00:13:06**, 2 phút 40 giây sau khi máy tắt |
| Khôi phục | Bật lại máy qua ESXi lúc 00:13:45; dịch vụ chạy lại sau **21 giây**, không cần thao tác gì thêm |
| Ngân sách lỗi | SLO 99,5 %/30 ngày cho phép 216 phút gián đoạn; sự cố này dùng ≈ 3,7 phút (**1,7 %** ngân sách) |
| Mức độ | Trung bình: mất toàn bộ dịch vụ nhưng ngắn, tự hồi phục dữ liệu |

## 2. Dòng thời gian (25/11/2026, giờ Việt Nam)

| Giờ | Sự kiện | Nguồn |
|---|---|---|
| 00:10:19 | Mọi phép kiểm tra của Gatus đều OK (13/13) | Gatus API |
| **00:10:26** | **T0**: lệnh `systemctl poweroff` chạy trên vps-data | thao tác |
| 00:10:45 | Lần gọi `https://cloud…/status.php` đầu tiên sau T0 bị treo, hết 10 s chờ → người dùng đã bị ảnh hưởng | máy đo laptop |
| 00:11:20 | Gatus ghi lần hỏng đầu: *Ping vps-data*, *Nextcloud (nội bộ)*, *Nextcloud (công khai)* (`STATUS 0`, `RESPONSE_TIME 10000 ms`) | Gatus API |
| 00:12:21 | *WebDAV* hỏng (`STATUS 0`, mong đợi 401) | Gatus API |
| **00:13:06** | **Cảnh báo Telegram #1**: *Nextcloud công khai không đạt* (sau 3 lần hỏng liên tiếp) | log Gatus `handleAlertsToTrigger` |
| 00:13:16 | Cảnh báo #2 *Nextcloud nội bộ lỗi*, #3 *Máy dữ liệu không phản hồi* | log Gatus |
| 00:13:45 | Chẩn đoán: ping vps-data hỏng trong khi vps-app, vps-mon vẫn sống → lỗi khu trú ở máy dữ liệu; ESXi báo `Powered off`. **T2**: `vim-cmd vmsvc/power.on 3` | thao tác |
| **00:14:06** | Người dùng vào lại được (`status.php` 200 trong 0,2 s) | máy đo laptop |
| 00:14:11 | Gatus: Nextcloud nội bộ/công khai, WebDAV, ping vps-data OK. Ba heartbeat do vps-data tự đẩy (PostgreSQL, rest-server, máy) chuyển LỖI vì im lặng > 3 phút | Gatus API |
| 00:14:53 | Ba heartbeat OK trở lại (lần đẩy đầu tiên sau khởi động). Chỉ hỏng 1 lần → **không** gửi cảnh báo, đúng thiết kế chống báo động giả | Gatus API |
| 00:15:06 | Gatus gửi 3 tin **"đã khôi phục"** về Telegram (sau 2 lần OK liên tiếp) | log Gatus `handleAlertsToResolve` |

**Các chỉ số:** thời gian phát hiện (T0 → cảnh báo) 2 phút 40 giây · thời gian phản ứng (cảnh báo → bắt đầu sửa) 39 giây ·
thời gian khôi phục (bắt đầu sửa → dịch vụ chạy) 21 giây · tổng gián đoạn ≈ 3 phút 40 giây.

> Lưu ý trung thực: 39 giây phản ứng là con số của buổi diễn tập, người trực đã biết trước sẽ có sự cố. Sự cố thật
> lúc nửa đêm phụ thuộc vào việc quản trị viên có thức và đọc được Telegram hay không; xem hành động 5.

## 3. Nguyên nhân

**Nguyên nhân trực tiếp:** máy chủ CSDL bị tắt. Nextcloud không mở được kết nối tới PostgreSQL (192.168.250.22:5432)
nên mọi trang trả lỗi sau thời gian chờ.

**Nguyên nhân gốc (vì sao một thao tác nhầm lại làm sập cả dịch vụ):**
1. **vps-data là điểm lỗi đơn (SPOF).** Chỉ có một máy CSDL, không có bản sao chạy song song. Kiến trúc chấp nhận điều
   này để vừa tài nguyên một laptop; SLA mục 7 đã ghi rõ giới hạn.
2. **Không có rào chắn khi tắt máy quan trọng.** Lệnh tắt chạy ngay, không hỏi lại tên máy. Tên hai VPS rất giống nhau
   (`vps-2424802010066` và `vps-data-2424802010066`).
3. **ESXi chưa cấu hình tự khởi động VPS.** Không gây ra sự cố này, nhưng diễn tập làm lộ ra: nếu ESXi (hoặc laptop) khởi
   động lại thì cả 3 VPS đứng yên ở trạng thái tắt cho tới khi có người bật tay.

## 4. Điều làm tốt / chưa tốt

**Làm tốt**
- Giám sát nhiều lớp giúp khoanh vùng nhanh: ping vps-data hỏng + vps-app/vps-mon vẫn sống + Nextcloud nội bộ hỏng
  ⇒ lỗi ở tầng dữ liệu chứ không phải ở Cloudflare Tunnel hay ứng dụng.
- Cảnh báo đến đúng người, đúng kênh; có tin "đã khôi phục" để biết sự cố đã khép.
- Ngưỡng 3 lần hỏng / 2 lần ổn chặn được báo động giả: 3 heartbeat của vps-data lỗi 1 lần lúc khởi động nhưng không gửi tin.
- Khôi phục không cần thao tác thủ công trong máy: Docker (`restart: unless-stopped`) tự chạy PostgreSQL + rest-server,
  Nextcloud tự kết nối lại. Máy tắt êm (`poweroff`) nên PostgreSQL dừng sạch, không mất dữ liệu. Trường hợp mất điện
  đột ngột chưa diễn tập; khi đó PostgreSQL phải tự phục hồi bằng WAL, và vẫn còn bản sao lưu đêm (RPO ≤ 24 giờ).

**Chưa tốt**
- 2 phút 40 giây mới có cảnh báo (kiểm tra mỗi 60 s × 3 lần). Đây là cái giá của việc chống báo động giả.
- Khi mất CSDL, Nextcloud **treo tới 10 s** rồi mới lỗi thay vì báo lỗi ngay: người dùng chờ lâu, ứng dụng đồng bộ thử lại liên tục.
- Phát sinh phụ: công cụ đo tự viết (Python) bị Cloudflare trả **403** vì User-Agent `Python-urllib` nằm trong luật chặn bot
  đã bật. Gatus không bị chặn. Bài học: máy đo tổng hợp từ bên ngoài phải có User-Agent được phép, nếu không sẽ đo sai.

## 5. Hành động khắc phục

| # | Hành động | Loại | Trạng thái |
|---|---|---|---|
| 1 | ESXi tự bật VPS theo thứ tự phụ thuộc **data → app → mon**, cách nhau 60 s; tắt host thì tắt êm (`guestShutdown`, cả 3 VPS có VMware Tools) | phòng ngừa | **Đã làm 25/11/2026**: thêm vào `infra/esxi/dung_vps.sh`, đã áp và kiểm tra bằng `vim-cmd hostsvc/autostartmanager/get_autostartseq` |
| 2 | Quy trình tắt máy (runbook): trước khi tắt phải đối chiếu **vmid + tên đầy đủ** bằng `vim-cmd vmsvc/getallvms`; xóa VPS bài 2 khỏi inventory sau khi chấm bài 2 để hết nhầm lẫn | phòng ngừa | Đề xuất |
| 3 | Đặt thời gian chờ kết nối CSDL ngắn (vd. 3 s) để Nextcloud báo lỗi nhanh thay vì treo 10 s | giảm tác động | Đề xuất |
| 4 | Bản sao PostgreSQL (streaming replica) trên vps-mon để chuyển đổi khi vps-data hỏng — xóa SPOF | giảm tác động | Đề xuất (cần thêm RAM, ngoài phạm vi đồ án) |
| 5 | Bật thông báo Telegram có âm thanh cho bot cảnh báo trên điện thoại; trong giờ 22:00–07:00 chấp nhận thời gian phản ứng ≤ 30 phút (ghi vào SLA) | phát hiện | Đề xuất |

## 6. Hướng dẫn xử lý nhanh khi nhận cảnh báo "Máy dữ liệu không phản hồi"

1. Mở trang trạng thái (`https://status.<tên-miền>` hoặc Gatus qua VPN): ping vps-app/vps-mon còn sống không? Có → lỗi ở vps-data.
2. Trên máy quản trị: `ssh root@ESXi "vim-cmd vmsvc/getallvms; vim-cmd vmsvc/power.getstate <vmid-data>"`.
3. Máy tắt → `vim-cmd vmsvc/power.on <vmid-data>`. Máy chạy nhưng không ping được → mở console trong ESXi Host Client.
4. Chờ ≤ 1 phút rồi kiểm tra `curl -s https://cloud.<tên-miền>/status.php`; trên vps-data: `docker compose ps` (PostgreSQL, rest-server `Up`).
5. Chờ tin "đã khôi phục" trên Telegram, ghi lại các mốc giờ, viết hậu kiểm nếu gián đoạn > 30 phút (SLA mục 6).
