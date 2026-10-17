package vn.skygo.security;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import vn.skygo.api.ApiException;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class SessionService {
    public record Principal(long accountId, Long customerId, String email, String role) {}
    private record Session(Principal principal, Instant expiresAt) {}
    private final Map<String, Session> sessions = new ConcurrentHashMap<>();
    public String create(Principal principal) {
        String token = UUID.randomUUID().toString();
        sessions.put(token, new Session(principal, Instant.now().plus(8, ChronoUnit.HOURS)));
        return token;
    }
    public Optional<Principal> optional(HttpServletRequest request) {
        if (request == null) return Optional.empty();
        String value = request.getHeader("Authorization");
        if (value == null || !value.startsWith("Bearer ")) return Optional.empty();
        Session session = sessions.get(value.substring(7));
        if (session == null || session.expiresAt().isBefore(Instant.now())) { sessions.remove(value.substring(7)); return Optional.empty(); }
        return Optional.of(session.principal());
    }
    public Principal requireUser(HttpServletRequest request) {
        return optional(request).orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "Bạn cần đăng nhập để thực hiện thao tác này."));
    }
    public Principal requireAdmin(HttpServletRequest request) {
        Principal p = requireUser(request);
        if (!"ADMIN".equals(p.role())) throw new ApiException(HttpStatus.FORBIDDEN, "Chỉ quản trị viên được phép thực hiện thao tác này.");
        return p;
    }
}
