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

CREATE OR ALTER PROCEDURE dbo.usp_LayGheKhaDung @MaVe BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.VE_CHUYEN_BAY WHERE MaVe=@MaVe)
        THROW 50004, N'Ve khong ton tai.', 1;
    SELECT MaGhe,SoGhe,HangVe FROM dbo.fn_DanhSachGheKhaDung(@MaVe)
    ORDER BY LEN(SoGhe),SoGhe;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CheckIn
    @MaVe BIGINT, @MaGhe BIGINT, @MaTK BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC dbo.usp_KhoaNghiepVu;
        DECLARE @HienTai DATETIME2=SYSUTCDATETIME();
        DECLARE @MaChuyenBay VARCHAR(20), @HangVe VARCHAR(10), @TrangThaiVe VARCHAR(10),
                @TrangThaiDon VARCHAR(10), @TrangThaiCB VARCHAR(12), @Mo DATETIME2, @Dong DATETIME2,
                @KhachCuaDon BIGINT;
        SELECT @MaChuyenBay=v.MaChuyenBay,@HangVe=v.HangVe,@TrangThaiVe=v.TrangThai,
               @TrangThaiDon=d.TrangThai,@TrangThaiCB=cb.TrangThai,
               @Mo=cb.MoCheckInLuc,@Dong=cb.DongCheckInLuc,@KhachCuaDon=d.MaKhachHang
        FROM dbo.VE_CHUYEN_BAY v
        JOIN dbo.DON_DAT_VE d ON d.MaDonDatVe=v.MaDonDatVe
        JOIN dbo.CHUYEN_BAY cb ON cb.MaChuyenBay=v.MaChuyenBay
        WHERE v.MaVe=@MaVe;
        IF @MaChuyenBay IS NULL THROW 50004, N'Ve khong ton tai.', 1;
        IF @MaTK IS NOT NULL
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.TAI_KHOAN_ND WHERE MaTK=@MaTK AND TrangThai=1)
                THROW 50020, N'Tai khoan khong hop le.', 1;
            IF @KhachCuaDon IS NOT NULL AND EXISTS
            (SELECT 1 FROM dbo.TAI_KHOAN_ND
             WHERE MaTK=@MaTK AND VaiTro='CUSTOMER' AND MaKhachHang<>@KhachCuaDon)
                THROW 50020, N'Tai khoan khong so huu don.', 1;
        END;
        IF @TrangThaiVe<>'ISSUED' OR @TrangThaiDon<>'PAID'
            THROW 50021, N'Chi check-in ve da phat hanh cua don da thanh toan.', 1;
        IF @TrangThaiCB NOT IN ('SCHEDULED','DELAYED') OR @HienTai<@Mo OR @HienTai>=@Dong
            THROW 50022, N'Chuyen bay khong trong thoi gian cho phep check-in.', 1;
        IF EXISTS (SELECT 1 FROM dbo.CHECK_IN WHERE MaVe=@MaVe AND TrangThai='CHECKED_IN')
            THROW 50023, N'Ve da check-in. Hay xem lai the len may bay.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.GHE_CHUYEN_BAY
                       WHERE MaGhe=@MaGhe AND MaChuyenBay=@MaChuyenBay AND HangVe=@HangVe)
            THROW 50024, N'Ghe khong cung chuyen bay hoac hang ve.', 1;
        IF EXISTS (SELECT 1 FROM dbo.CHECK_IN WHERE MaGhe=@MaGhe AND TrangThai='CHECKED_IN')
            THROW 50025, N'Ghe da duoc chon. Hay chon ghe khac.', 1;
        DECLARE @MaQR VARCHAR(100)=CONVERT(VARCHAR(64),CRYPT_GEN_RANDOM(32),2);
        INSERT INTO dbo.CHECK_IN(MaVe,MaGhe,ThoiGian,TrangThai,MaQR_BP,MaTK)
        VALUES(@MaVe,@MaGhe,@HienTai,'CHECKED_IN',@MaQR,@MaTK);
        DECLARE @MaCheckIn BIGINT=SCOPE_IDENTITY();
        COMMIT TRANSACTION;
        SELECT c.MaCheckIn,c.MaVe,g.SoGhe,c.ThoiGian,c.MaQR_BP
        FROM dbo.CHECK_IN c JOIN dbo.GHE_CHUYEN_BAY g ON g.MaGhe=c.MaGhe
        WHERE c.MaCheckIn=@MaCheckIn;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_LayTheLenMayBay @MaVe BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT MaVe,MaPNR,HoTenHanhKhach,SoHieuChuyen,MaSanBayDi,MaSanBayDen,
           GioCatCanh,SoGhe,HangVe,MaQR_BP
    FROM dbo.vw_ChiTietVe
    WHERE MaVe=@MaVe AND DaCheckIn=1 AND TrangThaiDon='PAID'
      AND TrangThaiVe IN ('ISSUED','USED') AND TrangThaiChuyenBay<>'CANCELLED';
END;
GO
