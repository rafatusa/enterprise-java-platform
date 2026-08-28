package com.example.app.dto;

import com.example.app.entity.Task;
import java.time.Instant;

/** Outbound representation of a task. */
public record TaskResponse(
    Long id,
    String title,
    String description,
    String status,
    int priority,
    Instant createdAt,
    Instant updatedAt) {

  public static TaskResponse from(Task task) {
    return new TaskResponse(
        task.getId(),
        task.getTitle(),
        task.getDescription(),
        task.getStatus().name(),
        task.getPriority(),
        task.getCreatedAt(),
        task.getUpdatedAt());
  }
}
