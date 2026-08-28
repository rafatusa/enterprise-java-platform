package com.example.app;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.app.controller.AuthController;
import com.example.app.controller.TaskController;
import com.example.app.service.TaskService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

/** Verifies the Spring context wires every layer together. */
@SpringBootTest
@ActiveProfiles("test")
class ApplicationTests {

  @Autowired private TaskController taskController;
  @Autowired private AuthController authController;
  @Autowired private TaskService taskService;

  @Test
  @DisplayName("the application context loads with all layers wired")
  void contextLoads() {
    assertThat(taskController).isNotNull();
    assertThat(authController).isNotNull();
    assertThat(taskService).isNotNull();
  }
}
