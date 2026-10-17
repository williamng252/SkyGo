package vn.skygo.api;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.validation.annotation.Validated;
import vn.skygo.dto.Requests;
import vn.skygo.security.SessionService;
import vn.skygo.service.*;
import java.time.LocalDate;
import java.util.*;

@RestController
@RequestMapping("/api")
@Validated
public class SkyGoController {
    private final AuthService auth; private final FlightService flights; private final BookingService bookings; private final SessionService sessions;
    public SkyGoController(AuthService auth, FlightService flights, BookingService bookings, SessionService sessions) { this.auth=auth;this.flights=flights;this.bookings=bookings;this.sessions=sessions; }

    @GetMapping("/health") public Map<String,String> health(){return Map.of("status","UP");}
    @PostMapping("/auth/register") public Map<String,String> register(@Valid @RequestBody Requests.Register r){auth.register(r);return Map.of("message","Đăng ký thành công.");}
    @PostMapping("/auth/login") public Map<String,Object> login(@Valid @RequestBody Requests.Login r){return auth.login(r);}
    @GetMapping("/auth/me") public Map<String,Object> me(HttpServletRequest request){return auth.me(request);}
    @PutMapping("/profile") public Map<String,Object> profile(HttpServletRequest request,@Valid @RequestBody Requests.Profile r){return auth.updateProfile(request,r);}

    @GetMapping("/airports") public List<Map<String,Object>> airports(){return flights.airports();}
    @GetMapping("/flights/search") public List<Map<String,Object>> search(@RequestParam @Size(min=3,max=3) String origin,@RequestParam @Size(min=3,max=3) String destination,@RequestParam @NotNull LocalDate departDate,@RequestParam(defaultValue="1") @Min(1) @Max(9) int adults,@RequestParam(defaultValue="0") @Min(0) int children,@RequestParam(defaultValue="0") @Min(0) int infants){return flights.search(origin, destination, departDate, adults+children);}
    @PostMapping("/bookings") public Map<String,Object> booking(HttpServletRequest request,@Valid @RequestBody Requests.Booking r){return bookings.create(request,r);}
    @GetMapping("/pnr/lookup") public Map<String,Object> lookup(@RequestParam String code,@RequestParam String lastName){return bookings.lookup(code,lastName);}
    @GetMapping("/bookings/my") public List<Map<String,Object>> history(HttpServletRequest request){return bookings.history(request);}
    @DeleteMapping("/bookings/{pnr}") public Map<String,String> cancel(HttpServletRequest request,@PathVariable String pnr){bookings.cancel(request,pnr);return Map.of("message","Đã hủy đơn đặt vé.");}
    @PostMapping("/checkin") public Map<String,Object> checkin(@Valid @RequestBody Requests.Checkin r){return bookings.prepareCheckin(r);}
    @PostMapping("/checkin/confirm") public Map<String,Object> checkinConfirm(@Valid @RequestBody Requests.CheckinConfirm r){return bookings.confirmCheckin(r);}

    @GetMapping("/admin/flights") public List<Map<String,Object>> adminFlights(HttpServletRequest request){sessions.requireAdmin(request);return flights.adminFlights();}
    @PostMapping("/admin/flights") public Map<String,String> createFlight(HttpServletRequest request,@Valid @RequestBody Requests.FlightUpsert r){sessions.requireAdmin(request);flights.createFlight(r);return Map.of("message","Đã tạo chuyến bay mới thành công.");}
    @DeleteMapping("/admin/flights/{code}") public Map<String,String> deleteFlight(HttpServletRequest request,@PathVariable String code){sessions.requireAdmin(request);flights.deleteFlight(code);return Map.of("message","Đã xóa chuyến bay.");}
    @PatchMapping("/admin/flights/{code}/status") public Map<String,String> status(HttpServletRequest request,@PathVariable String code,@Valid @RequestBody Requests.FlightStatus r){sessions.requireAdmin(request);flights.updateStatus(code,r.status());return Map.of("message","Đã cập nhật trạng thái chuyến bay.");}
    @GetMapping("/admin/stats") public Map<String,Object> adminStats(HttpServletRequest request){sessions.requireAdmin(request);return bookings.adminStats();}
    @GetMapping("/admin/bookings") public List<Map<String,Object>> adminBookings(HttpServletRequest request,@RequestParam(required=false) String pnr,@RequestParam(required=false) String status){sessions.requireAdmin(request);return bookings.adminBookings(pnr,status);}
    @GetMapping("/admin/customers") public List<Map<String,Object>> adminCustomers(HttpServletRequest request,@RequestParam(required=false) String keyword){sessions.requireAdmin(request);return bookings.adminCustomers(keyword);}
    @GetMapping("/admin/sales-report") public List<Map<String,Object>> adminSalesReport(HttpServletRequest request,@RequestParam(required=false) LocalDate fromDate,@RequestParam(required=false) LocalDate toDate){sessions.requireAdmin(request);return bookings.adminSalesReport(fromDate,toDate);}
}

