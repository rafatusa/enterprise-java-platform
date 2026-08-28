package com.example.app.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/** Inbound payload for creating or replacing a task. */
public record TaskRequest(
    @NotBlank(message = "title is required") @Size(max = 200) String title,
    @Size(max = 2000) String description,
    @Min(value = 1, message = "priority must be between 1 and 5")
        @Max(value = 5, message = "priority must be between 1 and 5")
        int priority) {}
