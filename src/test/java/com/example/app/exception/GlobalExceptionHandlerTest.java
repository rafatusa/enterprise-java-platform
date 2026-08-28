package com.example.app.exception;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Map;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.ResponseEntity;

/** Unit tests for the HTTP problem responses. */
class GlobalExceptionHandlerTest {

  private final GlobalExceptionHandler handler = new GlobalExceptionHandler();

  @Test
  @DisplayName("a missing task maps to 404 with a descriptive message")
  void notFound() {
    ResponseEntity<Map<String, Object>> response =
        handler.handleNotFound(new TaskNotFoundException(12L));

    assertThat(response.getStatusCode().value()).isEqualTo(404);
    assertThat(response.getBody()).containsEntry("status", 404);
    assertThat(response.getBody().get("message").toString()).contains("12");
    assertThat(response.getBody()).containsKey("timestamp");
  }

  @Test
  @DisplayName("an illegal state maps to 409 conflict")
  void conflict() {
    ResponseEntity<Map<String, Object>> response =
        handler.handleConflict(new IllegalStateException("Completed tasks cannot be reopened"));

    assertThat(response.getStatusCode().value()).isEqualTo(409);
    assertThat(response.getBody()).containsEntry("message", "Completed tasks cannot be reopened");
  }

  @Test
  @DisplayName("an illegal argument maps to 400 bad request")
  void badRequest() {
    ResponseEntity<Map<String, Object>> response =
        handler.handleBadRequest(new IllegalArgumentException("Unknown status: nope"));

    assertThat(response.getStatusCode().value()).isEqualTo(400);
    assertThat(response.getBody().get("message").toString()).contains("Unknown status");
  }
}
