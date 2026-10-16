# work

# SkyGo — Phân công công việc

## 1. Phạm vi và cách triển khai

- Website bán vé của **một hãng hàng không**, sử dụng thiết kế 11 bảng đã thống nhất.
- Chức năng khách hàng: đăng ký/đăng nhập, cập nhật hồ sơ, tìm chuyến, đặt vé nhiều hành khách, thanh toán mô phỏng, tra cứu PNR, xem lịch sử, check-in/chọn ghế và xem thẻ lên máy bay.
- Chức năng quản trị: quản lý chuyến bay, trạng thái chuyến, đơn đặt vé, khách hàng và thống kê bán vé.
- Công nghệ dự kiến: Java + Spring Boot, SQL Server. Nhóm phải chốt cách làm giao diện và kết nối với backend ; Thymeleaf + HTML/CSS/Bootstrap trong cùng dự án.
- Backend gọi SP có tham số để đọc/ghi dữ liệu nghiệp vụ; truy vấn bảng nằm trong SQL Server. SP có thể sử dụng function và view khi phù hợp.
- Phân công theo công nghệ, nhưng ghép lần lượt từng chức năng: tìm chuyến → đặt vé/thanh toán → tra cứu/check-in → quản trị/thống kê.

## 2. Thành viên

| Thành viên | Trách nhiệm chính | Trách nhiệm phối hợp |
| --- | --- | --- |
| Nhật | Java/backend và ghép ứng dụng | Thống nhất cách gọi SP với người 2; nối giao diện với người 3 |
| Quân | SQL Server, thiết kế dữ liệu và nghiệp vụ CSDL | Giao bài SQL nhỏ cho người 4; kiểm tra và ghép các script; cung cấp mô tả SP cho người 1 |
| Huy | Frontend khách hàng và quản trị | Thống nhất dữ liệu gửi/nhận với người 1; hỗ trợ kiểm thử giao diện |
| Nhựt Quân | Báo cáo, format, kiểm thử và hỗ trợ SQL | Viết các bài SQL được giao; gửi script và minh chứng để Quân kiểm tra |

## 3. Danh sách nhiệm vụ

### Xuân Nhật — Java/backend

| Mã | Công việc | Kết quả cần đạt | Trạng thái |
| --- | --- | --- | --- |
| BE-01 | Tạo khung dự án, cấu hình mẫu và kết nối SQL Server | Thành viên khác có thể chạy theo README; có chức năng thử gọi SP | Đã làm |
| BE-02 | Đăng ký, đăng nhập, phiên đăng nhập và phân quyền | Mật khẩu được băm bằng thư viện ở backend; chặn khách truy cập chức năng admin | Đã làm |
| BE-03 | Hồ sơ khách hàng và tìm chuyến | Gọi đúng SP, trả dữ liệu và lỗi để frontend hiển thị | Đã làm |
| BE-04 | Đặt vé, thanh toán mô phỏng, PNR và lịch sử | Nhận thông tin hành khách, gọi SP, trả mã đơn/PNR và trạng thái xử lý | Đã làm |
| BE-05 | Check-in và thẻ lên máy bay | Gọi SP, kiểm tra quyền truy cập đặt chỗ, trả ghế và thông tin thẻ | Đã làm |
| BE-06 | Quản trị và thống kê | Nối chức năng quản lý chuyến, trạng thái, đơn, khách hàng và báo cáo bán vé | Đã làm |
| BE-07 | Ghép bản cuối, hướng dẫn chạy | Chạy được luồng demo từ đầu trên máy thành viên khác | Đã làm |

### Quân - SQL

| Mã | Công việc | Kết quả cần đạt | Trạng thái |
| --- | --- | --- | --- |
| DB-01 | Chốt schema 11 bảng, khóa và ràng buộc | Có script tạo database mới; cung cấp cùng bộ script cho cả nhóm | Đã làm |
| DB-02 | Dữ liệu mẫu và bảng mô tả cách gọi SP | Có dữ liệu đủ cho tìm chuyến/đặt vé; thống nhất tên, tham số, cột trả về với người 1 | Đã làm |
| DB-03 | SP tài khoản, hồ sơ, tìm chuyến | Có lệnh gọi thử; tìm đúng tuyến/ngày/hạng, trả cả giá và chỗ còn | Chưa làm |
| DB-04 | SP tạo đơn và vé | Kiểm tra giá/chỗ ở CSDL, tạo đơn và các vé trong transaction; không để dữ liệu dở dang | Chưa làm |
| DB-05 | SP xác nhận thanh toán | Cập nhật giao dịch, đơn và vé nhất quán; kiểm tra hạn đơn, số tiền, chống xác nhận thành công lặp | Chưa làm |
| DB-06 | SP check-in, lấy ghế và thẻ lên máy bay | Kiểm tra vé, thời gian, chuyến/hạng của ghế; transaction và ràng buộc tránh trùng ghế | Chưa làm |
| DB-07 | SP quản trị và thống kê | Quản lý chuyến/trạng thái, tra cứu đơn/khách hàng; thống kê doanh thu từ thanh toán thành công | Chưa làm |
| DB-08 | Trigger, index và quyền SQL | Trigger phục vụ quy tắc nghiệp vụ phù hợp, xử lý được nhiều dòng; index cho truy vấn thực tế; minh chứng quyền thực thi SP | Chưa làm |
| DB-09 | Kiểm tra bài SQL của người 4 và đóng gói script | Chạy lại từ database mới; các tên SP/function/view không trùng, thống nhất với Java | Chưa làm |

### Huy— Frontend

| Mã | Công việc | Kết quả cần đạt | Trạng thái |
| --- | --- | --- | --- |
| FE-01 | Bố cục chung, trang chủ, đăng ký/đăng nhập | Có menu, thông báo lỗi/thành công, cấu trúc dùng chung để ghép màn hình | Chưa làm |
| FE-02 | Tìm và chọn chuyến bay | Hiển thị dữ liệu thật từ backend; có trường hợp không tìm thấy chuyến | Chưa làm |
| FE-03 | Hành khách, thanh toán, hoàn tất | Nhập nhiều hành khách, hiển thị tiền do server xác định, kết quả thanh toán và PNR | Chưa làm |
| FE-04 | Hồ sơ, PNR và lịch sử đặt vé | Hiển thị danh sách/chi tiết và trạng thái; xử lý trường hợp dữ liệu rỗng hoặc xác minh sai | Chưa làm |
| FE-05 | Check-in, chọn ghế và thẻ lên máy bay | Chọn ghế khả dụng; hiển thị lý do không thể check-in và kết quả làm thủ tục | Chưa làm |
| FE-06 | Giao diện quản trị và thống kê | Các màn hình admin gọi được backend, có dữ liệu thực tế | Chưa làm |
| FE-07 | Rà bố cục và lỗi hiển thị | Màn hình thống nhất, chữ/nút rõ, trạng thái chờ và lỗi được hiển thị | Chưa làm |

### Nhựt Quân — Báo cáo và SQL hỗ trợ

| Mã | Công việc | Kết quả cần đạt | Trạng thái |
| --- | --- | --- | --- |
| DOC-01 | Sửa format, mở đầu, giới thiệu, mục tiêu/phạm vi | Bám mô hình một hãng; thống nhất mục lục, tiêu đề, bảng và chú thích hình theo mẫu môn học | Chưa làm |
| DOC-02 | Đối chiếu thiết kế với sản phẩm | Use case, sequence, giao diện, sơ đồ logic/quan hệ và ràng buộc khớp bản triển khai | Chưa làm |
| DOC-03 | Tổng hợp nội dung CSDL và minh chứng | Ghi cách dùng SP/function/view/trigger/transaction/index/quyền/backup theo phần thực sự làm | Chưa làm |
| DOC-04 | Tổng hợp kiểm thử và danh sách lỗi | Ghi bước làm, kết quả mong đợi, kết quả thực tế; theo dõi lỗi đến khi được sửa | Chưa làm |
| DOC-05 | Đóng gói báo cáo và chuẩn bị demo | Rà format cuối, ảnh rõ, phân công trình bày và dữ liệu demo | Chưa làm |
| SQL-H01 | SP xem lịch sử đặt vé | Làm theo đề bài ở mục 4; Quân kiểm tra trước khi ghép | Chưa làm |
| SQL-H02 | Function tính tổng tiền vé trong đơn | Làm sau SQL-H01; Quân kiểm tra kết quả và cách dùng trong SP | Chưa làm |
| SQL-H03 | View chi tiết vé | Nhận khi hai bài trước và mốc báo cáo đã hoàn thành | Chưa làm |
| SQL-H04 | Script full backup và phục hồi thử | Nhận khi tiến độ cho phép; Quân chịu trách nhiệm hoàn tất nếu người 4 bận báo cáo | Chưa làm |

## 4. SQL của người thứ 4

### SQL-H01 — SP xem lịch sử đặt vé

- Tên: `usp_LayLichSuDatVe`.
- Đầu vào: `@MaKhachHang`, kiểu dữ liệu khớp cột trong schema.
- Trả các cột: `MaDonDatVe`, `MaPNR`, `NgayDat`, `TongTien`, `TrangThai`.
- Chỉ trả đơn của khách được truyền vào; sắp xếp `NgayDat` giảm dần, dùng `MaDonDatVe` giảm dần để phân định khi trùng thời gian.
- Khách không có đơn: trả danh sách rỗng, không tạo dòng giả.
- Kiểm thử: khách có nhiều đơn; khách không có đơn; hai khách khác nhau không bị lẫn đơn.
- Bàn giao: file tạo SP, lệnh `EXEC` thử, ảnh kết quả và giải thích ngắn.
- Backend phải lấy mã khách hàng từ phiên đăng nhập, không tin mã tự gửi từ giao diện.

### SQL-H02 — Function tính tổng tiền vé

- Tên: `fn_TinhTongTienDon`.
- Đầu vào: `@MaDonDatVe`.
- Kết quả: một số tiền, kiểu dữ liệu phù hợp với `TongTien` trong schema.
- Tính tổng giá đã chốt của các vé thuộc đơn (`GiaVeChot`); không dùng giá bán hiện tại của hạng vé.
- Quy ước: không có vé thì trả `0`. Việc kiểm tra đơn tồn tại và hợp lệ do SP gọi hàm thực hiện.
- Phạm vi hiện tại thanh toán toàn bộ đơn, chưa có hủy từng vé/hoàn tiền riêng; nếu nhóm bổ sung nghiệp vụ này phải chốt lại cách tính.
- Kiểm thử: đơn một vé, đơn nhiều vé, đơn không có vé và mã đơn không tồn tại.
- Bàn giao: file function, câu lệnh gọi thử và bảng đối chiếu tổng tiền.

### SQL-H03 — View chi tiết vé

- Tên: `vw_ChiTietVe`.
- Kết hợp vé, đơn, hành khách, hạng vé theo chuyến và chuyến bay.
- Cột dự kiến: `MaVe`, `MaDonDatVe`, `MaPNR`, `MaHanhKhach`, `HoTenHanhKhach`, `MaChuyenBay`, `SoHieuChuyen`, `GioCatCanh`, `MaSanBayDi`, `MaSanBayDen`, `HangVe`, `GiaVeChot`, `TrangThaiVe`.
- Mỗi vé xuất hiện đúng một dòng; khi nối hạng vé phải dùng cả mã chuyến và hạng vé.
- View phục vụ SP lấy chi tiết; quyền xem dữ liệu được kiểm tra trong luồng backend/SP, không coi view là cơ chế phân quyền khách hàng.
- Kiểm thử: đơn nhiều hành khách; một hành khách có vé ở nhiều chuyến; đối chiếu số dòng với số vé.
- Bàn giao: file view, truy vấn thử và ảnh đối chiếu.

### SQL-H04 — Full backup và phục hồi thử

- Viết script full backup database SkyGo, kiểm tra file backup và phục hồi sang một database thử riêng.
- Không ghi đè database đang dùng của nhóm; cấu hình đường dẫn phù hợp SQL Server trên máy thực hiện.
- Đối chiếu số dòng đơn/vé và tổng tiền thanh toán thành công giữa bản gốc và bản phục hồi.
- Bàn giao: script, ảnh kết quả, bảng đối chiếu, giải thích ngắn các bước.
- Differential/log backup hoặc phục hồi theo thời điểm chỉ bổ sung khi rubric yêu cầu và Quân đã thống nhất cách làm.

## 5. Điều kiện hoàn thành

- [ ]  Các thành viên chạy được dự án và database theo hướng dẫn chung.
- [ ]  Luồng tìm chuyến, đặt vé, thanh toán, PNR và check-in dùng dữ liệu thật trong SQL Server.
- [ ]  Không tạo đơn/vé dở dang khi thao tác bị lỗi; không bán vượt chỗ hoặc check-in trùng ghế.
- [ ]  Chặn thanh toán lặp, check-in vé chưa thanh toán, PNR/xác minh sai và xem đơn của khách khác.
- [ ]  Chức năng quản trị có kiểm tra quyền ở backend.
- [ ]  SP/function/view/trigger đã có lệnh gọi hoặc kịch bản chứng minh; có kiểm thử hợp lệ và không hợp lệ phù hợp.
- [ ]  Script dữ liệu, index, quyền SQL và backup/restore có hướng dẫn và minh chứng.
- [ ]  Báo cáo phản ánh chức năng thực sự đã triển khai, đủ ảnh và giải thích của người phụ trách.

##
