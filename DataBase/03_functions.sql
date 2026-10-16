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

-- SQL-H02 tham khao: tong gia da chot cua cac ve trong don.
CREATE OR ALTER FUNCTION dbo.fn_TinhTongTienDon(@MaDonDatVe BIGINT)
RETURNS DECIMAL(18,2)
AS
BEGIN
    DECLARE @TongTien DECIMAL(18,2);
    SELECT @TongTien = SUM(GiaVeChot)
    FROM dbo.VE_CHUYEN_BAY
    WHERE MaDonDatVe = @MaDonDatVe;
    RETURN ISNULL(@TongTien, 0);
END;
GO

-- Dem cho con ban, KHONG tru them mot lan vi ve da check-in.
-- @LucTinh giup ca mot yeu cau dung chung mot moc thoi gian.
CREATE OR ALTER FUNCTION dbo.fn_SoChoCon
(@MaChuyenBay VARCHAR(20), @HangVe VARCHAR(10), @LucTinh DATETIME2)
RETURNS INT
AS
BEGIN
    DECLARE @TongGhe INT, @ChoDaBan INT;
    SELECT @TongGhe = COUNT(*)
    FROM dbo.GHE_CHUYEN_BAY
    WHERE MaChuyenBay = @MaChuyenBay AND HangVe = @HangVe;

    SELECT @ChoDaBan = COUNT(*)
    FROM dbo.VE_CHUYEN_BAY v
    JOIN dbo.DON_DAT_VE d ON d.MaDonDatVe = v.MaDonDatVe
    WHERE v.MaChuyenBay = @MaChuyenBay AND v.HangVe = @HangVe
      AND ((v.TrangThai IN ('ISSUED','USED') AND d.TrangThai = 'PAID')
        OR (v.TrangThai = 'RESERVED' AND d.TrangThai = 'PENDING'
            AND d.HanThanhToan > @LucTinh));
    RETURN @TongGhe - @ChoDaBan;
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_DanhSachGheKhaDung(@MaVe BIGINT)
RETURNS TABLE
AS
RETURN
(
    SELECT g.MaGhe, g.SoGhe, g.HangVe
    FROM dbo.VE_CHUYEN_BAY v
    JOIN dbo.GHE_CHUYEN_BAY g
      ON g.MaChuyenBay = v.MaChuyenBay AND g.HangVe = v.HangVe
    WHERE v.MaVe = @MaVe
      AND NOT EXISTS
      (SELECT 1 FROM dbo.CHECK_IN c
       WHERE c.MaGhe = g.MaGhe AND c.TrangThai = 'CHECKED_IN')
);
GO
