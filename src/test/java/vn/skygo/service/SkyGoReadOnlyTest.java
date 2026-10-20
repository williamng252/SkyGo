package vn.skygo.service;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import vn.skygo.api.ApiException;
import vn.skygo.security.SessionService;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.junit.jupiter.api.Assumptions.assumeFalse;

// Opt-in: only SELECTs and the existing read-only flight-search procedure.
@EnabledIfSystemProperty(named = "skygo.readonly", matches = "true")
class SkyGoReadOnlyTest {
    static JdbcTemplate jdbc;
    @BeforeAll static void connect() {
        var ds = new DriverManagerDataSource(System.getProperty("skygo.readonly.url",
            "jdbc:sqlserver://127.0.0.1:1433;databaseName=SkyGo_Cnpm;integratedSecurity=true;encrypt=false;trustServerCertificate=true"));
        jdbc = new JdbcTemplate(ds);
    }

    @Test void actualSearchGroupsFlightInstancesAndPreservesServerPricesAndCapacity() {
        List<Map<String,Object>> candidates = jdbc.queryForList("""
            SELECT TOP 1 MaSanBayDi,MaSanBayDen,CONVERT(VARCHAR(10),DATEADD(HOUR,7,GioCatCanh),23) AS Ngay
            FROM dbo.CHUYEN_BAY cb WHERE GioCatCanh>SYSUTCDATETIME()
                AND TrangThai IN ('SCHEDULED','DELAYED')
                AND EXISTS (SELECT 1 FROM dbo.HANG_VE_CHUYEN_BAY hv WHERE hv.MaChuyenBay=cb.MaChuyenBay
                    AND hv.TrangThai=1 AND dbo.fn_SoChoCon(cb.MaChuyenBay,hv.HangVe,SYSUTCDATETIME())>=1)
            ORDER BY GioCatCanh
            """);
        assumeFalse(candidates.isEmpty(), "No future flights in current data");
        var route = candidates.get(0);
        var flights = new FlightService(jdbc).search(route.get("MaSanBayDi").toString().trim(),
            route.get("MaSanBayDen").toString().trim(), LocalDate.parse(route.get("Ngay").toString()), 1);
        assertFalse(flights.isEmpty());
        Set<Object> codes = new HashSet<>();
        for (var flight : flights) {
            assertTrue(codes.add(flight.get("flightCode")));
            assertEquals(route.get("Ngay"), flight.get("departDate"));
            @SuppressWarnings("unchecked") var fares = (List<Map<String,Object>>)flight.get("fares");
            var expected = jdbc.queryForList("""
                SELECT HangVe, GiaCoBan+ThuePhi AS Gia FROM dbo.HANG_VE_CHUYEN_BAY
                WHERE MaChuyenBay=? AND TrangThai=1 AND dbo.fn_SoChoCon(MaChuyenBay,HangVe,SYSUTCDATETIME())>=1
                """, flight.get("flightCode"));
            assertEquals(expected.size(), fares.size());
            for (var fare : fares) {
                var price = expected.stream().filter(e -> e.get("HangVe").equals(fare.get("fareClass")))
                    .findFirst().orElseThrow().get("Gia");
                assertEquals(0, ((BigDecimal)price).compareTo((BigDecimal)fare.get("price")));
                assertTrue(((Number)fare.get("seatsAvailable")).intValue() >= 1);
            }
        }
    }

    @Test void actualMultiPassengerPnrReturnsAllTicketsForEitherSurnameAndRejectsOthers() {
        var pnrs = jdbc.queryForList("""
            SELECT TOP 1 d.MaPNR FROM dbo.DON_DAT_VE d
            JOIN dbo.VE_CHUYEN_BAY v ON v.MaDonDatVe=d.MaDonDatVe
            JOIN dbo.HANH_KHACH h ON h.MaHanhKhach=v.MaHanhKhach
            GROUP BY d.MaPNR
            HAVING COUNT(DISTINCT LEFT(h.HoTen,CHARINDEX(' ',h.HoTen+' ')-1))>1
            ORDER BY d.MaPNR
            """, String.class);
        assumeFalse(pnrs.isEmpty(), "No multi-surname PNR in current data");
        String pnr = pnrs.get(0);
        var names = jdbc.queryForList("SELECT HoTenHanhKhach FROM dbo.vw_ChiTietVe WHERE MaPNR=?", String.class, pnr);
        var service = new BookingService(jdbc, new SessionService());
        for (String name : names) {
            String surname = name.strip().split("\\s+")[0];
            assertEquals(names.size(), ((List<?>)service.lookup(pnr, surname).get("tickets")).size());
            assertEquals(names.size(), ((List<?>)service.lookup(pnr, BookingService.normalizeName(surname)).get("tickets")).size());
        }
        assertThrows(ApiException.class, () -> service.lookup(pnr, "INVALIDSURNAME123"));
        assertThrows(ApiException.class, () -> service.lookup(pnr, ""));
    }
}
