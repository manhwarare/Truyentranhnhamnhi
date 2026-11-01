# Hộp Truyện – web truyện tranh (HTML + Supabase)

1. Tạo project tại supabase.com.
2. SQL Editor: dán và chạy `schema.sql` (tạo bảng, phân quyền, kho ảnh `comics`).
3. Authentication > Users: tạo user admin (email + mật khẩu), rồi chạy dòng `insert into admins ...` ở cuối schema.sql với email đó.
4. Project Settings > API: copy Project URL và anon public key vào `config.js`.
5. Chạy thử: `npx serve .` (hoặc mở bằng Live Server), rồi:
   - Trang đọc truyện: `index.html`
   - Trang quản trị: `admin.html`
6. Đã có database từ bản cũ? Chạy thêm `migration.sql` (v2: sắp xếp theo lượt truy cập) rồi `migration_v3.sql` (v3: tài khoản, tiến độ đọc, theo dõi, Hot, lọc thể loại). Không mất dữ liệu, chạy lại nhiều lần vẫn an toàn.
7. Triển khai: đẩy cả thư mục lên Netlify, Vercel hoặc Cloudflare Pages.

Anon key được phép công khai: quyền ghi dữ liệu và ảnh chỉ dành cho user nằm trong bảng `admins` (RLS).


## Sắp xếp theo độ truy cập
Trang chủ có 5 tab: Mới cập nhật (theo chương mới nhất), Xem nhiều (tổng), Top ngày, Top tuần, Top tháng. Mỗi lượt xem trang truyện được tính 1 lần cho mỗi phiên trình duyệt.

## Tài khoản & đọc tiếp (v3)
- Người đọc đăng ký/đăng nhập bằng email + mật khẩu (nút ở góc phải trên). Có quên mật khẩu và đổi mật khẩu/tên hiển thị ở trang `#/account`.
- Mở một chương (sau ~2 giây) sẽ lưu "đã đọc đến chương X" và đánh dấu ✓ chương đó trong danh sách chương. Trang truyện có nút **Đọc tiếp**, trang chủ có hàng **Tiếp tục đọc**.
- Chưa đăng nhập vẫn đọc bình thường: tiến độ lưu tạm trong trình duyệt và tự gộp vào tài khoản khi đăng nhập.
- Nút **Theo dõi** ở trang truyện (cần đăng nhập); xem ở tab "Theo dõi" hoặc trang tài khoản.
- Dữ liệu từng người được bảo vệ bằng RLS: chỉ chính chủ đọc/ghi được.
- Supabase mặc định bắt xác nhận email khi đăng ký. Muốn đăng ký xong đọc ngay: Authentication > Providers > Email > tắt "Confirm email". Với link quên mật khẩu/xác nhận email, thêm địa chỉ web của bạn vào Authentication > URL Configuration > Redirect URLs.

## Trang chủ phân loại
Tab: Mới cập nhật · 🔥 Hot · Xem nhiều · Top ngày/tuần/tháng · Theo dõi · Đã đọc. Bên dưới là lọc theo **trạng thái** và **thể loại** (tự lấy từ dữ liệu truyện, kèm số lượng; bấm thẻ thể loại ở trang truyện cũng lọc được). Điểm Hot = lượt xem hôm nay ×5 + 7 ngày ×2 + 30 ngày ×1 + mỗi lượt theo dõi mới trong 30 ngày ×10 (chỉnh trong hàm `hot_comics`).
