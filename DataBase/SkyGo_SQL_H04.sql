/*
   SKYGO - SQL-H04: FULL BACKUP VA PHUC HOI THU
   Schema xac dinh database: SkyGo_Cnpm.
   Backup va restore phai chay tren SQL Server (SSMS), khong phai LocalDB
   tren may khach neu dich vu SQL Server khong truy cap duoc duong dan.
*/
USE master;
GO

/* CAU HINH - SUA NEU CAN
   1) Tao thu muc C:\SQLBackup tren MAY CHU SQL SERVER truoc khi chay.
   2) Tai khoan dich vu SQL Server can quyen doc/ghi thu muc nay.
   3) Logical file name mac dinh thuong la SkyGo_Cnpm va SkyGo_Cnpm_log,
      nhung hay kiem tra ket qua RESTORE FILELISTONLY o ben duoi.
   4) Neu ten logic khac, sua @LogicalDataName/@LogicalLogName roi chay lai.
*/
DECLARE @SourceDatabase SYSNAME = N'SkyGo_Cnpm';
DECLARE @RestoreDatabase SYSNAME = N'SkyGo_Cnpm_RestoreTest';
DECLARE @BackupPath NVARCHAR(4000) = N'C:\SQLBackup\SkyGo_Cnpm_Full.bak';
DECLARE @RestoreDataPath NVARCHAR(4000) = N'C:\SQLBackup\SkyGo_Cnpm_RestoreTest.mdf';
DECLARE @RestoreLogPath NVARCHAR(4000) = N'C:\SQLBackup\SkyGo_Cnpm_RestoreTest_log.ldf';
DECLARE @LogicalDataName SYSNAME = N'SkyGo_Cnpm';
DECLARE @LogicalLogName SYSNAME = N'SkyGo_Cnpm_log';
DECLARE @SQL NVARCHAR(MAX);

-- Danh dau lan chay hien tai de tranh doi chieu voi database restore cu neu lan nay that bai.
IF OBJECT_ID(N'tempdb..#SkyGoH04_RunStatus') IS NOT NULL
    DROP TABLE #SkyGoH04_RunStatus;
CREATE TABLE #SkyGoH04_RunStatus (RestoreSucceeded BIT NOT NULL);
INSERT INTO #SkyGoH04_RunStatus (RestoreSucceeded) VALUES (0);

IF DB_ID(@SourceDatabase) IS NULL
    THROW 52001, N'Khong tim thay database nguon SkyGo_Cnpm. Hay chay schema/seed truoc.', 1;

IF DB_ID(@RestoreDatabase) IS NOT NULL
    THROW 52002, N'Database SkyGo_Cnpm_RestoreTest da ton tai. Script dung de tranh ghi de; hay doi ten database dich hoac tu xoa ban test cu sau khi kiem tra.', 1;

PRINT N'BUOC 1 - FULL BACKUP';
SET @SQL = N'BACKUP DATABASE ' + QUOTENAME(@SourceDatabase)
    + N' TO DISK = N''' + REPLACE(@BackupPath, N'''', N'''''')
    + N''' WITH INIT, COMPRESSION, CHECKSUM, STATS = 10;';
EXEC sys.sp_executesql @SQL;

PRINT N'BUOC 2 - KIEM TRA BACKUP';
SET @SQL = N'RESTORE VERIFYONLY FROM DISK = N''' + REPLACE(@BackupPath, N'''', N'''''') + N''' WITH CHECKSUM;';
EXEC sys.sp_executesql @SQL;

PRINT N'BUOC 3 - KIEM TRA LOGICAL FILE NAME';
-- Xem cot LogicalName / Type. Neu khac hai gia tri mac dinh o phan CAU HINH,
-- sua @LogicalDataName / @LogicalLogName trong file va chay lai.
SET @SQL = N'RESTORE FILELISTONLY FROM DISK = N''' + REPLACE(@BackupPath, N'''', N'''''') + N''';';
EXEC sys.sp_executesql @SQL;

PRINT N'BUOC 4 - PHUC HOI SANG DATABASE THU RIENG';
SET @SQL = N'RESTORE DATABASE ' + QUOTENAME(@RestoreDatabase)
    + N' FROM DISK = N''' + REPLACE(@BackupPath, N'''', N'''''')
    + N''' WITH MOVE N''' + REPLACE(@LogicalDataName, N'''', N'''''')
    + N''' TO N''' + REPLACE(@RestoreDataPath, N'''', N'''''')
    + N''', MOVE N''' + REPLACE(@LogicalLogName, N'''', N'''''')
    + N''' TO N''' + REPLACE(@RestoreLogPath, N'''', N'''''')
    + N''', CHECKSUM, RECOVERY, STATS = 10;';
EXEC sys.sp_executesql @SQL;
UPDATE #SkyGoH04_RunStatus SET RestoreSucceeded = 1;
GO

/* BUOC 5 - DOI CHIEU DU LIEU
   Chi chay sau khi BUOC RESTORE thanh cong.
   Theo schema/seed: DON_DAT_VE, VE_CHUYEN_BAY, GIAO_DICH_TT;
   thanh toan thanh cong duoc nhan dien bang TrangThaiTT = 'SUCCESS'.
*/
USE master;
GO

IF OBJECT_ID(N'tempdb..#SkyGoH04_RunStatus') IS NULL
   OR NOT EXISTS (SELECT 1 FROM #SkyGoH04_RunStatus WHERE RestoreSucceeded = 1)
    THROW 52003, N'Backup/restore cua lan chay hien tai chua hoan tat thanh cong; khong doi chieu voi database cu.', 1;

IF DB_ID(N'SkyGo_Cnpm') IS NULL OR DB_ID(N'SkyGo_Cnpm_RestoreTest') IS NULL
    THROW 52004, N'Khong tim thay database nguon hoac ban phuc hoi thu.', 1;

SELECT N'So don dat ve' AS ChiTieu,
       CONVERT(DECIMAL(38,2), (SELECT COUNT_BIG(*) FROM SkyGo_Cnpm.dbo.DON_DAT_VE)) AS BanGoc,
       CONVERT(DECIMAL(38,2), (SELECT COUNT_BIG(*) FROM SkyGo_Cnpm_RestoreTest.dbo.DON_DAT_VE)) AS BanPhucHoi
UNION ALL
SELECT N'So ve chuyen bay',
       CONVERT(DECIMAL(38,2), (SELECT COUNT_BIG(*) FROM SkyGo_Cnpm.dbo.VE_CHUYEN_BAY)),
       CONVERT(DECIMAL(38,2), (SELECT COUNT_BIG(*) FROM SkyGo_Cnpm_RestoreTest.dbo.VE_CHUYEN_BAY))
UNION ALL
SELECT N'Tong tien giao dich SUCCESS',
       CONVERT(DECIMAL(38,2), COALESCE((SELECT SUM(SoTien) FROM SkyGo_Cnpm.dbo.GIAO_DICH_TT WHERE TrangThaiTT = 'SUCCESS'), 0)),
       CONVERT(DECIMAL(38,2), COALESCE((SELECT SUM(SoTien) FROM SkyGo_Cnpm_RestoreTest.dbo.GIAO_DICH_TT WHERE TrangThaiTT = 'SUCCESS'), 0));

DROP TABLE #SkyGoH04_RunStatus;
GO

/* XAC NHAN TINH TOAN DOI CHIEU
   Ket qua mong doi: cot BanGoc va BanPhucHoi bang nhau o ca 3 chi tieu.
   Voi seed DB-02 hien tai:
   - So don dat ve: 4
   - So ve chuyen bay: 6
   - Tong giao dich SUCCESS: 4,600,000 VND
   Neu database da duoc nhom cap nhat, so lieu co the khac; dieu can xac nhan
   la gia tri truoc va sau restore bang nhau.
*/
