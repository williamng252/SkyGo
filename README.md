# SkyGo – Java/Spring Boot + SQL Server

SkyGo là hệ thống website bán vé máy bay hoàn chỉnh với backend Spring Boot kết nối trực tiếp đến cơ sở dữ liệu SQL Server. Giao diện frontend và RESTful API được Spring Boot phục vụ cùng cổng `http://localhost:8080`, toàn bộ dữ liệu tìm kiếm, đặt vé, lịch sử, làm thủ tục (check-in) và quản trị đều lấy và lưu trữ thời gian thực trên SQL Server.

## Yêu cầu môi trường

- JDK 25+ và Maven 3.9+ (kiểm tra bằng `java -version`, `mvn -version`).
- SQL Server (Developer, Standard hoặc Express) đang bật TCP/IP.
- SSMS hoặc Azure Data Studio để chạy script CSDL.

## Khởi tạo Database (Thực hiện một lần trên mỗi máy)

Mở SSMS hoặc terminal `sqlcmd` bằng quyền tạo database và chạy theo **đúng thứ tự**:

1. `DataBase/01_schemal.sql` — Tạo cấu trúc 11 bảng, khóa chính, khóa ngoại, ràng buộc và cột tự tính.
2. `DataBase/02_seed.sql` — Nạp dữ liệu mẫu (sân bay, chuyến bay, hạng vé, ghế, tài khoản mẫu).
3. `DataBase/03_functions.sql` — Các function (`fn_TinhTongTienDon`, `fn_SoChoCon`, `fn_DanhSachGheKhaDung`).
4. `DataBase/04_views.sql` — Các view (`vw_ChiTietVe`, `vw_DoanhThuNgay`).
5. `DataBase/05_DB03_tai_khoan_tim_chuyen.sql` — SP tài khoản, hồ sơ, tìm chuyến bay (`usp_DangKy`, `usp_LayTaiKhoanDangNhap`, `usp_TimChuyenBay`,...).
6. `DataBase/06_DB04_tao_don_va_ve.sql` — SP tạo đơn, vé và hủy đơn (`usp_TaoDonDatVe`, `usp_HuyDonDatVe`).
7. `DataBase/07_DB05_thanh_toan.sql` — SP thanh toán mô phỏng (`usp_XacNhanThanhToanMoPhong`, `usp_XuLyDonHetHan`).
8. `DataBase/08_DB06_checkin_the_len_may_bay.sql` — SP check-in và boarding pass (`usp_LayGheKhaDung`, `usp_CheckIn`, `usp_LayTheLenMayBay`).
9. `DataBase/09_DB07_tra_cuu_quan_tri_thong_ke.sql` — SP quản trị chuyến, đơn, khách hàng và thống kê bán vé.
10. `DataBase/10_DB08_trigger_index.sql` — Trigger ràng buộc và index tăng tốc.
11. `DataBase/11_DB08_phan_quyen.sql` — Phân quyền role SQL Server.

## Cấu hình và Khởi Chạy

Dự án tích hợp thư viện xác thực native `mssql-jdbc_auth-12.8.1.x64.dll` cho Windows Authentication. Maven tự cấu hình thư mục dự án làm đường dẫn nạp thư viện này.

### Cách 1: Chạy bằng Windows Authentication (Khuyên dùng - Nhanh nhất)
Không cần cấu hình tài khoản `sa` hay mật khẩu, chỉ cần mở PowerShell trong thư mục dự án và gõ:

```powershell
mvn spring-boot:run
```

*(Ứng dụng mặc định kết nối SQL Server tại cổng 1433. Nếu SQL Server của bạn dùng cổng khác, đặt `$env:SKYGO_DB_PORT` trước khi chạy, ví dụ `$env:SKYGO_DB_PORT=1434`.)*

### Cách 2: Chạy bằng SQL Server Authentication (sa)

```powershell
$env:SKYGO_DB_USERNAME='sa'
$env:SKYGO_DB_PASSWORD='mat_khau_sql_server'
mvn spring-boot:run
```

Mở trình duyệt truy cập: [http://localhost:8080](http://localhost:8080)  
Kiểm tra sức khỏe hệ thống: [http://localhost:8080/api/health](http://localhost:8080/api/health)

## Tài khoản dùng thử (Demo Accounts)

- **Quản trị viên (Admin):**
  - Email: `admin@skygo.vn` hoặc `admin@example.com`
  - Mật khẩu: `SkyGoDemo123!`
  - Quyền hạn: Quản lý chuyến bay (thêm, cập nhật trạng thái, xóa), xem biểu đồ và số liệu thống kê doanh thu thực tế từ CSDL.
- **Khách hàng có sẵn (Customer):**
  - Email: `quan@example.com`
  - Mật khẩu: `SkyGoDemo123!`
- **Khách hàng mới:** Có thể tự do đăng ký trực tiếp trên giao diện website bằng nút "Đăng Ký".

## Danh sách API Backend

- **Xác thực & Hồ sơ:**
  - `POST /api/auth/register` — Đăng ký tài khoản khách hàng mới (mật khẩu mã hóa BCrypt).
  - `POST /api/auth/login` — Đăng nhập, cấp token phiên làm việc 8 tiếng.
  - `GET /api/auth/me` — Lấy thông tin tài khoản hiện tại.
  - `PUT /api/profile` — Cập nhật họ tên, số điện thoại, đổi mật khẩu.
- **Sân bay & Chuyến bay:**
  - `GET /api/airports` — Lấy danh sách sân bay hoạt động từ bảng `SAN_BAY`.
  - `GET /api/flights/search` — Tìm chuyến bay thực qua Stored Procedure `usp_TimChuyenBay`.
- **Đặt vé & Thanh toán:**
  - `POST /api/bookings` — Đặt vé nhiều hành khách (tối đa 9 pax), chốt giá, tự sinh mã PNR ngẫu nhiên, lập giao dịch thanh toán trong transaction.
  - `GET /api/pnr/lookup` — Tra cứu vé theo mã PNR và Họ hành khách.
  - `GET /api/bookings/my` — Lấy lịch sử đặt vé của tài khoản đang đăng nhập qua `usp_LayLichSuDatVe` / `vw_ChiTietVe`.
  - `DELETE /api/bookings/{pnr}` — Hủy đơn đặt vé của chính chủ.
- **Làm thủ tục (Check-in):**
  - `POST /api/checkin` — Chuẩn bị check-in, kiểm tra vé hợp lệ và lấy sơ đồ ghế đã đặt trên chuyến.
  - `POST /api/checkin/confirm` — Chọn ghế, lưu vào bảng `CHECK_IN`, sinh thẻ lên máy bay (Boarding Pass) kèm mã QR.
- **Quản trị viên (Admin):**
  - `GET /api/admin/flights` — Lấy danh sách chuyến bay kèm tỷ lệ ghế đã bán.
  - `POST /api/admin/flights` — Thêm chuyến bay mới kèm khởi tạo hạng vé và ghế ngồi.
  - `PUT /api/admin/flights/{code}` — Cập nhật số hiệu, lộ trình, lịch bay, giá vé, trạng thái và loại tàu bay.
  - `PATCH /api/admin/flights/{code}/status` — Cập nhật trạng thái chuyến (Đang bán, Check-in, Boarding, Delay, Đã bay, Hủy).
  - `DELETE /api/admin/flights/{code}` — Xóa chuyến bay hoặc hủy nếu đã có vé.
  - `GET /api/admin/stats` — Thống kê tổng số đơn, đơn đã thanh toán, tổng doanh thu thực tế, số chuyến bay và khách hàng.
