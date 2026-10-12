# ShunTV 1.0 — thanh tua và thời gian (bản thử nghiệm)

Bộ mã bổ sung thanh thời gian, kéo tiến độ, tua lùi 10 giây và tua tới 10 giây vào IPA ShunTV 1.0 dựng từ TQM•TV 2.0.

- **PlayerViewController** (TV): sử dụng `AVPlayer` có sẵn. Đối với live HLS không có thời lượng xác định, thanh tua bị vô hiệu hóa và hiển thị LIVE.
- **MoviePlayerViewController** (phim): tìm thẻ `<video>` trong `WKWebView`, bật HTML5 native controls và đồng bộ vị trí/thời lượng. Nếu phim được nhúng trong iframe khác origin, DRM, hoặc trình phát không dùng thẻ video truy cập được thì điều khiển có thể không hoạt động.
- Bộ tiện ích **chưa kiểm thử chạy trên iPhone**, có nguy cơ xung đột với giao diện hoặc mã gốc. Nên giữ nguyên bản ShunTV đang hoạt động để phục hồi.

## GitHub Actions

1. Tạo repository **Private** mới hoặc một branch thử nghiệm. Tải lên **nội dung bên trong ZIP** (đặt đúng `.github/workflows/build.yml`), không tải nguyên ZIP.
2. Mở **Actions → Build ShunTV 1.0 - Seek Controls → Run workflow**.
3. Nếu job thành công, mở **Artifacts** và tải `ShunTV-1.0-SeekControls-unsigned`.
4. Ký lại IPA gồm file thực thi và dylib `Frameworks/ShunSeekControls.dylib` rồi cài trên iPhone.

Không cần `ShunTVAddon.m` cũ và không chạy cùng workflow của bản IPA 1.2.

**Quan trọng:** Build thành công chỉ chứng minh thư viện đã biên dịch và được chèn vào Mach-O. Việc thanh điều khiển xuất hiện, tương tác tốt và ký thành công phải được thử trên thiết bị thực.
