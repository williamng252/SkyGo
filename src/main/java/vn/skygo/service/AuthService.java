package vn.skygo.service;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import vn.skygo.api.ApiException;
import vn.skygo.dto.Requests;
import vn.skygo.security.SessionService;

import java.util.*;

@Service
public class AuthService {
    private final JdbcTemplate jdbc;
    private final PasswordEncoder encoder;
    private final SessionService sessions;

    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(AuthService.class);

    public AuthService(JdbcTemplate jdbc, PasswordEncoder encoder, SessionService sessions) {
        this.jdbc = jdbc;
        this.encoder = encoder;
        this.sessions = sessions;
    }

    @Transactional
    public void register(Requests.Register req) {
        String email = req.email().trim().toLowerCase();
        String username = usernameFor(email);
        String hash = encoder.encode(req.password());
        try {
            jdbc.queryForMap(
                "EXEC dbo.usp_DangKy @TenDangNhap=?, @Email=?, @MatKhauHash=?, @HoTen=?, @SDT=?",
                username, email, hash, req.fullName().trim(), emptyToNull(req.phone())
            );
        } catch (DataAccessException ex) {
            String msg = ex.getMessage();
            if (msg != null && (msg.contains("50003") || msg.contains("da ton tai") || msg.contains("UQ_TAIKHOAN"))) {
                throw new ApiException(HttpStatus.CONFLICT, "Tên đăng nhập hoặc email này đã tồn tại.");
            }
            throw new ApiException(HttpStatus.BAD_REQUEST, "Đăng ký thất bại: " + (msg != null && msg.contains(":") ? msg.substring(msg.lastIndexOf(":") + 1).trim() : "Dữ liệu không hợp lệ."));
        }
    }

    public Map<String, Object> login(Requests.Login req) {
        String identifier = req.email().trim().toLowerCase();
        // Support README demo alias admin@skygo.vn
        if ("admin@skygo.vn".equalsIgnoreCase(identifier)) {
            identifier = "admin@example.com";
        }

        List<Map<String, Object>> rows;
        try {
            rows = jdbc.queryForList(
                "EXEC dbo.usp_LayTaiKhoanDangNhap @TenDangNhap=?",
                identifier
            );
        } catch (DataAccessException ex) {
            log.error("Database error while loading login account for {}: {}", identifier, ex.getMessage());
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "Không thể kết nối đến cơ sở dữ liệu để xác thực. Vui lòng thử lại.");
        }

        if (rows.isEmpty()) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Email hoặc mật khẩu không đúng.");
        }

        Map<String, Object> account = rows.get(0);
        String hash = account.get("MatKhauHash") != null ? account.get("MatKhauHash").toString() : "";
        boolean matches = false;
        try {
            matches = !hash.isEmpty() && encoder.matches(req.password(), hash);
        } catch (Exception ex) {
            log.warn("Password match check failed for {}: {}", identifier, ex.getMessage());
            matches = false;
        }

        if (!matches) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Email hoặc mật khẩu không đúng.");
        }

        Object trangThaiObj = account.get("TrangThai");
        if (trangThaiObj == null) trangThaiObj = account.get("trangthai");
        boolean isActive = Boolean.TRUE.equals(trangThaiObj) || (trangThaiObj instanceof Number n && n.intValue() == 1);
        if (!isActive) {
            throw new ApiException(HttpStatus.FORBIDDEN, "Tài khoản đã bị khóa.");
        }

        Object maTK = account.get("MaTK");
        if (maTK == null) maTK = account.get("matk");
        long accountId = maTK instanceof Number n ? n.longValue() : 0L;

        Object maKH = account.get("MaKhachHang");
        if (maKH == null) maKH = account.get("makhachhang");
        Long customerId = maKH instanceof Number n ? n.longValue() : null;

        Object roleObj = account.get("VaiTro");
        if (roleObj == null) roleObj = account.get("vaitro");
        String role = roleObj != null ? roleObj.toString().trim().toUpperCase() : "CUSTOMER";

        Object emailObj = account.get("Email");
        if (emailObj == null) emailObj = account.get("email");
        String email = emailObj != null ? emailObj.toString().trim() : identifier;

        String fullName = "ADMIN".equalsIgnoreCase(role) ? "Quản trị viên" : "Khách hàng";
        String phone = "";

        if (customerId != null) {
            try {
                List<Map<String, Object>> profiles = jdbc.queryForList(
                    "EXEC dbo.usp_LayHoSoKhachHang @MaKhachHang=?",
                    customerId
                );
                if (!profiles.isEmpty()) {
                    Map<String, Object> profile = profiles.get(0);
                    if (profile.get("HoTen") != null) fullName = profile.get("HoTen").toString();
                    if (profile.get("SDT") != null) phone = profile.get("SDT").toString();
                    if (profile.get("Email") != null) email = profile.get("Email").toString();
                }
            } catch (Exception ex) {
                log.warn("Could not load customer profile for customer ID {}: {}", customerId, ex.getMessage());
            }
        }

        String token = sessions.create(new SessionService.Principal(accountId, customerId, email, role));

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("token", token);
        result.put("email", email);
        result.put("fullName", fullName);
        result.put("phone", phone);
        result.put("role", "ADMIN".equalsIgnoreCase(role) ? "admin" : "user");
        return result;
    }

    public Map<String, Object> me(HttpServletRequest request) {
        SessionService.Principal p = sessions.requireUser(request);
        if (p.customerId() != null) {
            List<Map<String, Object>> profiles = jdbc.queryForList(
                "EXEC dbo.usp_LayHoSoKhachHang @MaKhachHang=?",
                p.customerId()
            );
            if (!profiles.isEmpty()) {
                Map<String, Object> row = profiles.get(0);
                return Map.of(
                    "email", row.get("Email") != null ? row.get("Email") : p.email(),
                    "fullName", row.get("HoTen") != null ? row.get("HoTen") : "",
                    "phone", row.get("SDT") != null ? row.get("SDT") : "",
                    "role", "ADMIN".equalsIgnoreCase(p.role()) ? "admin" : "user"
                );
            }
        }
        return Map.of(
            "email", p.email(),
            "fullName", "Quản trị viên",
            "phone", "",
            "role", "ADMIN".equalsIgnoreCase(p.role()) ? "admin" : "user"
        );
    }

    @Transactional
    public Map<String, Object> updateProfile(HttpServletRequest request, Requests.Profile req) {
        SessionService.Principal p = sessions.requireUser(request);
        if (p.customerId() == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Tài khoản quản trị không có hồ sơ khách hàng.");
        }

        jdbc.queryForList(
            "EXEC dbo.usp_CapNhatHoSoKhachHang @MaKhachHang=?, @HoTen=?, @SDT=?",
            p.customerId(), req.fullName().trim(), emptyToNull(req.phone())
        );

        if (req.newPassword() != null && !req.newPassword().isBlank()) {
            if (req.newPassword().length() < 6) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "Mật khẩu mới phải có ít nhất 6 ký tự.");
            }
            jdbc.update(
                "EXEC dbo.usp_DoiMatKhau @MaTK=?, @MatKhauHash=?",
                p.accountId(), encoder.encode(req.newPassword())
            );
        }

        return me(request);
    }

    private String usernameFor(String email) {
        String s = email.substring(0, email.indexOf('@')).replaceAll("[^a-zA-Z0-9_]", "_");
        return s.length() < 3 ? "user_" + s : s.substring(0, Math.min(45, s.length()));
    }

    private String emptyToNull(String s) {
        return (s == null || s.trim().isEmpty()) ? null : s.trim();
    }
}
