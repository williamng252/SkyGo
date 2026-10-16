
-- 1.DATABASE
CREATE DATABASE SkyGo_Cnpm;
GO

USE SkyGo_Cnpm;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- 2. TẠO CÁC BẢNG
-- Bảng 1: Sân bay đi/đến
CREATE TABLE SAN_BAY
(
    MaSanBay CHAR(3) NOT NULL,
    TenSanBay NVARCHAR(100) NOT NULL,
    ThanhPho NVARCHAR(60) NOT NULL,
    QuocGia NVARCHAR(60) NOT NULL,
    TrangThai BIT NOT NULL
);
GO

-- Bảng 2: Hồ sơ người đặt vé
CREATE TABLE KHACH_HANG
(
    MaKhachHang BIGINT IDENTITY(1,1) NOT NULL,
    HoTen NVARCHAR(100) NOT NULL,
    SDT VARCHAR(20) NULL,
    Email VARCHAR(254) NOT NULL
);
GO

-- Bảng 3: Thông tin đăng nhập và vai trò
CREATE TABLE TAI_KHOAN_ND
(
    MaTK BIGINT IDENTITY(1,1) NOT NULL,
    TenDangNhap VARCHAR(50) NOT NULL,
    Email VARCHAR(254) NOT NULL,
    MatKhauHash VARCHAR(255) NOT NULL,
    VaiTro VARCHAR(10) NOT NULL,
    NgayTao DATETIME2 NOT NULL,
    TrangThai BIT NOT NULL,
    MaKhachHang BIGINT NULL
);
GO

-- Bảng 4: Người thực sự bay
CREATE TABLE HANH_KHACH
(
    MaHanhKhach BIGINT IDENTITY(1,1) NOT NULL,
    HoTen NVARCHAR(100) NOT NULL,
    NgaySinh DATE NOT NULL,
    GioiTinh VARCHAR(10) NULL,
    LoaiGiayTo VARCHAR(10) NULL,
    SoGiayTo VARCHAR(30) NULL,
    QuocTich NVARCHAR(60) NULL
);
GO

-- Bảng 5: Chuyến bay cụ thể theo ngày giờ
CREATE TABLE CHUYEN_BAY
(
    MaChuyenBay VARCHAR(20) NOT NULL,
    SoHieuChuyen VARCHAR(10) NOT NULL,
    GioCatCanh DATETIME2 NOT NULL,
    GioDenDuKien DATETIME2 NOT NULL,
    TrangThai VARCHAR(12) NOT NULL,
    LyDoThayDoi NVARCHAR(250) NULL,
    MoCheckInLuc DATETIME2 NOT NULL,
    DongCheckInLuc DATETIME2 NOT NULL,
    MaSanBayDi CHAR(3) NOT NULL,
    MaSanBayDen CHAR(3) NOT NULL
);
GO

-- Bảng 6: Giá và hạng vé của từng chuyến
CREATE TABLE HANG_VE_CHUYEN_BAY
(
    MaChuyenBay VARCHAR(20) NOT NULL,
    HangVe VARCHAR(10) NOT NULL,
    GiaCoBan DECIMAL(18,2) NOT NULL,
    ThuePhi DECIMAL(18,2) NOT NULL,
    TrangThai BIT NOT NULL
);
GO

-- Bảng 7: Các ghế của từng chuyến/hạng
CREATE TABLE GHE_CHUYEN_BAY
(
    MaGhe BIGINT IDENTITY(1,1) NOT NULL,
    MaChuyenBay VARCHAR(20) NOT NULL,
    HangVe VARCHAR(10) NOT NULL,
    SoGhe VARCHAR(5) NOT NULL
);
GO

-- Bảng 8: Một lần đặt, có thể gồm nhiều vé
CREATE TABLE DON_DAT_VE
(
    MaDonDatVe BIGINT IDENTITY(1,1) NOT NULL,
    MaPNR CHAR(6) NOT NULL,
    NgayDat DATETIME2 NOT NULL,
    HanThanhToan DATETIME2 NOT NULL,
    HoTenLienHe NVARCHAR(100) NOT NULL,
    EmailLienHe VARCHAR(254) NOT NULL,
    SDTLienHe VARCHAR(20) NOT NULL,
    TongTien DECIMAL(18,2) NOT NULL,
    TrangThai VARCHAR(10) NOT NULL,
    MaKhachHang BIGINT NULL
);
GO

-- Bảng 9: Vé của một hành khách trên một chuyến
-- GiaVeChot là cột tự tính = GiaCoBanChot + ThuePhiChot.
-- AS khai báo công thức; CONVERT ép kiểu số tiền; PERSISTED lưu kết quả tính.
-- Khi INSERT vé, không nhập trực tiếp cột GiaVeChot.
CREATE TABLE VE_CHUYEN_BAY
(
    MaVe BIGINT IDENTITY(1,1) NOT NULL,
    MaDonDatVe BIGINT NOT NULL,
    MaHanhKhach BIGINT NOT NULL,
    MaChuyenBay VARCHAR(20) NOT NULL,
    HangVe VARCHAR(10) NOT NULL,
    GiaCoBanChot DECIMAL(18,2) NOT NULL,
    ThuePhiChot DECIMAL(18,2) NOT NULL,
    GiaVeChot AS CONVERT(DECIMAL(18,2),GiaCoBanChot+ThuePhiChot) PERSISTED,
    TrangThai VARCHAR(10) NOT NULL
);
GO

-- Bảng 10: Kết quả làm thủ tục và ghế được phân
CREATE TABLE CHECK_IN
(
    MaCheckIn BIGINT IDENTITY(1,1) NOT NULL,
    MaVe BIGINT NOT NULL,
    MaGhe BIGINT NOT NULL,
    ThoiGian DATETIME2 NOT NULL,
    TrangThai VARCHAR(12) NOT NULL,
    MaQR_BP VARCHAR(100) NOT NULL,
    MaTK BIGINT NULL
);
GO

-- Bảng 11: Các lần thử thanh toán của đơn
CREATE TABLE GIAO_DICH_TT
(
    MaGiaoDich BIGINT IDENTITY(1,1) NOT NULL,
    MaDonDatVe BIGINT NOT NULL,
    SoTien DECIMAL(18,2) NOT NULL,
    PhuongThucTT VARCHAR(20) NOT NULL,
    TrangThaiTT VARCHAR(10) NOT NULL,
    ThoiGianTao DATETIME2 NOT NULL,
    ThoiGianTT DATETIME2 NULL,
    MaThamChieu VARCHAR(100) NULL
);
GO

-- 3. THÊM KHÓA CHÍNH
-- Khóa chính xác định duy nhất mỗi dòng; bảng hạng vé dùng khóa ghép hai cột.

ALTER TABLE SAN_BAY
ADD CONSTRAINT PK_SAN_BAY
    PRIMARY KEY (MaSanBay);
GO

ALTER TABLE KHACH_HANG
ADD CONSTRAINT PK_KHACH_HANG
    PRIMARY KEY (MaKhachHang);
GO

ALTER TABLE TAI_KHOAN_ND
ADD CONSTRAINT PK_TAI_KHOAN_ND
    PRIMARY KEY (MaTK);
GO

ALTER TABLE HANH_KHACH
ADD CONSTRAINT PK_HANH_KHACH
    PRIMARY KEY (MaHanhKhach);
GO

ALTER TABLE CHUYEN_BAY
ADD CONSTRAINT PK_CHUYEN_BAY
    PRIMARY KEY (MaChuyenBay);
GO

ALTER TABLE HANG_VE_CHUYEN_BAY
ADD CONSTRAINT PK_HANG_VE_CHUYEN_BAY
    PRIMARY KEY (MaChuyenBay,HangVe);
GO

ALTER TABLE GHE_CHUYEN_BAY
ADD CONSTRAINT PK_GHE_CHUYEN_BAY
    PRIMARY KEY (MaGhe);
GO

ALTER TABLE DON_DAT_VE
ADD CONSTRAINT PK_DON_DAT_VE
    PRIMARY KEY (MaDonDatVe);
GO

ALTER TABLE VE_CHUYEN_BAY
ADD CONSTRAINT PK_VE_CHUYEN_BAY
    PRIMARY KEY (MaVe);
GO

ALTER TABLE CHECK_IN
ADD CONSTRAINT PK_CHECK_IN
    PRIMARY KEY (MaCheckIn);
GO

ALTER TABLE GIAO_DICH_TT
ADD CONSTRAINT PK_GIAO_DICH_TT
    PRIMARY KEY (MaGiaoDich);
GO

-- 4. THÊM KHÓA NGOẠI
-- FOREIGN KEY: cột giữ mã tham chiếu. REFERENCES: bảng/cột được tham chiếu.

-- Tài khoản khách hàng tham chiếu hồ sơ khách hàng; admin được để mã này trống.
ALTER TABLE TAI_KHOAN_ND
ADD CONSTRAINT FK_TAIKHOAN_KHACHHANG
    FOREIGN KEY (MaKhachHang)
    REFERENCES dbo.KHACH_HANG(MaKhachHang);
GO

-- Mã sân bay đi của chuyến phải có trong SAN_BAY.
ALTER TABLE CHUYEN_BAY
ADD CONSTRAINT FK_CHUYENBAY_SANBAYDI
    FOREIGN KEY (MaSanBayDi)
    REFERENCES dbo.SAN_BAY(MaSanBay);
GO

-- Mã sân bay đến của chuyến phải có trong SAN_BAY.
ALTER TABLE CHUYEN_BAY
ADD CONSTRAINT FK_CHUYENBAY_SANBAYDEN
    FOREIGN KEY (MaSanBayDen)
    REFERENCES dbo.SAN_BAY(MaSanBay);
GO

-- Hạng vé phải thuộc chuyến bay đã tồn tại.
ALTER TABLE HANG_VE_CHUYEN_BAY
ADD CONSTRAINT FK_HANGVE_CHUYENBAY
    FOREIGN KEY (MaChuyenBay)
    REFERENCES dbo.CHUYEN_BAY(MaChuyenBay);
GO

-- Ghế thuộc cặp chuyến/hạng đã tồn tại; đây là một khóa ngoại ghép.
ALTER TABLE GHE_CHUYEN_BAY
ADD CONSTRAINT FK_GHE_HANGVE
    FOREIGN KEY (MaChuyenBay,HangVe)
    REFERENCES dbo.HANG_VE_CHUYEN_BAY(MaChuyenBay,HangVe);
GO

-- Đơn tham chiếu người đặt có tài khoản; khách vãng lai được để trống.
ALTER TABLE DON_DAT_VE
ADD CONSTRAINT FK_DONDATVE_KHACHHANG
    FOREIGN KEY (MaKhachHang)
    REFERENCES dbo.KHACH_HANG(MaKhachHang);
GO

-- Vé phải nằm trong đơn đã tồn tại.
ALTER TABLE VE_CHUYEN_BAY
ADD CONSTRAINT FK_VE_DONDATVE
    FOREIGN KEY (MaDonDatVe)
    REFERENCES dbo.DON_DAT_VE(MaDonDatVe);
GO

-- Vé phải xác định người thực sự bay đã tồn tại.
ALTER TABLE VE_CHUYEN_BAY
ADD CONSTRAINT FK_VE_HANHKHACH
    FOREIGN KEY (MaHanhKhach)
    REFERENCES dbo.HANH_KHACH(MaHanhKhach);
GO

-- Vé phải chọn cặp chuyến/hạng đã tồn tại; tham chiếu cả hai cột.
ALTER TABLE VE_CHUYEN_BAY
ADD CONSTRAINT FK_VE_HANGVE
    FOREIGN KEY (MaChuyenBay,HangVe)
    REFERENCES dbo.HANG_VE_CHUYEN_BAY(MaChuyenBay,HangVe);
GO

-- Check-in phải tham chiếu vé đã tồn tại.
ALTER TABLE CHECK_IN
ADD CONSTRAINT FK_CHECKIN_VE
    FOREIGN KEY (MaVe)
    REFERENCES dbo.VE_CHUYEN_BAY(MaVe);
GO

-- Ghế được phân phải có trong danh sách ghế.
ALTER TABLE CHECK_IN
ADD CONSTRAINT FK_CHECKIN_GHE
    FOREIGN KEY (MaGhe)
    REFERENCES dbo.GHE_CHUYEN_BAY(MaGhe);
GO

-- Nếu ghi tài khoản thực hiện check-in thì tài khoản phải tồn tại.
ALTER TABLE CHECK_IN
ADD CONSTRAINT FK_CHECKIN_TAIKHOAN
    FOREIGN KEY (MaTK)
    REFERENCES dbo.TAI_KHOAN_ND(MaTK);
GO

-- Mỗi lần thanh toán phải thuộc một đơn đã tồn tại.
ALTER TABLE GIAO_DICH_TT
ADD CONSTRAINT FK_GIAODICH_DONDATVE
    FOREIGN KEY (MaDonDatVe)
    REFERENCES dbo.DON_DAT_VE(MaDonDatVe);
GO

-- 5. THÊM RÀNG BUỘC KHÔNG TRÙNG
-- UNIQUE áp dụng cho một cột hoặc một tổ hợp nhiều cột.

-- Không trùng tên đăng nhập.
ALTER TABLE TAI_KHOAN_ND
ADD CONSTRAINT UQ_TAIKHOAN_TenDangNhap
    UNIQUE (TenDangNhap);
GO

-- Không trùng email tài khoản.
ALTER TABLE TAI_KHOAN_ND
ADD CONSTRAINT UQ_TAIKHOAN_Email
    UNIQUE (Email);
GO

-- Không trùng số hiệu chuyến và thời điểm cất cánh.
ALTER TABLE CHUYEN_BAY
ADD CONSTRAINT UQ_CHUYENBAY_SoHieuNgay
    UNIQUE (SoHieuChuyen,GioCatCanh);
GO

-- Không trùng số ghế trong cùng một chuyến.
ALTER TABLE GHE_CHUYEN_BAY
ADD CONSTRAINT UQ_GHE_CHUYENBAY_SoGhe
    UNIQUE (MaChuyenBay,SoGhe);
GO

-- Không trùng mã đặt chỗ PNR.
ALTER TABLE DON_DAT_VE
ADD CONSTRAINT UQ_DONDATVE_PNR
    UNIQUE (MaPNR);
GO

-- Không có hai vé cho cùng người/chuyến trong cùng đơn.
ALTER TABLE VE_CHUYEN_BAY
ADD CONSTRAINT UQ_VE_DonHanhKhachChuyen
    UNIQUE (MaDonDatVe,MaHanhKhach,MaChuyenBay);
GO

-- Không trùng mã QR của thẻ lên máy bay.
ALTER TABLE CHECK_IN
ADD CONSTRAINT UQ_CHECKIN_QR
    UNIQUE (MaQR_BP);
GO

-- 6. THÊM RÀNG BUỘC KIỂM TRA GIÁ TRỊ
-- CHECK chỉ cho ghi dữ liệu thỏa điều kiện.

-- CUSTOMER phải có hồ sơ khách; ADMIN không liên kết hồ sơ khách.
ALTER TABLE TAI_KHOAN_ND
ADD CONSTRAINT CK_TAIKHOAN_VaiTro
    CHECK ( (VaiTro='CUSTOMER' AND MaKhachHang IS NOT NULL) OR (VaiTro='ADMIN' AND MaKhachHang IS NULL));
GO

-- Tên đăng nhập có từ 3 đến 50 ký tự.
ALTER TABLE TAI_KHOAN_ND
ADD CONSTRAINT CK_TAIKHOAN_TenDangNhap
    CHECK (LEN(TenDangNhap) BETWEEN 3 AND 50);
GO

-- Giới tính thuộc danh sách quy định hoặc để trống.
ALTER TABLE HANH_KHACH
ADD CONSTRAINT CK_HANHKHACH_GioiTinh
    CHECK (GioiTinh IS NULL OR GioiTinh IN ('MALE','FEMALE','OTHER'));
GO

-- Loại giấy tờ thuộc danh sách quy định hoặc để trống.
ALTER TABLE HANH_KHACH
ADD CONSTRAINT CK_HANHKHACH_LoaiGiayTo
    CHECK (LoaiGiayTo IS NULL OR LoaiGiayTo IN ('CCCD','PASSPORT','OTHER'));
GO

-- Ngày sinh không sau ngày hiện tại (tính theo UTC).
ALTER TABLE HANH_KHACH
ADD CONSTRAINT CK_HANHKHACH_NgaySinh
    CHECK (NgaySinh<=CONVERT(DATE,SYSUTCDATETIME()));
GO

-- Sân bay đi và sân bay đến khác nhau.
ALTER TABLE CHUYEN_BAY
ADD CONSTRAINT CK_CHUYENBAY_SanBay
    CHECK (MaSanBayDi<>MaSanBayDen);
GO

-- Giờ đến sau giờ cất cánh; mở check-in trước đóng, đóng trước cất cánh.
ALTER TABLE CHUYEN_BAY
ADD CONSTRAINT CK_CHUYENBAY_ThoiGian
    CHECK (GioDenDuKien>GioCatCanh AND MoCheckInLuc<DongCheckInLuc AND DongCheckInLuc<GioCatCanh);
GO

-- Trạng thái chuyến bay chỉ nhận các giá trị đã quy định.
ALTER TABLE CHUYEN_BAY
ADD CONSTRAINT CK_CHUYENBAY_TrangThai
    CHECK (TrangThai IN ('SCHEDULED','DELAYED','CANCELLED','DEPARTED','ARRIVED'));
GO

-- Hai hạng vé: phổ thông (ECONOMY), thương gia (BUSINESS).
ALTER TABLE HANG_VE_CHUYEN_BAY
ADD CONSTRAINT CK_HANGVE_Loai
    CHECK (HangVe IN ('ECONOMY','BUSINESS'));
GO

-- Giá cơ bản và thuế phí không âm.
ALTER TABLE HANG_VE_CHUYEN_BAY
ADD CONSTRAINT CK_HANGVE_Gia
    CHECK (GiaCoBan>=0 AND ThuePhi>=0);
GO

-- Tổng tiền đơn phải lớn hơn 0.
ALTER TABLE DON_DAT_VE
ADD CONSTRAINT CK_DONDATVE_TongTien
    CHECK (TongTien>0);
GO

-- Hạn thanh toán sau thời điểm đặt.
ALTER TABLE DON_DAT_VE
ADD CONSTRAINT CK_DONDATVE_Han
    CHECK (HanThanhToan>NgayDat);
GO

-- PNR có 6 ký tự, chỉ gồm A-Z và 0-9. COLLATE phân biệt chữ hoa/thường khi kiểm tra.
ALTER TABLE DON_DAT_VE
ADD CONSTRAINT CK_DONDATVE_PNR
    CHECK (LEN(MaPNR)=6 AND MaPNR COLLATE Latin1_General_100_BIN2 NOT LIKE '%[^A-Z0-9]%');
GO

-- Trạng thái đơn thuộc danh sách đã quy định.
ALTER TABLE DON_DAT_VE
ADD CONSTRAINT CK_DONDATVE_TrangThai
    CHECK (TrangThai IN ('PENDING','PAID','CANCELLED','EXPIRED'));
GO

-- Giá và thuế phí đã chốt của vé không âm.
ALTER TABLE VE_CHUYEN_BAY
ADD CONSTRAINT CK_VE_Gia
    CHECK (GiaCoBanChot>=0 AND ThuePhiChot>=0);
GO

-- Trạng thái vé thuộc danh sách đã quy định.
ALTER TABLE VE_CHUYEN_BAY
ADD CONSTRAINT CK_VE_TrangThai
    CHECK (TrangThai IN ('RESERVED','ISSUED','CANCELLED','USED'));
GO

-- Check-in còn hiệu lực hoặc đã hủy.
ALTER TABLE CHECK_IN
ADD CONSTRAINT CK_CHECKIN_TrangThai
    CHECK (TrangThai IN ('CHECKED_IN','CANCELLED'));
GO

-- Số tiền thanh toán phải lớn hơn 0.
ALTER TABLE GIAO_DICH_TT
ADD CONSTRAINT CK_GIAODICH_SoTien
    CHECK (SoTien>0);
GO

-- Lần thanh toán đang xử lý, thành công hoặc thất bại.
ALTER TABLE GIAO_DICH_TT
ADD CONSTRAINT CK_GIAODICH_TrangThai
    CHECK (TrangThaiTT IN ('PENDING','SUCCESS','FAILED'));
GO

-- Đang xử lý thì chưa có thời điểm kết thúc; kết thúc không trước lúc tạo.
ALTER TABLE GIAO_DICH_TT
ADD CONSTRAINT CK_GIAODICH_ThoiGian
    CHECK ( (TrangThaiTT='PENDING' AND ThoiGianTT IS NULL) OR (TrangThaiTT IN ('SUCCESS','FAILED') AND ThoiGianTT IS NOT NULL AND ThoiGianTT>=ThoiGianTao));
GO

-- 7. THÊM GIÁ TRỊ MẶC ĐỊNH
-- DEFAULT được dùng khi INSERT bỏ qua cột đó; SYSUTCDATETIME() trả ngày giờ UTC.

ALTER TABLE SAN_BAY
ADD CONSTRAINT DF_SANBAY_TrangThai
    DEFAULT (1) FOR TrangThai;
GO

ALTER TABLE TAI_KHOAN_ND
ADD CONSTRAINT DF_TAIKHOAN_VaiTro
    DEFAULT ('CUSTOMER') FOR VaiTro;
GO

ALTER TABLE TAI_KHOAN_ND
ADD CONSTRAINT DF_TAIKHOAN_NgayTao
    DEFAULT (SYSUTCDATETIME()) FOR NgayTao;
GO

ALTER TABLE TAI_KHOAN_ND
ADD CONSTRAINT DF_TAIKHOAN_TrangThai
    DEFAULT (1) FOR TrangThai;
GO

ALTER TABLE CHUYEN_BAY
ADD CONSTRAINT DF_CHUYENBAY_TrangThai
    DEFAULT ('SCHEDULED') FOR TrangThai;
GO

ALTER TABLE HANG_VE_CHUYEN_BAY
ADD CONSTRAINT DF_HANGVE_ThuePhi
    DEFAULT (0) FOR ThuePhi;
GO

ALTER TABLE HANG_VE_CHUYEN_BAY
ADD CONSTRAINT DF_HANGVE_TrangThai
    DEFAULT (1) FOR TrangThai;
GO

ALTER TABLE DON_DAT_VE
ADD CONSTRAINT DF_DONDATVE_NgayDat
    DEFAULT (SYSUTCDATETIME()) FOR NgayDat;
GO

ALTER TABLE DON_DAT_VE
ADD CONSTRAINT DF_DONDATVE_TrangThai
    DEFAULT ('PENDING') FOR TrangThai;
GO

ALTER TABLE VE_CHUYEN_BAY
ADD CONSTRAINT DF_VE_TrangThai
    DEFAULT ('RESERVED') FOR TrangThai;
GO

ALTER TABLE CHECK_IN
ADD CONSTRAINT DF_CHECKIN_ThoiGian
    DEFAULT (SYSUTCDATETIME()) FOR ThoiGian;
GO

ALTER TABLE CHECK_IN
ADD CONSTRAINT DF_CHECKIN_TrangThai
    DEFAULT ('CHECKED_IN') FOR TrangThai;
GO

ALTER TABLE GIAO_DICH_TT
ADD CONSTRAINT DF_GIAODICH_TrangThai
    DEFAULT ('PENDING') FOR TrangThaiTT;
GO

ALTER TABLE GIAO_DICH_TT
ADD CONSTRAINT DF_GIAODICH_ThoiGianTao
    DEFAULT (SYSUTCDATETIME()) FOR ThoiGianTao;
GO

-- 8. CHỈ MỤC 
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
GO

-- Mỗi khách có tối đa một tài khoản; nhiều admin vẫn được có MaKhachHang = NULL.
CREATE UNIQUE INDEX UX_TAIKHOAN_KhachHang
ON TAI_KHOAN_ND(MaKhachHang)
WHERE MaKhachHang IS NOT NULL;
GO

-- Một vé chỉ có tối đa một lượt check-in còn hiệu lực; lượt đã hủy được lưu lại.
CREATE UNIQUE INDEX UX_CHECKIN_VeHieuLuc
ON CHECK_IN(MaVe)
WHERE TrangThai = 'CHECKED_IN';
GO

-- Một ghế chỉ được dùng cho tối đa một lượt check-in còn hiệu lực.
CREATE UNIQUE INDEX UX_CHECKIN_GheHieuLuc
ON CHECK_IN(MaGhe)
WHERE TrangThai = 'CHECKED_IN';
GO

-- Mã tham chiếu thanh toán không trùng khi có giá trị; được phép có nhiều NULL.
CREATE UNIQUE INDEX UX_GIAODICH_ThamChieu
ON GIAO_DICH_TT(MaThamChieu)
WHERE MaThamChieu IS NOT NULL;
GO

-- Mỗi đơn có tối đa một lần thanh toán thành công, vẫn lưu được nhiều lần thất bại.
CREATE UNIQUE INDEX UX_GIAODICH_DonThanhCong
ON GIAO_DICH_TT(MaDonDatVe)
WHERE TrangThaiTT = 'SUCCESS';
GO

