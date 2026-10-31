# Hộp Truyện – web truyện tranh (HTML + Supabase)

1. Tạo project tại supabase.com.
2. SQL Editor: dán và chạy `schema.sql` (tạo bảng, phân quyền, kho ảnh `comics`).
3. Authentication > Users: tạo user admin (email + mật khẩu), rồi chạy dòng `insert into admins ...` ở cuối schema.sql với email đó.
4. Project Settings > API: copy Project URL và anon public key vào `config.js`.
5. Chạy thử: `npx serve .` (hoặc mở bằng Live Server), rồi:
   - Trang đọc truyện: `index.html`
   - Trang quản trị: `admin.html`
6. Đã có database từ bản cũ? Chạy thêm `migration.sql` (không mất dữ liệu) để bật sắp xếp theo lượt truy cập.
7. Triển khai: đẩy cả thư mục lên Netlify, Vercel hoặc Cloudflare Pages.

Anon key được phép công khai: quyền ghi dữ liệu và ảnh chỉ dành cho user nằm trong bảng `admins` (RLS).


## Sắp xếp theo độ truy cập
Trang chủ có 5 tab: Mới cập nhật (theo chương mới nhất), Xem nhiều (tổng), Top ngày, Top tuần, Top tháng. Mỗi lượt xem trang truyện được tính 1 lần cho mỗi phiên trình duyệt.
