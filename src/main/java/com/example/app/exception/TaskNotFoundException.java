package com.example.app.exception;

/** Raised when a task id does not resolve to a stored task. */
public class TaskNotFoundException extends RuntimeException {

  private static final long serialVersionUID = 1L;

  public TaskNotFoundException(Long id) {
    super("Task not found: " + id);
  }
}
