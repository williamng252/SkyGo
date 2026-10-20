USE SkyGo_Cnpm;
GO

SELECT SoHieuChuyen,MaSanBayDi,MaSanBayDen,GioCatCanh,COUNT(*) AS SoBanGhi
FROM dbo.CHUYEN_BAY
GROUP BY SoHieuChuyen,MaSanBayDi,MaSanBayDen,GioCatCanh HAVING COUNT(*)>1;
SELECT MaChuyenBay,HangVe,COUNT(*) AS SoBanGhi
FROM dbo.HANG_VE_CHUYEN_BAY GROUP BY MaChuyenBay,HangVe HAVING COUNT(*)>1;
SELECT cb.MaChuyenBay,cb.SoHieuChuyen,cb.GioCatCanh,hv.HangVe,
       hv.GiaCoBan,hv.ThuePhi,hv.TrangThai,
       dbo.fn_SoChoCon(cb.MaChuyenBay,hv.HangVe,SYSUTCDATETIME()) AS SoChoCon
FROM dbo.CHUYEN_BAY cb JOIN dbo.HANG_VE_CHUYEN_BAY hv ON hv.MaChuyenBay=cb.MaChuyenBay
ORDER BY cb.GioCatCanh,cb.MaChuyenBay,hv.HangVe;

DECLARE @PNR CHAR(6)='JK56LM';
SELECT MaPNR,MaVe,HoTenHanhKhach,MaChuyenBay,HangVe,GiaVeChot,SoGhe,TrangThaiVe,DaCheckIn
FROM dbo.vw_ChiTietVe WHERE MaPNR=@PNR ORDER BY GioCatCanh,MaVe;
SELECT d.MaPNR,d.TongTien,dbo.fn_TinhTongTienDon(d.MaDonDatVe) AS TongGiaVe
FROM dbo.DON_DAT_VE d WHERE d.MaPNR=@PNR;
