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

-- Moi lan goi tao mot don cho mot chuyen/hang, gom 1 den 9 hanh khach.
-- Danh sach hanh khach la JSON de Java truyen ca danh sach trong mot tham so.
-- Java KHONG truyen gia ve; SP lay gia hien tai va chot vao tung ve.
CREATE OR ALTER PROCEDURE dbo.usp_TaoDonDatVe
    @MaKhachHang BIGINT = NULL,
    @MaChuyenBay VARCHAR(20), @HangVe VARCHAR(10),
    @HoTenLienHe NVARCHAR(100), @EmailLienHe VARCHAR(254), @SDTLienHe VARCHAR(20),
    @DanhSachHanhKhach NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SET @HoTenLienHe = LTRIM(RTRIM(@HoTenLienHe));
    SET @EmailLienHe = LOWER(LTRIM(RTRIM(@EmailLienHe)));
    SET @SDTLienHe = LTRIM(RTRIM(@SDTLienHe));
    IF @HoTenLienHe IS NULL OR LEN(@HoTenLienHe) = 0
       OR @EmailLienHe IS NULL OR @EmailLienHe NOT LIKE '%_@_%._%'
       OR @SDTLienHe IS NULL OR LEN(@SDTLienHe) = 0
        THROW 50002, N'Thong tin lien he khong hop le.', 1;
    IF @DanhSachHanhKhach IS NULL OR LEN(@DanhSachHanhKhach) > 20000
       OR ISJSON(@DanhSachHanhKhach) <> 1
       OR LEFT(LTRIM(@DanhSachHanhKhach),1) <> '['
        THROW 50002, N'Danh sach hanh khach phai la mang JSON.', 1;
    IF EXISTS (SELECT 1 FROM OPENJSON(@DanhSachHanhKhach) WHERE [type] <> 5)
        THROW 50002, N'Moi phan tu JSON phai la mot hanh khach.', 1;

    DECLARE @DS TABLE
    (STT INT PRIMARY KEY, HoTen NVARCHAR(MAX), NgaySinhText NVARCHAR(MAX),
     GioiTinh NVARCHAR(MAX), LoaiGiayTo NVARCHAR(MAX), SoGiayTo NVARCHAR(MAX),
     QuocTich NVARCHAR(MAX));
    INSERT INTO @DS
    SELECT CONVERT(INT,j.[key])+1, LTRIM(RTRIM(p.HoTen)), p.NgaySinh,
           NULLIF(UPPER(LTRIM(RTRIM(p.GioiTinh))),''),
           NULLIF(UPPER(LTRIM(RTRIM(p.LoaiGiayTo))),''),
           NULLIF(LTRIM(RTRIM(p.SoGiayTo)),''), NULLIF(LTRIM(RTRIM(p.QuocTich)),'')
    FROM OPENJSON(@DanhSachHanhKhach) j
    CROSS APPLY OPENJSON(j.[value]) WITH
    (HoTen NVARCHAR(MAX) '$.HoTen', NgaySinh NVARCHAR(MAX) '$.NgaySinh',
     GioiTinh NVARCHAR(MAX) '$.GioiTinh', LoaiGiayTo NVARCHAR(MAX) '$.LoaiGiayTo',
     SoGiayTo NVARCHAR(MAX) '$.SoGiayTo', QuocTich NVARCHAR(MAX) '$.QuocTich') p;
    DECLARE @SoKhach INT = (SELECT COUNT(*) FROM @DS);
    IF @SoKhach NOT BETWEEN 1 AND 9
        THROW 50002, N'Moi don can tu 1 den 9 hanh khach.', 1;
    IF EXISTS
    (SELECT 1 FROM @DS WHERE HoTen IS NULL OR LEN(HoTen) NOT BETWEEN 1 AND 100
       OR NgaySinhText IS NULL OR LEN(NgaySinhText) <> 10
       OR TRY_CONVERT(DATE,NgaySinhText,23) IS NULL
       OR TRY_CONVERT(DATE,NgaySinhText,23) > CONVERT(DATE,SYSUTCDATETIME())
       OR (GioiTinh IS NOT NULL AND GioiTinh NOT IN ('MALE','FEMALE','OTHER'))
       OR (LoaiGiayTo IS NOT NULL AND LoaiGiayTo NOT IN ('CCCD','PASSPORT','OTHER'))
       OR LEN(SoGiayTo) > 30 OR LEN(QuocTich) > 60
       OR (SoGiayTo IS NOT NULL AND LoaiGiayTo IS NULL))
        THROW 50002, N'Thong tin hanh khach khong hop le.', 1;
    IF EXISTS
    (SELECT LoaiGiayTo,SoGiayTo FROM @DS WHERE SoGiayTo IS NOT NULL
     GROUP BY LoaiGiayTo,SoGiayTo HAVING COUNT(*) > 1)
        THROW 50002, N'Trung giay to hanh khach trong cung don.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC dbo.usp_KhoaNghiepVu;
        DECLARE @HienTai DATETIME2 = SYSUTCDATETIME();
        IF @MaKhachHang IS NOT NULL AND NOT EXISTS
        (SELECT 1 FROM dbo.TAI_KHOAN_ND
         WHERE MaKhachHang = @MaKhachHang AND VaiTro = 'CUSTOMER' AND TrangThai = 1)
            THROW 50004, N'Khach hang khong ton tai hoac tai khoan bi khoa.', 1;
        IF NOT EXISTS
        (SELECT 1 FROM dbo.CHUYEN_BAY cb
         JOIN dbo.SAN_BAY s1 ON s1.MaSanBay = cb.MaSanBayDi
         JOIN dbo.SAN_BAY s2 ON s2.MaSanBay = cb.MaSanBayDen
         WHERE cb.MaChuyenBay = @MaChuyenBay AND cb.GioCatCanh > @HienTai
           AND cb.TrangThai IN ('SCHEDULED','DELAYED') AND s1.TrangThai = 1 AND s2.TrangThai = 1)
            THROW 50010, N'Chuyen bay khong con du dieu kien dat ve.', 1;
        DECLARE @GiaCoBan DECIMAL(18,2), @ThuePhi DECIMAL(18,2);
        SELECT @GiaCoBan = GiaCoBan, @ThuePhi = ThuePhi
        FROM dbo.HANG_VE_CHUYEN_BAY
        WHERE MaChuyenBay = @MaChuyenBay AND HangVe = @HangVe AND TrangThai = 1;
        IF @GiaCoBan IS NULL OR @GiaCoBan + @ThuePhi <= 0
            THROW 50010, N'Hang ve chua mo ban hoac gia khong hop le.', 1;
        IF dbo.fn_SoChoCon(@MaChuyenBay,@HangVe,@HienTai) < @SoKhach
            THROW 50011, N'Khong du cho. Hay chon chuyen hoac hang ve khac.', 1;
        DECLARE @TongTien DECIMAL(18,2) = (@GiaCoBan+@ThuePhi)*@SoKhach;
        DECLARE @HanThanhToan DATETIME2 = DATEADD(MINUTE,30,@HienTai);
        -- Don khong duoc giu cho qua luc chuyen bay cat canh.
        DECLARE @GioBay DATETIME2;
        SELECT @GioBay = GioCatCanh FROM dbo.CHUYEN_BAY WHERE MaChuyenBay = @MaChuyenBay;
        IF @HanThanhToan >= @GioBay SET @HanThanhToan = DATEADD(SECOND,-1,@GioBay);
        IF @HanThanhToan <= @HienTai THROW 50010, N'Qua sat gio bay de dat ve.', 1;
        DECLARE @MaPNR CHAR(6), @SoLan INT = 0;
        WHILE 1 = 1
        BEGIN
            SET @MaPNR = UPPER(LEFT(REPLACE(CONVERT(VARCHAR(36),NEWID()),'-',''),6));
            IF NOT EXISTS (SELECT 1 FROM dbo.DON_DAT_VE WHERE MaPNR = @MaPNR) BREAK;
            SET @SoLan = @SoLan + 1;
            IF @SoLan >= 50 THROW 50012, N'Khong tao duoc PNR, hay thu lai.', 1;
        END;
        INSERT INTO dbo.DON_DAT_VE
        (MaPNR,NgayDat,HanThanhToan,HoTenLienHe,EmailLienHe,SDTLienHe,TongTien,TrangThai,MaKhachHang)
        VALUES(@MaPNR,@HienTai,@HanThanhToan,@HoTenLienHe,@EmailLienHe,@SDTLienHe,@TongTien,'PENDING',@MaKhachHang);
        DECLARE @MaDonDatVe BIGINT = SCOPE_IDENTITY();
        DECLARE @i INT = 1, @MaHK BIGINT;
        WHILE @i <= @SoKhach
        BEGIN
            INSERT INTO dbo.HANH_KHACH(HoTen,NgaySinh,GioiTinh,LoaiGiayTo,SoGiayTo,QuocTich)
            SELECT HoTen,CONVERT(DATE,NgaySinhText,23),GioiTinh,LoaiGiayTo,SoGiayTo,QuocTich
            FROM @DS WHERE STT = @i;
            SET @MaHK = SCOPE_IDENTITY();
            INSERT INTO dbo.VE_CHUYEN_BAY
            (MaDonDatVe,MaHanhKhach,MaChuyenBay,HangVe,GiaCoBanChot,ThuePhiChot,TrangThai)
            VALUES(@MaDonDatVe,@MaHK,@MaChuyenBay,@HangVe,@GiaCoBan,@ThuePhi,'RESERVED');
            SET @i = @i + 1;
        END;
        INSERT INTO dbo.GIAO_DICH_TT(MaDonDatVe,SoTien,PhuongThucTT,TrangThaiTT,ThoiGianTao)
        VALUES(@MaDonDatVe,@TongTien,'DEMO','PENDING',@HienTai);
        COMMIT TRANSACTION;
        SELECT @MaDonDatVe AS MaDonDatVe, @MaPNR AS MaPNR, @TongTien AS TongTien,
               @HanThanhToan AS HanThanhToan, CONVERT(VARCHAR(10),'PENDING') AS TrangThai;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- Huy don dat ve: xu ly hop le check-in, ve va don theo dung trigger va rang buoc
CREATE OR ALTER PROCEDURE dbo.usp_HuyDonDatVe
    @MaPNR CHAR(6), @MaKhachHang BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC dbo.usp_KhoaNghiepVu;
        DECLARE @MaDonDatVe BIGINT, @TrangThai VARCHAR(10), @Khach BIGINT;
        SELECT @MaDonDatVe = MaDonDatVe, @TrangThai = TrangThai, @Khach = MaKhachHang
        FROM dbo.DON_DAT_VE WHERE MaPNR = UPPER(LTRIM(RTRIM(@MaPNR)));
        IF @MaDonDatVe IS NULL THROW 50004, N'Don dat ve khong ton tai.', 1;
        IF @MaKhachHang IS NULL THROW 50020, N'Chi tai khoan khach hang moi duoc huy don.', 1;
        IF @Khach IS NULL OR @Khach <> @MaKhachHang
            THROW 50020, N'Tai khoan khong so huu don dat ve nay.', 1;
        IF @TrangThai NOT IN ('PENDING','PAID')
            THROW 50015, N'Don dat ve da duoc xu ly hoac da huy truoc do.', 1;

        -- 1. Huy cac luot check-in dang con hieu luc truoc (de thoa man trigger trg_Ve_BaoVe)
        UPDATE c SET TrangThai = 'CANCELLED'
        FROM dbo.CHECK_IN c
        JOIN dbo.VE_CHUYEN_BAY v ON v.MaVe = c.MaVe
        WHERE v.MaDonDatVe = @MaDonDatVe AND c.TrangThai = 'CHECKED_IN';

        -- 2. Chuyen trang thai cac ve ve CANCELLED
        UPDATE dbo.VE_CHUYEN_BAY SET TrangThai = 'CANCELLED'
        WHERE MaDonDatVe = @MaDonDatVe AND TrangThai IN ('RESERVED','ISSUED');

        -- 3. Chuyen trang thai don ve CANCELLED
        UPDATE dbo.DON_DAT_VE SET TrangThai = 'CANCELLED' WHERE MaDonDatVe = @MaDonDatVe;

        -- 4. Neu co giao dich PENDING thi danh dau FAILED
        UPDATE dbo.GIAO_DICH_TT SET TrangThaiTT = 'FAILED', ThoiGianTT = SYSUTCDATETIME()
        WHERE MaDonDatVe = @MaDonDatVe AND TrangThaiTT = 'PENDING';

        COMMIT TRANSACTION;
        SELECT @MaDonDatVe AS MaDonDatVe, @MaPNR AS MaPNR, CONVERT(VARCHAR(10),'CANCELLED') AS TrangThai;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
