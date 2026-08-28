package com.example.app.controller;

import com.example.app.dto.AuthRequest;
import com.example.app.dto.AuthResponse;
import com.example.app.security.JwtService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Token issuance.
 *
 * <p>Credentials are checked against a single configured operator account whose password arrives as
 * a bcrypt hash from configuration — there is no user store in this service by design. Replace with
 * your identity provider when one exists.
 */
@RestController
@RequestMapping("/api/v1/auth")
@Tag(name = "Authentication", description = "JWT token issuance")
public class AuthController {

  private final JwtService jwtService;
  private final PasswordEncoder passwordEncoder;
  private final String operatorUsername;
  private final String operatorPasswordHash;

  public AuthController(
      JwtService jwtService,
      PasswordEncoder passwordEncoder,
      @Value("${app.auth.username}") String operatorUsername,
      @Value("${app.auth.password-hash}") String operatorPasswordHash) {
    this.jwtService = jwtService;
    this.passwordEncoder = passwordEncoder;
    this.operatorUsername = operatorUsername;
    this.operatorPasswordHash = operatorPasswordHash;
  }

  @PostMapping("/login")
  @Operation(summary = "Exchange credentials for a JWT bearer token")
  public ResponseEntity<AuthResponse> login(@Valid @RequestBody AuthRequest request) {
    boolean userMatches = operatorUsername.equals(request.username());
    boolean passwordMatches = passwordEncoder.matches(request.password(), operatorPasswordHash);

    if (!userMatches || !passwordMatches) {
      return ResponseEntity.status(401).build();
    }

    String token = jwtService.issue(request.username());
    return ResponseEntity.ok(AuthResponse.bearer(token, jwtService.getTtlSeconds()));
  }
}
