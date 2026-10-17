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
        List<Map<String, Object>> rows = jdbc.queryForList(
            "EXEC dbo.usp_LayTaiKhoanDangNhap @TenDangNhap=?",
            identifier
        );

        if (rows.isEmpty() || !encoder.matches(req.password(), (String) rows.get(0).get("MatKhauHash"))) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Email hoặc mật khẩu không đúng.");
        }

        Map<String, Object> account = rows.get(0);
        if (!Boolean.TRUE.equals(account.get("TrangThai"))) {
            throw new ApiException(HttpStatus.FORBIDDEN, "Tài khoản đã bị khóa.");
        }

        long accountId = ((Number) account.get("MaTK")).longValue();
        Long customerId = account.get("MaKhachHang") == null ? null : ((Number) account.get("MaKhachHang")).longValue();
        String role = (String) account.get("VaiTro");
        String email = account.get("Email") != null ? (String) account.get("Email") : identifier;

        String fullName = "Quản trị viên";
        String phone = "";

        if (customerId != null) {
            List<Map<String, Object>> profiles = jdbc.queryForList(
                "EXEC dbo.usp_LayHoSoKhachHang @MaKhachHang=?",
                customerId
            );
            if (!profiles.isEmpty()) {
                Map<String, Object> profile = profiles.get(0);
                if (profile.get("HoTen") != null) fullName = (String) profile.get("HoTen");
                if (profile.get("SDT") != null) phone = (String) profile.get("SDT");
                if (profile.get("Email") != null) email = (String) profile.get("Email");
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
