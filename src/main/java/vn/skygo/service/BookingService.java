package vn.skygo.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import vn.skygo.api.ApiException;
import vn.skygo.dto.Requests;
import vn.skygo.security.SessionService;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;

@Service
public class BookingService {
    private final JdbcTemplate jdbc;
    private final SessionService sessions;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public BookingService(JdbcTemplate jdbc, SessionService sessions) {
        this.jdbc = jdbc;
        this.sessions = sessions;
    }

    public Map<String, Object> flightSeatMap(String flightCode) {
        String code = resolveFlightCode(flightCode);
        return Map.of("flightCode", code, "seats", jdbc.queryForList("""
            SELECT g.SoGhe AS seat, g.HangVe AS fareClass,
                CASE WHEN EXISTS (SELECT 1 FROM dbo.CHECK_IN c
                    WHERE c.MaGhe=g.MaGhe AND c.TrangThai='CHECKED_IN') THEN 1 ELSE 0 END AS taken
            FROM dbo.GHE_CHUYEN_BAY g WHERE g.MaChuyenBay=? ORDER BY g.SoGhe
            """, code));
    }

    @Transactional
    public Map<String, Object> create(HttpServletRequest request, Requests.Booking req) {
        if (req.passengers() == null || req.passengers().isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Đơn đặt vé cần ít nhất 1 hành khách.");
        }
        if (req.passengers().size() > 9) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Mỗi đơn chỉ tối đa 9 hành khách.");
        }

        SessionService.Principal principal = sessions.optional(request).orElse(null);
        Long customerId = principal != null ? principal.customerId() : null;

        // Resolve flight code
        String flightCode = resolveFlightCode(req.flightNumber());

        // Contact info
        Requests.Passenger contact = req.passengers().get(0);
        String contactName = fullName(contact);
        String contactEmail = principal != null && principal.email() != null ? principal.email() : "guest@skygo.local";
        String contactPhone = "0900000000";

        // Build Passenger JSON
        List<Map<String, Object>> paxList = new ArrayList<>();
        for (Requests.Passenger p : req.passengers()) {
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("HoTen", fullName(p));
            LocalDate dob = p.dateOfBirth();
            if (dob == null || dob.isAfter(LocalDate.now(java.time.ZoneId.of("Asia/Ho_Chi_Minh")))) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "Ngày sinh không hợp lệ.");
            }
            item.put("NgaySinh", dob.toString());
            item.put("GioiTinh", gender(p.gender()));
            item.put("LoaiGiayTo", "CCCD");
            String doc = (p.documentNumber() != null && !p.documentNumber().isBlank())
                ? p.documentNumber().trim()
                : String.format("%012d", (long) (Math.random() * 899999999999L + 100000000000L));
            item.put("SoGiayTo", doc);
            item.put("QuocTich", "Viet Nam");
            paxList.add(item);
        }

        String paxJson;
        try {
            paxJson = objectMapper.writeValueAsString(paxList);
        } catch (Exception ex) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Lỗi định dạng danh sách hành khách.");
        }

        Map<String, Object> orderResult;
        try {
            // 1. Tao don dat ve va cac ve qua usp_TaoDonDatVe
            orderResult = jdbc.queryForMap(
                "EXEC dbo.usp_TaoDonDatVe @MaKhachHang=?, @MaChuyenBay=?, @HangVe=?, @HoTenLienHe=?, @EmailLienHe=?, @SDTLienHe=?, @DanhSachHanhKhach=?, @MaChuyenBayVe=?, @HangVeVe=?",
                customerId, flightCode, fareClass(req.fareClass()), contactName, contactEmail, contactPhone, paxJson,
                req.returnFlightNumber() == null || req.returnFlightNumber().isBlank() ? null : resolveFlightCode(req.returnFlightNumber()),
                fareClass(req.returnFareClass())
            );
        } catch (DataAccessException ex) {
            Throwable root = ex.getMostSpecificCause() != null ? ex.getMostSpecificCause() : ex;
            String msg = root.getMessage();
            if (msg != null) {
                if (msg.contains("50010") || msg.contains("khong con du dieu kien")) {
                    msg = "Chuyến bay đã qua giờ khởi hành hoặc không còn mở bán để đặt vé.";
                } else if (msg.contains("50011") || msg.contains("Khong du cho")) {
                    msg = "Chuyến bay không còn đủ chỗ trống cho số lượng hành khách đã chọn.";
                } else if (msg.contains("50002")) {
                    msg = "Thông tin hành khách không hợp lệ.";
                } else if (msg.contains("50004")) {
                    msg = "Tài khoản khách hàng không tồn tại hoặc đã bị khóa.";
                } else if (msg.contains(";")) {
                    msg = msg.substring(msg.lastIndexOf(";") + 1).trim();
                } else if (msg.contains(":")) {
                    msg = msg.substring(msg.lastIndexOf(":") + 1).trim();
                }
            }
            throw new ApiException(HttpStatus.BAD_REQUEST, "Đặt vé thất bại: " + (msg != null ? msg : "Dữ liệu không hợp lệ."));
        }

        long orderId = ((Number) orderResult.get("MaDonDatVe")).longValue();
        String pnr = (String) orderResult.get("MaPNR");
        BigDecimal totalAmount = (BigDecimal) orderResult.get("TongTien");

        // 2. Xac nhan thanh toan mo phong qua usp_XacNhanThanhToanMoPhong
        String paymentRef = "PAY-" + pnr + "-" + System.currentTimeMillis();
        try {
            jdbc.queryForList(
                "EXEC dbo.usp_XacNhanThanhToanMoPhong @MaDonDatVe=?, @KetQua='SUCCESS', @MaThamChieu=?, @SoTien=?",
                orderId, paymentRef, totalAmount
            );
        } catch (DataAccessException ex) {
            String msg = ex.getMessage();
            throw new ApiException(HttpStatus.BAD_REQUEST, "Thanh toán thất bại: " + (msg != null && msg.contains(":") ? msg.substring(msg.lastIndexOf(":") + 1).trim() : msg));
        }

        Map<String, Object> response = lookup(pnr, contact.lastName());
        response.put("orderId", orderId);
        response.put("totalAmount", totalAmount);
        return response;
    }

    public Map<String, Object> lookup(String pnr, String lastName) {
        List<Map<String, Object>> rows = tickets(pnr, lastName);
        List<Map<String, Object>> result = rows.stream().map(this::ticketResponse).toList();
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("pnr", rows.get(0).get("MaPNR"));
        response.put("status", rows.get(0).get("TrangThaiDon"));
        response.put("tickets", result);
        return response;
    }

    public List<Map<String, Object>> history(HttpServletRequest request) {
        SessionService.Principal p = sessions.requireUser(request);
        if (p.customerId() == null) {
            throw new ApiException(HttpStatus.FORBIDDEN, "Tài khoản này không có lịch sử đặt vé.");
        }

        // Goi Stored Procedure usp_LayLichSuDatVe
        List<Map<String, Object>> orders = jdbc.queryForList(
            "EXEC dbo.usp_LayLichSuDatVe @MaKhachHang=?",
            p.customerId()
        );

        List<Map<String, Object>> result = new ArrayList<>();
        for (Map<String, Object> o : orders) {
            long orderId = ((Number) o.get("MaDonDatVe")).longValue();
            String pnr = (String) o.get("MaPNR");
            BigDecimal totalAmount = (BigDecimal) o.get("TongTien");
            String status = (String) o.get("TrangThai");
            Timestamp createdAt = (Timestamp) o.get("NgayDat");

            // Lay thong tin chuyen bay va ve tu vw_ChiTietVe
            List<Map<String, Object>> tickets = jdbc.queryForList(
                """
                SELECT v.*, v.HoTenHanhKhach AS HoTen, h.NgaySinh,
                    cb.MoCheckInLuc, cb.DongCheckInLuc, SYSUTCDATETIME() AS HienTai
                FROM dbo.vw_ChiTietVe v
                JOIN dbo.HANH_KHACH h ON h.MaHanhKhach=v.MaHanhKhach
                JOIN dbo.CHUYEN_BAY cb ON cb.MaChuyenBay=v.MaChuyenBay
                WHERE v.MaDonDatVe=? ORDER BY v.GioCatCanh,v.MaVe
                """,
                orderId
            );

            LinkedHashMap<String, Object> item = new LinkedHashMap<>();
            item.put("orderId", orderId);
            item.put("pnr", pnr);
            item.put("createdAt", createdAt);
            item.put("totalAmount", totalAmount);
            item.put("status", status);

            if (!tickets.isEmpty()) {
                Map<String, Object> t = tickets.get(0);
                item.put("passengerName", t.get("HoTenHanhKhach"));
                item.put("flightNumber", t.get("SoHieuChuyen") != null ? t.get("SoHieuChuyen").toString().trim() : "");
                item.put("origin", t.get("MaSanBayDi") != null ? t.get("MaSanBayDi").toString().trim() : "");
                item.put("destination", t.get("MaSanBayDen") != null ? t.get("MaSanBayDen").toString().trim() : "");
                item.put("departure", t.get("GioCatCanh"));
                item.put("seat", t.get("SoGhe"));
            } else {
                item.put("passengerName", "Hành khách");
                item.put("flightNumber", "");
                item.put("origin", "");
                item.put("destination", "");
                item.put("departure", null);
                item.put("seat", null);
            }
            item.put("tickets", tickets.stream().map(this::ticketResponse).toList());
            result.add(item);
        }

        return result;
    }

    @Transactional
    public void cancel(HttpServletRequest request, String pnr) {
        SessionService.Principal p = sessions.requireUser(request);
        try {
            jdbc.queryForList(
                "EXEC dbo.usp_HuyDonDatVe @MaPNR=?, @MaKhachHang=?",
                pnr.toUpperCase().trim(), p.customerId()
            );
        } catch (DataAccessException ex) {
            String msg = ex.getMessage();
            throw new ApiException(HttpStatus.BAD_REQUEST, "Hủy đơn thất bại: " + (msg != null && msg.contains(":") ? msg.substring(msg.lastIndexOf(":") + 1).trim() : msg));
        }
    }

    public Map<String, Object> prepareCheckin(Requests.Checkin req) {
        if (req.ticketId() == null) return lookup(req.pnr(), req.lastName());
        Map<String, Object> ticket = selectedTicket(tickets(req.pnr(), req.lastName()), req.ticketId());
        Map<String, Object> result = ticketResponse(ticket);
        if (!Boolean.TRUE.equals(result.get("checkinEligible"))) {
            throw new ApiException(HttpStatus.CONFLICT, result.get("checkinReason").toString());
        }
        result.put("availableSeats", jdbc.queryForList(
            "SELECT SoGhe FROM dbo.fn_DanhSachGheKhaDung(?) ORDER BY SoGhe", String.class, req.ticketId()));
        result.put("allSeats", jdbc.queryForList("""
            SELECT g.SoGhe AS seat, g.HangVe AS fareClass,
                CASE WHEN EXISTS (SELECT 1 FROM dbo.CHECK_IN c
                    WHERE c.MaGhe=g.MaGhe AND c.TrangThai='CHECKED_IN') THEN 1 ELSE 0 END AS taken
            FROM dbo.GHE_CHUYEN_BAY g WHERE g.MaChuyenBay=? ORDER BY LEN(g.SoGhe),g.SoGhe
            """, ticket.get("MaChuyenBay").toString().trim()));
        return result;
    }

    @Transactional
    public Map<String, Object> confirmCheckin(Requests.CheckinConfirm req) {
        selectedTicket(tickets(req.pnr(), req.lastName()), req.ticketId());
        String rawSeat = req.seat().trim().toUpperCase(Locale.ROOT).replaceFirst("^0+", "");
        List<Long> seats = jdbc.queryForList("""
            SELECT MaGhe FROM dbo.fn_DanhSachGheKhaDung(?)
            WHERE SoGhe=? OR SoGhe=?
            """, Long.class, req.ticketId(), rawSeat, "0" + rawSeat);
        if (seats.size() != 1) throw new ApiException(HttpStatus.CONFLICT, "Ghế không khả dụng hoặc không thuộc hạng vé.");
        try {
            jdbc.queryForList("EXEC dbo.usp_CheckIn @MaVe=?, @MaGhe=?, @MaTK=NULL", req.ticketId(), seats.get(0));
        } catch (DataAccessException ex) {
            throw new ApiException(HttpStatus.CONFLICT, "Không thể check-in: " + ex.getMostSpecificCause().getMessage());
        }
        Map<String, Object> result = ticketResponse(selectedTicket(tickets(req.pnr(), req.lastName()), req.ticketId()));
        result.put("status", "CHECKED_IN");
        return result;
    }

    static Map<String, Object> selectedTicket(List<Map<String, Object>> rows, Long id) {
        if (id == null) throw new ApiException(HttpStatus.BAD_REQUEST, "Vui lòng chọn vé của hành khách và chặng bay.");
        return rows.stream().filter(t -> ((Number)t.get("MaVe")).longValue() == id)
            .findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Vé không thuộc đặt chỗ được phép truy cập."));
    }

    public Map<String, Object> adminStats() {
        Map<String, Object> stats = new LinkedHashMap<>();

        // Thong ke don tu DON_DAT_VE & GIAO_DICH_TT
        Map<String, Object> bookingRow = jdbc.queryForMap("""
            SELECT
                COUNT(*) AS totalOrders,
                SUM(CASE WHEN TrangThai='PAID' THEN 1 ELSE 0 END) AS paidOrders,
                SUM(CASE WHEN TrangThai='CANCELLED' THEN 1 ELSE 0 END) AS cancelledOrders,
                ISNULL(SUM(CASE WHEN TrangThai='PAID' THEN TongTien ELSE 0 END), 0) AS totalRevenue
            FROM DON_DAT_VE
        """);

        stats.put("totalOrders", bookingRow.get("totalOrders"));
        stats.put("paidOrders", bookingRow.get("paidOrders"));
        stats.put("cancelledOrders", bookingRow.get("cancelledOrders"));
        stats.put("totalRevenue", bookingRow.get("totalRevenue"));

        // Thong ke chuyen bay tu CHUYEN_BAY
        Map<String, Object> flightRow = jdbc.queryForMap("""
            SELECT
                COUNT(*) AS totalFlights,
                SUM(CASE WHEN TrangThai='SCHEDULED' THEN 1 ELSE 0 END) AS activeFlights
            FROM CHUYEN_BAY
        """);

        stats.put("totalFlights", flightRow.get("totalFlights"));
        stats.put("activeFlights", flightRow.get("activeFlights"));

        // Thong ke khach hang tu KHACH_HANG
        Integer totalCustomers = jdbc.queryForObject("SELECT COUNT(*) FROM KHACH_HANG", Integer.class);
        stats.put("totalCustomers", totalCustomers != null ? totalCustomers : 0);

        // Thong ke ve tu VE_CHUYEN_BAY
        Map<String, Object> ticketRow = jdbc.queryForMap("""
            SELECT
                COUNT(*) AS totalTickets,
                SUM(CASE WHEN TrangThai='USED' THEN 1 ELSE 0 END) AS usedTickets
            FROM VE_CHUYEN_BAY
        """);

        stats.put("totalTickets", ticketRow.get("totalTickets"));
        stats.put("usedTickets", ticketRow.get("usedTickets"));

        return stats;
    }

    public List<Map<String, Object>> adminBookings(String pnr, String status) {
        return jdbc.queryForList(
            "EXEC dbo.usp_AdminTimDonDatVe @MaPNR=?, @TrangThai=?",
            (pnr == null || pnr.isBlank()) ? null : pnr.trim().toUpperCase(),
            (status == null || status.isBlank()) ? null : status.trim().toUpperCase()
        );
    }

    public List<Map<String, Object>> adminCustomers(String keyword) {
        return jdbc.queryForList(
            "EXEC dbo.usp_AdminTimKhachHang @TuKhoa=?",
            (keyword == null || keyword.isBlank()) ? null : keyword.trim()
        );
    }

    public List<Map<String, Object>> adminSalesReport(LocalDate fromDate, LocalDate toDate) {
        LocalDate from = fromDate != null ? fromDate : LocalDate.now().minusDays(30);
        LocalDate to = toDate != null ? toDate : LocalDate.now();
        return jdbc.queryForList(
            "EXEC dbo.usp_AdminThongKeBanVe @TuNgay=?, @DenNgay=?",
            java.sql.Date.valueOf(from), java.sql.Date.valueOf(to)
        );
    }

    private List<Map<String, Object>> tickets(String pnr, String lastName) {
        List<Map<String, Object>> rows = jdbc.queryForList("""
            SELECT v.*, v.HoTenHanhKhach AS HoTen, h.NgaySinh,
                cb.MoCheckInLuc, cb.DongCheckInLuc, SYSUTCDATETIME() AS HienTai
            FROM dbo.vw_ChiTietVe v
            JOIN dbo.HANH_KHACH h ON h.MaHanhKhach=v.MaHanhKhach
            JOIN dbo.CHUYEN_BAY cb ON cb.MaChuyenBay=v.MaChuyenBay
            WHERE v.MaPNR=? ORDER BY v.GioCatCanh, v.MaVe
            """, pnr == null ? "" : pnr.trim().toUpperCase(Locale.ROOT));
        return authorizeTickets(rows, lastName);
    }

    static List<Map<String, Object>> authorizeTickets(List<Map<String, Object>> rows, String lastName) {
        String surname = normalizeName(lastName);
        if (surname.isBlank() || rows.stream().noneMatch(t -> {
            String name = normalizeName(Objects.toString(t.get("HoTen"), ""));
            return name.equals(surname) || name.startsWith(surname + " ");
        })) throw new ApiException(HttpStatus.NOT_FOUND, "Không tìm thấy PNR hoặc họ hành khách không khớp.");
        return rows;
    }

    static String normalizeName(String name) {
        String value = java.text.Normalizer.normalize(name == null ? "" : name, java.text.Normalizer.Form.NFD);
        return value.replaceAll("\\p{M}", "").replace('đ', 'd').replace('Đ', 'D')
            .replaceAll("[\\p{Z}\\s]+", " ").trim().toUpperCase(Locale.ROOT);
    }

    private Map<String, Object> ticketResponse(Map<String, Object> t) {
        LocalDateTime dep = ((Timestamp)t.get("GioCatCanh")).toLocalDateTime().plusHours(7);
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("pnr", t.get("MaPNR"));
        r.put("status", t.get("TrangThaiDon"));
        r.put("ticketStatus", t.get("TrangThaiVe"));
        r.put("passengerName", t.get("HoTen"));
        r.put("dateOfBirth", t.get("NgaySinh") == null ? null : t.get("NgaySinh").toString());
        r.put("flightNumber", t.get("SoHieuChuyen").toString().trim());
        r.put("flightCode", t.get("MaChuyenBay").toString().trim());
        r.put("fareClass", t.get("HangVe"));
        r.put("price", t.get("GiaVeChot"));
        r.put("origin", t.get("MaSanBayDi").toString().trim());
        r.put("destination", t.get("MaSanBayDen").toString().trim());
        r.put("route", r.get("origin") + " → " + r.get("destination"));
        r.put("departDate", dep.toLocalDate().toString());
        r.put("departTime", dep.toLocalTime().toString().substring(0, 5));
        r.put("seat", t.get("SoGhe"));
        r.put("ticketId", t.get("MaVe"));
        r.put("qrCode", t.get("MaQR_BP"));
        boolean checked = Boolean.TRUE.equals(t.get("DaCheckIn")) || "1".equals(Objects.toString(t.get("DaCheckIn")));
        String reason;
        if (checked) reason = "Đã check-in";
        else if (!"PAID".equals(t.get("TrangThaiDon")) || !"ISSUED".equals(t.get("TrangThaiVe"))) reason = "Vé chưa phát hành, đã dùng hoặc đã hủy";
        else if (!Set.of("SCHEDULED", "DELAYED").contains(t.get("TrangThaiChuyenBay"))) reason = "Chuyến bay không cho phép check-in";
        else if (t.get("HienTai") == null || t.get("MoCheckInLuc") == null) reason = "Chưa có thông tin khung giờ check-in";
        else {
            LocalDateTime now = ((Timestamp)t.get("HienTai")).toLocalDateTime();
            LocalDateTime open = ((Timestamp)t.get("MoCheckInLuc")).toLocalDateTime();
            LocalDateTime close = ((Timestamp)t.get("DongCheckInLuc")).toLocalDateTime();
            reason = now.isBefore(open) ? "Chưa đến giờ mở check-in" : !now.isBefore(close) ? "Đã đóng check-in" : "Có thể check-in";
        }
        r.put("checkedIn", checked);
        r.put("checkinEligible", "Có thể check-in".equals(reason));
        r.put("checkinReason", reason);
        return r;
    }

    private String resolveFlightCode(String flight) {
        if (flight == null || flight.isBlank()) throw new ApiException(HttpStatus.BAD_REQUEST, "Thiếu mã chuyến bay.");
        List<String> codes = jdbc.queryForList("SELECT MaChuyenBay FROM dbo.CHUYEN_BAY WHERE MaChuyenBay=?", String.class, flight.trim());
        if (codes.size() != 1) throw new ApiException(HttpStatus.BAD_REQUEST, "Phải chọn mã chuyến bay cụ thể, không dùng số hiệu chuyến.");
        return codes.get(0).trim();
    }

    private String fareClass(String value) {
        String fare = value == null ? "ECONOMY" : value.trim().toUpperCase(Locale.ROOT);
        if (!Set.of("ECONOMY", "BUSINESS").contains(fare)) throw new ApiException(HttpStatus.BAD_REQUEST, "Hạng vé không hợp lệ.");
        return fare;
    }

    private String fullName(Requests.Passenger p) {
        return (p.lastName() + " " + p.firstName()).replaceAll("[\\p{Z}\\s]+", " ").trim().toUpperCase(Locale.ROOT);
    }

    private String gender(String g) {
        if (g == null) return "OTHER";
        return switch (g.trim().toUpperCase()) {
            case "F", "FEMALE", "NU", "NỮ" -> "FEMALE";
            case "M", "MALE", "NAM" -> "MALE";
            default -> "OTHER";
        };
    }
}
