package vn.skygo.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

public final class Requests {
    private Requests() {}
    public record Register(@NotBlank String fullName, @Email String email, @NotBlank @Size(min=6) String password, String phone) {}
    public record Login(@Email String email, @NotBlank String password) {}
    public record Passenger(@NotBlank String lastName, @NotBlank String firstName, LocalDate dateOfBirth, String gender, String documentNumber) {}
    public record Booking(@NotBlank String flightNumber, String returnFlightNumber, @NotEmpty List<@Valid Passenger> passengers, String paymentMethod) {}
    public record Checkin(@NotBlank String pnr, @NotBlank String lastName) {}
    public record CheckinConfirm(@NotBlank String pnr, @NotBlank String lastName, @NotBlank String seat) {}
    public record FlightUpsert(String flightCode, @NotBlank String flightNumber, @NotBlank String origin, @NotBlank String destination,
                               @NotNull java.time.LocalDateTime departure, @NotNull java.time.LocalDateTime arrival,
                               @NotNull @DecimalMin("0") BigDecimal basePrice, BigDecimal tax, String status) {}
    public record FlightStatus(@NotBlank String status) {}
    public record Profile(@NotBlank String fullName, String phone, String newPassword) {}
}
