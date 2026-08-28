package com.example.app.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.example.app.dto.TaskRequest;
import com.example.app.dto.TaskResponse;
import com.example.app.service.TaskService;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;

/** Unit tests for request delegation and response shaping. */
@ExtendWith(MockitoExtension.class)
class TaskControllerTest {

  @Mock private TaskService service;

  @InjectMocks private TaskController controller;

  private TaskResponse sample(long id) {
    return new TaskResponse(id, "Title", "Desc", "OPEN", 3, Instant.EPOCH, Instant.EPOCH);
  }

  @Test
  @DisplayName("list passes the status filter through to the service")
  void listWithFilter() {
    when(service.findAll("DONE")).thenReturn(List.of(sample(1L)));

    assertThat(controller.list("DONE")).hasSize(1);
    verify(service).findAll("DONE");
  }

  @Test
  @DisplayName("list without a filter passes null through")
  void listWithoutFilter() {
    when(service.findAll(null)).thenReturn(List.of(sample(1L), sample(2L)));

    assertThat(controller.list(null)).hasSize(2);
  }

  @Test
  @DisplayName("urgent delegates to the urgent query")
  void urgent() {
    when(service.findUrgent()).thenReturn(List.of(sample(9L)));

    assertThat(controller.urgent()).hasSize(1);
    verify(service).findUrgent();
  }

  @Test
  @DisplayName("get returns the single task")
  void get() {
    when(service.findById(4L)).thenReturn(sample(4L));

    assertThat(controller.get(4L).id()).isEqualTo(4L);
  }

  @Test
  @DisplayName("create returns 201 with a Location header")
  void create() {
    when(service.create(any(TaskRequest.class))).thenReturn(sample(11L));

    ResponseEntity<TaskResponse> response = controller.create(new TaskRequest("Title", "Desc", 3));

    assertThat(response.getStatusCode().value()).isEqualTo(201);
    assertThat(response.getHeaders().getLocation()).hasToString("/api/v1/tasks/11");
  }

  @Test
  @DisplayName("update delegates with the path id")
  void update() {
    when(service.update(eq(6L), any(TaskRequest.class))).thenReturn(sample(6L));

    assertThat(controller.update(6L, new TaskRequest("Title", "Desc", 3)).id()).isEqualTo(6L);
  }

  @Test
  @DisplayName("transition passes the target status value")
  void transition() {
    when(service.transition(2L, "DONE")).thenReturn(sample(2L));

    controller.transition(2L, "DONE");

    verify(service).transition(2L, "DONE");
  }

  @Test
  @DisplayName("delete returns 204 with no body")
  void delete() {
    ResponseEntity<Void> response = controller.delete(3L);

    assertThat(response.getStatusCode().value()).isEqualTo(204);
    verify(service).delete(3L);
  }
}
