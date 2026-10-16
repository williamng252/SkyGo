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

-- SQL-H03 tham khao: moi ve mot dong, chi noi check-in con hieu luc.
CREATE OR ALTER VIEW dbo.vw_ChiTietVe
AS
SELECT v.MaVe, v.MaDonDatVe, d.MaPNR, d.MaKhachHang,
       d.TrangThai AS TrangThaiDon, v.MaHanhKhach,
       h.HoTen AS HoTenHanhKhach, v.MaChuyenBay, cb.SoHieuChuyen,
       cb.GioCatCanh, cb.GioDenDuKien, cb.MaSanBayDi, cb.MaSanBayDen,
       cb.TrangThai AS TrangThaiChuyenBay, v.HangVe, v.GiaVeChot,
       v.TrangThai AS TrangThaiVe,
       CONVERT(BIT, CASE WHEN c.MaCheckIn IS NULL THEN 0 ELSE 1 END) AS DaCheckIn,
       c.MaCheckIn, g.SoGhe, c.ThoiGian AS ThoiGianCheckIn, c.MaQR_BP
FROM dbo.VE_CHUYEN_BAY v
JOIN dbo.DON_DAT_VE d ON d.MaDonDatVe = v.MaDonDatVe
JOIN dbo.HANH_KHACH h ON h.MaHanhKhach = v.MaHanhKhach
JOIN dbo.HANG_VE_CHUYEN_BAY hv
  ON hv.MaChuyenBay = v.MaChuyenBay AND hv.HangVe = v.HangVe
JOIN dbo.CHUYEN_BAY cb ON cb.MaChuyenBay = v.MaChuyenBay
LEFT JOIN dbo.CHECK_IN c ON c.MaVe = v.MaVe AND c.TrangThai = 'CHECKED_IN'
LEFT JOIN dbo.GHE_CHUYEN_BAY g ON g.MaGhe = c.MaGhe;
GO

-- Khong JOIN ve vao day de tranh cong lap so tien cua mot don nhieu ve.
CREATE OR ALTER VIEW dbo.vw_DoanhThuNgay
AS
SELECT CONVERT(DATE, DATEADD(HOUR, 7, ThoiGianTT)) AS Ngay,
       COUNT(*) AS SoDonDaThanhToan,
       CONVERT(DECIMAL(18,2), SUM(SoTien)) AS DoanhThu
FROM dbo.GIAO_DICH_TT
WHERE TrangThaiTT = 'SUCCESS'
GROUP BY CONVERT(DATE, DATEADD(HOUR, 7, ThoiGianTT));
GO
