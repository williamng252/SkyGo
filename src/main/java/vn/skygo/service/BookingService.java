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
            LocalDate dob = p.dateOfBirth() != null ? p.dateOfBirth() : LocalDate.of(1995, 1, 1);
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
                "EXEC dbo.usp_TaoDonDatVe @MaKhachHang=?, @MaChuyenBay=?, @HangVe='ECONOMY', @HoTenLienHe=?, @EmailLienHe=?, @SDTLienHe=?, @DanhSachHanhKhach=?",
                customerId, flightCode, contactName, contactEmail, contactPhone, paxJson
            );
        } catch (DataAccessException ex) {
            String msg = ex.getMessage();
            throw new ApiException(HttpStatus.BAD_REQUEST, "Đặt vé thất bại: " + (msg != null && msg.contains(":") ? msg.substring(msg.lastIndexOf(":") + 1).trim() : msg));
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

        // 3. Lay chi tiet chuyen bay de tra ve cho frontend
        Map<String, Object> flight = jdbc.queryForMap(
            "SELECT SoHieuChuyen, MaSanBayDi, MaSanBayDen, GioCatCanh FROM CHUYEN_BAY WHERE MaChuyenBay=?",
            flightCode
        );

        LocalDateTime dep = ((Timestamp) flight.get("GioCatCanh")).toLocalDateTime();

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("orderId", orderId);
        response.put("pnr", pnr);
        response.put("status", "PAID");
        response.put("totalAmount", totalAmount);
        response.put("passengerName", contactName);
        response.put("flightNumber", ((String) flight.get("SoHieuChuyen")).trim());
        response.put("origin", ((String) flight.get("MaSanBayDi")).trim());
        response.put("destination", ((String) flight.get("MaSanBayDen")).trim());
        response.put("departDate", dep.toLocalDate().toString());
        response.put("departTime", dep.toLocalTime().toString().substring(0, 5));
        response.put("route", flight.get("MaSanBayDi").toString().trim() + " → " + flight.get("MaSanBayDen").toString().trim());
        return response;
    }

    public Map<String, Object> lookup(String pnr, String lastName) {
        List<Map<String, Object>> rows = tickets(pnr, lastName);
        if (rows.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Không tìm thấy mã PNR hoặc họ hành khách không khớp.");
        }
        return ticketResponse(rows.get(0));
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
                "SELECT TOP 1 HoTenHanhKhach, SoHieuChuyen, MaSanBayDi, MaSanBayDen, GioCatCanh, SoGhe FROM dbo.vw_ChiTietVe WHERE MaDonDatVe=? ORDER BY MaVe",
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
        List<Map<String, Object>> rows = tickets(req.pnr(), req.lastName());
        if (rows.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Không tìm thấy mã PNR hoặc họ hành khách không khớp.");
        }
        Map<String, Object> ticket = rows.get(0);
        String ticketStatus = (String) ticket.get("TrangThaiVe");
        if (!"ISSUED".equals(ticketStatus) && !"USED".equals(ticketStatus)) {
            throw new ApiException(HttpStatus.CONFLICT, "Vé chưa thanh toán hoặc đã bị hủy, không thể check-in.");
        }

        long ticketId = ((Number) ticket.get("MaVe")).longValue();
        String flightCode = (String) ticket.get("MaChuyenBay");

        // Lay danh sach ghe kha dung qua usp_LayGheKhaDung
        List<String> availableSeats = jdbc.query(
            "EXEC dbo.usp_LayGheKhaDung @MaVe=?",
            (rs, n) -> rs.getString("SoGhe"),
            ticketId
        );

        // Lay tat ca ghe de tinh danh sach unavailableSeats
        List<String> allSeats = jdbc.queryForList(
            "SELECT SoGhe FROM GHE_CHUYEN_BAY WHERE MaChuyenBay=?",
            String.class, flightCode
        );

        Set<String> availSet = new HashSet<>(availableSeats);
        List<String> unavailableSeats = new ArrayList<>();
        for (String s : allSeats) {
            if (!availSet.contains(s)) {
                unavailableSeats.add(s);
            }
        }

        Map<String, Object> response = ticketResponse(ticket);
        response.put("availableSeats", availableSeats);
        response.put("unavailableSeats", unavailableSeats);
        return response;
    }

    @Transactional
    public Map<String, Object> confirmCheckin(Requests.CheckinConfirm req) {
        List<Map<String, Object>> rows = tickets(req.pnr(), req.lastName());
        if (rows.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Không tìm thấy mã PNR hoặc họ hành khách không khớp.");
        }

        Map<String, Object> rawTicket = rows.get(0);
        long ticketId = ((Number) rawTicket.get("MaVe")).longValue();
        String flightCode = (String) rawTicket.get("MaChuyenBay");
        String seatName = req.seat().toUpperCase().trim();

        // Tim MaGhe tuong ung
        Long seatId = jdbc.query(
            "SELECT MaGhe FROM GHE_CHUYEN_BAY WHERE MaChuyenBay=? AND (SoGhe=? OR SoGhe=?)",
            rs -> rs.next() ? rs.getLong(1) : null,
            flightCode, seatName, seatName.replaceFirst("^0", "")
        );
        if (seatId == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Ghế không tồn tại trên chuyến bay này.");
        }

        try {
            // Goi Stored Procedure usp_CheckIn
            jdbc.queryForList(
                "EXEC dbo.usp_CheckIn @MaVe=?, @MaGhe=?, @MaTK=NULL",
                ticketId, seatId
            );
        } catch (DataAccessException ex) {
            Throwable root = ex.getMostSpecificCause() != null ? ex.getMostSpecificCause() : ex;
            String msg = root.getMessage();
            if (msg != null) {
                if (msg.contains("Ghe da duoc chon")) {
                    msg = "Ghế đã được chọn bởi hành khách khác. Hãy chọn ghế khác.";
                } else if (msg.contains("Ghe khong cung chuyen bay")) {
                    msg = "Ghế không thuộc chuyến bay hoặc không đúng hạng vé đã mua.";
                } else if (msg.contains("Ve da check-in")) {
                    msg = "Vé này đã được check-in trước đó. Vui lòng kiểm tra lại thẻ lên máy bay.";
                } else if (msg.contains("Chuyen bay khong trong thoi gian")) {
                    msg = "Chuyến bay không trong khung giờ cho phép làm thủ tục check-in (24h - 1h trước giờ bay).";
                } else if (msg.contains(";")) {
                    msg = msg.substring(msg.lastIndexOf(';') + 1).trim();
                }
            }
            throw new ApiException(HttpStatus.CONFLICT, "Lỗi check-in: " + (msg != null ? msg : "Không thể thực hiện check-in."));
        }

        // Goi Stored Procedure usp_LayTheLenMayBay
        List<Map<String, Object>> bpRows = jdbc.queryForList(
            "EXEC dbo.usp_LayTheLenMayBay @MaVe=?",
            ticketId
        );

        Map<String, Object> result = ticketResponse(rawTicket);
        result.put("seat", seatName);
        result.put("status", "CHECKED_IN");
        result.put("gate", "B12");

        if (!bpRows.isEmpty()) {
            Map<String, Object> bp = bpRows.get(0);
            result.put("qrCode", bp.get("MaQR_BP"));
            if (bp.get("SoGhe") != null) result.put("seat", bp.get("SoGhe"));
        }

        return result;
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
        // Su dung view vw_ChiTietVe
        return jdbc.queryForList("""
            SELECT TOP 20
                v.MaVe, v.HangVe, v.TrangThaiVe, v.MaChuyenBay, v.SoHieuChuyen,
                v.MaSanBayDi, v.MaSanBayDen, v.GioCatCanh, v.MaPNR, v.TrangThaiDon,
                v.HoTenHanhKhach AS HoTen, v.SoGhe, v.DaCheckIn, v.GiaVeChot
            FROM dbo.vw_ChiTietVe v
            WHERE v.MaPNR = ?
              AND (UPPER(v.HoTenHanhKhach) LIKE ? OR ? = '')
            ORDER BY CASE WHEN v.DaCheckIn = 0 THEN 0 ELSE 1 END, v.MaVe
        """, pnr.toUpperCase().trim(), "%" + lastName.trim().toUpperCase() + "%", lastName.trim());
    }

    private Map<String, Object> ticketResponse(Map<String, Object> t) {
        Timestamp ts = (Timestamp) t.get("GioCatCanh");
        LocalDateTime d = ts != null ? ts.toLocalDateTime() : LocalDateTime.now();
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("pnr", t.get("MaPNR"));
        r.put("status", t.get("TrangThaiDon"));
        r.put("passengerName", t.get("HoTen"));
        r.put("flightNumber", t.get("SoHieuChuyen") != null ? t.get("SoHieuChuyen").toString().trim() : "");
        r.put("flightCode", t.get("MaChuyenBay") != null ? t.get("MaChuyenBay").toString().trim() : "");
        r.put("fareClass", t.get("HangVe"));
        r.put("origin", t.get("MaSanBayDi") != null ? t.get("MaSanBayDi").toString().trim() : "");
        r.put("destination", t.get("MaSanBayDen") != null ? t.get("MaSanBayDen").toString().trim() : "");
        r.put("route", r.get("origin") + " → " + r.get("destination"));
        r.put("departDate", d.toLocalDate().toString());
        r.put("departTime", d.toLocalTime().toString().substring(0, 5));
        r.put("seat", t.get("SoGhe"));
        r.put("ticketId", t.get("MaVe"));
        return r;
    }

    private String resolveFlightCode(String flight) {
        List<String> list = jdbc.queryForList(
            "SELECT MaChuyenBay FROM CHUYEN_BAY WHERE MaChuyenBay=? OR SoHieuChuyen=?",
            String.class, flight.trim(), flight.trim()
        );
        if (list.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Không tìm thấy chuyến bay: " + flight);
        }
        return list.get(0).trim();
    }

    private String fullName(Requests.Passenger p) {
        return (p.lastName().trim() + " " + p.firstName().trim()).toUpperCase();
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
