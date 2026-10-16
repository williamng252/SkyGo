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

-- SQL-H01 tham khao, cung ten/tham so da giao nguoi 4.
CREATE OR ALTER PROCEDURE dbo.usp_LayLichSuDatVe @MaKhachHang BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT MaDonDatVe,MaPNR,NgayDat,TongTien,TrangThai
    FROM dbo.DON_DAT_VE WHERE MaKhachHang=@MaKhachHang
    ORDER BY NgayDat DESC,MaDonDatVe DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_TraCuuPNR
    @MaPNR CHAR(6), @EmailLienHe VARCHAR(254)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT v.MaDonDatVe,v.MaPNR,v.TrangThaiDon,v.MaVe,v.HoTenHanhKhach,
           v.MaChuyenBay,v.HangVe,v.TrangThaiVe,v.DaCheckIn
    FROM dbo.vw_ChiTietVe v JOIN dbo.DON_DAT_VE d ON d.MaDonDatVe=v.MaDonDatVe
    WHERE d.MaPNR=UPPER(@MaPNR) AND d.EmailLienHe=LOWER(LTRIM(RTRIM(@EmailLienHe)))
    ORDER BY v.MaVe;
END;
GO

-- Backend phai kiem tra quyen truoc khi tra chi tiet don cho trinh duyet.
CREATE OR ALTER PROCEDURE dbo.usp_LayChiTietDon @MaDonDatVe BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT v.MaDonDatVe,v.MaPNR,v.MaKhachHang,v.TrangThaiDon,
           d.NgayDat,d.HanThanhToan,d.HoTenLienHe,d.EmailLienHe,d.SDTLienHe,d.TongTien,
           v.MaVe,v.MaHanhKhach,v.HoTenHanhKhach,v.MaChuyenBay,v.SoHieuChuyen,
           v.GioCatCanh,v.GioDenDuKien,v.MaSanBayDi,v.MaSanBayDen,
           v.HangVe,v.GiaVeChot,v.TrangThaiVe,v.DaCheckIn,v.SoGhe
    FROM dbo.vw_ChiTietVe v JOIN dbo.DON_DAT_VE d ON d.MaDonDatVe=v.MaDonDatVe
    WHERE v.MaDonDatVe=@MaDonDatVe ORDER BY v.MaVe;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AdminLayChuyenBay
    @TuNgay DATE=NULL,@DenNgay DATE=NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF (@TuNgay IS NOT NULL AND @DenNgay IS NOT NULL AND @TuNgay>@DenNgay)
       OR @TuNgay<'20000101' OR @DenNgay>'21000101'
        THROW 50002, N'Khoang ngay khong hop le.', 1;
    SELECT MaChuyenBay,SoHieuChuyen,GioCatCanh,GioDenDuKien,TrangThai,LyDoThayDoi,
           MoCheckInLuc,DongCheckInLuc,MaSanBayDi,MaSanBayDen
    FROM dbo.CHUYEN_BAY
    WHERE (@TuNgay IS NULL OR GioCatCanh>=DATEADD(HOUR,-7,CONVERT(DATETIME2,@TuNgay)))
      AND (@DenNgay IS NULL OR GioCatCanh<DATEADD(DAY,1,DATEADD(HOUR,-7,CONVERT(DATETIME2,@DenNgay))))
    ORDER BY GioCatCanh,MaChuyenBay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AdminThemChuyenBay
    @MaChuyenBay VARCHAR(20),@SoHieuChuyen VARCHAR(10),
    @GioCatCanh DATETIME2,@GioDenDuKien DATETIME2,@MoCheckInLuc DATETIME2,@DongCheckInLuc DATETIME2,
    @MaSanBayDi CHAR(3),@MaSanBayDen CHAR(3)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @MaChuyenBay IS NULL OR LEN(LTRIM(RTRIM(@MaChuyenBay)))=0
       OR @SoHieuChuyen IS NULL OR LEN(LTRIM(RTRIM(@SoHieuChuyen)))=0
       OR @GioCatCanh IS NULL OR @GioDenDuKien IS NULL OR @MoCheckInLuc IS NULL OR @DongCheckInLuc IS NULL
       OR @GioCatCanh<=SYSUTCDATETIME() OR @GioDenDuKien<=@GioCatCanh
       OR @MoCheckInLuc>=@DongCheckInLuc OR @DongCheckInLuc>=@GioCatCanh
       OR @MaSanBayDi IS NULL OR @MaSanBayDen IS NULL OR @MaSanBayDi=@MaSanBayDen
        THROW 50002, N'Thong tin chuyen bay khong hop le.', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC dbo.usp_KhoaNghiepVu;
        IF EXISTS (SELECT 1 FROM dbo.CHUYEN_BAY WHERE MaChuyenBay=@MaChuyenBay)
            THROW 50030, N'Ma chuyen bay da ton tai.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.SAN_BAY WHERE MaSanBay=@MaSanBayDi AND TrangThai=1)
           OR NOT EXISTS (SELECT 1 FROM dbo.SAN_BAY WHERE MaSanBay=@MaSanBayDen AND TrangThai=1)
            THROW 50002, N'San bay khong hop le.', 1;
        INSERT INTO dbo.CHUYEN_BAY
        (MaChuyenBay,SoHieuChuyen,GioCatCanh,GioDenDuKien,TrangThai,MoCheckInLuc,DongCheckInLuc,MaSanBayDi,MaSanBayDen)
        VALUES(@MaChuyenBay,@SoHieuChuyen,@GioCatCanh,@GioDenDuKien,'SCHEDULED',@MoCheckInLuc,@DongCheckInLuc,@MaSanBayDi,@MaSanBayDen);
        COMMIT TRANSACTION;
        SELECT @MaChuyenBay AS MaChuyenBay;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AdminSuaChuyenBay
    @MaChuyenBay VARCHAR(20),@SoHieuChuyen VARCHAR(10),
    @GioCatCanh DATETIME2,@GioDenDuKien DATETIME2,@MoCheckInLuc DATETIME2,@DongCheckInLuc DATETIME2,
    @MaSanBayDi CHAR(3),@MaSanBayDen CHAR(3)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @SoHieuChuyen IS NULL OR LEN(LTRIM(RTRIM(@SoHieuChuyen)))=0
       OR @GioCatCanh IS NULL OR @GioDenDuKien IS NULL OR @MoCheckInLuc IS NULL OR @DongCheckInLuc IS NULL
       OR @GioCatCanh<=SYSUTCDATETIME() OR @GioDenDuKien<=@GioCatCanh
       OR @MoCheckInLuc>=@DongCheckInLuc OR @DongCheckInLuc>=@GioCatCanh
       OR @MaSanBayDi IS NULL OR @MaSanBayDen IS NULL OR @MaSanBayDi=@MaSanBayDen
        THROW 50002, N'Thong tin chuyen bay khong hop le.', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC dbo.usp_KhoaNghiepVu;
        IF NOT EXISTS (SELECT 1 FROM dbo.CHUYEN_BAY WHERE MaChuyenBay=@MaChuyenBay)
            THROW 50004, N'Chuyen bay khong ton tai.', 1;
        IF EXISTS (SELECT 1 FROM dbo.VE_CHUYEN_BAY
                   WHERE MaChuyenBay=@MaChuyenBay AND TrangThai IN ('RESERVED','ISSUED','USED'))
            THROW 50031, N'Chuyen da co ve. Khong sua hanh trinh; hay xu ly don truoc.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.SAN_BAY WHERE MaSanBay=@MaSanBayDi AND TrangThai=1)
           OR NOT EXISTS (SELECT 1 FROM dbo.SAN_BAY WHERE MaSanBay=@MaSanBayDen AND TrangThai=1)
            THROW 50002, N'San bay khong hop le.', 1;
        UPDATE dbo.CHUYEN_BAY
        SET SoHieuChuyen=@SoHieuChuyen,GioCatCanh=@GioCatCanh,GioDenDuKien=@GioDenDuKien,
            MoCheckInLuc=@MoCheckInLuc,DongCheckInLuc=@DongCheckInLuc,
            MaSanBayDi=@MaSanBayDi,MaSanBayDen=@MaSanBayDen
        WHERE MaChuyenBay=@MaChuyenBay;
        COMMIT TRANSACTION;
        SELECT @MaChuyenBay AS MaChuyenBay;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- Tao/cap nhat gia theo chuyen; viec doi gia khong doi gia da chot o ve.
CREATE OR ALTER PROCEDURE dbo.usp_AdminLuuHangVe
    @MaChuyenBay VARCHAR(20),@HangVe VARCHAR(10),@GiaCoBan DECIMAL(18,2),
    @ThuePhi DECIMAL(18,2),@TrangThai BIT=1
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @HangVe IS NULL OR @HangVe NOT IN ('ECONOMY','BUSINESS')
       OR @GiaCoBan IS NULL OR @ThuePhi IS NULL OR @GiaCoBan<0 OR @ThuePhi<0
       OR @GiaCoBan+@ThuePhi<=0 OR @TrangThai IS NULL
        THROW 50002, N'Gia hoac hang ve khong hop le.', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC dbo.usp_KhoaNghiepVu;
        IF NOT EXISTS (SELECT 1 FROM dbo.CHUYEN_BAY
                       WHERE MaChuyenBay=@MaChuyenBay AND GioCatCanh>SYSUTCDATETIME()
                         AND TrangThai IN ('SCHEDULED','DELAYED'))
            THROW 50010, N'Chuyen bay khong con duoc phep mo ban.', 1;
        IF EXISTS (SELECT 1 FROM dbo.HANG_VE_CHUYEN_BAY WHERE MaChuyenBay=@MaChuyenBay AND HangVe=@HangVe)
            UPDATE dbo.HANG_VE_CHUYEN_BAY SET GiaCoBan=@GiaCoBan,ThuePhi=@ThuePhi,TrangThai=@TrangThai
            WHERE MaChuyenBay=@MaChuyenBay AND HangVe=@HangVe;
        ELSE
            INSERT INTO dbo.HANG_VE_CHUYEN_BAY(MaChuyenBay,HangVe,GiaCoBan,ThuePhi,TrangThai)
            VALUES(@MaChuyenBay,@HangVe,@GiaCoBan,@ThuePhi,@TrangThai);
        COMMIT TRANSACTION;
        SELECT MaChuyenBay,HangVe,GiaCoBan,ThuePhi,TrangThai FROM dbo.HANG_VE_CHUYEN_BAY
        WHERE MaChuyenBay=@MaChuyenBay AND HangVe=@HangVe;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- Them tung ghe cho chuyen moi; khong thay doi ghe cua chuyen da co ve.
CREATE OR ALTER PROCEDURE dbo.usp_AdminThemGhe
    @MaChuyenBay VARCHAR(20),@HangVe VARCHAR(10),@SoGhe VARCHAR(5)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SET @SoGhe=UPPER(LTRIM(RTRIM(@SoGhe)));
    IF @SoGhe IS NULL OR LEN(@SoGhe)=0 THROW 50002, N'So ghe khong hop le.', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC dbo.usp_KhoaNghiepVu;
        IF NOT EXISTS (SELECT 1 FROM dbo.CHUYEN_BAY
                       WHERE MaChuyenBay=@MaChuyenBay AND GioCatCanh>SYSUTCDATETIME()
                         AND TrangThai IN ('SCHEDULED','DELAYED'))
            THROW 50010, N'Chuyen bay khong du dieu kien them ghe.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.HANG_VE_CHUYEN_BAY WHERE MaChuyenBay=@MaChuyenBay AND HangVe=@HangVe)
            THROW 50004, N'Chua khai bao hang ve cua chuyen.', 1;
        IF EXISTS (SELECT 1 FROM dbo.VE_CHUYEN_BAY
                   WHERE MaChuyenBay=@MaChuyenBay AND TrangThai IN ('RESERVED','ISSUED','USED'))
            THROW 50031, N'Chuyen da co ve, khong thay doi danh sach ghe.', 1;
        INSERT INTO dbo.GHE_CHUYEN_BAY(MaChuyenBay,HangVe,SoGhe) VALUES(@MaChuyenBay,@HangVe,@SoGhe);
        DECLARE @MaGhe BIGINT=SCOPE_IDENTITY();
        COMMIT TRANSACTION;
        SELECT @MaGhe AS MaGhe,@SoGhe AS SoGhe;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AdminCapNhatTrangThaiChuyenBay
    @MaChuyenBay VARCHAR(20),@TrangThai VARCHAR(12),@LyDoThayDoi NVARCHAR(250)=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @TrangThai IS NULL OR @TrangThai NOT IN ('SCHEDULED','DELAYED','CANCELLED','DEPARTED','ARRIVED')
        THROW 50002, N'Trang thai chuyen bay khong hop le.', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC dbo.usp_KhoaNghiepVu;
        DECLARE @Cu VARCHAR(12);
        SELECT @Cu=TrangThai FROM dbo.CHUYEN_BAY WHERE MaChuyenBay=@MaChuyenBay;
        IF @Cu IS NULL THROW 50004, N'Chuyen bay khong ton tai.', 1;
        IF @Cu<>@TrangThai AND NOT
        ((@Cu='SCHEDULED' AND @TrangThai IN ('DELAYED','CANCELLED','DEPARTED'))
          OR (@Cu='DELAYED' AND @TrangThai IN ('SCHEDULED','CANCELLED','DEPARTED'))
          OR (@Cu='DEPARTED' AND @TrangThai='ARRIVED'))
            THROW 50032, N'Khong duoc chuyen trang thai theo huong nay.', 1;
        IF @TrangThai IN ('DELAYED','CANCELLED') AND NULLIF(LTRIM(RTRIM(@LyDoThayDoi)),'') IS NULL
            THROW 50002, N'Can nhap ly do cham hoac huy chuyen.', 1;
        UPDATE dbo.CHUYEN_BAY SET TrangThai=@TrangThai,LyDoThayDoi=@LyDoThayDoi
        WHERE MaChuyenBay=@MaChuyenBay;
        -- Huy chuyen: giai phong don cho, KHONG tu dong hoan tien don da tra.
        IF @TrangThai='CANCELLED'
        BEGIN
            DECLARE @DonHuy TABLE(MaDonDatVe BIGINT PRIMARY KEY);
            UPDATE d SET TrangThai='CANCELLED'
            OUTPUT inserted.MaDonDatVe INTO @DonHuy
            FROM dbo.DON_DAT_VE d
            WHERE d.TrangThai='PENDING' AND EXISTS
              (SELECT 1 FROM dbo.VE_CHUYEN_BAY v WHERE v.MaDonDatVe=d.MaDonDatVe AND v.MaChuyenBay=@MaChuyenBay);
            UPDATE v SET TrangThai='CANCELLED'
            FROM dbo.VE_CHUYEN_BAY v JOIN @DonHuy d ON d.MaDonDatVe=v.MaDonDatVe
            WHERE v.TrangThai='RESERVED';
            UPDATE g SET TrangThaiTT='FAILED',ThoiGianTT=SYSUTCDATETIME()
            FROM dbo.GIAO_DICH_TT g JOIN @DonHuy d ON d.MaDonDatVe=g.MaDonDatVe
            WHERE g.TrangThaiTT='PENDING';
        END;
        COMMIT TRANSACTION;
        SELECT @MaChuyenBay AS MaChuyenBay,@TrangThai AS TrangThai;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AdminTimDonDatVe
    @MaPNR CHAR(6)=NULL,@TrangThai VARCHAR(10)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT MaDonDatVe,MaPNR,NgayDat,HoTenLienHe,TongTien,TrangThai
    FROM dbo.DON_DAT_VE
    WHERE (@MaPNR IS NULL OR MaPNR=@MaPNR) AND (@TrangThai IS NULL OR TrangThai=@TrangThai)
    ORDER BY NgayDat DESC,MaDonDatVe DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AdminTimKhachHang @TuKhoa NVARCHAR(100)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT MaKhachHang,HoTen,SDT,Email FROM dbo.KHACH_HANG
    WHERE @TuKhoa IS NULL OR HoTen LIKE N'%'+@TuKhoa+N'%'
       OR Email LIKE N'%'+@TuKhoa+N'%' OR SDT LIKE N'%'+@TuKhoa+N'%'
    ORDER BY MaKhachHang DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AdminThongKeBanVe @TuNgay DATE,@DenNgay DATE
AS
BEGIN
    SET NOCOUNT ON;
    IF @TuNgay IS NULL OR @DenNgay IS NULL OR @TuNgay>@DenNgay
       OR @TuNgay<'20000101' OR @DenNgay>'21000101'
        THROW 50002, N'Khoang ngay thong ke khong hop le.', 1;
    DECLARE @TuGio DATETIME2=DATEADD(HOUR,-7,CONVERT(DATETIME2,@TuNgay));
    DECLARE @DenGio DATETIME2=DATEADD(DAY,1,DATEADD(HOUR,-7,CONVERT(DATETIME2,@DenNgay)));
    ;WITH DonThanhCong AS
    (
        SELECT MaDonDatVe,SoTien,CONVERT(DATE,DATEADD(HOUR,7,ThoiGianTT)) AS Ngay
        FROM dbo.GIAO_DICH_TT
        WHERE TrangThaiTT='SUCCESS' AND ThoiGianTT>=@TuGio AND ThoiGianTT<@DenGio
    ), VeTheoDon AS
    (
        SELECT MaDonDatVe,COUNT(*) AS SoVe FROM dbo.VE_CHUYEN_BAY
        WHERE TrangThai IN ('ISSUED','USED') GROUP BY MaDonDatVe
    )
    SELECT d.Ngay,COUNT(*) AS SoDonDaThanhToan,
           CONVERT(INT,SUM(ISNULL(v.SoVe,0))) AS SoVeDaPhatHanh,
           CONVERT(DECIMAL(18,2),SUM(d.SoTien)) AS DoanhThu
    FROM DonThanhCong d LEFT JOIN VeTheoDon v ON v.MaDonDatVe=d.MaDonDatVe
    GROUP BY d.Ngay ORDER BY d.Ngay;
END;
GO
