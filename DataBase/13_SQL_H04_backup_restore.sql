/* SKYGO - SQL-H04: FULL BACKUP VA PHUC HOI THU
   Chay rieng trong SSMS, sau khi cai xong cac file 01-12.
   Tao thu muc C:\SQLBackup tren may chay SQL Server truoc.
   Tai khoan dich vu SQL Server can quyen doc/ghi thu muc nay.
   Chay bang tai khoan quan tri co quyen backup va tao database.
   Tam dung cac thao tac ghi du lieu / doi schema trong luc chay.
   Khong chay ben trong BEGIN TRAN cua file kiem thu khac.
   File nay danh cho schema co 1 file data va 1 file log.
   Neu database thu da ton tai, doi ten dich; khong tu xoa ban cu.
   Chua thuc thi kiem thu tren SQL Server tai moi truong soan file.
*/
USE master;
GO
SET NOCOUNT ON;

-- Cau hinh: chi sua hai ten database va thu muc nay neu can.
DECLARE @SourceDatabase SYSNAME = N'SkyGo_Cnpm';
DECLARE @RestoreDatabase SYSNAME = N'SkyGo_Cnpm_RestoreTest';
DECLARE @Folder NVARCHAR(2000) = N'C:\SQLBackup\';

DECLARE @RunId VARCHAR(32) = REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', '');
DECLARE @BackupPath NVARCHAR(4000);
DECLARE @RestoreDataPath NVARCHAR(4000);
DECLARE @RestoreLogPath NVARCHAR(4000);
DECLARE @LogicalDataName SYSNAME;
DECLARE @LogicalLogName SYSNAME;
DECLARE @SQL NVARCHAR(MAX);

BEGIN TRY
    IF @@TRANCOUNT > 0
        THROW 52000, N'Hay chay file nay rieng, ngoai giao tac BEGIN TRAN.', 1;

    IF DB_ID(@SourceDatabase) IS NULL
        THROW 52001, N'Khong tim thay database nguon. Hay chay schema/seed truoc.', 1;

    IF @SourceDatabase = @RestoreDatabase OR DB_ID(@RestoreDatabase) IS NOT NULL
        THROW 52002, N'Database dich da ton tai hoac trung database nguon. Hay doi ten dich.', 1;

    IF NOT EXISTS (SELECT 1 FROM sys.databases
                   WHERE name = @SourceDatabase AND state_desc = N'ONLINE')
        THROW 52003, N'Database nguon chua ONLINE.', 1;

    IF (SELECT COUNT(*) FROM sys.master_files WHERE database_id = DB_ID(@SourceDatabase)) <> 2
       OR (SELECT COUNT(*) FROM sys.master_files
           WHERE database_id = DB_ID(@SourceDatabase) AND type = 0) <> 1
       OR (SELECT COUNT(*) FROM sys.master_files
           WHERE database_id = DB_ID(@SourceDatabase) AND type = 1) <> 1
        THROW 52004, N'Script nay chi ho tro 1 file data va 1 file log. Can bo sung MOVE neu co them file.', 1;

    SELECT @LogicalDataName = name FROM sys.master_files
    WHERE database_id = DB_ID(@SourceDatabase) AND type = 0;
    SELECT @LogicalLogName = name FROM sys.master_files
    WHERE database_id = DB_ID(@SourceDatabase) AND type = 1;

    IF NULLIF(LTRIM(RTRIM(@Folder)), N'') IS NULL
        THROW 52005, N'Can dien thu muc backup.', 1;

    IF RIGHT(@Folder, 1) NOT IN (N'\', N'/')
        SET @Folder = @Folder + N'\';

    -- Ten file rieng cho moi lan chay, tranh trung file cua lan truoc.
    SET @BackupPath = @Folder + N'SkyGo_Full_' + @RunId + N'.bak';
    SET @RestoreDataPath = @Folder + N'SkyGo_Restore_' + @RunId + N'.mdf';
    SET @RestoreLogPath = @Folder + N'SkyGo_Restore_' + @RunId + N'_log.ldf';

    SELECT @SourceDatabase AS DatabaseNguon, @RestoreDatabase AS DatabaseThu,
           @BackupPath AS FileBackup, @RestoreDataPath AS FileDataThu,
           @RestoreLogPath AS FileLogThu;

    PRINT N'BUOC 1 - FULL BACKUP';
    -- COPY_ONLY: khong doi moc cua chuoi differential backup hien co.
    -- NO_COMPRESSION: dung duoc ca voi SQL Server Express.
    SET @SQL = N'BACKUP DATABASE ' + QUOTENAME(@SourceDatabase)
        + N' TO DISK = N''' + REPLACE(@BackupPath, N'''', N'''''')
        + N''' WITH COPY_ONLY, NO_COMPRESSION, CHECKSUM, STATS = 10;';
    EXEC sys.sp_executesql @SQL;

    PRINT N'BUOC 2 - KIEM TRA BACKUP';
    SET @SQL = N'RESTORE VERIFYONLY FROM DISK = N'''
        + REPLACE(@BackupPath, N'''', N'''''') + N''' WITH CHECKSUM;';
    EXEC sys.sp_executesql @SQL;

    PRINT N'BUOC 3 - XEM FILE TRONG BACKUP';
    SET @SQL = N'RESTORE FILELISTONLY FROM DISK = N'''
        + REPLACE(@BackupPath, N'''', N'''''') + N''';';
    EXEC sys.sp_executesql @SQL;

    PRINT N'BUOC 4 - PHUC HOI SANG DATABASE THU';
    -- Kiem tra lai truoc restore, khong dung WITH REPLACE.
    IF DB_ID(@RestoreDatabase) IS NOT NULL
        THROW 52006, N'Database dich vua duoc tao boi phien khac. Dung phuc hoi.', 1;

    SET @SQL = N'RESTORE DATABASE ' + QUOTENAME(@RestoreDatabase)
        + N' FROM DISK = N''' + REPLACE(@BackupPath, N'''', N'''''')
        + N''' WITH MOVE N''' + REPLACE(@LogicalDataName, N'''', N'''''')
        + N''' TO N''' + REPLACE(@RestoreDataPath, N'''', N'''''')
        + N''', MOVE N''' + REPLACE(@LogicalLogName, N'''', N'''''')
        + N''' TO N''' + REPLACE(@RestoreLogPath, N'''', N'''''')
        + N''', CHECKSUM, RECOVERY, STATS = 10;';
    EXEC sys.sp_executesql @SQL;

    IF NOT EXISTS (SELECT 1 FROM sys.databases
                   WHERE name = @RestoreDatabase AND state_desc = N'ONLINE')
        THROW 52007, N'Database phuc hoi chua ONLINE; khong doi chieu.', 1;

    PRINT N'BUOC 5 - DOI CHIEU DU LIEU';
    -- Dung bien ten database cho ca phan doi chieu.
    -- SQL dong cung giup bat loi thieu bang trong CATCH.
    DECLARE @SourcePrefix NVARCHAR(300) = QUOTENAME(@SourceDatabase) + N'.dbo.';
    DECLARE @RestorePrefix NVARCHAR(300) = QUOTENAME(@RestoreDatabase) + N'.dbo.';

    CREATE TABLE #DoiChieu (
        ChiTieu NVARCHAR(100) NOT NULL,
        BanGoc DECIMAL(38,2) NOT NULL,
        BanPhucHoi DECIMAL(38,2) NOT NULL
    );

    SET @SQL = N'INSERT INTO #DoiChieu (ChiTieu, BanGoc, BanPhucHoi)
        SELECT N''So don dat ve'',
          (SELECT COUNT_BIG(*) FROM ' + @SourcePrefix + N'DON_DAT_VE),
          (SELECT COUNT_BIG(*) FROM ' + @RestorePrefix + N'DON_DAT_VE)
        UNION ALL
        SELECT N''So ve chuyen bay'',
          (SELECT COUNT_BIG(*) FROM ' + @SourcePrefix + N'VE_CHUYEN_BAY),
          (SELECT COUNT_BIG(*) FROM ' + @RestorePrefix + N'VE_CHUYEN_BAY)
        UNION ALL
        SELECT N''Tong tien giao dich SUCCESS'',
          COALESCE((SELECT SUM(SoTien) FROM ' + @SourcePrefix + N'GIAO_DICH_TT
                    WHERE TrangThaiTT = ''SUCCESS''), 0),
          COALESCE((SELECT SUM(SoTien) FROM ' + @RestorePrefix + N'GIAO_DICH_TT
                    WHERE TrangThaiTT = ''SUCCESS''), 0);';
    EXEC sys.sp_executesql @SQL;

    SELECT ChiTieu, BanGoc, BanPhucHoi,
           CASE WHEN BanGoc = BanPhucHoi THEN N'KHOP' ELSE N'LECH' END AS KetQua
    FROM #DoiChieu;

    DECLARE @CoChenhLech BIT = 0;
    IF EXISTS (SELECT 1 FROM #DoiChieu WHERE BanGoc <> BanPhucHoi)
        SET @CoChenhLech = 1;
    DROP TABLE #DoiChieu;

    IF @CoChenhLech = 1
        THROW 52008, N'Ba chi tieu chua khop. Kiem tra co ghi du lieu vao ban goc trong luc backup/doi chieu khong.', 1;

    PRINT N'HOAN TAT: backup, restore va ba chi tieu doi chieu deu thanh cong.';
    PRINT N'Day la kiem tra co ban, khong thay the doi chieu toan bo du lieu.';
END TRY
BEGIN CATCH
    IF OBJECT_ID(N'tempdb..#DoiChieu') IS NOT NULL
        DROP TABLE #DoiChieu;
    PRINT N'DUNG: co loi, xem thong bao ben duoi. Khong tu xoa file hay database thu.';
    THROW;
END CATCH;
GO

/* Seed DB-02 chua thay doi: 4 don, 6 ve, SUCCESS = 4600000 VND.
   Neu da them du lieu, so lieu khac van hop le khi ca 3 dong KHOP.
   Sau khi chay: chup bang doi chieu va luu thong bao backup/restore.
   Chi dua file .sql len Git; file .bak/.mdf/.ldf giu tai may.
   Tai lieu: https://learn.microsoft.com/en-us/sql/t-sql/statements/backup-transact-sql
   https://learn.microsoft.com/en-us/sql/t-sql/statements/restore-statements-arguments-transact-sql
*/
