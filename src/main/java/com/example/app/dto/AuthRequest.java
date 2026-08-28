package com.example.app.dto;

import jakarta.validation.constraints.NotBlank;

/** Credentials submitted to obtain a JWT. */
public record AuthRequest(
    @NotBlank(message = "username is required") String username,
    @NotBlank(message = "password is required") String password) {}
