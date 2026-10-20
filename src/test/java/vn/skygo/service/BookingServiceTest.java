package vn.skygo.service;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import vn.skygo.api.ApiException;
import vn.skygo.dto.Requests;
import vn.skygo.security.SessionService;

import java.math.BigDecimal;
import java.sql.Date;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;

class BookingServiceTest {
    @Test
    void eitherSurnameUnlocksAllPassengersAndLegsButOtherNamesDoNot() {
        RecordingJdbc jdbc = new RecordingJdbc();
        BookingService service = new BookingService(jdbc, new SessionService());
        for (String surname : List.of("  Nguyễn  ", "nguyen", " TRẦN ", "tran", "\u00a0Nguyễn\u00a0")) {
            List<?> tickets = (List<?>) service.lookup("ABC123", surname).get("tickets");
            assertEquals(4, tickets.size());
        }
        for (String surname : List.of("", " ", "%", "Van", "Ngo", "Nguy")) {
            assertThrows(ApiException.class, () -> service.lookup("ABC123", surname));
        }
        assertEquals(4, ((List<?>)service.prepareCheckin(new Requests.Checkin("ABC123", "Tran")).get("tickets")).size());
    }

    @Test
    void checkinChangesOnlySelectedPassengerOnSelectedLegAndReloadKeepsAllTickets() {
        RecordingJdbc jdbc = new RecordingJdbc();
        BookingService service = new BookingService(jdbc, new SessionService());
        Map<String, Object> prepared = service.prepareCheckin(new Requests.Checkin("ABC123", "Nguyen", 4L));
        assertEquals(List.of("03A"), prepared.get("availableSeats"));
        assertEquals(3, ((List<?>)prepared.get("allSeats")).size());
        assertEquals("BACK-20300103", jdbc.seatFlight);
        Map<String, Object> confirmed = service.confirmCheckin(new Requests.CheckinConfirm("ABC123", "Nguyen", "3A", 4L));
        assertEquals(List.of(4L), jdbc.checkedTickets);
        assertEquals("03A", confirmed.get("seat"));
        assertEquals(true, confirmed.get("checkedIn"));
        List<Map<String, Object>> reloaded = responseTickets(service.lookup("ABC123", "Tran"));
        assertEquals(4, reloaded.size());
        assertEquals(1, reloaded.stream().filter(t -> Boolean.TRUE.equals(t.get("checkedIn"))).count());
        assertEquals(4L, reloaded.stream().filter(t -> Boolean.TRUE.equals(t.get("checkedIn"))).findFirst().orElseThrow().get("ticketId"));
    }

    @Test
    void rejectsTicketOutsidePnrMissingTicketAndInvalidSeatWithoutFallback() {
        RecordingJdbc jdbc = new RecordingJdbc();
        BookingService service = new BookingService(jdbc, new SessionService());
        assertThrows(ApiException.class, () -> service.confirmCheckin(new Requests.CheckinConfirm("ABC123", "Nguyen", "03A", 999L)));
        assertThrows(ApiException.class, () -> service.confirmCheckin(new Requests.CheckinConfirm("ABC123", "Nguyen", "03A", null)));
        assertThrows(ApiException.class, () -> service.confirmCheckin(new Requests.CheckinConfirm("ABC123", "Other", "03A", 1L)));
        assertThrows(ApiException.class, () -> service.confirmCheckin(new Requests.CheckinConfirm("ABC123", "Tran", "99Z", 1L)));
        assertTrue(jdbc.checkedTickets.isEmpty());
    }

    @Test
    void checkinReportsClosedWindowCancelledTicketAndExistingCheckinWithoutChangingSchedule() {
        RecordingJdbc jdbc = new RecordingJdbc();
        jdbc.rows.get(0).put("MoCheckInLuc", Timestamp.valueOf("2030-01-02 00:00:00"));
        jdbc.rows.get(1).put("TrangThaiVe", "CANCELLED");
        jdbc.rows.get(2).put("DaCheckIn", true);
        BookingService service = new BookingService(jdbc, new SessionService());
        List<Map<String, Object>> tickets = responseTickets(service.lookup("ABC123", "Tran"));
        assertEquals("Chưa đến giờ mở check-in", tickets.get(0).get("checkinReason"));
        assertEquals(false, tickets.get(1).get("checkinEligible"));
        assertEquals("Đã check-in", tickets.get(2).get("checkinReason"));
        for (long id : List.of(1L, 2L, 3L)) {
            assertThrows(ApiException.class, () -> service.prepareCheckin(new Requests.Checkin("ABC123", "Nguyen", id)));
        }
    }

    @Test
    void bookingPassesIndependentFaresExactFlightKeysAndIsoBirthdayAndUsesServerTotal() {
        RecordingJdbc jdbc = new RecordingJdbc();
        BookingService service = new BookingService(jdbc, new SessionService());
        Requests.Passenger pax = new Requests.Passenger("Nguyễn", "An", LocalDate.of(2005, 11, 23), "MALE", "123");
        Map<String, Object> result = service.create(null, new Requests.Booking(
            "OUT-20300101", "BACK-20300103", List.of(pax), "DEMO", List.of(), null, "BUSINESS", "ECONOMY"));
        assertEquals("OUT-20300101", jdbc.createArgs[1]);
        assertEquals("BUSINESS", jdbc.createArgs[2]);
        assertEquals("BACK-20300103", jdbc.createArgs[7]);
        assertEquals("ECONOMY", jdbc.createArgs[8]);
        assertTrue(jdbc.createArgs[6].toString().contains("\"NgaySinh\":\"2005-11-23\""));
        assertEquals(new BigDecimal("4200000"), result.get("totalAmount"));
        assertEquals(result.get("totalAmount"), jdbc.paymentArgs[2]);
        assertEquals("2005-11-23", responseTickets(result).get(0).get("dateOfBirth"));
        assertEquals("2030-01-01", responseTickets(result).get(0).get("departDate"));
    }

    @Test
    void singlePassengerOneWayStillReturnsOneTicketAndFutureBirthdayIsRejected() {
        RecordingJdbc jdbc = new RecordingJdbc();
        jdbc.rows = new ArrayList<>(jdbc.rows.subList(0, 1));
        BookingService service = new BookingService(jdbc, new SessionService());
        Requests.Passenger pax = new Requests.Passenger("Nguyen", "An", LocalDate.of(2005, 11, 23), "M", null);
        Map<String, Object> result = service.create(null, new Requests.Booking("OUT-20300101", null, List.of(pax), "DEMO", List.of(), null));
        assertEquals(1, responseTickets(result).size());
        assertNull(jdbc.createArgs[7]);
        assertEquals("ECONOMY", jdbc.createArgs[2]);
        Requests.Passenger future = new Requests.Passenger("Nguyen", "An", LocalDate.now().plusYears(1), "M", null);
        assertThrows(ApiException.class, () -> service.create(null, new Requests.Booking("OUT-20300101", null, List.of(future), "DEMO", List.of(), null)));
        assertThrows(ApiException.class, () -> service.create(null, new Requests.Booking("SG101", null, List.of(pax), "DEMO", List.of(), null)));
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> responseTickets(Map<String, Object> response) {
        return (List<Map<String, Object>>)response.get("tickets");
    }

    private static class RecordingJdbc extends JdbcTemplate {
        List<Map<String, Object>> rows = new ArrayList<>();
        List<Long> checkedTickets = new ArrayList<>();
        Object[] createArgs;
        Object[] paymentArgs;
        Object seatFlight;
        RecordingJdbc() {
            for (long id = 1; id <= 4; id++) {
                Map<String, Object> t = new LinkedHashMap<>();
                t.put("MaVe", id);
                t.put("MaPNR", "ABC123");
                t.put("HoTen", id % 2 == 1 ? "NGUYỄN  AN" : "TRẦN BÌNH");
                t.put("NgaySinh", Date.valueOf("2005-11-23"));
                t.put("MaChuyenBay", id <= 2 ? "OUT-20300101" : "BACK-20300103");
                t.put("SoHieuChuyen", id <= 2 ? "SG101" : "SG102");
                t.put("MaSanBayDi", id <= 2 ? "SGN" : "HAN");
                t.put("MaSanBayDen", id <= 2 ? "HAN" : "SGN");
                t.put("GioCatCanh", Timestamp.valueOf(id <= 2 ? "2029-12-31 20:00:00" : "2030-01-03 03:00:00"));
                t.put("HangVe", id <= 2 ? "BUSINESS" : "ECONOMY");
                t.put("GiaVeChot", new BigDecimal("2100000"));
                t.put("TrangThaiDon", "PAID");
                t.put("TrangThaiVe", "ISSUED");
                t.put("TrangThaiChuyenBay", "SCHEDULED");
                t.put("DaCheckIn", false);
                t.put("HienTai", Timestamp.valueOf("2030-01-01 04:00:00"));
                t.put("MoCheckInLuc", Timestamp.valueOf("2030-01-01 00:00:00"));
                t.put("DongCheckInLuc", Timestamp.valueOf("2030-01-01 09:00:00"));
                rows.add(t);
            }
        }
        @Override public List<Map<String, Object>> queryForList(String sql, Object... args) {
            if (sql.contains("FROM dbo.GHE_CHUYEN_BAY g WHERE")) {
                seatFlight = args[0];
                return List.of(Map.of("seat", "01A", "fareClass", "BUSINESS", "taken", 0),
                    Map.of("seat", "03A", "fareClass", "ECONOMY", "taken", 0),
                    Map.of("seat", "03B", "fareClass", "ECONOMY", "taken", 1));
            }
            if (sql.contains("usp_CheckIn")) {
                long id = ((Number)args[0]).longValue();
                checkedTickets.add(id);
                Map<String,Object> t = BookingService.selectedTicket(rows, id);
                t.put("DaCheckIn", true);
                t.put("SoGhe", "03A");
                t.put("MaQR_BP", "TEST-QR");
                return List.of();
            }
            if (sql.contains("usp_XacNhanThanhToanMoPhong")) { paymentArgs = args; return List.of(); }
            assertTrue(sql.contains("WHERE v.MaPNR=?"), sql);
            assertFalse(sql.contains("TOP "));
            return "ABC123".equals(args[0]) ? rows : List.of();
        }
        @Override public <T> List<T> queryForList(String sql, Class<T> type, Object... args) {
            if (sql.contains("fn_DanhSachGheKhaDung")) {
                if (type == Long.class) return "3A".equals(args[1]) ? List.of(type.cast(30L)) : List.of();
                return List.of(type.cast("03A"));
            }
            if (sql.contains("FROM dbo.CHUYEN_BAY WHERE MaChuyenBay=?"))
                return args[0].toString().contains("2030") ? List.of(type.cast(args[0])) : List.of();
            throw new AssertionError(sql);
        }
        @Override public Map<String,Object> queryForMap(String sql, Object... args) {
            assertTrue(sql.contains("usp_TaoDonDatVe"));
            createArgs = args;
            return Map.of("MaDonDatVe", 10L, "MaPNR", "ABC123", "TongTien", new BigDecimal("4200000"));
        }
        @Override public int update(String sql, Object... args) { throw new AssertionError("Unexpected data mutation: " + sql); }
    }
}
