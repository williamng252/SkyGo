/* 
   SKYGO - SQL-H01, SQL-H02, SQL-H03
   Dua tren schema 01 va seed DB-02 cua du an SkyGo_Cnpm.
   Yeu cau: da chay schema va seed thanh cong truoc khi chay file nay.
   Nen chay tren SQL Server 2016 SP1 tro len (CREATE OR ALTER).
*/

USE SkyGo_Cnpm;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
   SQL-H01 - STORED PROCEDURE: LICH SU DAT VE CUA KHACH HANG
   Bang dung theo schema: dbo.DON_DAT_VE
   MaKhachHang co kieu BIGINT.
*/
CREATE OR ALTER PROCEDURE dbo.usp_LayLichSuDatVe
    @MaKhachHang BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ddv.MaDonDatVe,
        ddv.MaPNR,
        ddv.NgayDat,
        ddv.TongTien,
        ddv.TrangThai
    FROM dbo.DON_DAT_VE AS ddv
    WHERE ddv.MaKhachHang = @MaKhachHang
    ORDER BY
        ddv.NgayDat DESC,
        ddv.MaDonDatVe DESC;
END;
GO

/* ----------------------- KIEM THU SQL-H01 -----------------------
   Seed DB-02 tao cac khach hang qua email, khong nen gia dinh IDENTITY
   luc nao cung bat dau tu 1. Do do, lay MaKhachHang theo email demo.
   Ket qua mong doi voi seed hien tai:
   - quan@example.com: 2 don (AB12CD va NP78QR).
   - an@example.com: 1 don (EF34GH).
   - binh@example.com: khong co don, danh sach rong.
*/
DECLARE @MaKhachQuan BIGINT;
DECLARE @MaKhachAn BIGINT;
DECLARE @MaKhachBinh BIGINT;

SELECT @MaKhachQuan = MaKhachHang
FROM dbo.KHACH_HANG
WHERE Email = 'quan@example.com';

SELECT @MaKhachAn = MaKhachHang
FROM dbo.KHACH_HANG
WHERE Email = 'an@example.com';

SELECT @MaKhachBinh = MaKhachHang
FROM dbo.KHACH_HANG
WHERE Email = 'binh@example.com';

IF @MaKhachQuan IS NULL OR @MaKhachAn IS NULL OR @MaKhachBinh IS NULL
    THROW 51001, N'Khong tim thay du lieu khach hang seed. Hay chay DB-02 seed truoc.', 1;

PRINT N'SQL-H01 - Lich su cua Nguyen Anh Quan';
EXEC dbo.usp_LayLichSuDatVe @MaKhachHang = @MaKhachQuan;

PRINT N'SQL-H01 - Lich su cua Tran Minh An (chi duoc thay don cua An)';
EXEC dbo.usp_LayLichSuDatVe @MaKhachHang = @MaKhachAn;

PRINT N'SQL-H01 - Khach hang Le Bao Binh khong co don: ket qua phai rong';
EXEC dbo.usp_LayLichSuDatVe @MaKhachHang = @MaKhachBinh;

PRINT N'SQL-H01 - Ma khach hang khong ton tai: ket qua phai rong';
EXEC dbo.usp_LayLichSuDatVe @MaKhachHang = -1;
GO

/*
   SQL-H02 - FUNCTION: TINH TONG GIA VE DA CHOT CUA DON
   GiaVeChot la computed column trong dbo.VE_CHUYEN_BAY.
   Khong lay gia hien tai tu HANG_VE_CHUYEN_BAY.
*/
CREATE OR ALTER FUNCTION dbo.fn_TinhTongTienDon
(
    @MaDonDatVe BIGINT
)
RETURNS DECIMAL(18,2)
AS
BEGIN
    DECLARE @TongTien DECIMAL(38,2);

    SELECT @TongTien = SUM(CONVERT(DECIMAL(38,2), v.GiaVeChot))
    FROM dbo.VE_CHUYEN_BAY AS v
    WHERE v.MaDonDatVe = @MaDonDatVe;

    -- SUM tra NULL neu don khong co ve hoac ma don khong co ve.
    RETURN CONVERT(DECIMAL(18,2), COALESCE(@TongTien, 0));
END;
GO

/* ----------------------- KIEM THU SQL-H02 -----------------------
   Gia tri du kien theo DB-02 seed:
   AB12CD = 2,600,000 (2 ve); EF34GH = 2,200,000 (1 ve);
   JK56LM = 2,000,000 (2 ve); NP78QR = 1,200,000 (1 ve bi huy).
   Ham cong tat ca ve trong don theo yeu cau, khong loc TrangThai ve.
*/
SELECT
    ddv.MaPNR,
    ddv.MaDonDatVe,
    COUNT(v.MaVe) AS SoVe,
    COALESCE(SUM(v.GiaVeChot), 0) AS TongGiaVeDoiChieu,
    dbo.fn_TinhTongTienDon(ddv.MaDonDatVe) AS TongTienTuFunction,
    ddv.TongTien AS TongTienLuuTrongDon
FROM dbo.DON_DAT_VE AS ddv
LEFT JOIN dbo.VE_CHUYEN_BAY AS v
    ON v.MaDonDatVe = ddv.MaDonDatVe
GROUP BY ddv.MaPNR, ddv.MaDonDatVe, ddv.TongTien
ORDER BY ddv.MaPNR;
GO

-- Kiem tra ma don khong ton tai: function phai tra 0.
SELECT dbo.fn_TinhTongTienDon(-1) AS TongTienDonKhongTonTai;
GO

/* Kiem tra don khong co ve bang du lieu tam.
   Transaction duoc ROLLBACK de khong de lai du lieu test trong database.
   PNR test duoc tao tu GUID, gom 6 ky tu A-F/0-9, phu hop CHECK constraint.
*/
BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @MaKhachTest BIGINT;
    DECLARE @MaDonRong BIGINT;
    DECLARE @NgayDatTest DATETIME2 = SYSUTCDATETIME();
    DECLARE @PNRTest CHAR(6) = LEFT(UPPER(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', '')), 6);

    SELECT @MaKhachTest = MaKhachHang
    FROM dbo.KHACH_HANG
    WHERE Email = 'quan@example.com';

    IF @MaKhachTest IS NULL
        THROW 51002, N'Khong tim thay khach hang seed de tao don test.', 1;

    INSERT INTO dbo.DON_DAT_VE
    (
        MaPNR, NgayDat, HanThanhToan, HoTenLienHe,
        EmailLienHe, SDTLienHe, TongTien, TrangThai, MaKhachHang
    )
    VALUES
    (
        @PNRTest, @NgayDatTest, DATEADD(MINUTE, 30, @NgayDatTest),
        N'Don kiem thu khong co ve', 'quan@example.com', '0900000001',
        1.00, 'PENDING', @MaKhachTest
    );

    SET @MaDonRong = CONVERT(BIGINT, SCOPE_IDENTITY());

    SELECT
        @PNRTest AS PNRDonRongTest,
        dbo.fn_TinhTongTienDon(@MaDonRong) AS TongTienMongDoiBang0;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/*
   SQL-H03 - VIEW CHI TIET VE
   HangVe duoc noi bang ca MaChuyenBay va HangVe theo khoa ghep
   PK_HANG_VE_CHUYEN_BAY(MaChuyenBay, HangVe).
*/
CREATE OR ALTER VIEW dbo.vw_ChiTietVe
AS
    SELECT
        v.MaVe,
        v.MaDonDatVe,
        ddv.MaPNR,
        hk.MaHanhKhach,
        hk.HoTen AS HoTenHanhKhach,
        cb.MaChuyenBay,
        cb.SoHieuChuyen,
        cb.GioCatCanh,
        cb.MaSanBayDi,
        cb.MaSanBayDen,
        hv.HangVe AS HangVe,
        v.GiaVeChot,
        v.TrangThai AS TrangThaiVe
    FROM dbo.VE_CHUYEN_BAY AS v
    INNER JOIN dbo.DON_DAT_VE AS ddv
        ON ddv.MaDonDatVe = v.MaDonDatVe
    INNER JOIN dbo.HANH_KHACH AS hk
        ON hk.MaHanhKhach = v.MaHanhKhach
    INNER JOIN dbo.CHUYEN_BAY AS cb
        ON cb.MaChuyenBay = v.MaChuyenBay
    INNER JOIN dbo.HANG_VE_CHUYEN_BAY AS hv
        ON hv.MaChuyenBay = v.MaChuyenBay
       AND hv.HangVe = v.HangVe;
GO

/* ----------------------- KIEM THU SQL-H03 ----------------------- */
-- Xem cac ve trong du lieu seed, bao gom don nhieu hanh khach.
SELECT
    MaVe, MaDonDatVe, MaPNR, MaHanhKhach, HoTenHanhKhach,
    MaChuyenBay, SoHieuChuyen, GioCatCanh, MaSanBayDi,
    MaSanBayDen, HangVe, GiaVeChot, TrangThaiVe
FROM dbo.vw_ChiTietVe
ORDER BY MaDonDatVe, MaVe;
GO

-- So dong view phai bang so ve trong bang goc (seed hien tai: 6 ve).
SELECT
    (SELECT COUNT_BIG(*) FROM dbo.VE_CHUYEN_BAY) AS SoDongBangVe,
    (SELECT COUNT_BIG(*) FROM dbo.vw_ChiTietVe) AS SoDongViewChiTietVe;
GO

-- Tim ve trong bang goc bi thieu khoi view; ket qua mong doi: 0 dong.
SELECT v.MaVe AS VeBiThieuKhoiView
FROM dbo.VE_CHUYEN_BAY AS v
LEFT JOIN dbo.vw_ChiTietVe AS ct
    ON ct.MaVe = v.MaVe
WHERE ct.MaVe IS NULL;
GO

-- Tim mot MaVe bi nhan thanh nhieu dong; ket qua mong doi: 0 dong.
SELECT MaVe, COUNT_BIG(*) AS SoDong
FROM dbo.vw_ChiTietVe
GROUP BY MaVe
HAVING COUNT_BIG(*) > 1;
GO

-- Xem cac hanh khach co ve tren hon mot chuyen (seed co the khong co truong hop nay).
SELECT
    MaHanhKhach,
    HoTenHanhKhach,
    COUNT(DISTINCT MaChuyenBay) AS SoChuyenBay
FROM dbo.vw_ChiTietVe
GROUP BY MaHanhKhach, HoTenHanhKhach
HAVING COUNT(DISTINCT MaChuyenBay) > 1;
GO

/* Test view voi cung mot hanh khach tren hai chuyen khac nhau.
   Don va ve test duoc rollback; khong giu lai du lieu kiem thu.
*/
BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @MaKhachQuanView BIGINT;
    DECLARE @MaHanhKhachTest BIGINT;
    DECLARE @MaDonViewTest BIGINT;
    DECLARE @NgayDatViewTest DATETIME2 = SYSUTCDATETIME();
    DECLARE @PNRViewTest CHAR(6) = LEFT(UPPER(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', '')), 6);
    DECLARE @TongTienViewTest DECIMAL(18,2);

    SELECT @MaKhachQuanView = MaKhachHang
    FROM dbo.KHACH_HANG
    WHERE Email = 'quan@example.com';

    SELECT @MaHanhKhachTest = MaHanhKhach
    FROM dbo.HANH_KHACH
    WHERE SoGiayTo = '000000000101'; -- Nguyen Thi Mai trong seed

    IF @MaKhachQuanView IS NULL OR @MaHanhKhachTest IS NULL
        THROW 51003, N'Khong tim thay khach/hanh khach seed de kiem thu view.', 1;

    SELECT @TongTienViewTest = SUM(GiaCoBan + ThuePhi)
    FROM dbo.HANG_VE_CHUYEN_BAY
    WHERE (MaChuyenBay = 'SG001' AND HangVe = 'ECONOMY')
       OR (MaChuyenBay = 'SG002' AND HangVe = 'ECONOMY');

    IF @TongTienViewTest IS NULL
        THROW 51004, N'Thieu hang ve SG001/SG002 trong seed de kiem thu view.', 1;

    INSERT INTO dbo.DON_DAT_VE
    (
        MaPNR, NgayDat, HanThanhToan, HoTenLienHe,
        EmailLienHe, SDTLienHe, TongTien, TrangThai, MaKhachHang
    )
    VALUES
    (
        @PNRViewTest, @NgayDatViewTest, DATEADD(MINUTE, 30, @NgayDatViewTest),
        N'Don kiem thu view', 'quan@example.com', '0900000001',
        @TongTienViewTest, 'PENDING', @MaKhachQuanView
    );

    SET @MaDonViewTest = CONVERT(BIGINT, SCOPE_IDENTITY());

    INSERT INTO dbo.VE_CHUYEN_BAY
    (
        MaDonDatVe, MaHanhKhach, MaChuyenBay, HangVe,
        GiaCoBanChot, ThuePhiChot, TrangThai
    )
    SELECT
        @MaDonViewTest,
        @MaHanhKhachTest,
        hv.MaChuyenBay,
        hv.HangVe,
        hv.GiaCoBan,
        hv.ThuePhi,
        'RESERVED'
    FROM dbo.HANG_VE_CHUYEN_BAY AS hv
    WHERE (hv.MaChuyenBay = 'SG001' AND hv.HangVe = 'ECONOMY')
       OR (hv.MaChuyenBay = 'SG002' AND hv.HangVe = 'ECONOMY');

    SELECT
        MaVe, MaPNR, MaHanhKhach, HoTenHanhKhach,
        MaChuyenBay, HangVe, GiaVeChot, TrangThaiVe
    FROM dbo.vw_ChiTietVe
    WHERE MaDonDatVe = @MaDonViewTest
    ORDER BY MaChuyenBay;
    -- Mong doi: 2 dong, cung hanh khach, hai MaChuyenBay khac nhau.

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* GHI CHU NGHIEM VU
   - View ghep theo khoa; khong phai co che phan quyen theo khach hang.
   - Backend/SP phai kiem tra nguoi dang dang nhap co quyen xem don nao.
   - Dung MaKhachHang lay tu phien dang nhap da xac thuc; khong tin ID tu UI.
*/
