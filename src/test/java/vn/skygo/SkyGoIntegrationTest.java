package vn.skygo;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import vn.skygo.dto.Requests;
import vn.skygo.service.AuthService;
import vn.skygo.service.BookingService;
import vn.skygo.service.FlightService;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest
class SkyGoIntegrationTest {

    @Autowired
    private AuthService authService;

    @Autowired
    private FlightService flightService;

    @Autowired
    private BookingService bookingService;

    @Test
    void testAirportsProcedure() {
        List<Map<String, Object>> airports = flightService.airports();
        assertNotNull(airports);
        assertFalse(airports.isEmpty(), "Danh sách sân bay không được rỗng");
        System.out.println("Airports count: " + airports.size());
    }

    @Autowired
    private org.springframework.jdbc.core.JdbcTemplate jdbcTemplate;

    @Test
    void testLoginDemoAccounts() {
        // Customer login by email
        Map<String, Object> customer = authService.login(new Requests.Login("quan@example.com", "SkyGoDemo123!"));
        assertNotNull(customer.get("token"));
        assertEquals("user", customer.get("role"));
        System.out.println("Customer login by email OK: " + customer.get("fullName"));

        // Customer login by username
        Map<String, Object> customerByUsername = authService.login(new Requests.Login("quan_demo", "SkyGoDemo123!"));
        assertNotNull(customerByUsername.get("token"));
        assertEquals("user", customerByUsername.get("role"));
        System.out.println("Customer login by username OK: " + customerByUsername.get("fullName"));

        // Admin login by email
        Map<String, Object> admin = authService.login(new Requests.Login("admin@example.com", "SkyGoDemo123!"));
        assertNotNull(admin.get("token"));
        assertEquals("admin", admin.get("role"));
        System.out.println("Admin login by email OK: " + admin.get("fullName"));

        // Admin login by username
        Map<String, Object> adminByUsername = authService.login(new Requests.Login("admin_demo", "SkyGoDemo123!"));
        assertNotNull(adminByUsername.get("token"));
        assertEquals("admin", adminByUsername.get("role"));
        System.out.println("Admin login by username OK: " + adminByUsername.get("fullName"));

        // Admin login by alias (admin@skygo.vn)
        Map<String, Object> adminAlias = authService.login(new Requests.Login("admin@skygo.vn", "SkyGoDemo123!"));
        assertNotNull(adminAlias.get("token"));
        assertEquals("admin", adminAlias.get("role"));
        System.out.println("Admin login by alias OK: " + adminAlias.get("fullName"));
    }

    @Test
    void testAuthNegativeCases() {
        // Wrong password
        vn.skygo.api.ApiException exWrongPass = assertThrows(vn.skygo.api.ApiException.class, () ->
            authService.login(new Requests.Login("quan@example.com", "WrongPassword!"))
        );
        assertEquals(org.springframework.http.HttpStatus.UNAUTHORIZED, exWrongPass.status());

        // Non-existent account
        vn.skygo.api.ApiException exNotFound = assertThrows(vn.skygo.api.ApiException.class, () ->
            authService.login(new Requests.Login("notfound@example.com", "SkyGoDemo123!"))
        );
        assertEquals(org.springframework.http.HttpStatus.UNAUTHORIZED, exNotFound.status());

        // Locked account (binh@example.com)
        vn.skygo.api.ApiException exLocked = assertThrows(vn.skygo.api.ApiException.class, () ->
            authService.login(new Requests.Login("binh@example.com", "SkyGoDemo123!"))
        );
        assertEquals(org.springframework.http.HttpStatus.FORBIDDEN, exLocked.status());
    }

    @Test
    void testRegisterAndLoginFlow() {
        String testEmail = "testuser_" + System.currentTimeMillis() + "@example.com";
        String testPass = "Secret123!";
        authService.register(new Requests.Register("Nguyen Van Test", testEmail, testPass, "0912345678"));

        // Login with new user
        Map<String, Object> loggedIn = authService.login(new Requests.Login(testEmail, testPass));
        assertNotNull(loggedIn.get("token"));
        assertEquals("user", loggedIn.get("role"));
        assertEquals("Nguyen Van Test", loggedIn.get("fullName"));
        System.out.println("Registered and logged in OK: " + loggedIn.get("fullName"));
    }

    @Test
    void testFlightSearchProcedure() {
        // SG001 is SGN -> HAN, 3 days after seed
        LocalDate date = LocalDate.now().plusDays(3);
        List<Map<String, Object>> flights = flightService.search("SGN", "HAN", date, 1);
        assertNotNull(flights);
        System.out.println("Found flights for " + date + ": " + flights.size());
    }

    @Test
    void testAdminFlightsProcedure() {
        List<Map<String, Object>> flights = flightService.adminFlights();
        assertNotNull(flights);
        assertFalse(flights.isEmpty());
        System.out.println("Admin flights count: " + flights.size());
    }

    @Test
    void testAdminStats() {
        Map<String, Object> stats = bookingService.adminStats();
        assertNotNull(stats);
        assertTrue(((Number) stats.get("totalOrders")).intValue() >= 0);
        System.out.println("Admin stats: " + stats);
    }

    @Test
    void testCheckinPrepareAndConfirm() {
        // Ensure SG003 is within check-in window and satisfies CK_CHUYENBAY_ThoiGian (GioDenDuKien > GioCatCanh)
        jdbcTemplate.update(
            "UPDATE CHUYEN_BAY SET " +
            "GioCatCanh = DATEADD(HOUR, 4, SYSUTCDATETIME()), " +
            "GioDenDuKien = DATEADD(HOUR, 6, SYSUTCDATETIME()), " +
            "MoCheckInLuc = DATEADD(HOUR, -12, DATEADD(HOUR, 4, SYSUTCDATETIME())), " +
            "DongCheckInLuc = DATEADD(HOUR, -1, DATEADD(HOUR, 4, SYSUTCDATETIME())), " +
            "TrangThai = 'SCHEDULED' WHERE MaChuyenBay = 'SG003'"
        );

        // Delete any existing check-in for Huy so the test can check in cleanly
        jdbcTemplate.update("DELETE FROM CHECK_IN WHERE MaVe IN (SELECT v.MaVe FROM VE_CHUYEN_BAY v JOIN DON_DAT_VE d ON v.MaDonDatVe = d.MaDonDatVe JOIN HANH_KHACH h ON v.MaHanhKhach = h.MaHanhKhach WHERE d.MaPNR = 'JK56LM' AND h.HoTen LIKE '%Huy%')");
        jdbcTemplate.update("UPDATE VE_CHUYEN_BAY SET TrangThai = 'ISSUED' WHERE MaDonDatVe = (SELECT MaDonDatVe FROM DON_DAT_VE WHERE MaPNR = 'JK56LM') AND MaHanhKhach = (SELECT MaHanhKhach FROM HANH_KHACH WHERE HoTen LIKE '%Huy%')");

        // Seed order JK56LM has Lan (already checked in) and Huy (not checked in)
        Map<String, Object> checkin = bookingService.prepareCheckin(new Requests.Checkin("JK56LM", "Pham"));
        assertNotNull(checkin);
        assertEquals("JK56LM", checkin.get("pnr"));
        List<?> avail = (List<?>) checkin.get("availableSeats");
        assertNotNull(avail);
        assertFalse(avail.isEmpty(), "Phải có ít nhất 1 ghế trống");
        String chooseSeat = avail.get(0).toString();
        System.out.println("Available seats: " + avail + ", choosing: " + chooseSeat);

        // Confirm check-in for Huy
        Map<String, Object> confirmed = bookingService.confirmCheckin(new Requests.CheckinConfirm("JK56LM", "Pham", chooseSeat));
        assertNotNull(confirmed);
        assertEquals("CHECKED_IN", confirmed.get("status"));
        assertEquals(chooseSeat, confirmed.get("seat"));
        assertNotNull(confirmed.get("qrCode"));
        System.out.println("Check-in confirmed with QR: " + confirmed.get("qrCode"));
    }

    @Test
    void testBookingCreationFlow() {
        // Clean up previous test bookings for Tran Van Nam so seats are always available
        jdbcTemplate.update("UPDATE VE_CHUYEN_BAY SET TrangThai = 'CANCELLED' WHERE MaDonDatVe IN (SELECT MaDonDatVe FROM DON_DAT_VE WHERE HoTenLienHe = 'TRAN VAN NAM')");
        jdbcTemplate.update("UPDATE DON_DAT_VE SET TrangThai = 'CANCELLED' WHERE HoTenLienHe = 'TRAN VAN NAM'");

        Requests.Passenger pax = new Requests.Passenger("Tran", "Van Nam", LocalDate.of(1998, 5, 20), "MALE", "079098000999");
        Requests.Booking req = new Requests.Booking("SG101", null, List.of(pax), "VIETQR");

        Map<String, Object> booking = bookingService.create(null, req);
        assertNotNull(booking);
        String pnr = (String) booking.get("pnr");
        assertNotNull(pnr);
        assertEquals(6, pnr.length());
        assertEquals("PAID", booking.get("status"));
        System.out.println("Created booking PNR: " + pnr + ", Total: " + booking.get("totalAmount"));

        // Lookup booking
        Map<String, Object> lookup = bookingService.lookup(pnr, "Tran");
        assertNotNull(lookup);
        assertEquals(pnr, lookup.get("pnr"));
    }

    @Test
    void testAdminProcedures() {
        // Test AdminTimDonDatVe
        List<Map<String, Object>> orders = bookingService.adminBookings(null, null);
        assertNotNull(orders);
        assertFalse(orders.isEmpty());
        System.out.println("Admin bookings count: " + orders.size());

        // Test AdminTimKhachHang
        List<Map<String, Object>> customers = bookingService.adminCustomers("Quan");
        assertNotNull(customers);
        assertFalse(customers.isEmpty());
        System.out.println("Admin customers found: " + customers.size());

        // Test AdminThongKeBanVe
        List<Map<String, Object>> report = bookingService.adminSalesReport(LocalDate.now().minusDays(10), LocalDate.now().plusDays(10));
        assertNotNull(report);
        System.out.println("Sales report rows: " + report.size());
    }

    @Test
    void testAdminCreateAndStatusFlight() {
        String testFlightCode = "SG999";
        // Clean up SG999 if it already exists from a previous run (delete in correct FK order)
        jdbcTemplate.update("DELETE FROM GHE_CHUYEN_BAY WHERE MaChuyenBay = ?", testFlightCode);
        jdbcTemplate.update("DELETE FROM HANG_VE_CHUYEN_BAY WHERE MaChuyenBay = ?", testFlightCode);
        jdbcTemplate.update("DELETE FROM CHUYEN_BAY WHERE MaChuyenBay = ?", testFlightCode);

        LocalDateTime dep = LocalDateTime.now().plusDays(5).withHour(10).withMinute(0).withSecond(0).withNano(0);
        LocalDateTime arr = dep.plusHours(2);

        Requests.FlightUpsert flightUpsert = new Requests.FlightUpsert(
            testFlightCode, "SG999", "SGN", "HAN", dep, arr,
            new BigDecimal("1500000"), new BigDecimal("150000"), "SCHEDULED"
        );

        flightService.createFlight(flightUpsert);
        System.out.println("Created flight " + testFlightCode);

        // Update status to DELAYED
        flightService.updateStatus(testFlightCode, "DELAYED");
        System.out.println("Updated status to DELAYED for " + testFlightCode);

        // Update status to CANCELLED
        flightService.updateStatus(testFlightCode, "CANCELLED");
        System.out.println("Cancelled flight " + testFlightCode);
    }
}
