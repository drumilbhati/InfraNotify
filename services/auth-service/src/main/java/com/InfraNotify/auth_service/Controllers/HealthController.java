package com.InfraNotify.auth_service.Controllers;

import java.util.Map;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
@Tag(name = "Health", description = "Service health endpoints")
public class HealthController {

	@GetMapping(value = "/health", produces = MediaType.APPLICATION_JSON_VALUE)
	@Operation(summary = "Check auth service health")
	@ApiResponse(responseCode = "200", description = "Service is healthy")
	public ResponseEntity<Map<String, String>> health() {
		return ResponseEntity.ok(Map.of(
				"status", "UP",
				"service", "auth-service"
		));
	}
}