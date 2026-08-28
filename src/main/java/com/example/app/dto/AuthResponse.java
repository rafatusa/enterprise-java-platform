package com.example.app.dto;

/** Issued bearer token and its lifetime in seconds. */
public record AuthResponse(String token, String tokenType, long expiresIn) {

  public static AuthResponse bearer(String token, long expiresIn) {
    return new AuthResponse(token, "Bearer", expiresIn);
  }
}
