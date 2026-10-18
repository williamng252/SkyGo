USE SkyGo_Cnpm;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;

-- 1. CAU HINH
DECLARE @HienTaiUTC DATETIME2 = SYSUTCDATETIME();
DECLARE @NgayBatDau DATE = DATEADD(DAY, 1,
    CONVERT(DATE, DATEADD(HOUR, 7, @HienTaiUTC)));
-- Muon co dinh lich de demo: sua dong tren thanh ngay, vi du '2026-10-20'.
DECLARE @SoNgay INT = 30;

IF @@TRANCOUNT > 0
    THROW 53000, N'Hay chay file nay rieng, ngoai giao tac khac.', 1;
IF @SoNgay IS NULL OR @SoNgay NOT BETWEEN 1 AND 365
    THROW 53001, N'So ngay phai tu 1 den 365.', 1;
IF @NgayBatDau IS NULL OR @NgayBatDau <= CONVERT(DATE, DATEADD(HOUR,7,@HienTaiUTC))
    THROW 53002, N'Ngay bat dau phai tu ngay mai theo gio Viet Nam.', 1;
IF OBJECT_ID(N'dbo.usp_KhoaNghiepVu', N'P') IS NULL
    THROW 53003, N'Can chay cac file 01-11 truoc khi nap bo sung.', 1;

-- 2. LICH MAU MOI NGAY
DECLARE @Tuyen TABLE (
    STT INT PRIMARY KEY,
    SanBayDi CHAR(3), SanBayDen CHAR(3),
    SoHieuChuyen VARCHAR(10), GioDiVN INT, PhutDiVN INT,
    PhutBay INT, GiaEconomy DECIMAL(18,2), ThuePhi DECIMAL(18,2)
);

INSERT INTO @Tuyen VALUES
-- SGN <-> HAN: 2 chuyen moi chieu moi ngay
(1, 'SGN','HAN','SG301', 8, 0,130,1200000,300000),
(2, 'SGN','HAN','SG303',17, 0,130,1350000,300000),
(3, 'HAN','SGN','SG302', 9,30,130,1200000,300000),
(4, 'HAN','SGN','SG304',19, 0,130,1350000,300000),
-- SGN <-> DAD: 2 chuyen moi chieu moi ngay
(5, 'SGN','DAD','SG305', 8, 0, 80, 750000,250000),
(6, 'SGN','DAD','SG307',17, 0, 80, 850000,250000),
(7, 'DAD','SGN','SG306', 9,30, 80, 750000,250000),
(8, 'DAD','SGN','SG308',19, 0, 80, 850000,250000),
-- Cac chang con lai: 1 chuyen/chieu/ngay
(9, 'HAN','DAD','SG309',10, 0, 85, 800000,250000),
(10,'DAD','HAN','SG310',14, 0, 85, 800000,250000),
(11,'SGN','TBB','SG311',10,30, 70, 650000,250000),
(12,'TBB','SGN','SG312',14,30, 70, 650000,250000),
(13,'HAN','TBB','SG313',11, 0,110,1000000,300000),
(14,'TBB','HAN','SG314',15, 0,110,1000000,300000);

-- 3. LAP DANH SACH CHUYEN CAN NAP
DECLARE @Lich TABLE (
    MaChuyenBay VARCHAR(20) PRIMARY KEY, SoHieuChuyen VARCHAR(10),
    GioCatCanh DATETIME2, GioDenDuKien DATETIME2,
    SanBayDi CHAR(3), SanBayDen CHAR(3),
    GiaEconomy DECIMAL(18,2), ThuePhi DECIMAL(18,2)
);
DECLARE @NgayThu INT = 0;
WHILE @NgayThu < @SoNgay
BEGIN
    INSERT INTO @Lich
    SELECT t.SoHieuChuyen + '-' + CONVERT(CHAR(8), DATEADD(DAY,@NgayThu,@NgayBatDau),112),
           t.SoHieuChuyen, g.GioUTC, DATEADD(MINUTE,t.PhutBay,g.GioUTC),
           t.SanBayDi, t.SanBayDen, t.GiaEconomy, t.ThuePhi
    FROM @Tuyen t
    CROSS APPLY (
        SELECT DATEADD(HOUR,-7,
            DATEADD(MINUTE,t.GioDiVN*60+t.PhutDiVN,
                CONVERT(DATETIME2,DATEADD(DAY,@NgayThu,@NgayBatDau)))) AS GioUTC
    ) g;
    SET @NgayThu = @NgayThu + 1;
END;

-- Ghe cung mau voi chuyen duoc tao tu ung dung Java.
DECLARE @GheMau TABLE (HangVe VARCHAR(10), SoGhe VARCHAR(5) PRIMARY KEY);
INSERT INTO @GheMau VALUES
('BUSINESS','01A'),('BUSINESS','01B'),('BUSINESS','01C'),('BUSINESS','01D'),
('BUSINESS','02A'),('BUSINESS','02B'),('BUSINESS','02C'),('BUSINESS','02D');
DECLARE @HangGhe INT = 3;
WHILE @HangGhe <= 8
BEGIN
    INSERT INTO @GheMau
    SELECT 'ECONOMY', RIGHT('0'+CONVERT(VARCHAR(2),@HangGhe),2)+c.Cot
    FROM (VALUES ('A'),('B'),('C'),('D'),('E'),('F')) c(Cot);
    SET @HangGhe = @HangGhe + 1;
END;

-- 4. NAP TRONG CUNG MOT GIAO TAC
DECLARE @Moi TABLE (MaChuyenBay VARCHAR(20) PRIMARY KEY);
DECLARE @SoChuyenMoi INT, @SoHangVeMoi INT, @SoGheMoi INT;
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC dbo.usp_KhoaNghiepVu;

    IF EXISTS (
        SELECT 1 FROM @Tuyen t
        LEFT JOIN dbo.SAN_BAY s1 ON s1.MaSanBay=t.SanBayDi
        LEFT JOIN dbo.SAN_BAY s2 ON s2.MaSanBay=t.SanBayDen
        WHERE s1.MaSanBay IS NULL OR s2.MaSanBay IS NULL
           OR s1.TrangThai <> 1 OR s2.TrangThai <> 1
    )
        THROW 53004, N'Thieu san bay SGN/HAN/DAD/TBB hoac san bay da ngung hoat dong.', 1;

    -- Ma cung ten nhung noi dung khac: dung, khong sua du lieu cu.
    IF EXISTS (
        SELECT 1 FROM @Lich l
        JOIN dbo.CHUYEN_BAY cb ON cb.MaChuyenBay=l.MaChuyenBay
        WHERE cb.SoHieuChuyen<>l.SoHieuChuyen OR cb.GioCatCanh<>l.GioCatCanh
           OR cb.MaSanBayDi<>l.SanBayDi OR cb.MaSanBayDen<>l.SanBayDen
    )
        THROW 53005, N'Ma chuyen bay du kien bi trung voi chuyen khac. Can doi so hieu trong bang @Tuyen.', 1;

    IF EXISTS (
        SELECT 1 FROM @Lich l
        JOIN dbo.CHUYEN_BAY cb ON cb.SoHieuChuyen=l.SoHieuChuyen AND cb.GioCatCanh=l.GioCatCanh
        WHERE cb.MaSanBayDi<>l.SanBayDi OR cb.MaSanBayDen<>l.SanBayDen
    )
        THROW 53006, N'So hieu va gio bay da duoc dung cho chang khac.', 1;

    INSERT INTO dbo.CHUYEN_BAY
        (MaChuyenBay,SoHieuChuyen,GioCatCanh,GioDenDuKien,TrangThai,
         LyDoThayDoi,MoCheckInLuc,DongCheckInLuc,MaSanBayDi,MaSanBayDen)
    OUTPUT inserted.MaChuyenBay INTO @Moi(MaChuyenBay)
    SELECT l.MaChuyenBay,l.SoHieuChuyen,l.GioCatCanh,l.GioDenDuKien,'SCHEDULED',
           NULL,DATEADD(HOUR,-12,l.GioCatCanh),DATEADD(HOUR,-1,l.GioCatCanh),
           l.SanBayDi,l.SanBayDen
    FROM @Lich l
    WHERE NOT EXISTS (SELECT 1 FROM dbo.CHUYEN_BAY cb
                      WHERE cb.MaChuyenBay=l.MaChuyenBay)
      AND NOT EXISTS (SELECT 1 FROM dbo.CHUYEN_BAY cb
                      WHERE cb.SoHieuChuyen=l.SoHieuChuyen AND cb.GioCatCanh=l.GioCatCanh)
      AND NOT EXISTS (SELECT 1 FROM dbo.CHUYEN_BAY cb
                      WHERE cb.MaSanBayDi=l.SanBayDi AND cb.MaSanBayDen=l.SanBayDen
                        AND cb.GioCatCanh=l.GioCatCanh);
    SET @SoChuyenMoi = @@ROWCOUNT;

    -- Gia Business = 1.8 lan Economy; thue/phi giu nhu nhau.
    INSERT INTO dbo.HANG_VE_CHUYEN_BAY
        (MaChuyenBay,HangVe,GiaCoBan,ThuePhi,TrangThai)
    SELECT l.MaChuyenBay,'ECONOMY',l.GiaEconomy,l.ThuePhi,1
    FROM @Lich l JOIN @Moi m ON m.MaChuyenBay=l.MaChuyenBay
    UNION ALL
    SELECT l.MaChuyenBay,'BUSINESS',CONVERT(DECIMAL(18,2),l.GiaEconomy*1.8),l.ThuePhi,1
    FROM @Lich l JOIN @Moi m ON m.MaChuyenBay=l.MaChuyenBay;
    SET @SoHangVeMoi = @@ROWCOUNT;

    INSERT INTO dbo.GHE_CHUYEN_BAY(MaChuyenBay,HangVe,SoGhe)
    SELECT m.MaChuyenBay,g.HangVe,g.SoGhe
    FROM @Moi m CROSS JOIN @GheMau g;
    SET @SoGheMoi = @@ROWCOUNT;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

-- 5. KET QUA: CHI DEM DU LIEU VUA THEM TRONG LAN CHAY NAY
SELECT @NgayBatDau AS NgayBatDauVN,
       DATEADD(DAY,@SoNgay-1,@NgayBatDau) AS NgayKetThucVN,
       (SELECT COUNT(*) FROM @Lich) AS SoChuyenDuKien,
       @SoChuyenMoi AS SoChuyenVuaThem,
       (SELECT COUNT(*) FROM @Lich)-@SoChuyenMoi AS SoChuyenDaCoBoQua,
       @SoHangVeMoi AS SoHangVeVuaThem, @SoGheMoi AS SoGheVuaThem;

SELECT cb.MaSanBayDi,cb.MaSanBayDen,COUNT(*) AS SoChuyenVuaThem,
       MIN(CONVERT(DATE,DATEADD(HOUR,7,cb.GioCatCanh))) AS TuNgayVN,
       MAX(CONVERT(DATE,DATEADD(HOUR,7,cb.GioCatCanh))) AS DenNgayVN
FROM dbo.CHUYEN_BAY cb JOIN @Moi m ON m.MaChuyenBay=cb.MaChuyenBay
GROUP BY cb.MaSanBayDi,cb.MaSanBayDen
ORDER BY cb.MaSanBayDi,cb.MaSanBayDen;

SELECT TOP (20) cb.MaChuyenBay,cb.SoHieuChuyen,cb.MaSanBayDi,cb.MaSanBayDen,
       DATEADD(HOUR,7,cb.GioCatCanh) AS GioCatCanhVN,
       DATEADD(HOUR,7,cb.GioDenDuKien) AS GioDenDuKienVN,
       DATEADD(HOUR,7,cb.MoCheckInLuc) AS MoCheckInVN,
       DATEADD(HOUR,7,cb.DongCheckInLuc) AS DongCheckInVN
FROM dbo.CHUYEN_BAY cb JOIN @Moi m ON m.MaChuyenBay=cb.MaChuyenBay
ORDER BY cb.GioCatCanh,cb.MaChuyenBay;
GO
