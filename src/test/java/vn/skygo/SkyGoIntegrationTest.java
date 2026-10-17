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

    @Test
    void testLoginDemoAccounts() {
        // Customer login
        Map<String, Object> customer = authService.login(new Requests.Login("quan@example.com", "SkyGoDemo123!"));
        assertNotNull(customer.get("token"));
        assertEquals("user", customer.get("role"));
        System.out.println("Customer login OK: " + customer.get("fullName"));

        // Admin login
        Map<String, Object> admin = authService.login(new Requests.Login("admin@example.com", "SkyGoDemo123!"));
        assertNotNull(admin.get("token"));
        assertEquals("admin", admin.get("role"));
        System.out.println("Admin login OK: " + admin.get("fullName"));
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
