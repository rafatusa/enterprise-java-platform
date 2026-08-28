package com.example.app.service;

import com.example.app.dto.TaskRequest;
import com.example.app.dto.TaskResponse;
import com.example.app.entity.Task;
import com.example.app.entity.TaskStatus;
import com.example.app.exception.TaskNotFoundException;
import com.example.app.repository.TaskRepository;
import java.util.List;
import java.util.Locale;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Task lifecycle rules.
 *
 * <p>This is the class the mutation-testing gate targets, so every branch here is behaviour someone
 * depends on rather than defensive padding.
 */
@Service
public class TaskService {

  private final TaskRepository repository;

  public TaskService(TaskRepository repository) {
    this.repository = repository;
  }

  @Transactional(readOnly = true)
  public List<TaskResponse> findAll(String status) {
    List<Task> tasks;
    if (status == null || status.isBlank()) {
      tasks = repository.findAll();
    } else {
      tasks = repository.findByStatus(parseStatus(status));
    }
    return tasks.stream().map(TaskResponse::from).toList();
  }

  @Transactional(readOnly = true)
  public TaskResponse findById(Long id) {
    return repository
        .findById(id)
        .map(TaskResponse::from)
        .orElseThrow(() -> new TaskNotFoundException(id));
  }

  @Transactional
  public TaskResponse create(TaskRequest request) {
    Task task = new Task(request.title().trim(), request.description(), request.priority());
    return TaskResponse.from(repository.save(task));
  }

  @Transactional
  public TaskResponse update(Long id, TaskRequest request) {
    Task task = repository.findById(id).orElseThrow(() -> new TaskNotFoundException(id));
    task.setTitle(request.title().trim());
    task.setDescription(request.description());
    task.setPriority(request.priority());
    task.touch();
    return TaskResponse.from(repository.save(task));
  }

  /**
   * Advances a task's status.
   *
   * <p>A task that is already DONE is terminal: re-transitioning it is rejected so completed work
   * cannot be silently reopened by a retrying client.
   */
  @Transactional
  public TaskResponse transition(Long id, String targetStatus) {
    Task task = repository.findById(id).orElseThrow(() -> new TaskNotFoundException(id));
    TaskStatus target = parseStatus(targetStatus);

    if (task.getStatus() == TaskStatus.DONE && target != TaskStatus.DONE) {
      throw new IllegalStateException("Completed tasks cannot be reopened");
    }

    task.setStatus(target);
    task.touch();
    return TaskResponse.from(repository.save(task));
  }

  @Transactional
  public void delete(Long id) {
    if (!repository.existsById(id)) {
      throw new TaskNotFoundException(id);
    }
    repository.deleteById(id);
  }

  @Transactional(readOnly = true)
  public List<TaskResponse> findUrgent() {
    return repository.findByPriorityLessThanEqual(2).stream().map(TaskResponse::from).toList();
  }

  private TaskStatus parseStatus(String value) {
    try {
      return TaskStatus.valueOf(value.toUpperCase(Locale.ROOT));
    } catch (IllegalArgumentException ex) {
      throw new IllegalArgumentException("Unknown status: " + value, ex);
    }
  }
}
