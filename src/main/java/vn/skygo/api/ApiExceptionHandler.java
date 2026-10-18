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
    ResponseEntity<Map<String,String>> api(ApiException e) { return ResponseEntity.status(e.status().value()).body(Map.of("message", e.getMessage())); }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<Map<String,String>> handleMethodArgumentNotValid(MethodArgumentNotValidException e) {
        String msg = "Dữ liệu không hợp lệ.";
        var fieldErrors = e.getBindingResult().getFieldErrors();
        if (!fieldErrors.isEmpty()) {
            var fieldError = fieldErrors.get(0);
            var defaultMessage = fieldError.getDefaultMessage();
            if (defaultMessage != null) {
                msg = fieldError.getField() + ": " + defaultMessage;
            }
        }
        return ResponseEntity.badRequest().body(Map.of("message", msg));
    }

    @ExceptionHandler(org.springframework.http.converter.HttpMessageNotReadableException.class)
    ResponseEntity<Map<String,String>> handleNotReadable(Exception e) {
        return ResponseEntity.badRequest().body(Map.of("message", "Định dạng dữ liệu yêu cầu không hợp lệ."));
    }

    @ExceptionHandler({ConstraintViolationException.class, DataIntegrityViolationException.class})
    ResponseEntity<Map<String,String>> badRequest(Exception e) { return ResponseEntity.badRequest().body(Map.of("message", "Dữ liệu không hợp lệ hoặc đã tồn tại.")); }

    @ExceptionHandler(IllegalArgumentException.class)
    ResponseEntity<Map<String,String>> handleIllegalArgument(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(Map.of("message", e.getMessage() != null ? e.getMessage() : "Yêu cầu không hợp lệ."));
    }

    @ExceptionHandler(org.springframework.dao.DataAccessException.class)
    ResponseEntity<Map<String,String>> handleDataAccessException(org.springframework.dao.DataAccessException e) {
        log.error("Database access error: ", e);
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body(Map.of("message", "Lỗi kết nối hoặc xử lý cơ sở dữ liệu. Vui lòng thử lại sau."));
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<Map<String,String>> unknown(Exception e) {
        log.error("Unhandled exception: ", e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(Map.of("message", "Hệ thống đang gặp lỗi. Vui lòng thử lại."));
    }
}
