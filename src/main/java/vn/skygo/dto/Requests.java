package vn.skygo.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

public final class Requests {
    private Requests() {}
    public record Register(@NotBlank String fullName, @Email String email, @NotBlank @Size(min=6) String password, String phone) {}
    public record Login(@jakarta.validation.constraints.NotBlank @com.fasterxml.jackson.annotation.JsonAlias({"username", "identifier"}) String email, @NotBlank String password) {}
    public record Passenger(@NotBlank String lastName, @NotBlank String firstName, @NotNull @PastOrPresent LocalDate dateOfBirth, String gender, String documentNumber) {}
    public record Booking(@NotBlank String flightNumber, String returnFlightNumber, @NotEmpty List<@Valid Passenger> passengers, String paymentMethod, List<String> selectedSeats, String seat, String fareClass, String returnFareClass) {
        public Booking(String flightNumber, String returnFlightNumber, List<Passenger> passengers, String paymentMethod, List<String> selectedSeats, String seat) {
            this(flightNumber, returnFlightNumber, passengers, paymentMethod, selectedSeats, seat, "ECONOMY", "ECONOMY");
        }
    }
    public record Checkin(@NotBlank String pnr, @NotBlank String lastName, @Positive Long ticketId) {
        public Checkin(String pnr, String lastName) { this(pnr, lastName, null); }
    }
    public record CheckinConfirm(@NotBlank String pnr, @NotBlank String lastName, @NotBlank String seat, @NotNull @Positive Long ticketId) {
        public CheckinConfirm(String pnr, String lastName, String seat) { this(pnr, lastName, seat, null); }
    }
    public record FlightUpsert(String flightCode, @NotBlank String flightNumber, @NotBlank String origin, @NotBlank String destination,
                               @NotNull java.time.LocalDateTime departure, @NotNull java.time.LocalDateTime arrival,
                               @NotNull @DecimalMin("0") BigDecimal basePrice, BigDecimal tax, String status, String aircraft) {}
    public record FlightStatus(@NotBlank String status) {}
    public record Profile(@NotBlank String fullName, String phone, String newPassword) {}
}
