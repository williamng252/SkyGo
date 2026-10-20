
USE SkyGo_Cnpm;
GO
SELECT name,TYPE_NAME(user_type_id) AS KieuDuLieu
FROM sys.parameters WHERE object_id=OBJECT_ID('dbo.usp_TaoDonDatVe') ORDER BY parameter_id;

DECLARE @PNR CHAR(6)='ABC123'; -- Replace with the PNR just booked in the UI.
SELECT v.MaPNR,v.MaVe,v.MaHanhKhach,v.HoTenHanhKhach,v.MaChuyenBay,v.HangVe,v.GiaVeChot,
       CONVERT(VARCHAR(10),h.NgaySinh,23) AS NgaySinhISO,
       CONVERT(VARCHAR(10),h.NgaySinh,103) AS NgaySinhHienThi,
       CONVERT(VARCHAR(10),DATEADD(HOUR,7,v.GioCatCanh),103) AS NgayBayVN,
       v.SoGhe,v.TrangThaiVe,v.DaCheckIn
FROM dbo.vw_ChiTietVe v JOIN dbo.HANH_KHACH h ON h.MaHanhKhach=v.MaHanhKhach
WHERE v.MaPNR=@PNR ORDER BY v.GioCatCanh,v.MaVe;

SELECT d.MaPNR,d.TongTien,dbo.fn_TinhTongTienDon(d.MaDonDatVe) AS TongGiaVe
FROM dbo.DON_DAT_VE d WHERE d.MaPNR=@PNR;
