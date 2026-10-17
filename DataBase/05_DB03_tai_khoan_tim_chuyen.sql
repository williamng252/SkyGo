USE SkyGo_Cnpm;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
GO

-- Thu tuc noi bo: khoa chung cho cac thao tac GHI nghiep vu.
-- Phai goi ben trong BEGIN TRANSACTION; COMMIT/ROLLBACK tu giai phong khoa.
-- Quy mo do an nho: doi toi da 10 giay; ung dung bao thu lai neu het thoi gian.
CREATE OR ALTER PROCEDURE dbo.usp_KhoaNghiepVu
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @KetQua INT;
    EXEC @KetQua = sys.sp_getapplock
        @Resource = N'SkyGo_NghiepVu', @LockMode = 'Exclusive',
        @LockOwner = 'Transaction', @LockTimeout = 10000;
    IF @KetQua < 0
        THROW 50001, N'He thong dang ban. Hay thu lai.', 1;
END;
GO

-- Dang ky: Java bam BCrypt truoc, SQL khong nhan mat khau goc.
CREATE OR ALTER PROCEDURE dbo.usp_DangKy
    @TenDangNhap VARCHAR(50), @Email VARCHAR(254), @MatKhauHash VARCHAR(255),
    @HoTen NVARCHAR(100), @SDT VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SET @TenDangNhap = LTRIM(RTRIM(@TenDangNhap));
    SET @Email = LOWER(LTRIM(RTRIM(@Email)));
    SET @HoTen = LTRIM(RTRIM(@HoTen));
    IF @TenDangNhap IS NULL OR LEN(@TenDangNhap) < 3
       OR @HoTen IS NULL OR LEN(@HoTen) = 0
       OR @Email IS NULL OR @Email NOT LIKE '%_@_%._%'
        THROW 50002, N'Thong tin dang ky khong hop le.', 1;
    IF @MatKhauHash IS NULL OR LEN(@MatKhauHash) <> 60
       OR LEFT(@MatKhauHash,4) NOT IN ('$2a$','$2b$','$2y$')
        THROW 50002, N'Java phai truyen BCrypt hash hop le, khong truyen mat khau goc.', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC dbo.usp_KhoaNghiepVu;
        IF EXISTS (SELECT 1 FROM dbo.TAI_KHOAN_ND
                   WHERE TenDangNhap = @TenDangNhap OR Email = @Email)
            THROW 50003, N'Ten dang nhap hoac email da ton tai.', 1;
        INSERT INTO dbo.KHACH_HANG(HoTen,SDT,Email) VALUES(@HoTen,@SDT,@Email);
        DECLARE @MaKhachHang BIGINT = SCOPE_IDENTITY();
        INSERT INTO dbo.TAI_KHOAN_ND
            (TenDangNhap,Email,MatKhauHash,VaiTro,MaKhachHang)
        VALUES(@TenDangNhap,@Email,@MatKhauHash,'CUSTOMER',@MaKhachHang);
        DECLARE @MaTK BIGINT = SCOPE_IDENTITY();
        COMMIT TRANSACTION;
        SELECT @MaTK AS MaTK, @MaKhachHang AS MaKhachHang;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- Chi backend doc hash de so khop BCrypt. Khong tra hash cho trinh duyet.
-- Cho phep dang nhap bang ten dang nhap hoac email.
CREATE OR ALTER PROCEDURE dbo.usp_LayTaiKhoanDangNhap
    @TenDangNhap VARCHAR(254)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT MaTK, TenDangNhap, Email, MatKhauHash, VaiTro, TrangThai, MaKhachHang
    FROM dbo.TAI_KHOAN_ND
    WHERE TenDangNhap = LTRIM(RTRIM(@TenDangNhap))
       OR Email = LOWER(LTRIM(RTRIM(@TenDangNhap)));
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_DoiMatKhau
    @MaTK BIGINT, @MatKhauHash VARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @MatKhauHash IS NULL OR LEN(@MatKhauHash) <> 60
       OR LEFT(@MatKhauHash,4) NOT IN ('$2a$','$2b$','$2y$')
        THROW 50002, N'BCrypt hash khong hop le.', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC dbo.usp_KhoaNghiepVu;
        UPDATE dbo.TAI_KHOAN_ND SET MatKhauHash = @MatKhauHash WHERE MaTK = @MaTK;
        IF @@ROWCOUNT = 0 THROW 50004, N'Tai khoan khong ton tai.', 1;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_LayHoSoKhachHang @MaKhachHang BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT MaKhachHang, HoTen, SDT, Email FROM dbo.KHACH_HANG
    WHERE MaKhachHang = @MaKhachHang;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CapNhatHoSoKhachHang
    @MaKhachHang BIGINT, @HoTen NVARCHAR(100), @SDT VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SET @HoTen = LTRIM(RTRIM(@HoTen));
    IF @HoTen IS NULL OR LEN(@HoTen) = 0
        THROW 50002, N'Ho ten khong duoc rong.', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC dbo.usp_KhoaNghiepVu;
        UPDATE dbo.KHACH_HANG SET HoTen = @HoTen, SDT = @SDT
        WHERE MaKhachHang = @MaKhachHang;
        IF @@ROWCOUNT = 0 THROW 50004, N'Khach hang khong ton tai.', 1;
        COMMIT TRANSACTION;
        SELECT MaKhachHang, HoTen, SDT FROM dbo.KHACH_HANG
        WHERE MaKhachHang = @MaKhachHang;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_LayDanhSachSanBay
AS
BEGIN
    SET NOCOUNT ON;
    SELECT MaSanBay, TenSanBay, ThanhPho, QuocGia
    FROM dbo.SAN_BAY WHERE TrangThai = 1 ORDER BY ThanhPho, MaSanBay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_TimChuyenBay
    @MaSanBayDi CHAR(3), @MaSanBayDen CHAR(3), @NgayDi DATE, @SoHanhKhach INT
AS
BEGIN
    SET NOCOUNT ON;
    IF @NgayDi IS NULL OR @NgayDi < '20000101' OR @NgayDi > '21000101'
       OR @SoHanhKhach IS NULL OR @SoHanhKhach NOT BETWEEN 1 AND 9
       OR @MaSanBayDi IS NULL OR @MaSanBayDen IS NULL OR @MaSanBayDi = @MaSanBayDen
        THROW 50002, N'Dieu kien tim chuyen khong hop le; moi don toi da 9 khach.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.SAN_BAY WHERE MaSanBay = @MaSanBayDi AND TrangThai = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.SAN_BAY WHERE MaSanBay = @MaSanBayDen AND TrangThai = 1)
        THROW 50002, N'San bay khong hop le.', 1;
    DECLARE @HienTai DATETIME2 = SYSUTCDATETIME();
    DECLARE @TuGio DATETIME2 = DATEADD(HOUR,-7,CONVERT(DATETIME2,@NgayDi));
    DECLARE @DenGio DATETIME2 = DATEADD(DAY,1,@TuGio);
    SELECT cb.MaChuyenBay, cb.SoHieuChuyen, cb.MaSanBayDi, cb.MaSanBayDen,
           cb.GioCatCanh, cb.GioDenDuKien, cb.TrangThai AS TrangThaiChuyenBay,
           hv.HangVe, hv.GiaCoBan, hv.ThuePhi,
           CONVERT(DECIMAL(18,2),hv.GiaCoBan+hv.ThuePhi) AS GiaVe,
           dbo.fn_SoChoCon(cb.MaChuyenBay,hv.HangVe,@HienTai) AS SoChoCon
    FROM dbo.CHUYEN_BAY cb
    JOIN dbo.HANG_VE_CHUYEN_BAY hv ON hv.MaChuyenBay = cb.MaChuyenBay
    WHERE cb.MaSanBayDi = @MaSanBayDi AND cb.MaSanBayDen = @MaSanBayDen
      AND cb.GioCatCanh >= @TuGio AND cb.GioCatCanh < @DenGio
      AND cb.GioCatCanh > @HienTai AND cb.TrangThai IN ('SCHEDULED','DELAYED')
      AND hv.TrangThai = 1
      AND dbo.fn_SoChoCon(cb.MaChuyenBay,hv.HangVe,@HienTai) >= @SoHanhKhach
    ORDER BY cb.GioCatCanh,hv.GiaCoBan+hv.ThuePhi;
END;
GO
