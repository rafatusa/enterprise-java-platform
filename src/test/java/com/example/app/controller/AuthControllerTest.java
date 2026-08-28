package com.example.app.controller;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.app.dto.AuthRequest;
import com.example.app.dto.AuthResponse;
import com.example.app.security.JwtService;
import com.example.app.support.TestKeys;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

/** Unit tests for credential checking at the token endpoint. */
class AuthControllerTest {

  // Generated per test run rather than written as a literal, so no
  // credential-shaped constant lives in the repository.
  private static final String TEST_CREDENTIAL = TestKeys.signingKey("operator-credential");

  private final PasswordEncoder encoder = new BCryptPasswordEncoder();
  private final JwtService jwtService =
      new JwtService(TestKeys.signingKey("auth-controller"), 1800);
  private final AuthController controller =
      new AuthController(jwtService, encoder, "operator", encoder.encode(TEST_CREDENTIAL));

  @Test
  @DisplayName("correct credentials return a usable bearer token")
  void validCredentials() {
    ResponseEntity<AuthResponse> response =
        controller.login(new AuthRequest("operator", TEST_CREDENTIAL));

    assertThat(response.getStatusCode().value()).isEqualTo(200);
    AuthResponse body = response.getBody();
    assertThat(body).isNotNull();
    assertThat(body.tokenType()).isEqualTo("Bearer");
    assertThat(body.expiresIn()).isEqualTo(1800);
    assertThat(jwtService.resolveSubject(body.token())).contains("operator");
  }

  @Test
  @DisplayName("a wrong password is rejected with 401")
  void wrongPassword() {
    ResponseEntity<AuthResponse> response =
        controller.login(new AuthRequest("operator", "not-the-credential"));

    assertThat(response.getStatusCode().value()).isEqualTo(401);
    assertThat(response.getBody()).isNull();
  }

  @Test
  @DisplayName("an unknown username is rejected with 401")
  void wrongUsername() {
    ResponseEntity<AuthResponse> response =
        controller.login(new AuthRequest("intruder", TEST_CREDENTIAL));

    assertThat(response.getStatusCode().value()).isEqualTo(401);
  }

  @Test
  @DisplayName("both credentials wrong is rejected with 401")
  void bothWrong() {
    ResponseEntity<AuthResponse> response =
        controller.login(new AuthRequest("intruder", "not-the-credential"));

    assertThat(response.getStatusCode().value()).isEqualTo(401);
  }
}
