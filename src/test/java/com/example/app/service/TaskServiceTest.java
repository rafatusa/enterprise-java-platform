package com.example.app.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.example.app.dto.TaskRequest;
import com.example.app.dto.TaskResponse;
import com.example.app.entity.Task;
import com.example.app.entity.TaskStatus;
import com.example.app.exception.TaskNotFoundException;
import com.example.app.repository.TaskRepository;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/** Mockito unit tests for the task lifecycle rules. */
@ExtendWith(MockitoExtension.class)
class TaskServiceTest {

  @Mock private TaskRepository repository;

  @InjectMocks private TaskService service;

  private Task task(TaskStatus status, int priority) {
    Task t = new Task("Ship the pipeline", "End to end", priority);
    t.setStatus(status);
    return t;
  }

  @Test
  @DisplayName("findAll without a status returns every task")
  void findAllUnfiltered() {
    when(repository.findAll()).thenReturn(List.of(task(TaskStatus.OPEN, 3)));

    List<TaskResponse> result = service.findAll(null);

    assertThat(result).hasSize(1);
    assertThat(result.get(0).status()).isEqualTo("OPEN");
    verify(repository, never()).findByStatus(any());
  }

  @Test
  @DisplayName("findAll with a blank status is treated as unfiltered")
  void findAllBlankStatus() {
    when(repository.findAll()).thenReturn(List.of(task(TaskStatus.OPEN, 3)));

    assertThat(service.findAll("   ")).hasSize(1);
    verify(repository, never()).findByStatus(any());
  }

  @Test
  @DisplayName("findAll with a status filters via the repository, case-insensitively")
  void findAllFiltered() {
    when(repository.findByStatus(TaskStatus.DONE)).thenReturn(List.of(task(TaskStatus.DONE, 1)));

    List<TaskResponse> result = service.findAll("done");

    assertThat(result).hasSize(1);
    assertThat(result.get(0).status()).isEqualTo("DONE");
    verify(repository, never()).findAll();
  }

  @Test
  @DisplayName("findAll rejects an unknown status value")
  void findAllUnknownStatus() {
    assertThatThrownBy(() -> service.findAll("nonsense"))
        .isInstanceOf(IllegalArgumentException.class)
        .hasMessageContaining("Unknown status");
  }

  @Test
  @DisplayName("findById returns the stored task")
  void findByIdFound() {
    when(repository.findById(7L)).thenReturn(Optional.of(task(TaskStatus.OPEN, 2)));

    assertThat(service.findById(7L).title()).isEqualTo("Ship the pipeline");
  }

  @Test
  @DisplayName("findById raises TaskNotFoundException for a missing id")
  void findByIdMissing() {
    when(repository.findById(99L)).thenReturn(Optional.empty());

    assertThatThrownBy(() -> service.findById(99L))
        .isInstanceOf(TaskNotFoundException.class)
        .hasMessageContaining("99");
  }

  @Test
  @DisplayName("create trims the title before persisting")
  void createTrimsTitle() {
    when(repository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

    TaskResponse result = service.create(new TaskRequest("  padded  ", "desc", 2));

    assertThat(result.title()).isEqualTo("padded");
    assertThat(result.priority()).isEqualTo(2);
  }

  @Test
  @DisplayName("update overwrites editable fields on an existing task")
  void updateExisting() {
    Task existing = task(TaskStatus.IN_PROGRESS, 4);
    when(repository.findById(3L)).thenReturn(Optional.of(existing));
    when(repository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

    TaskResponse result = service.update(3L, new TaskRequest(" renamed ", "new desc", 1));

    assertThat(result.title()).isEqualTo("renamed");
    assertThat(result.description()).isEqualTo("new desc");
    assertThat(result.priority()).isEqualTo(1);
    assertThat(result.status()).isEqualTo("IN_PROGRESS");
  }

  @Test
  @DisplayName("update raises TaskNotFoundException for a missing id")
  void updateMissing() {
    when(repository.findById(42L)).thenReturn(Optional.empty());

    assertThatThrownBy(() -> service.update(42L, new TaskRequest("x", null, 3)))
        .isInstanceOf(TaskNotFoundException.class);
    verify(repository, never()).save(any());
  }

  @Test
  @DisplayName("transition moves an open task to a new status")
  void transitionOpenTask() {
    when(repository.findById(1L)).thenReturn(Optional.of(task(TaskStatus.OPEN, 3)));
    when(repository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

    assertThat(service.transition(1L, "IN_PROGRESS").status()).isEqualTo("IN_PROGRESS");
  }

  @Test
  @DisplayName("a DONE task cannot be reopened")
  void transitionDoneTaskIsRejected() {
    when(repository.findById(1L)).thenReturn(Optional.of(task(TaskStatus.DONE, 3)));

    assertThatThrownBy(() -> service.transition(1L, "OPEN"))
        .isInstanceOf(IllegalStateException.class)
        .hasMessageContaining("cannot be reopened");
    verify(repository, never()).save(any());
  }

  @Test
  @DisplayName("re-applying DONE to a DONE task is idempotent, not a conflict")
  void transitionDoneToDoneIsAllowed() {
    when(repository.findById(1L)).thenReturn(Optional.of(task(TaskStatus.DONE, 3)));
    when(repository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

    assertThat(service.transition(1L, "DONE").status()).isEqualTo("DONE");
  }

  @Test
  @DisplayName("transition raises TaskNotFoundException for a missing id")
  void transitionMissing() {
    when(repository.findById(5L)).thenReturn(Optional.empty());

    assertThatThrownBy(() -> service.transition(5L, "DONE"))
        .isInstanceOf(TaskNotFoundException.class);
  }

  @Test
  @DisplayName("delete removes an existing task")
  void deleteExisting() {
    when(repository.existsById(8L)).thenReturn(true);

    service.delete(8L);

    verify(repository).deleteById(8L);
  }

  @Test
  @DisplayName("delete raises TaskNotFoundException for a missing id")
  void deleteMissing() {
    when(repository.existsById(8L)).thenReturn(false);

    assertThatThrownBy(() -> service.delete(8L)).isInstanceOf(TaskNotFoundException.class);
    verify(repository, never()).deleteById(any());
  }

  @Test
  @DisplayName("findUrgent asks the repository for priority 2 and below")
  void findUrgent() {
    when(repository.findByPriorityLessThanEqual(2)).thenReturn(List.of(task(TaskStatus.OPEN, 1)));

    assertThat(service.findUrgent()).hasSize(1);
    verify(repository).findByPriorityLessThanEqual(2);
  }
}
