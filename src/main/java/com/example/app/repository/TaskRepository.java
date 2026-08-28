package com.example.app.repository;

import com.example.app.entity.Task;
import com.example.app.entity.TaskStatus;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

/** Persistence access for {@link Task}. */
@Repository
public interface TaskRepository extends JpaRepository<Task, Long> {

  List<Task> findByStatus(TaskStatus status);

  List<Task> findByPriorityLessThanEqual(int priority);
}
