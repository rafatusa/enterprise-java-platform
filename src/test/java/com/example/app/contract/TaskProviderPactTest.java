package com.example.app.contract;

import au.com.dius.pact.provider.junit5.HttpTestTarget;
import au.com.dius.pact.provider.junit5.PactVerificationContext;
import au.com.dius.pact.provider.junit5.PactVerificationInvocationContextProvider;
import au.com.dius.pact.provider.junitsupport.Provider;
import au.com.dius.pact.provider.junitsupport.State;
import au.com.dius.pact.provider.junitsupport.loader.PactFolder;
import com.example.app.entity.Task;
import com.example.app.entity.TaskStatus;
import com.example.app.repository.TaskRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.TestTemplate;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.ActiveProfiles;

/**
 * Pact provider verification.
 *
 * <p>Consumer contracts are read from src/test/resources/pacts. When a Pact Broker is configured
 * (PACT_BROKER_URL), the CI stage additionally publishes results; without a broker this still
 * verifies every contract committed to the repo, so the gate is meaningful in both setups.
 *
 * <p>The committed contracts cover unauthenticated interactions (health, and the 401 an anonymous
 * task request must return), so no login fixture is required here.
 */
@Provider("enterprise-java-platform")
@PactFolder("pacts")
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("test")
class TaskProviderPactTest {

  @LocalServerPort private int port;

  @Autowired private TaskRepository repository;

  @BeforeEach
  void setTarget(PactVerificationContext context) {
    if (context != null) {
      context.setTarget(new HttpTestTarget("localhost", port));
    }
  }

  @TestTemplate
  @ExtendWith(PactVerificationInvocationContextProvider.class)
  void verifyContracts(PactVerificationContext context) {
    if (context != null) {
      context.verifyInteraction();
    }
  }

  @State("the service is healthy")
  void serviceIsHealthy() {
    // No fixture required: the actuator health endpoint reflects live state.
  }

  @State("a task with id 1 exists")
  void taskExists() {
    repository.deleteAll();
    Task task = new Task("Contract task", "Fixture for consumer contract", 2);
    task.setStatus(TaskStatus.OPEN);
    repository.save(task);
  }
}
