package com.example.app.security;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.app.support.TestKeys;
import java.util.Optional;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** Unit tests for token issuance and validation. */
class JwtServiceTest {

  private final JwtService service = new JwtService(TestKeys.signingKey("jwt-service"), 3600);

  @Test
  @DisplayName("an issued token resolves back to its subject")
  void roundTrip() {
    String token = service.issue("operator");

    assertThat(service.resolveSubject(token)).contains("operator");
  }

  @Test
  @DisplayName("ttl is exposed for the login response")
  void ttlExposed() {
    assertThat(service.getTtlSeconds()).isEqualTo(3600);
  }

  @Test
  @DisplayName("a null token resolves to empty")
  void nullToken() {
    assertThat(service.resolveSubject(null)).isEmpty();
  }

  @Test
  @DisplayName("a blank token resolves to empty")
  void blankToken() {
    assertThat(service.resolveSubject("   ")).isEmpty();
  }

  @Test
  @DisplayName("a malformed token resolves to empty rather than throwing")
  void malformedToken() {
    assertThat(service.resolveSubject("not-a-jwt")).isEmpty();
  }

  @Test
  @DisplayName("a token signed with another key is rejected")
  void wrongSignature() {
    String foreign = new JwtService(TestKeys.foreignKey(), 3600).issue("intruder");

    assertThat(service.resolveSubject(foreign)).isEmpty();
  }

  @Test
  @DisplayName("an expired token is rejected")
  void expiredToken() {
    JwtService shortLived = new JwtService(TestKeys.signingKey("jwt-service"), -60);
    String token = shortLived.issue("operator");

    Optional<String> subject = service.resolveSubject(token);

    assertThat(subject).isEmpty();
  }

  @Test
  @DisplayName("two services sharing a key validate each other's tokens")
  void sharedKeyInteroperates() {
    JwtService peer = new JwtService(TestKeys.signingKey("jwt-service"), 3600);

    assertThat(service.resolveSubject(peer.issue("operator"))).contains("operator");
  }
}
