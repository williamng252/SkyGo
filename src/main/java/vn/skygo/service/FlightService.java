package vn.skygo.service;

import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import vn.skygo.api.ApiException;
import vn.skygo.dto.Requests;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;

@Service
public class FlightService {
    private final JdbcTemplate jdbc;

    public FlightService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Map<String, Object>> search(String origin, String destination, LocalDate date, int passengers) {
        if (origin.equalsIgnoreCase(destination)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Điểm đi và điểm đến phải khác nhau.");
        }
        if (passengers < 1 || passengers > 9) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Số hành khách phải từ 1 đến 9.");
        }

        try {
            return jdbc.query(
                "EXEC dbo.usp_TimChuyenBay @MaSanBayDi=?, @MaSanBayDen=?, @NgayDi=?, @SoHanhKhach=?",
                (rs, n) -> {
                    String code = rs.getString("MaChuyenBay");
                    String number = rs.getString("SoHieuChuyen");
                    String orig = rs.getString("MaSanBayDi");
                    String dest = rs.getString("MaSanBayDen");
                    LocalDateTime dep = rs.getTimestamp("GioCatCanh").toLocalDateTime();
                    LocalDateTime arr = rs.getTimestamp("GioDenDuKien").toLocalDateTime();
                    BigDecimal price = rs.getBigDecimal("GiaVe");
                    int seats = rs.getInt("SoChoCon");
                    String fareClass = rs.getString("HangVe");

                    Map<String, Object> m = flightMap(code, number, orig, dest, dep, arr, price, seats);
                    m.put("fareClass", fareClass);
                    return m;
                },
                origin.toUpperCase().trim(),
                destination.toUpperCase().trim(),
                java.sql.Date.valueOf(date),
                passengers
            );
        } catch (DataAccessException ex) {
            String msg = ex.getMessage();
            throw new ApiException(HttpStatus.BAD_REQUEST, "Lỗi tìm chuyến bay: " + (msg != null && msg.contains(":") ? msg.substring(msg.lastIndexOf(":") + 1).trim() : msg));
        }
    }

    private Map<String, Object> flightMap(String code, String number, String origin, String destination,
                                          LocalDateTime dep, LocalDateTime arr, BigDecimal price, int seats) {
        long mins = Math.max(0, Duration.between(dep, arr).toMinutes());
        LinkedHashMap<String, Object> m = new LinkedHashMap<>();
        m.put("flightCode", code == null ? "" : code.trim());
        m.put("flightNumber", number == null ? "" : number.trim());
        m.put("origin", origin == null ? "" : origin.trim());
        m.put("destination", destination == null ? "" : destination.trim());
        m.put("departure", dep);
        m.put("arrival", arr);
        m.put("departureTime", dep.toLocalTime().toString().substring(0, 5));
        m.put("arrivalTime", arr.toLocalTime().toString().substring(0, 5));
        m.put("departDate", dep.toLocalDate().toString());
        m.put("duration", (mins / 60) + "h " + (mins % 60) + "m");
        m.put("price", price != null ? price : BigDecimal.ZERO);
        m.put("seatsAvailable", Math.max(0, seats));
        m.put("airline", "SkyGo Airways");
        return m;
    }

    public List<Map<String, Object>> airports() {
        return jdbc.query("EXEC dbo.usp_LayDanhSachSanBay", (rs, n) -> {
            LinkedHashMap<String, Object> m = new LinkedHashMap<>();
            String code = rs.getString("MaSanBay") == null ? "" : rs.getString("MaSanBay").trim();
            String name = rs.getString("TenSanBay") == null ? "" : rs.getString("TenSanBay").trim();
            String city = rs.getString("ThanhPho") == null ? "" : rs.getString("ThanhPho").trim();
            String country = rs.getString("QuocGia") == null ? "" : rs.getString("QuocGia").trim();
            m.put("code", code);
            m.put("name", name);
            m.put("city", city);
            m.put("country", country);
            m.put("label", city + " (" + code + ")");
            return m;
        });
    }

    public List<Map<String, Object>> adminFlights() {
        // Use dbo.usp_AdminLayChuyenBay for listing all flights
        List<Map<String, Object>> flights = jdbc.query("EXEC dbo.usp_AdminLayChuyenBay", (rs, n) -> {
            LinkedHashMap<String, Object> m = new LinkedHashMap<>();
            m.put("flightCode", rs.getString("MaChuyenBay").trim());
            m.put("flightNumber", rs.getString("SoHieuChuyen").trim());
            m.put("origin", rs.getString("MaSanBayDi").trim());
            m.put("destination", rs.getString("MaSanBayDen").trim());
            LocalDateTime dep = rs.getTimestamp("GioCatCanh").toLocalDateTime();
            LocalDateTime arr = rs.getTimestamp("GioDenDuKien").toLocalDateTime();
            m.put("departTime", dep.toLocalDate().toString() + " " + dep.toLocalTime().toString().substring(0, 5));
            m.put("arriveTime", arr.toLocalDate().toString() + " " + arr.toLocalTime().toString().substring(0, 5));
            m.put("departDate", dep.toLocalDate().toString());
            String dbStatus = rs.getString("TrangThai");
            m.put("status", uiStatus(dbStatus));
            m.put("dbStatus", dbStatus);
            m.put("reason", rs.getString("LyDoThayDoi"));
            return m;
        });

        // Enrich with seat statistics and pricing
        for (Map<String, Object> f : flights) {
            String code = (String) f.get("flightCode");
            List<Map<String, Object>> stats = jdbc.queryForList("""
                SELECT
                    ISNULL((SELECT MIN(GiaCoBan+ThuePhi) FROM HANG_VE_CHUYEN_BAY WHERE MaChuyenBay=?), 0) AS minPrice,
                    (SELECT COUNT(*) FROM GHE_CHUYEN_BAY WHERE MaChuyenBay=?) AS totalSeats,
                    (SELECT COUNT(*) FROM VE_CHUYEN_BAY WHERE MaChuyenBay=? AND TrangThai IN ('RESERVED','ISSUED','USED')) AS bookedSeats
            """, code, code, code);

            if (!stats.isEmpty()) {
                Map<String, Object> row = stats.get(0);
                BigDecimal minPrice = (BigDecimal) row.get("minPrice");
                int total = ((Number) row.get("totalSeats")).intValue();
                int booked = ((Number) row.get("bookedSeats")).intValue();
                f.put("price", minPrice != null ? minPrice : BigDecimal.ZERO);
                f.put("total", total == 0 ? 150 : total);
                f.put("booked", booked);
                f.put("aircraft", total >= 180 ? "A321" : (total == 162 ? "B737" : "A320"));
            } else {
                f.put("price", BigDecimal.ZERO);
                f.put("total", 150);
                f.put("booked", 0);
                f.put("aircraft", "A320");
            }
        }

        return flights;
    }

    public void updateStatus(String code, String status) {
        String dbStatus = switch (status.toLowerCase()) {
            case "selling", "scheduled" -> "SCHEDULED";
            case "delayed" -> "DELAYED";
            case "departed", "checkin", "boarding" -> "DEPARTED";
            case "cancelled" -> "CANCELLED";
            case "arrived" -> "ARRIVED";
            default -> throw new ApiException(HttpStatus.BAD_REQUEST, "Trạng thái không hợp lệ: " + status);
        };

        String realCode = resolveFlightCode(code);
        String reason = "CANCELLED".equals(dbStatus) ? "Hủy chuyến theo yêu cầu quản trị viên"
            : ("DELAYED".equals(dbStatus) ? "Thay đổi lịch trình vận hành" : null);

        try {
            jdbc.queryForList(
                "EXEC dbo.usp_AdminCapNhatTrangThaiChuyenBay @MaChuyenBay=?, @TrangThai=?, @LyDoThayDoi=?",
                realCode, dbStatus, reason
            );
        } catch (DataAccessException ex) {
            String msg = ex.getMessage();
            throw new ApiException(HttpStatus.BAD_REQUEST, "Không thể cập nhật trạng thái: " + (msg != null && msg.contains(":") ? msg.substring(msg.lastIndexOf(":") + 1).trim() : msg));
        }
    }

    @Transactional
    public void createFlight(Requests.FlightUpsert req) {
        String code = req.flightCode();
        if (code == null || code.isBlank()) {
            code = "SG" + String.format("%03d", (int) (Math.random() * 899 + 100));
        } else {
            code = code.trim().toUpperCase();
        }

        LocalDateTime dep = req.departure();
        LocalDateTime arr = req.arrival();
        if (arr.isBefore(dep)) arr = arr.plusHours(2);
        LocalDateTime openCheckin = dep.minusHours(24);
        LocalDateTime closeCheckin = dep.minusHours(1);

        try {
            // 1. Tao chuyen bay qua usp_AdminThemChuyenBay
            jdbc.queryForList(
                "EXEC dbo.usp_AdminThemChuyenBay @MaChuyenBay=?, @SoHieuChuyen=?, @GioCatCanh=?, @GioDenDuKien=?, @MoCheckInLuc=?, @DongCheckInLuc=?, @MaSanBayDi=?, @MaSanBayDen=?",
                code, req.flightNumber().trim().toUpperCase(), Timestamp.valueOf(dep), Timestamp.valueOf(arr),
                Timestamp.valueOf(openCheckin), Timestamp.valueOf(closeCheckin),
                req.origin().trim().toUpperCase(), req.destination().trim().toUpperCase()
            );

            // 2. Thiet lap gia hang ve qua usp_AdminLuuHangVe
            BigDecimal base = req.basePrice();
            BigDecimal tax = req.tax() != null ? req.tax() : base.multiply(new BigDecimal("0.1"));
            jdbc.queryForList(
                "EXEC dbo.usp_AdminLuuHangVe @MaChuyenBay=?, @HangVe='ECONOMY', @GiaCoBan=?, @ThuePhi=?, @TrangThai=1",
                code, base, tax
            );
            jdbc.queryForList(
                "EXEC dbo.usp_AdminLuuHangVe @MaChuyenBay=?, @HangVe='BUSINESS', @GiaCoBan=?, @ThuePhi=?, @TrangThai=1",
                code, base.multiply(new BigDecimal("1.8")), tax.multiply(new BigDecimal("1.5"))
            );

            // 3. Khoi tao ghe qua usp_AdminThemGhe
            String[] busSeats = {"01A", "01B", "01C", "01D", "02A", "02B", "02C", "02D"};
            for (String s : busSeats) {
                jdbc.queryForList(
                    "EXEC dbo.usp_AdminThemGhe @MaChuyenBay=?, @HangVe='BUSINESS', @SoGhe=?",
                    code, s
                );
            }

            String[] cols = {"A", "B", "C", "D", "E", "F"};
            for (int r = 3; r <= 8; r++) {
                for (String c : cols) {
                    jdbc.queryForList(
                        "EXEC dbo.usp_AdminThemGhe @MaChuyenBay=?, @HangVe='ECONOMY', @SoGhe=?",
                        code, String.format("%02d%s", r, c)
                    );
                }
            }
        } catch (DataAccessException ex) {
            String msg = ex.getMessage();
            throw new ApiException(HttpStatus.BAD_REQUEST, "Không thể tạo chuyến bay: " + (msg != null && msg.contains(":") ? msg.substring(msg.lastIndexOf(":") + 1).trim() : msg));
        }
    }

    @Transactional
    public void deleteFlight(String code) {
        String realCode = resolveFlightCode(code);
        Integer booked = jdbc.queryForObject(
            "SELECT COUNT(*) FROM VE_CHUYEN_BAY WHERE MaChuyenBay=?",
            Integer.class, realCode
        );

        if (booked != null && booked > 0) {
            // Chuyen da co ve: chuyen trang thai CANCELLED qua SP
            updateStatus(realCode, "CANCELLED");
        } else {
            jdbc.update("DELETE FROM GHE_CHUYEN_BAY WHERE MaChuyenBay=?", realCode);
            jdbc.update("DELETE FROM HANG_VE_CHUYEN_BAY WHERE MaChuyenBay=?", realCode);
            jdbc.update("DELETE FROM CHUYEN_BAY WHERE MaChuyenBay=?", realCode);
        }
    }

    private String resolveFlightCode(String input) {
        List<String> list = jdbc.queryForList(
            "SELECT MaChuyenBay FROM CHUYEN_BAY WHERE MaChuyenBay=? OR SoHieuChuyen=?",
            String.class, input, input
        );
        if (list.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Không tìm thấy chuyến bay: " + input);
        }
        return list.get(0).trim();
    }

    private String uiStatus(String status) {
        if (status == null) return "selling";
        return switch (status.toUpperCase()) {
            case "DEPARTED", "ARRIVED" -> "departed";
            case "CANCELLED" -> "cancelled";
            case "DELAYED" -> "delayed";
            default -> "selling";
        };
    }
}
