package vn.skygo.service;

import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import vn.skygo.dto.Requests;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.HashSet;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.*;

class FlightServiceTest {
    @Test
    void groupsAllFaresByFlightInstanceWithoutMergingOtherDaysOrFlightKeys() {
        var rows = List.of(
            Map.<String,Object>of("flightCode", "SG101-20300101", "flightNumber", "SG101", "fareClass", "BUSINESS", "price", new BigDecimal("300"), "seatsAvailable", 8),
            Map.<String,Object>of("flightCode", "SG101-20300101", "flightNumber", "SG101", "fareClass", "ECONOMY", "price", new BigDecimal("100"), "seatsAvailable", 142),
            Map.<String,Object>of("flightCode", "SG101-20300102", "flightNumber", "SG101", "fareClass", "BUSINESS", "price", new BigDecimal("350"), "seatsAvailable", 4));
        var grouped = FlightService.groupFares(rows);
        assertEquals(2, grouped.size());
        assertEquals(2, ((List<?>)grouped.get(0).get("fares")).size());
        assertEquals(new BigDecimal("100"), grouped.get(0).get("price"));
        assertEquals(1, ((List<?>)grouped.get(1).get("fares")).size());
        assertEquals(new BigDecimal("350"), grouped.get(1).get("price"));
        assertEquals("BUSINESS", rows.get(0).get("fareClass"));
        assertTrue(FlightService.groupFares(List.of()).isEmpty());
    }

    @ParameterizedTest
    @CsvSource({"A320,150,scheduled", "A321,180,selling", "B737,162,DELAYED"})
    void createsUniqueSeatsForAircraftAndAppliesRequestedStatus(String aircraft, int capacity, String status) {
        RecordingJdbc jdbc = new RecordingJdbc();
        LocalDateTime departure = LocalDateTime.of(2030, 1, 1, 10, 0);
        Requests.FlightUpsert request = new Requests.FlightUpsert(
            "SG999", "SG999", "SGN", "HAN", departure, departure.plusHours(2),
            new BigDecimal("1500000"), null, status, aircraft
        );

        new FlightService(jdbc).createFlight(request);

        assertEquals(1, jdbc.seatBatches);
        List<Object[]> seats = jdbc.seats;
        assertEquals(capacity, seats.size());
        Set<String> seatNumbers = new HashSet<>();
        int businessSeats = 0;
        for (Object[] seat : seats) {
            assertEquals("SG999", seat[0]);
            assertTrue(seatNumbers.add((String) seat[2]), "Duplicate seat: " + seat[2]);
            if ("BUSINESS".equals(seat[1])) businessSeats++;
            else assertEquals("ECONOMY", seat[1]);
        }
        assertEquals(8, businessSeats);
        assertTrue(seatNumbers.containsAll(Set.of("01A", "02D", "03A", "18F")));
        assertTrue(jdbc.calls.get(0).contains("usp_AdminThemChuyenBay"));
        assertTrue(jdbc.calls.get(1).contains("@HangVe='ECONOMY'"));
        assertTrue(jdbc.calls.get(2).contains("@HangVe='BUSINESS'"));
        assertEquals("seats", jdbc.calls.get(3));
        if ("DELAYED".equals(status)) {
            assertEquals(5, jdbc.calls.size());
            assertTrue(jdbc.calls.get(4).contains("usp_AdminCapNhatTrangThaiChuyenBay"));
            assertEquals("SG999", jdbc.statusArguments[0]);
            assertEquals("DELAYED", jdbc.statusArguments[1]);
        } else {
            assertEquals(4, jdbc.calls.size());
        }
    }

    // Record database operations without a database connection or JVM instrumentation.
    private static class RecordingJdbc extends JdbcTemplate {
        final List<String> calls = new ArrayList<>();
        List<Object[]> seats;
        Object[] statusArguments;
        int seatBatches;

        @Override
        public List<Map<String, Object>> queryForList(String sql, Object... args) {
            calls.add(sql);
            if (sql.contains("usp_AdminCapNhatTrangThaiChuyenBay")) statusArguments = args;
            return List.of();
        }

        @Override
        public <T> List<T> queryForList(String sql, Class<T> type, Object... args) {
            return List.of(type.cast("SG999"));
        }

        @Override
        public int[] batchUpdate(String sql, List<Object[]> batchArgs) {
            assertTrue(sql.contains("INSERT INTO dbo.GHE_CHUYEN_BAY"));
            calls.add("seats");
            seatBatches++;
            seats = batchArgs;
            return new int[batchArgs.size()];
        }
    }
}
