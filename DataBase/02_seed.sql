-- DB-02: DU LIEU MAU SKYGO
-- Chay sau 01_schema.sql, khi ca 11 bang chua co du lieu.
-- Chay ca file mot lan; khong boi den tung doan vi co dung bien.
-- Khong can tao lai database, khong tu y sua ma khoa ngoai.
-- Moi ngay gio luu trong CSDL la UTC; giao dien Viet Nam hien UTC+7.
-- Tai khoan DEMO dung BCrypt, mat khau chung: SkyGoDemo123!

USE SkyGo_Cnpm;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
GO

-- 1. KIEM TRA BANG DA CO DU LIEU CHUA
IF EXISTS (SELECT 1 FROM SAN_BAY)
OR EXISTS (SELECT 1 FROM KHACH_HANG)
OR EXISTS (SELECT 1 FROM TAI_KHOAN_ND)
OR EXISTS (SELECT 1 FROM HANH_KHACH)
OR EXISTS (SELECT 1 FROM CHUYEN_BAY)
OR EXISTS (SELECT 1 FROM HANG_VE_CHUYEN_BAY)
OR EXISTS (SELECT 1 FROM GHE_CHUYEN_BAY)
OR EXISTS (SELECT 1 FROM DON_DAT_VE)
OR EXISTS (SELECT 1 FROM VE_CHUYEN_BAY)
OR EXISTS (SELECT 1 FROM GIAO_DICH_TT)
OR EXISTS (SELECT 1 FROM CHECK_IN)
BEGIN
    RAISERROR (N'Chi chay seed khi 11 bang chua co du lieu. Khong chay lap file.', 16, 1);
    RETURN;
END;

-- 2. CAC BIEN DUNG CHUNG
-- Gio hien tai va moc 0 gio UTC hom nay.
DECLARE @HienTai DATETIME2 = SYSUTCDATETIME();
DECLARE @DauNgay DATETIME2 = CONVERT(DATE, @HienTai);

-- SG001, SG002, SG005: sau ngay chay seed 3 ngay.
-- SG003: sau 4 gio, de demo check-in ngay sau khi chay seed.
DECLARE @GioSG001 DATETIME2 = DATEADD(HOUR, 1, DATEADD(DAY, 3, @DauNgay));
DECLARE @GioSG002 DATETIME2 = DATEADD(HOUR, 5, DATEADD(DAY, 3, @DauNgay));
DECLARE @GioSG003 DATETIME2 = DATEADD(HOUR, 4, @HienTai);
DECLARE @GioSG004 DATETIME2 = DATEADD(HOUR, 2, DATEADD(DAY, 4, @DauNgay));
DECLARE @GioSG005 DATETIME2 = DATEADD(HOUR, 9, DATEADD(DAY, 3, @DauNgay));
DECLARE @GioSG006 DATETIME2 = DATEADD(HOUR, 3, DATEADD(DAY, 4, @DauNgay));

BEGIN TRANSACTION;

-- 3. SAN BAY
INSERT INTO SAN_BAY (MaSanBay, TenSanBay, ThanhPho, QuocGia, TrangThai)
VALUES
('SGN', N'Tan Son Nhat', N'TP. Ho Chi Minh', N'Viet Nam', 1),
('HAN', N'Noi Bai', N'Ha Noi', N'Viet Nam', 1),
('DAD', N'Da Nang', N'Da Nang', N'Viet Nam', 1),
('TBB', N'Tuy Hoa', N'Tuy Hoa', N'Viet Nam', 1);

-- 4. KHACH HANG
-- SCOPE_IDENTITY lay ma vua tu tang; khong gia dinh ma luon bat dau tu 1.
INSERT INTO KHACH_HANG (HoTen, SDT, Email)
VALUES (N'Nguyen Anh Quan', '0900000001', 'quan@example.com');
DECLARE @KhachQuan BIGINT = SCOPE_IDENTITY();

INSERT INTO KHACH_HANG (HoTen, SDT, Email)
VALUES (N'Tran Minh An', '0900000002', 'an@example.com');
DECLARE @KhachAn BIGINT = SCOPE_IDENTITY();

INSERT INTO KHACH_HANG (HoTen, SDT, Email)
VALUES (N'Le Bao Binh', '0900000003', 'binh@example.com');
DECLARE @KhachBinh BIGINT = SCOPE_IDENTITY();

-- 5. TAI KHOAN
-- BCrypt hash cua mat khau demo, khong phai mat khau goc.
DECLARE @MatKhauHash VARCHAR(255) = '$2b$12$9oXge1oOSx1VGrZvWUBz1u4qbvFCt51C6Y9TaA1MVpvm2lkIUwXz.';
INSERT INTO TAI_KHOAN_ND
(TenDangNhap, Email, MatKhauHash, VaiTro, NgayTao, TrangThai, MaKhachHang)
VALUES
('admin_demo', 'admin@example.com', @MatKhauHash, 'ADMIN', @HienTai, 1, NULL),
('quan_demo', 'quan@example.com', @MatKhauHash, 'CUSTOMER', @HienTai, 1, @KhachQuan),
('an_demo', 'an@example.com', @MatKhauHash, 'CUSTOMER', @HienTai, 1, @KhachAn),
('binh_khoa', 'binh@example.com', @MatKhauHash, 'CUSTOMER', @HienTai, 0, @KhachBinh);

-- 6. HANH KHACH
INSERT INTO HANH_KHACH (HoTen, NgaySinh, GioiTinh, LoaiGiayTo, SoGiayTo, QuocTich)
VALUES (N'Nguyen Thi Mai', '19800210', 'FEMALE', 'CCCD', '000000000101', N'Viet Nam');
DECLARE @HanhKhachMai BIGINT = SCOPE_IDENTITY();

INSERT INTO HANH_KHACH (HoTen, NgaySinh, GioiTinh, LoaiGiayTo, SoGiayTo, QuocTich)
VALUES (N'Nguyen Minh Khoa', '20080915', 'MALE', 'CCCD', '000000000102', N'Viet Nam');
DECLARE @HanhKhachKhoa BIGINT = SCOPE_IDENTITY();

INSERT INTO HANH_KHACH (HoTen, NgaySinh, GioiTinh, LoaiGiayTo, SoGiayTo, QuocTich)
VALUES (N'Tran Minh An', '20050320', 'MALE', 'CCCD', '000000000103', N'Viet Nam');
DECLARE @HanhKhachAn BIGINT = SCOPE_IDENTITY();

INSERT INTO HANH_KHACH (HoTen, NgaySinh, GioiTinh, LoaiGiayTo, SoGiayTo, QuocTich)
VALUES (N'Pham Thi Lan', '19980712', 'FEMALE', 'CCCD', '000000000104', N'Viet Nam');
DECLARE @HanhKhachLan BIGINT = SCOPE_IDENTITY();

INSERT INTO HANH_KHACH (HoTen, NgaySinh, GioiTinh, LoaiGiayTo, SoGiayTo, QuocTich)
VALUES (N'Nguyen Anh Quan', '20060225', 'MALE', 'CCCD', '000000000105', N'Viet Nam');
DECLARE @HanhKhachQuan BIGINT = SCOPE_IDENTITY();

INSERT INTO HANH_KHACH (HoTen, NgaySinh, GioiTinh, LoaiGiayTo, SoGiayTo, QuocTich)
VALUES (N'Pham Minh Huy', '20010422', 'MALE', 'CCCD', '000000000106', N'Viet Nam');
DECLARE @HanhKhachHuy BIGINT = SCOPE_IDENTITY();

-- 7. CHUYEN BAY
-- Mo check-in truoc 12 gio; dong truoc 1 gio: quy uoc DU LIEU DEMO.
-- Day khong phai quy dinh check-in cua mot hang hang khong thuc te.
INSERT INTO CHUYEN_BAY
(MaChuyenBay, SoHieuChuyen, GioCatCanh, GioDenDuKien, TrangThai,
 LyDoThayDoi, MoCheckInLuc, DongCheckInLuc, MaSanBayDi, MaSanBayDen)
VALUES
('SG001', 'SG101', @GioSG001, DATEADD(MINUTE, 130, @GioSG001), 'SCHEDULED',
 NULL, DATEADD(HOUR, -12, @GioSG001), DATEADD(HOUR, -1, @GioSG001), 'SGN', 'HAN'),
('SG002', 'SG103', @GioSG002, DATEADD(MINUTE, 130, @GioSG002), 'SCHEDULED',
 NULL, DATEADD(HOUR, -12, @GioSG002), DATEADD(HOUR, -1, @GioSG002), 'SGN', 'HAN'),
('SG003', 'SG201', @GioSG003, DATEADD(MINUTE, 80, @GioSG003), 'SCHEDULED',
 NULL, DATEADD(HOUR, -12, @GioSG003), DATEADD(HOUR, -1, @GioSG003), 'SGN', 'DAD'),
('SG004', 'SG102', @GioSG004, DATEADD(MINUTE, 130, @GioSG004), 'SCHEDULED',
 NULL, DATEADD(HOUR, -12, @GioSG004), DATEADD(HOUR, -1, @GioSG004), 'HAN', 'SGN'),
('SG005', 'SG105', @GioSG005, DATEADD(MINUTE, 130, @GioSG005), 'CANCELLED',
 N'Huy chuyen de kiem thu', DATEADD(HOUR, -12, @GioSG005), DATEADD(HOUR, -1, @GioSG005), 'SGN', 'HAN'),
('SG006', 'SG107', @GioSG006, DATEADD(MINUTE, 130, @GioSG006), 'DELAYED',
 N'Doi gio de kiem thu', DATEADD(HOUR, -12, @GioSG006), DATEADD(HOUR, -1, @GioSG006), 'SGN', 'HAN');

-- 8. HANG VE VA GIA (DON VI: VND)
INSERT INTO HANG_VE_CHUYEN_BAY (MaChuyenBay, HangVe, GiaCoBan, ThuePhi, TrangThai)
VALUES
('SG001', 'ECONOMY', 1100000, 200000, 1),
('SG001', 'BUSINESS', 2100000, 200000, 1),
('SG002', 'ECONOMY', 1000000, 200000, 1),
('SG002', 'BUSINESS', 2000000, 200000, 1),
('SG003', 'ECONOMY', 800000, 200000, 1),
('SG003', 'BUSINESS', 1600000, 200000, 1),
('SG004', 'ECONOMY', 1000000, 200000, 1),
('SG004', 'BUSINESS', 2000000, 200000, 1),
('SG005', 'ECONOMY', 900000, 200000, 0),
('SG005', 'BUSINESS', 1900000, 200000, 0),
('SG006', 'ECONOMY', 1200000, 200000, 1),
('SG006', 'BUSINESS', 2200000, 200000, 1);

-- 9. GHE: MOI CHUYEN CO 6 GHE PHO THONG VA 2 GHE THUONG GIA
INSERT INTO GHE_CHUYEN_BAY (MaChuyenBay, HangVe, SoGhe)
VALUES
('SG001', 'ECONOMY', '12A'),
('SG001', 'ECONOMY', '12B'),
('SG001', 'ECONOMY', '12C'),
('SG001', 'ECONOMY', '13A'),
('SG001', 'ECONOMY', '13B'),
('SG001', 'ECONOMY', '13C'),
('SG001', 'BUSINESS', '1A'),
('SG001', 'BUSINESS', '1B'),
('SG002', 'ECONOMY', '12A'),
('SG002', 'ECONOMY', '12B'),
('SG002', 'ECONOMY', '12C'),
('SG002', 'ECONOMY', '13A'),
('SG002', 'ECONOMY', '13B'),
('SG002', 'ECONOMY', '13C'),
('SG002', 'BUSINESS', '1A'),
('SG002', 'BUSINESS', '1B'),
('SG003', 'ECONOMY', '12A'),
('SG003', 'ECONOMY', '12B'),
('SG003', 'ECONOMY', '12C'),
('SG003', 'ECONOMY', '13A'),
('SG003', 'ECONOMY', '13B'),
('SG003', 'ECONOMY', '13C'),
('SG003', 'BUSINESS', '1A'),
('SG003', 'BUSINESS', '1B'),
('SG004', 'ECONOMY', '12A'),
('SG004', 'ECONOMY', '12B'),
('SG004', 'ECONOMY', '12C'),
('SG004', 'ECONOMY', '13A'),
('SG004', 'ECONOMY', '13B'),
('SG004', 'ECONOMY', '13C'),
('SG004', 'BUSINESS', '1A'),
('SG004', 'BUSINESS', '1B'),
('SG005', 'ECONOMY', '12A'),
('SG005', 'ECONOMY', '12B'),
('SG005', 'ECONOMY', '12C'),
('SG005', 'ECONOMY', '13A'),
('SG005', 'ECONOMY', '13B'),
('SG005', 'ECONOMY', '13C'),
('SG005', 'BUSINESS', '1A'),
('SG005', 'BUSINESS', '1B'),
('SG006', 'ECONOMY', '12A'),
('SG006', 'ECONOMY', '12B'),
('SG006', 'ECONOMY', '12C'),
('SG006', 'ECONOMY', '13A'),
('SG006', 'ECONOMY', '13B'),
('SG006', 'ECONOMY', '13C'),
('SG006', 'BUSINESS', '1A'),
('SG006', 'BUSINESS', '1B');

-- 10. DON DAT VE
-- AB12CD: Quan dat cho Mai va Khoa, da thanh toan, chua check-in.
INSERT INTO DON_DAT_VE
(MaPNR, NgayDat, HanThanhToan, HoTenLienHe, EmailLienHe, SDTLienHe, TongTien, TrangThai, MaKhachHang)
VALUES ('AB12CD', DATEADD(DAY, -1, @HienTai), DATEADD(MINUTE, 30, DATEADD(DAY, -1, @HienTai)),
 N'Nguyen Anh Quan', 'quan@example.com', '0900000001', 2600000, 'PAID', @KhachQuan);
DECLARE @DonDaTra BIGINT = SCOPE_IDENTITY();

-- EF34GH: An giu 1 ve thuong gia, han thanh toan con 30 phut sau khi seed.
INSERT INTO DON_DAT_VE
(MaPNR, NgayDat, HanThanhToan, HoTenLienHe, EmailLienHe, SDTLienHe, TongTien, TrangThai, MaKhachHang)
VALUES ('EF34GH', @HienTai, DATEADD(MINUTE, 30, @HienTai),
 N'Tran Minh An', 'an@example.com', '0900000002', 2200000, 'PENDING', @KhachAn);
DECLARE @DonChoTra BIGINT = SCOPE_IDENTITY();

-- JK56LM: khach vang lai dat 2 ve; Lan da check-in 12A, Huy chua check-in.
INSERT INTO DON_DAT_VE
(MaPNR, NgayDat, HanThanhToan, HoTenLienHe, EmailLienHe, SDTLienHe, TongTien, TrangThai, MaKhachHang)
VALUES ('JK56LM', DATEADD(HOUR, -2, @HienTai), DATEADD(MINUTE, -90, @HienTai),
 N'Pham Thi Lan', 'lan@example.com', '0900000004', 2000000, 'PAID', NULL);
DECLARE @DonVangLai BIGINT = SCOPE_IDENTITY();

-- NP78QR: don het han, ve da huy va khong chiem cho.
INSERT INTO DON_DAT_VE
(MaPNR, NgayDat, HanThanhToan, HoTenLienHe, EmailLienHe, SDTLienHe, TongTien, TrangThai, MaKhachHang)
VALUES ('NP78QR', DATEADD(HOUR, -3, @HienTai), DATEADD(MINUTE, -150, @HienTai),
 N'Nguyen Anh Quan', 'quan@example.com', '0900000001', 1200000, 'EXPIRED', @KhachQuan);
DECLARE @DonHetHan BIGINT = SCOPE_IDENTITY();

-- 11. VE CHUYEN BAY
-- Khong INSERT GiaVeChot vi SQL Server tu tinh cot nay.
INSERT INTO VE_CHUYEN_BAY
(MaDonDatVe, MaHanhKhach, MaChuyenBay, HangVe, GiaCoBanChot, ThuePhiChot, TrangThai)
VALUES
(@DonDaTra, @HanhKhachMai, 'SG001', 'ECONOMY', 1100000, 200000, 'ISSUED'),
(@DonDaTra, @HanhKhachKhoa, 'SG001', 'ECONOMY', 1100000, 200000, 'ISSUED'),
(@DonChoTra, @HanhKhachAn, 'SG002', 'BUSINESS', 2000000, 200000, 'RESERVED'),
(@DonHetHan, @HanhKhachQuan, 'SG004', 'ECONOMY', 1000000, 200000, 'CANCELLED');

INSERT INTO VE_CHUYEN_BAY
(MaDonDatVe, MaHanhKhach, MaChuyenBay, HangVe, GiaCoBanChot, ThuePhiChot, TrangThai)
VALUES (@DonVangLai, @HanhKhachLan, 'SG003', 'ECONOMY', 800000, 200000, 'ISSUED');
DECLARE @VeLan BIGINT = SCOPE_IDENTITY();

INSERT INTO VE_CHUYEN_BAY
(MaDonDatVe, MaHanhKhach, MaChuyenBay, HangVe, GiaCoBanChot, ThuePhiChot, TrangThai)
VALUES (@DonVangLai, @HanhKhachHuy, 'SG003', 'ECONOMY', 800000, 200000, 'ISSUED');

-- 12. THANH TOAN
-- Don AB12CD co 1 lan that bai, sau do 1 lan thanh cong.
INSERT INTO GIAO_DICH_TT
(MaDonDatVe, SoTien, PhuongThucTT, TrangThaiTT, ThoiGianTao, ThoiGianTT, MaThamChieu)
VALUES
(@DonDaTra, 2600000, 'DEMO', 'FAILED', DATEADD(MINUTE, 5, DATEADD(DAY, -1, @HienTai)),
 DATEADD(MINUTE, 6, DATEADD(DAY, -1, @HienTai)), 'DEMO-AB12CD-FAIL'),
(@DonDaTra, 2600000, 'DEMO', 'SUCCESS', DATEADD(MINUTE, 10, DATEADD(DAY, -1, @HienTai)),
 DATEADD(MINUTE, 11, DATEADD(DAY, -1, @HienTai)), 'DEMO-AB12CD-OK'),
(@DonChoTra, 2200000, 'DEMO', 'PENDING', @HienTai, NULL, NULL),
(@DonVangLai, 2000000, 'DEMO', 'SUCCESS', DATEADD(MINUTE, -115, @HienTai),
 DATEADD(MINUTE, -114, @HienTai), 'DEMO-JK56LM-OK');

-- 13. CHECK-IN MAU
DECLARE @GheLan BIGINT;
SELECT @GheLan = MaGhe
FROM GHE_CHUYEN_BAY
WHERE MaChuyenBay = 'SG003' AND SoGhe = '12A';

INSERT INTO CHECK_IN (MaVe, MaGhe, ThoiGian, TrangThai, MaQR_BP, MaTK)
VALUES (@VeLan, @GheLan, @HienTai, 'CHECKED_IN', 'DEMO-BP-JK56LM-LAN', NULL);

COMMIT TRANSACTION;

-- 14. KIEM TRA KET QUA
-- NgayTimVietNam la ngay nhap tren giao dien neu chon mui gio Viet Nam.
SELECT MaChuyenBay, MaSanBayDi, MaSanBayDen, TrangThai,
       GioCatCanh AS GioCatCanhUTC,
       DATEADD(HOUR, 7, GioCatCanh) AS GioCatCanhVietNam,
       CONVERT(DATE, DATEADD(HOUR, 7, GioCatCanh)) AS NgayTimVietNam
FROM CHUYEN_BAY
ORDER BY GioCatCanh;

-- TongTien phai bang TongGiaVe; du lieu mau khong co don rong.
SELECT d.MaPNR, d.TrangThai, d.TongTien, SUM(v.GiaVeChot) AS TongGiaVe,
       COUNT(v.MaVe) AS SoVe
FROM DON_DAT_VE d JOIN VE_CHUYEN_BAY v ON d.MaDonDatVe = v.MaDonDatVe
GROUP BY d.MaPNR, d.TrangThai, d.TongTien
ORDER BY d.MaPNR;

-- Ket qua mong doi: 4600000; khong cong lan FAILED/PENDING.
SELECT SUM(SoTien) AS DoanhThuMau
FROM GIAO_DICH_TT
WHERE TrangThaiTT = 'SUCCESS';

-- So dong mong doi: 4, 3, 4, 6, 6, 12, 48, 4, 6, 4, 1.
SELECT 'SAN_BAY' AS TenBang, COUNT(*) AS SoDong FROM SAN_BAY
UNION ALL
SELECT 'KHACH_HANG' AS TenBang, COUNT(*) AS SoDong FROM KHACH_HANG
UNION ALL
SELECT 'TAI_KHOAN_ND' AS TenBang, COUNT(*) AS SoDong FROM TAI_KHOAN_ND
UNION ALL
SELECT 'HANH_KHACH' AS TenBang, COUNT(*) AS SoDong FROM HANH_KHACH
UNION ALL
SELECT 'CHUYEN_BAY' AS TenBang, COUNT(*) AS SoDong FROM CHUYEN_BAY
UNION ALL
SELECT 'HANG_VE_CHUYEN_BAY' AS TenBang, COUNT(*) AS SoDong FROM HANG_VE_CHUYEN_BAY
UNION ALL
SELECT 'GHE_CHUYEN_BAY' AS TenBang, COUNT(*) AS SoDong FROM GHE_CHUYEN_BAY
UNION ALL
SELECT 'DON_DAT_VE' AS TenBang, COUNT(*) AS SoDong FROM DON_DAT_VE
UNION ALL
SELECT 'VE_CHUYEN_BAY' AS TenBang, COUNT(*) AS SoDong FROM VE_CHUYEN_BAY
UNION ALL
SELECT 'GIAO_DICH_TT' AS TenBang, COUNT(*) AS SoDong FROM GIAO_DICH_TT
UNION ALL
SELECT 'CHECK_IN' AS TenBang, COUNT(*) AS SoDong FROM CHECK_IN;
