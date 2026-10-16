package vn.skygo.api;

import jakarta.validation.ConstraintViolationException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.*;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

@RestControllerAdvice
public class ApiExceptionHandler {
    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(ApiExceptionHandler.class);

    @ExceptionHandler(ApiException.class)
    ResponseEntity<Map<String,String>> api(ApiException e) { return ResponseEntity.status(e.status()).body(Map.of("message", e.getMessage())); }
    @ExceptionHandler({MethodArgumentNotValidException.class, ConstraintViolationException.class, DataIntegrityViolationException.class})
    ResponseEntity<Map<String,String>> badRequest(Exception e) { return ResponseEntity.badRequest().body(Map.of("message", "Dữ liệu không hợp lệ hoặc đã tồn tại.")); }
    @ExceptionHandler(Exception.class)
    ResponseEntity<Map<String,String>> unknown(Exception e) {
        log.error("Unhandled exception: ", e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(Map.of("message", "Hệ thống đang gặp lỗi. Vui lòng thử lại."));
    }
}
