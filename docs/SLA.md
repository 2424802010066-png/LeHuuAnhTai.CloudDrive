# Thỏa thuận mức chất lượng dịch vụ (SLA) — AnhTai Cloud Drive

Nhà cung cấp: Lê Hữu Anh Tài (MSSV 2424802010066) · Dịch vụ: lưu trữ đám mây cá nhân Nextcloud (mô hình **SaaS**)
Hiệu lực: từ 25/11/2026 đến hết đợt chấm đồ án học phần Điện toán đám mây.

## 1. Phạm vi dịch vụ
- Lưu trữ, đồng bộ (web, Nextcloud Desktop, Nextcloud Android/iOS), chia sẻ tệp bằng link.
- Mỗi tài khoản có hạn mức riêng: sinh viên 1 GB, giảng viên (dùng thử) 2 GB.
- Địa chỉ: `https://cloud.<tên-miền>.id.vn` · Trang trạng thái: `https://status.<tên-miền>.id.vn`

## 2. Mục tiêu chất lượng (SLO) và cách đo (SLI)

| Chỉ số (SLI) | Cách đo | Mục tiêu (SLO) |
|---|---|---|
| Độ sẵn sàng | Gatus gọi `https://cloud.<tên-miền>/status.php` mỗi 60 s; thành công khi HTTP 200, `installed=true`, `maintenance=false` | **≥ 99,5 %** mỗi 30 ngày (≤ 3 giờ 36 phút gián đoạn) |
| Thời gian phản hồi | Thời gian của chính phép kiểm tra trên | **< 1,5 s** (đi qua Internet) |
| Sao lưu | Bản sao lưu đêm đẩy kết quả về Gatus | **100 %** số đêm có bản sao lưu thành công |

Không tính vào thời gian gián đoạn: cửa sổ bảo trì định kỳ (mục 3), sự cố do Cloudflare/nhà mạng của người dùng.

## 3. Bảo trì
- Định kỳ **02:00 – 04:00 hằng ngày** (giờ Việt Nam): sao lưu (02:00, dịch vụ ở chế độ bảo trì vài phút),
  chép bản sao (02:40), cập nhật bản vá Nextcloud (Chủ nhật 02:30), khởi động lại máy khi bản vá nhân yêu cầu (03:10–03:30).
- Bảo trì ngoài giờ trên: báo trước ≥ 24 giờ trên trang trạng thái.

## 4. Dữ liệu
- Sao lưu mỗi đêm sang máy chủ khác (mã hóa AES-256, kho append-only), bản sao thứ hai trên máy thứ ba.
- Giữ 7 bản theo ngày, 4 bản theo tuần, 3 bản theo tháng.
- **RPO ≤ 24 giờ** (mất tối đa dữ liệu của một ngày) · **RTO ≤ 2 giờ** (thời gian khôi phục toàn bộ dịch vụ).
- Tệp bị xóa nằm trong thùng rác 30 ngày, người dùng tự khôi phục được.

## 5. Bảo mật
- HTTPS cho mọi truy cập; tài khoản quản trị bắt buộc xác thực hai lớp và chỉ dùng được qua VPN.
- Đăng nhập sai 5 lần / 10 phút: địa chỉ IP bị chặn 1 giờ.
- Nhà cung cấp không đọc nội dung tệp của người dùng trừ khi người dùng yêu cầu hỗ trợ.

## 6. Báo và xử lý sự cố
- Theo dõi tình trạng tại trang trạng thái; quản trị viên nhận cảnh báo Telegram tự động.
- Hỗ trợ: liên hệ quản trị viên qua email hoặc Zalo của lớp.
- Thời gian phản hồi hỗ trợ: trong 4 giờ (07:00–22:00). Sự cố > 30 phút có bản hậu kiểm (postmortem) công bố trong 48 giờ.

## 7. Giới hạn
Dịch vụ phục vụ mục đích học tập, chạy trên **một máy vật lý** (laptop) nên không cam kết khi mất điện / mất Internet tại
nơi đặt máy chủ. Không lưu dữ liệu nhạy cảm (mật khẩu, giấy tờ tùy thân) trên dịch vụ.
