package com.example.app;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.greaterThanOrEqualTo;
import static org.hamcrest.Matchers.notNullValue;

import com.example.app.support.TestCredentials;
import io.restassured.RestAssured;
import io.restassured.http.ContentType;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.ContextConfiguration;

/**
 * REST Assured API tests against a real running application context.
 *
 * <p>These cover the wire contract — status codes, headers, JSON shape and the authentication
 * boundary — which the unit tests deliberately do not.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ContextConfiguration(initializers = TestCredentials.class)
@ActiveProfiles("test")
class TaskApiIT {

  @LocalServerPort private int port;

  private String token;

  @BeforeEach
  void setUp() {
    RestAssured.baseURI = "http://localhost";
    RestAssured.port = port;

    token =
        given()
            .contentType(ContentType.JSON)
            .body(Map.of("username", TestCredentials.USERNAME, "password", TestCredentials.SECRET))
            .when()
            .post("/api/v1/auth/login")
            .then()
            .statusCode(200)
            .extract()
            .path("token");
  }

  @Test
  @DisplayName("health probe reports UP")
  void healthIsUp() {
    given().when().get("/actuator/health").then().statusCode(200).body("status", equalTo("UP"));
  }

  @Test
  @DisplayName("info endpoint is served")
  void infoIsExposed() {
    given().when().get("/actuator/info").then().statusCode(200);
  }

  @Test
  @DisplayName("the OpenAPI document is served")
  void openApiIsServed() {
    given()
        .when()
        .get("/v3/api-docs")
        .then()
        .statusCode(200)
        .body("info.title", equalTo("Enterprise Java Platform API"));
  }

  @Test
  @DisplayName("tasks require authentication")
  void tasksRequireAuth() {
    given().when().get("/api/v1/tasks").then().statusCode(401);
  }

  @Test
  @DisplayName("an invalid token is rejected")
  void invalidTokenRejected() {
    given()
        .header("Authorization", "Bearer not-a-real-token")
        .when()
        .get("/api/v1/tasks")
        .then()
        .statusCode(401);
  }

  @Test
  @DisplayName("a task can be created, read, transitioned and deleted")
  void taskLifecycle() {
    int id =
        given()
            .header("Authorization", "Bearer " + token)
            .contentType(ContentType.JSON)
            .body(
                Map.of("title", "Integration task", "description", "created by IT", "priority", 2))
            .when()
            .post("/api/v1/tasks")
            .then()
            .statusCode(201)
            .header("Location", notNullValue())
            .body("title", equalTo("Integration task"))
            .body("status", equalTo("OPEN"))
            .extract()
            .path("id");

    given()
        .header("Authorization", "Bearer " + token)
        .when()
        .get("/api/v1/tasks/" + id)
        .then()
        .statusCode(200)
        .body("priority", equalTo(2));

    given()
        .header("Authorization", "Bearer " + token)
        .when()
        .patch("/api/v1/tasks/" + id + "/status?value=DONE")
        .then()
        .statusCode(200)
        .body("status", equalTo("DONE"));

    given()
        .header("Authorization", "Bearer " + token)
        .when()
        .patch("/api/v1/tasks/" + id + "/status?value=OPEN")
        .then()
        .statusCode(409);

    given()
        .header("Authorization", "Bearer " + token)
        .when()
        .delete("/api/v1/tasks/" + id)
        .then()
        .statusCode(204);

    given()
        .header("Authorization", "Bearer " + token)
        .when()
        .get("/api/v1/tasks/" + id)
        .then()
        .statusCode(404);
  }

  @Test
  @DisplayName("validation rejects a blank title and an out-of-range priority")
  void validationRejectsBadInput() {
    given()
        .header("Authorization", "Bearer " + token)
        .contentType(ContentType.JSON)
        .body(Map.of("title", "", "description", "no title", "priority", 9))
        .when()
        .post("/api/v1/tasks")
        .then()
        .statusCode(400)
        .body("fields", notNullValue());
  }

  @Test
  @DisplayName("the urgent view returns only high-priority tasks")
  void urgentView() {
    given()
        .header("Authorization", "Bearer " + token)
        .contentType(ContentType.JSON)
        .body(Map.of("title", "Urgent item", "description", "p1", "priority", 1))
        .when()
        .post("/api/v1/tasks")
        .then()
        .statusCode(201);

    given()
        .header("Authorization", "Bearer " + token)
        .when()
        .get("/api/v1/tasks/urgent")
        .then()
        .statusCode(200)
        .body("size()", greaterThanOrEqualTo(1));
  }

  @Test
  @DisplayName("bad credentials do not yield a token")
  void badCredentials() {
    given()
        .contentType(ContentType.JSON)
        .body(Map.of("username", TestCredentials.USERNAME, "password", "wrong"))
        .when()
        .post("/api/v1/auth/login")
        .then()
        .statusCode(401);
  }
}
