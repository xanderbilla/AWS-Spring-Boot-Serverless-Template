package com.example.demo.controller;

import com.example.demo.dto.ApiResponse;
import com.example.demo.dto.HealthResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.lang.management.ManagementFactory;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/health")
public class SimpleHealthController {

    @Value("${spring.application.name:demo}")
    private String applicationName;

    @Value("${app.version:1.0.0}")
    private String applicationVersion;

    @GetMapping
    public ResponseEntity<ApiResponse<HealthResponse>> getHealth() {
        try {
            Map<String, Object> details = new HashMap<>();
            details.put("diskSpace", "available");
            details.put("memory", "available");
            details.put("uptime", ManagementFactory.getRuntimeMXBean().getUptime());

            HealthResponse healthResponse = HealthResponse.builder()
                    .status("UP")
                    .message("Application health check completed successfully")
                    .version(applicationVersion)
                    .timestamp(LocalDateTime.now())
                    .uptime(ManagementFactory.getRuntimeMXBean().getUptime())
                    .details(details)
                    .build();

            ApiResponse<HealthResponse> response = ApiResponse.<HealthResponse>builder()
                    .success(true)
                    .message("Health check successful")
                    .status(200)
                    .timestamp(LocalDateTime.now())
                    .data(healthResponse)
                    .build();

            return ResponseEntity.ok(response);

        } catch (Exception e) {
            Map<String, Object> errorDetails = new HashMap<>();
            errorDetails.put("error", e.getMessage());

            HealthResponse healthResponse = HealthResponse.builder()
                    .status("DOWN")
                    .message("Health check failed")
                    .version(applicationVersion)
                    .timestamp(LocalDateTime.now())
                    .details(errorDetails)
                    .build();

            ApiResponse<HealthResponse> response = ApiResponse.<HealthResponse>builder()
                    .success(false)
                    .message("Health check failed")
                    .status(503)
                    .timestamp(LocalDateTime.now())
                    .data(healthResponse)
                    .build();

            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body(response);
        }
    }
}
