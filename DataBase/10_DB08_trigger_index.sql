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

-- Trigger kiem tra TOAN BO inserted, khong gan mot dong inserted vao bien.
CREATE OR ALTER TRIGGER dbo.trg_CheckIn_KiemTra
ON dbo.CHECK_IN
AFTER INSERT,UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS
    (SELECT 1 FROM inserted i JOIN deleted d ON d.MaCheckIn=i.MaCheckIn
     WHERE i.MaVe<>d.MaVe OR i.MaGhe<>d.MaGhe OR i.MaQR_BP<>d.MaQR_BP
        OR (d.TrangThai='CANCELLED' AND i.TrangThai='CHECKED_IN'))
        THROW 50101, N'Khong doi ve/ghe/QR hoac kich hoat lai luot check-in cu.', 1;
    IF EXISTS
    (SELECT 1 FROM inserted i
     JOIN dbo.VE_CHUYEN_BAY v ON v.MaVe=i.MaVe
     JOIN dbo.DON_DAT_VE d ON d.MaDonDatVe=v.MaDonDatVe
     JOIN dbo.GHE_CHUYEN_BAY g ON g.MaGhe=i.MaGhe
     JOIN dbo.CHUYEN_BAY cb ON cb.MaChuyenBay=v.MaChuyenBay
     WHERE i.TrangThai='CHECKED_IN'
       AND (g.MaChuyenBay<>v.MaChuyenBay OR g.HangVe<>v.HangVe
         OR v.TrangThai<>'ISSUED' OR d.TrangThai<>'PAID'
         OR cb.TrangThai NOT IN ('SCHEDULED','DELAYED')
         OR SYSUTCDATETIME()<cb.MoCheckInLuc OR SYSUTCDATETIME()>=cb.DongCheckInLuc
         OR i.ThoiGian<cb.MoCheckInLuc OR i.ThoiGian>=cb.DongCheckInLuc))
        THROW 50102, N'Check-in sai chuyen/hang, trang thai hoac thoi gian.', 1;
END;
GO

-- Bao ve gia va thong tin ve da tao; thanh toan chi doi TrangThai.
CREATE OR ALTER TRIGGER dbo.trg_Ve_BaoVe
ON dbo.VE_CHUYEN_BAY
AFTER UPDATE,DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS
    (SELECT 1 FROM deleted d JOIN inserted i ON i.MaVe=d.MaVe
     WHERE i.MaDonDatVe<>d.MaDonDatVe OR i.MaHanhKhach<>d.MaHanhKhach
        OR i.MaChuyenBay<>d.MaChuyenBay OR i.HangVe<>d.HangVe
        OR i.GiaCoBanChot<>d.GiaCoBanChot OR i.ThuePhiChot<>d.ThuePhiChot)
        THROW 50103, N'Khong doi dinh danh, hanh khach hoac gia da chot cua ve.', 1;
    IF EXISTS
    (SELECT 1 FROM deleted d
     WHERE d.TrangThai IN ('ISSUED','USED') AND NOT EXISTS
       (SELECT 1 FROM inserted i WHERE i.MaVe=d.MaVe))
        THROW 50104, N'Khong xoa ve da phat hanh. Hay xu ly bang trang thai.', 1;
    IF EXISTS
    (SELECT 1 FROM inserted i JOIN dbo.CHECK_IN c ON c.MaVe=i.MaVe
     WHERE c.TrangThai='CHECKED_IN' AND i.TrangThai NOT IN ('ISSUED','USED'))
        THROW 50105, N'Can huy check-in truoc khi doi ve ve trang thai nay.', 1;
END;
GO

-- Neu sua bang ghe truc tiep trong SSMS, van bao ve lich su check-in.
CREATE OR ALTER TRIGGER dbo.trg_Ghe_BaoVe
ON dbo.GHE_CHUYEN_BAY
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS
    (SELECT 1 FROM inserted i JOIN deleted d ON d.MaGhe=i.MaGhe
     WHERE (i.MaChuyenBay<>d.MaChuyenBay OR i.HangVe<>d.HangVe OR i.SoGhe<>d.SoGhe)
       AND EXISTS (SELECT 1 FROM dbo.CHECK_IN c WHERE c.MaGhe=d.MaGhe))
        THROW 50106, N'Khong doi ghe da co lich su check-in.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_ThanhToan_KiemTraSoTien
ON dbo.GIAO_DICH_TT
AFTER INSERT,UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS
    (SELECT 1 FROM inserted i JOIN dbo.DON_DAT_VE d ON d.MaDonDatVe=i.MaDonDatVe
     WHERE i.TrangThaiTT='SUCCESS' AND i.SoTien<>d.TongTien)
        THROW 50107, N'Thanh toan thanh cong phai dung tong tien don.', 1;
    IF EXISTS
    (SELECT 1 FROM inserted i JOIN deleted d ON d.MaGiaoDich=i.MaGiaoDich
     WHERE d.TrangThaiTT IN ('SUCCESS','FAILED')
       AND (i.MaDonDatVe<>d.MaDonDatVe OR i.SoTien<>d.SoTien
         OR i.TrangThaiTT<>d.TrangThaiTT OR i.PhuongThucTT<>d.PhuongThucTT
         OR ISNULL(i.MaThamChieu,'')<>ISNULL(d.MaThamChieu,'')
         OR i.ThoiGianTao<>d.ThoiGianTao
         OR ISNULL(i.ThoiGianTT,CONVERT(DATETIME2,'19000101'))
            <>ISNULL(d.ThoiGianTT,CONVERT(DATETIME2,'19000101'))))
        THROW 50108, N'Khong sua ket qua thanh toan da ket thuc.', 1;
END;
GO

-- Chi muc da co trong schema thi khong tao lap.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.CHUYEN_BAY') AND name='IX_CB_TimChuyen')
CREATE INDEX IX_CB_TimChuyen ON dbo.CHUYEN_BAY(MaSanBayDi,MaSanBayDen,GioCatCanh)
INCLUDE (SoHieuChuyen,GioDenDuKien,TrangThai);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.VE_CHUYEN_BAY') AND name='IX_VE_ChuyenHang')
CREATE INDEX IX_VE_ChuyenHang ON dbo.VE_CHUYEN_BAY(MaChuyenBay,HangVe,TrangThai)
INCLUDE (MaDonDatVe);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.DON_DAT_VE') AND name='IX_DON_KhachHang')
CREATE INDEX IX_DON_KhachHang ON dbo.DON_DAT_VE(MaKhachHang,NgayDat DESC)
INCLUDE (MaPNR,TongTien,TrangThai);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.GIAO_DICH_TT') AND name='IX_TT_DoanhThu')
CREATE INDEX IX_TT_DoanhThu ON dbo.GIAO_DICH_TT(TrangThaiTT,ThoiGianTT)
INCLUDE (MaDonDatVe,SoTien);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.VE_CHUYEN_BAY') AND name='IX_VE_Don')
CREATE INDEX IX_VE_Don ON dbo.VE_CHUYEN_BAY(MaDonDatVe)
INCLUDE (MaHanhKhach,MaChuyenBay,HangVe,TrangThai,GiaCoBanChot,ThuePhiChot);
GO
