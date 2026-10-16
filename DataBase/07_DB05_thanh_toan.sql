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

-- @SoTien la tham so kiem tra bo sung. NULL: mo phong lay dung tong tien don.
-- Java xac minh quyen so huu don/PNR truoc khi goi. Khong phai cong thanh toan that.
CREATE OR ALTER PROCEDURE dbo.usp_XacNhanThanhToanMoPhong
    @MaDonDatVe BIGINT, @KetQua VARCHAR(10), @MaThamChieu VARCHAR(100),
    @SoTien DECIMAL(18,2) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SET @KetQua = UPPER(LTRIM(RTRIM(@KetQua)));
    SET @MaThamChieu = LTRIM(RTRIM(@MaThamChieu));
    IF @KetQua IS NULL OR @KetQua NOT IN ('SUCCESS','FAILED')
       OR @MaThamChieu IS NULL OR LEN(@MaThamChieu) = 0
        THROW 50002, N'Ket qua hoac ma tham chieu thanh toan khong hop le.', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC dbo.usp_KhoaNghiepVu;
        DECLARE @HienTai DATETIME2 = SYSUTCDATETIME();
        DECLARE @MaPNR CHAR(6), @TrangThai VARCHAR(10), @TongTien DECIMAL(18,2), @Han DATETIME2;
        SELECT @MaPNR = MaPNR, @TrangThai = TrangThai, @TongTien = TongTien, @Han = HanThanhToan
        FROM dbo.DON_DAT_VE WHERE MaDonDatVe = @MaDonDatVe;
        IF @MaPNR IS NULL THROW 50004, N'Don dat ve khong ton tai.', 1;
        IF @SoTien IS NOT NULL AND (@SoTien <= 0 OR @SoTien <> @TongTien)
            THROW 50013, N'So tien khong khop tong tien don.', 1;

        -- Cung ma tham chieu + cung don + cung ket qua: tra lai, khong ghi them.
        IF EXISTS (SELECT 1 FROM dbo.GIAO_DICH_TT WHERE MaThamChieu = @MaThamChieu)
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.GIAO_DICH_TT
                           WHERE MaThamChieu = @MaThamChieu AND MaDonDatVe = @MaDonDatVe
                             AND TrangThaiTT = @KetQua AND SoTien = @TongTien)
                THROW 50014, N'Ma tham chieu da dung cho yeu cau khac.', 1;
            COMMIT TRANSACTION;
            SELECT @MaDonDatVe AS MaDonDatVe, @MaPNR AS MaPNR, @TrangThai AS TrangThaiDon,
                   @KetQua AS TrangThaiTT;
            RETURN;
        END;
        IF @TrangThai <> 'PENDING'
            THROW 50015, N'Don khong o trang thai cho thanh toan.', 1;
        IF @Han <= @HienTai
        BEGIN
            UPDATE dbo.DON_DAT_VE SET TrangThai = 'EXPIRED' WHERE MaDonDatVe = @MaDonDatVe;
            UPDATE dbo.VE_CHUYEN_BAY SET TrangThai = 'CANCELLED'
            WHERE MaDonDatVe = @MaDonDatVe AND TrangThai = 'RESERVED';
            UPDATE dbo.GIAO_DICH_TT SET TrangThaiTT = 'FAILED', ThoiGianTT = @HienTai
            WHERE MaDonDatVe = @MaDonDatVe AND TrangThaiTT = 'PENDING';
            -- Luu trang thai het han, sau do bao loi cho Java.
            COMMIT TRANSACTION;
            THROW 50016, N'Don da het han thanh toan.', 1;
        END;
        IF NOT EXISTS (SELECT 1 FROM dbo.VE_CHUYEN_BAY WHERE MaDonDatVe = @MaDonDatVe)
           OR EXISTS (SELECT 1 FROM dbo.VE_CHUYEN_BAY
                      WHERE MaDonDatVe = @MaDonDatVe AND TrangThai <> 'RESERVED')
           OR dbo.fn_TinhTongTienDon(@MaDonDatVe) <> @TongTien
            THROW 50017, N'Du lieu ve hoac tong tien don khong nhat quan.', 1;
        IF EXISTS
        (SELECT 1 FROM dbo.VE_CHUYEN_BAY v JOIN dbo.CHUYEN_BAY cb ON cb.MaChuyenBay=v.MaChuyenBay
         WHERE v.MaDonDatVe=@MaDonDatVe
           AND (cb.TrangThai NOT IN ('SCHEDULED','DELAYED') OR cb.GioCatCanh<=@HienTai))
            THROW 50010, N'Chuyen bay khong con du dieu kien thanh toan.', 1;

        IF @KetQua = 'SUCCESS'
        BEGIN
            UPDATE dbo.DON_DAT_VE SET TrangThai='PAID' WHERE MaDonDatVe=@MaDonDatVe;
            UPDATE dbo.VE_CHUYEN_BAY SET TrangThai='ISSUED' WHERE MaDonDatVe=@MaDonDatVe;
            SET @TrangThai = 'PAID';
        END;
        DECLARE @MaGD BIGINT;
        SELECT TOP (1) @MaGD=MaGiaoDich FROM dbo.GIAO_DICH_TT
        WHERE MaDonDatVe=@MaDonDatVe AND TrangThaiTT='PENDING' ORDER BY MaGiaoDich DESC;
        IF @MaGD IS NOT NULL
            UPDATE dbo.GIAO_DICH_TT
            SET SoTien=@TongTien, TrangThaiTT=@KetQua, ThoiGianTT=@HienTai, MaThamChieu=@MaThamChieu
            WHERE MaGiaoDich=@MaGD;
        ELSE
            INSERT INTO dbo.GIAO_DICH_TT
            (MaDonDatVe,SoTien,PhuongThucTT,TrangThaiTT,ThoiGianTao,ThoiGianTT,MaThamChieu)
            VALUES(@MaDonDatVe,@TongTien,'DEMO',@KetQua,@HienTai,@HienTai,@MaThamChieu);
        -- Don PAID khong de lai lan dang cho xu ly.
        IF @KetQua='SUCCESS'
            UPDATE dbo.GIAO_DICH_TT SET TrangThaiTT='FAILED',ThoiGianTT=@HienTai
            WHERE MaDonDatVe=@MaDonDatVe AND TrangThaiTT='PENDING';
        COMMIT TRANSACTION;
        SELECT @MaDonDatVe AS MaDonDatVe, @MaPNR AS MaPNR, @TrangThai AS TrangThaiDon,
               @KetQua AS TrangThaiTT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- Goi dinh ky tu Java hoac truoc khi hien trang quan tri.
-- So cho con van tinh dung theo HanThanhToan, ke ca chua goi SP nay.
CREATE OR ALTER PROCEDURE dbo.usp_XuLyDonHetHan
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC dbo.usp_KhoaNghiepVu;
        DECLARE @HienTai DATETIME2=SYSUTCDATETIME();
        DECLARE @DS TABLE(MaDonDatVe BIGINT PRIMARY KEY);
        UPDATE dbo.DON_DAT_VE SET TrangThai='EXPIRED'
        OUTPUT inserted.MaDonDatVe INTO @DS
        WHERE TrangThai='PENDING' AND HanThanhToan<=@HienTai;
        UPDATE v SET TrangThai='CANCELLED'
        FROM dbo.VE_CHUYEN_BAY v JOIN @DS d ON d.MaDonDatVe=v.MaDonDatVe
        WHERE v.TrangThai='RESERVED';
        UPDATE g SET TrangThaiTT='FAILED',ThoiGianTT=@HienTai
        FROM dbo.GIAO_DICH_TT g JOIN @DS d ON d.MaDonDatVe=g.MaDonDatVe
        WHERE g.TrangThaiTT='PENDING';
        COMMIT TRANSACTION;
        SELECT COUNT(*) AS SoDonHetHan FROM @DS;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
