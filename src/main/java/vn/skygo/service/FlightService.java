package vn.skygo.service;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import vn.skygo.api.ApiException;
import org.springframework.http.HttpStatus;
import vn.skygo.dto.Requests;
import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;

@Service
public class FlightService {
    private final JdbcTemplate jdbc;
    public FlightService(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    public List<Map<String,Object>> search(String origin, String destination, LocalDate date, int passengers) {
        if (origin.equalsIgnoreCase(destination)) throw new ApiException(HttpStatus.BAD_REQUEST, "Điểm đi và điểm đến phải khác nhau.");
        try {
            return jdbc.query("EXEC dbo.usp_TimChuyenBay @MaSanBayDi=?, @MaSanBayDen=?, @NgayBay=?, @SoHanhKhach=?",
                    (rs, n) -> flightMap(rs.getString("MaChuyenBay"), rs.getString("SoHieuChuyen"), rs.getString("MaSanBayDi"), rs.getString("MaSanBayDen"), rs.getTimestamp("GioCatCanh").toLocalDateTime(), rs.getTimestamp("GioDenDuKien").toLocalDateTime(), rs.getBigDecimal("GiaTu"), rs.getInt("SoChoCon")),
                    origin.toUpperCase(), destination.toUpperCase(), java.sql.Date.valueOf(date), passengers);
        } catch (Exception ex) {
            String sql = """
              SELECT cb.MaChuyenBay AS flightCode, cb.SoHieuChuyen AS flightNumber, cb.MaSanBayDi AS origin, cb.MaSanBayDen AS destination,
                     cb.GioCatCanh AS departure, cb.GioDenDuKien AS arrival, MIN(hv.GiaCoBan+hv.ThuePhi) AS price,
                     COUNT(DISTINCT g.MaGhe) - COUNT(DISTINCT v.MaVe) AS seatsAvailable
              FROM CHUYEN_BAY cb JOIN HANG_VE_CHUYEN_BAY hv ON hv.MaChuyenBay=cb.MaChuyenBay AND hv.TrangThai=1
              JOIN GHE_CHUYEN_BAY g ON g.MaChuyenBay=hv.MaChuyenBay AND g.HangVe=hv.HangVe
              LEFT JOIN VE_CHUYEN_BAY v ON v.MaChuyenBay=g.MaChuyenBay AND v.HangVe=g.HangVe AND v.TrangThai IN ('RESERVED','ISSUED','USED')
              WHERE cb.MaSanBayDi=? AND cb.MaSanBayDen=? AND CAST(cb.GioCatCanh AS date)=? AND cb.TrangThai IN ('SCHEDULED','DELAYED')
              GROUP BY cb.MaChuyenBay,cb.SoHieuChuyen,cb.MaSanBayDi,cb.MaSanBayDen,cb.GioCatCanh,cb.GioDenDuKien
              HAVING COUNT(DISTINCT g.MaGhe)-COUNT(DISTINCT v.MaVe) >= ? ORDER BY cb.GioCatCanh""";
            return jdbc.query(sql, (rs, n) -> flightMap(rs.getString("flightCode"), rs.getString("flightNumber"), rs.getString("origin"), rs.getString("destination"), rs.getTimestamp("departure").toLocalDateTime(), rs.getTimestamp("arrival").toLocalDateTime(), rs.getBigDecimal("price"), rs.getInt("seatsAvailable")), origin.toUpperCase(), destination.toUpperCase(), date, passengers);
        }
    }
    private Map<String,Object> flightMap(String code, String number, String origin, String destination, LocalDateTime dep, LocalDateTime arr, BigDecimal price, int seats) {
        long mins = Duration.between(dep, arr).toMinutes();
        LinkedHashMap<String,Object> m = new LinkedHashMap<>();
        m.put("flightCode", code == null ? "" : code.trim());
        m.put("flightNumber", number == null ? "" : number.trim());
        m.put("origin", origin == null ? "" : origin.trim());
        m.put("destination", destination == null ? "" : destination.trim());
        m.put("departure", dep);
        m.put("arrival", arr);
        m.put("departureTime", dep.toLocalTime().toString().substring(0, 5));
        m.put("arrivalTime", arr.toLocalTime().toString().substring(0, 5));
        m.put("departDate", dep.toLocalDate().toString());
        m.put("duration", (mins/60)+"h "+(mins%60)+"m");
        m.put("price", price);
        m.put("seatsAvailable", Math.max(0, seats));
        m.put("airline", "SkyGo Airways");
        return m;
    }
    public List<Map<String,Object>> airports() {
        return jdbc.query("SELECT MaSanBay AS code, TenSanBay AS name, ThanhPho AS city, QuocGia AS country FROM SAN_BAY WHERE TrangThai=1 ORDER BY MaSanBay",
                (rs,n) -> {
                    LinkedHashMap<String,Object> m = new LinkedHashMap<>();
                    String code = rs.getString("code") == null ? "" : rs.getString("code").trim();
                    String name = rs.getString("name") == null ? "" : rs.getString("name").trim();
                    String city = rs.getString("city") == null ? "" : rs.getString("city").trim();
                    String country = rs.getString("country") == null ? "" : rs.getString("country").trim();
                    m.put("code", code);
                    m.put("name", name);
                    m.put("city", city);
                    m.put("country", country);
                    m.put("label", city + " (" + code + ")");
                    return m;
                });
    }
    public List<Map<String,Object>> adminFlights() {
        String sql = """
          SELECT cb.MaChuyenBay,cb.SoHieuChuyen,cb.MaSanBayDi,cb.MaSanBayDen,cb.GioCatCanh,cb.GioDenDuKien,cb.TrangThai,
                 MIN(hv.GiaCoBan+hv.ThuePhi) AS price, COUNT(DISTINCT g.MaGhe) total, COUNT(DISTINCT v.MaVe) booked
          FROM CHUYEN_BAY cb LEFT JOIN HANG_VE_CHUYEN_BAY hv ON hv.MaChuyenBay=cb.MaChuyenBay
          LEFT JOIN GHE_CHUYEN_BAY g ON g.MaChuyenBay=hv.MaChuyenBay AND g.HangVe=hv.HangVe
          LEFT JOIN VE_CHUYEN_BAY v ON v.MaChuyenBay=g.MaChuyenBay AND v.HangVe=g.HangVe AND v.TrangThai IN ('RESERVED','ISSUED','USED')
          GROUP BY cb.MaChuyenBay,cb.SoHieuChuyen,cb.MaSanBayDi,cb.MaSanBayDen,cb.GioCatCanh,cb.GioDenDuKien,cb.TrangThai ORDER BY cb.GioCatCanh DESC""";
        return jdbc.query(sql, (rs,n) -> {
            LinkedHashMap<String,Object> m = new LinkedHashMap<>();
            m.put("flightCode", rs.getString(1).trim());
            m.put("flightNumber", rs.getString(2).trim());
            m.put("origin", rs.getString(3).trim());
            m.put("destination", rs.getString(4).trim());
            LocalDateTime dep = rs.getTimestamp(5).toLocalDateTime();
            LocalDateTime arr = rs.getTimestamp(6).toLocalDateTime();
            m.put("departTime", dep.toLocalDate().toString() + " " + dep.toLocalTime().toString().substring(0,5));
            m.put("arriveTime", arr.toLocalDate().toString() + " " + arr.toLocalTime().toString().substring(0,5));
            m.put("departDate", dep.toLocalDate().toString());
            String dbStatus = rs.getString(7);
            m.put("status", uiStatus(dbStatus));
            m.put("dbStatus", dbStatus);
            m.put("price", rs.getBigDecimal(8) == null ? BigDecimal.ZERO : rs.getBigDecimal(8));
            int total = rs.getInt(9);
            m.put("total", total == 0 ? 150 : total);
            m.put("booked", rs.getInt(10));
            m.put("aircraft", total >= 180 ? "A321" : (total == 162 ? "B737" : "A320"));
            return m;
        }, new Object[]{});
    }
    public void updateStatus(String code, String status) {
        String dbStatus = switch(status.toLowerCase()) {
            case "selling","scheduled" -> "SCHEDULED";
            case "delayed" -> "DELAYED";
            case "departed","checkin","boarding" -> "DEPARTED";
            case "cancelled" -> "CANCELLED";
            case "arrived" -> "ARRIVED";
            default -> throw new ApiException(HttpStatus.BAD_REQUEST,"Trạng thái không hợp lệ.");
        };
        if (jdbc.update("UPDATE CHUYEN_BAY SET TrangThai=? WHERE MaChuyenBay=? OR SoHieuChuyen=?", dbStatus, code, code) == 0)
            throw new ApiException(HttpStatus.NOT_FOUND,"Không tìm thấy chuyến bay.");
    }
    @Transactional
    public void createFlight(Requests.FlightUpsert req) {
        String code = req.flightCode();
        if (code == null || code.isBlank()) {
            code = "SG" + String.format("%03d", (int)(Math.random() * 899 + 100));
        }
        LocalDateTime dep = req.departure();
        LocalDateTime arr = req.arrival();
        if (arr.isBefore(dep)) arr = arr.plusHours(2);
        LocalDateTime openCheckin = dep.minusHours(24);
        LocalDateTime closeCheckin = dep.minusHours(1);
        String dbStatus = switch(req.status() == null ? "selling" : req.status().toLowerCase()) {
            case "delayed" -> "DELAYED";
            case "cancelled" -> "CANCELLED";
            case "departed" -> "DEPARTED";
            default -> "SCHEDULED";
        };
        jdbc.update("INSERT INTO CHUYEN_BAY(MaChuyenBay,SoHieuChuyen,GioCatCanh,GioDenDuKien,TrangThai,MoCheckInLuc,DongCheckInLuc,MaSanBayDi,MaSanBayDen) VALUES(?,?,?,?,?,?,?,?,?)",
                code, req.flightNumber().trim().toUpperCase(), Timestamp.valueOf(dep), Timestamp.valueOf(arr), dbStatus, Timestamp.valueOf(openCheckin), Timestamp.valueOf(closeCheckin), req.origin().trim().toUpperCase(), req.destination().trim().toUpperCase());

        BigDecimal base = req.basePrice();
        BigDecimal tax = req.tax() != null ? req.tax() : base.multiply(new BigDecimal("0.1"));
        jdbc.update("INSERT INTO HANG_VE_CHUYEN_BAY(MaChuyenBay,HangVe,GiaCoBan,ThuePhi,TrangThai) VALUES(?,?,?,?,?)",
                code, "ECONOMY", base, tax, true);
        jdbc.update("INSERT INTO HANG_VE_CHUYEN_BAY(MaChuyenBay,HangVe,GiaCoBan,ThuePhi,TrangThai) VALUES(?,?,?,?,?)",
                code, "BUSINESS", base.multiply(new BigDecimal("1.8")), tax.multiply(new BigDecimal("1.5")), true);

        // Generate standard seats: 8 business seats + 36 economy seats
        String[] busSeats = {"01A","01B","01C","01D","02A","02B","02C","02D"};
        for (String s : busSeats) {
            jdbc.update("INSERT INTO GHE_CHUYEN_BAY(MaChuyenBay,HangVe,SoGhe) VALUES(?,?,?)", code, "BUSINESS", s);
        }
        String[] cols = {"A","B","C","D","E","F"};
        for (int r = 3; r <= 8; r++) {
            for (String c : cols) {
                jdbc.update("INSERT INTO GHE_CHUYEN_BAY(MaChuyenBay,HangVe,SoGhe) VALUES(?,?,?)", code, "ECONOMY", String.format("%02d%s", r, c));
            }
        }
    }
    @Transactional
    public void deleteFlight(String code) {
        Integer booked = jdbc.queryForObject("SELECT COUNT(*) FROM VE_CHUYEN_BAY WHERE MaChuyenBay=? OR MaChuyenBay=(SELECT TOP 1 MaChuyenBay FROM CHUYEN_BAY WHERE SoHieuChuyen=?)", Integer.class, code, code);
        if (booked != null && booked > 0) {
            jdbc.update("UPDATE CHUYEN_BAY SET TrangThai='CANCELLED' WHERE MaChuyenBay=? OR SoHieuChuyen=?", code, code);
        } else {
            jdbc.update("DELETE FROM GHE_CHUYEN_BAY WHERE MaChuyenBay=? OR MaChuyenBay=(SELECT TOP 1 MaChuyenBay FROM CHUYEN_BAY WHERE SoHieuChuyen=?)", code, code);
            jdbc.update("DELETE FROM HANG_VE_CHUYEN_BAY WHERE MaChuyenBay=? OR MaChuyenBay=(SELECT TOP 1 MaChuyenBay FROM CHUYEN_BAY WHERE SoHieuChuyen=?)", code, code);
            jdbc.update("DELETE FROM CHUYEN_BAY WHERE MaChuyenBay=? OR SoHieuChuyen=?", code, code);
        }
    }
    private String uiStatus(String status) { return switch(status) { case "DEPARTED","ARRIVED" -> "departed"; case "CANCELLED" -> "cancelled"; case "DELAYED" -> "delayed"; default -> "selling"; }; }
}
