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

-- DB-08: ROLE O SQL SERVER, KHAC VOI VAI TRO CUSTOMER/ADMIN CUA WEBSITE.
-- Backend dung role_SkyGoApp; backend van phai kiem tra quyen tren tung yeu cau.
-- role_SkyGoBaoCao chi duoc goi SP thong ke va danh sach chuyen.
-- User WITHOUT LOGIN chi de minh hoa EXECUTE AS, khong dung dang nhap Java.
IF DATABASE_PRINCIPAL_ID('role_SkyGoApp') IS NULL
    CREATE ROLE role_SkyGoApp;
IF DATABASE_PRINCIPAL_ID('role_SkyGoBaoCao') IS NULL
    CREATE ROLE role_SkyGoBaoCao;
GO
GRANT EXECUTE ON OBJECT::dbo.usp_AdminCapNhatTrangThaiChuyenBay TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_AdminLayChuyenBay TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_AdminLuuHangVe TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_AdminSuaChuyenBay TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_AdminThemChuyenBay TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_AdminThemGhe TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_AdminThongKeBanVe TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_AdminTimDonDatVe TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_AdminTimKhachHang TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_CapNhatHoSoKhachHang TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_CheckIn TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_DangKy TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_DoiMatKhau TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_HuyDonDatVe TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_LayChiTietDon TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_LayDanhSachSanBay TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_LayGheKhaDung TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_LayHoSoKhachHang TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_LayLichSuDatVe TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_LayTaiKhoanDangNhap TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_LayTheLenMayBay TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_TaoDonDatVe TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_TimChuyenBay TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_TraCuuPNR TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_XacNhanThanhToanMoPhong TO role_SkyGoApp;
GRANT EXECUTE ON OBJECT::dbo.usp_XuLyDonHetHan TO role_SkyGoApp;

GRANT EXECUTE ON OBJECT::dbo.usp_AdminThongKeBanVe TO role_SkyGoBaoCao;
GRANT EXECUTE ON OBJECT::dbo.usp_AdminLayChuyenBay TO role_SkyGoBaoCao;

-- Chi cho thao tac du lieu thong qua SP (ownership chaining cung chu so huu dbo).
DENY SELECT,INSERT,UPDATE,DELETE ON SCHEMA::dbo TO role_SkyGoApp;
DENY SELECT,INSERT,UPDATE,DELETE ON SCHEMA::dbo TO role_SkyGoBaoCao;
GO

IF DATABASE_PRINCIPAL_ID('SkyGo_DemoApp') IS NULL
    CREATE USER SkyGo_DemoApp WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID('SkyGo_DemoBaoCao') IS NULL
    CREATE USER SkyGo_DemoBaoCao WITHOUT LOGIN;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members
    WHERE role_principal_id=DATABASE_PRINCIPAL_ID('role_SkyGoApp')
      AND member_principal_id=DATABASE_PRINCIPAL_ID('SkyGo_DemoApp'))
    ALTER ROLE role_SkyGoApp ADD MEMBER SkyGo_DemoApp;
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members
    WHERE role_principal_id=DATABASE_PRINCIPAL_ID('role_SkyGoBaoCao')
      AND member_principal_id=DATABASE_PRINCIPAL_ID('SkyGo_DemoBaoCao'))
    ALTER ROLE role_SkyGoBaoCao ADD MEMBER SkyGo_DemoBaoCao;
GO

-- MAU tao login cho Java: CHI chay khi da sua mat khau tren may minh.
-- Khong dua mat khau that vao GitHub. Khong dung sa de ket noi ung dung.
-- USE master;
-- CREATE LOGIN skygo_app WITH PASSWORD = 'THAY_MAT_KHAU_RIENG_TREN_MAY';
-- USE SkyGo_Cnpm;
-- CREATE USER skygo_app FOR LOGIN skygo_app;
-- ALTER ROLE role_SkyGoApp ADD MEMBER skygo_app;
