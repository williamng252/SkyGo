/*
  Chạy file này SAU 01_schemal.sql và 02_seed.sql.
  Các object giúp kiểm thử API; backend vẫn dùng PreparedStatement/JdbcTemplate
  (tham số hóa) cho các transaction ghi nhiều bảng.
*/
USE SkyGo_Cnpm;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER FUNCTION dbo.fn_TinhTongTienDon(@MaDonDatVe BIGINT)
RETURNS DECIMAL(18,2)
AS
BEGIN
    RETURN CONVERT(DECIMAL(18,2), ISNULL((SELECT SUM(GiaVeChot) FROM dbo.VE_CHUYEN_BAY WHERE MaDonDatVe=@MaDonDatVe),0));
END;
GO

CREATE OR ALTER VIEW dbo.vw_ChiTietVe
AS
SELECT v.MaVe,v.MaDonDatVe,d.MaPNR,v.MaHanhKhach,h.HoTen AS HoTenHanhKhach,
       v.MaChuyenBay,cb.SoHieuChuyen,cb.GioCatCanh,cb.MaSanBayDi,cb.MaSanBayDen,
       v.HangVe,v.GiaVeChot,v.TrangThai AS TrangThaiVe
FROM dbo.VE_CHUYEN_BAY v
JOIN dbo.DON_DAT_VE d ON d.MaDonDatVe=v.MaDonDatVe
JOIN dbo.HANH_KHACH h ON h.MaHanhKhach=v.MaHanhKhach
JOIN dbo.CHUYEN_BAY cb ON cb.MaChuyenBay=v.MaChuyenBay;
GO

CREATE OR ALTER PROCEDURE dbo.usp_LayLichSuDatVe
    @MaKhachHang BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT MaDonDatVe,MaPNR,NgayDat,TongTien,TrangThai
    FROM dbo.DON_DAT_VE WHERE MaKhachHang=@MaKhachHang
    ORDER BY NgayDat DESC,MaDonDatVe DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_TimChuyenBay
    @MaSanBayDi CHAR(3), @MaSanBayDen CHAR(3), @NgayBay DATE, @SoHanhKhach INT=1
AS
BEGIN
    SET NOCOUNT ON;
    SELECT cb.MaChuyenBay,cb.SoHieuChuyen,cb.GioCatCanh,cb.GioDenDuKien,
           cb.MaSanBayDi,cb.MaSanBayDen,MIN(hv.GiaCoBan+hv.ThuePhi) AS GiaTu,
           COUNT(DISTINCT g.MaGhe)-COUNT(DISTINCT v.MaVe) AS SoChoCon
    FROM dbo.CHUYEN_BAY cb
    JOIN dbo.HANG_VE_CHUYEN_BAY hv ON hv.MaChuyenBay=cb.MaChuyenBay AND hv.TrangThai=1
    JOIN dbo.GHE_CHUYEN_BAY g ON g.MaChuyenBay=hv.MaChuyenBay AND g.HangVe=hv.HangVe
    LEFT JOIN dbo.VE_CHUYEN_BAY v ON v.MaChuyenBay=g.MaChuyenBay AND v.HangVe=g.HangVe AND v.TrangThai IN ('RESERVED','ISSUED','USED')
    WHERE cb.MaSanBayDi=@MaSanBayDi AND cb.MaSanBayDen=@MaSanBayDen
      AND CAST(cb.GioCatCanh AS DATE)=@NgayBay AND cb.TrangThai IN ('SCHEDULED','DELAYED')
    GROUP BY cb.MaChuyenBay,cb.SoHieuChuyen,cb.GioCatCanh,cb.GioDenDuKien,cb.MaSanBayDi,cb.MaSanBayDen
    HAVING COUNT(DISTINCT g.MaGhe)-COUNT(DISTINCT v.MaVe)>=@SoHanhKhach
    ORDER BY cb.GioCatCanh;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_CHUYEN_BAY_TimKiem' AND object_id = OBJECT_ID('dbo.CHUYEN_BAY'))
    CREATE INDEX IX_CHUYEN_BAY_TimKiem ON dbo.CHUYEN_BAY(MaSanBayDi,MaSanBayDen,GioCatCanh) INCLUDE(TrangThai,SoHieuChuyen,GioDenDuKien);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_VE_DON' AND object_id = OBJECT_ID('dbo.VE_CHUYEN_BAY'))
    CREATE INDEX IX_VE_DON ON dbo.VE_CHUYEN_BAY(MaDonDatVe,MaChuyenBay,HangVe) INCLUDE(MaHanhKhach,TrangThai,GiaVeChot);
GO
