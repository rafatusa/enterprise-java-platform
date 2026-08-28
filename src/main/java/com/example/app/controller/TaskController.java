package com.example.app.controller;

import com.example.app.dto.TaskRequest;
import com.example.app.dto.TaskResponse;
import com.example.app.service.TaskService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.net.URI;
import java.util.List;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Task CRUD and lifecycle endpoints. Requires a valid JWT. */
@RestController
@RequestMapping("/api/v1/tasks")
@Tag(name = "Tasks", description = "Task management operations")
public class TaskController {

  private final TaskService service;

  public TaskController(TaskService service) {
    this.service = service;
  }

  @GetMapping
  @Operation(summary = "List tasks, optionally filtered by status")
  public List<TaskResponse> list(@RequestParam(required = false) String status) {
    return service.findAll(status);
  }

  @GetMapping("/urgent")
  @Operation(summary = "List tasks at priority 1 or 2")
  public List<TaskResponse> urgent() {
    return service.findUrgent();
  }

  @GetMapping("/{id}")
  @Operation(summary = "Fetch a single task")
  public TaskResponse get(@PathVariable Long id) {
    return service.findById(id);
  }

  @PostMapping
  @Operation(summary = "Create a task")
  public ResponseEntity<TaskResponse> create(@Valid @RequestBody TaskRequest request) {
    TaskResponse created = service.create(request);
    return ResponseEntity.created(URI.create("/api/v1/tasks/" + created.id())).body(created);
  }

  @PutMapping("/{id}")
  @Operation(summary = "Replace a task's editable fields")
  public TaskResponse update(@PathVariable Long id, @Valid @RequestBody TaskRequest request) {
    return service.update(id, request);
  }

  @PatchMapping("/{id}/status")
  @Operation(summary = "Transition a task to a new status")
  public TaskResponse transition(@PathVariable Long id, @RequestParam String value) {
    return service.transition(id, value);
  }

  @DeleteMapping("/{id}")
  @Operation(summary = "Delete a task")
  public ResponseEntity<Void> delete(@PathVariable Long id) {
    service.delete(id);
    return ResponseEntity.noContent().build();
  }
}
