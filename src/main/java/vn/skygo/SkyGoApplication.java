package vn.skygo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

@SpringBootApplication
public class SkyGoApplication {
    static {
        try {
            java.io.File dll = new java.io.File("mssql-jdbc_auth.dll");
            if (!dll.exists()) {
                try (java.io.InputStream in = SkyGoApplication.class.getResourceAsStream("/mssql-jdbc_auth.dll")) {
                    if (in != null) {
                        java.nio.file.Files.copy(in, dll.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                    }
                }
            }
            if (dll.exists()) {
                System.load(dll.getAbsolutePath());
            }
        } catch (Throwable ignored) {}
    }
    public static void main(String[] args) { SpringApplication.run(SkyGoApplication.class, args); }
    @Bean PasswordEncoder passwordEncoder() { return new BCryptPasswordEncoder(); }
}
