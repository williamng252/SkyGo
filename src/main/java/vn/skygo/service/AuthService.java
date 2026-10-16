package vn.skygo.service;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import vn.skygo.api.ApiException;
import vn.skygo.dto.Requests;
import vn.skygo.security.SessionService;
import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.util.*;

@Service
public class AuthService {
    private final JdbcTemplate jdbc; private final PasswordEncoder encoder; private final SessionService sessions;
    public AuthService(JdbcTemplate jdbc, PasswordEncoder encoder, SessionService sessions) { this.jdbc=jdbc; this.encoder=encoder; this.sessions=sessions; }

    @Transactional
    public void register(Requests.Register req) {
        Integer exists = jdbc.queryForObject("SELECT COUNT(*) FROM TAI_KHOAN_ND WHERE Email=?", Integer.class, req.email().trim().toLowerCase());
        if (exists != null && exists > 0) throw new ApiException(HttpStatus.CONFLICT, "Email này đã được đăng ký.");
        String username = usernameFor(req.email());
        int suffix = 1;
        while (Boolean.TRUE.equals(jdbc.queryForObject("SELECT CASE WHEN EXISTS(SELECT 1 FROM TAI_KHOAN_ND WHERE TenDangNhap=?) THEN 1 ELSE 0 END", Boolean.class, username))) username = usernameFor(req.email()) + (++suffix);
        Long customerId = jdbc.queryForObject("INSERT INTO KHACH_HANG(HoTen,SDT,Email) OUTPUT INSERTED.MaKhachHang VALUES(?,?,?)", Long.class, req.fullName().trim(), req.phone(), req.email().trim().toLowerCase());
        jdbc.update("INSERT INTO TAI_KHOAN_ND(TenDangNhap,Email,MatKhauHash,VaiTro,NgayTao,TrangThai,MaKhachHang) VALUES(?,?,?,?,?,?,?)", username, req.email().trim().toLowerCase(), encoder.encode(req.password()), "CUSTOMER", Timestamp.valueOf(LocalDateTime.now()), true, customerId);
    }
    public Map<String,Object> login(Requests.Login req) {
        List<Map<String,Object>> rows = jdbc.queryForList("SELECT tk.MaTK,tk.Email,tk.MatKhauHash,tk.VaiTro,tk.TrangThai,tk.MaKhachHang,kh.HoTen,kh.SDT FROM TAI_KHOAN_ND tk LEFT JOIN KHACH_HANG kh ON kh.MaKhachHang=tk.MaKhachHang WHERE tk.Email=?", req.email().trim().toLowerCase());
        if (rows.isEmpty() || !encoder.matches(req.password(), (String)rows.get(0).get("MatKhauHash"))) throw new ApiException(HttpStatus.UNAUTHORIZED, "Email hoặc mật khẩu không đúng.");
        Map<String,Object> row=rows.get(0); if (!(Boolean)row.get("TrangThai")) throw new ApiException(HttpStatus.FORBIDDEN,"Tài khoản đã bị khóa.");
        long accountId=((Number)row.get("MaTK")).longValue(); Long customerId=row.get("MaKhachHang")==null?null:((Number)row.get("MaKhachHang")).longValue(); String role=(String)row.get("VaiTro");
        String token=sessions.create(new SessionService.Principal(accountId,customerId,(String)row.get("Email"),role));
        Map<String,Object> result=new LinkedHashMap<>(); result.put("token",token); result.put("email",row.get("Email")); result.put("fullName", row.get("HoTen") == null ? "Quản trị viên" : row.get("HoTen")); result.put("phone",row.get("SDT")); result.put("role",role.equals("ADMIN")?"admin":"user"); return result;
    }
    public Map<String,Object> me(HttpServletRequest request) { SessionService.Principal p=sessions.requireUser(request); Map<String,Object> row=jdbc.queryForMap("SELECT tk.Email,tk.VaiTro,kh.HoTen,kh.SDT FROM TAI_KHOAN_ND tk LEFT JOIN KHACH_HANG kh ON kh.MaKhachHang=tk.MaKhachHang WHERE tk.MaTK=?",p.accountId()); return Map.of("email",row.get("Email"),"fullName",row.get("HoTen")==null?"Quản trị viên":row.get("HoTen"),"phone",row.get("SDT")==null?"":row.get("SDT"),"role","ADMIN".equals(row.get("VaiTro"))?"admin":"user"); }
    @Transactional
    public Map<String,Object> updateProfile(HttpServletRequest request, Requests.Profile req) {
        SessionService.Principal p=sessions.requireUser(request); if (p.customerId()==null) throw new ApiException(HttpStatus.BAD_REQUEST,"Tài khoản quản trị không có hồ sơ khách hàng.");
        jdbc.update("UPDATE KHACH_HANG SET HoTen=?, SDT=? WHERE MaKhachHang=?",req.fullName().trim(),req.phone(),p.customerId());
        if(req.newPassword()!=null&&!req.newPassword().isBlank()){if(req.newPassword().length()<6)throw new ApiException(HttpStatus.BAD_REQUEST,"Mật khẩu mới phải có ít nhất 6 ký tự."); jdbc.update("UPDATE TAI_KHOAN_ND SET MatKhauHash=? WHERE MaTK=?",encoder.encode(req.newPassword()),p.accountId());}
        return me(request);
    }
    private String usernameFor(String email) { String s=email.substring(0,email.indexOf('@')).replaceAll("[^a-zA-Z0-9_]", "_"); return s.length()<3 ? "user_"+s : s.substring(0,Math.min(45,s.length())); }
}
