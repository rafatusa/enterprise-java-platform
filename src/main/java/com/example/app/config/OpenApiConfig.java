package com.example.app.config;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** OpenAPI document served at /v3/api-docs and rendered by Swagger UI. */
@Configuration
public class OpenApiConfig {

  private static final String SCHEME_NAME = "bearerAuth";

  @Bean
  public OpenAPI apiDocumentation() {
    return new OpenAPI()
        .info(
            new Info()
                .title("Enterprise Java Platform API")
                .version("1.0.0")
                .description(
                    "Task management API secured with JWT bearer tokens. "
                        + "Obtain a token from POST /api/v1/auth/login.")
                .contact(new Contact().name("Platform Team"))
                .license(new License().name("Apache-2.0")))
        .addSecurityItem(new SecurityRequirement().addList(SCHEME_NAME))
        .components(
            new Components()
                .addSecuritySchemes(
                    SCHEME_NAME,
                    new SecurityScheme()
                        .name(SCHEME_NAME)
                        .type(SecurityScheme.Type.HTTP)
                        .scheme("bearer")
                        .bearerFormat("JWT")));
  }
}
