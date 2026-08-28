package com.example.app.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;

import com.example.app.support.TestKeys;
import jakarta.servlet.FilterChain;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.context.SecurityContextHolder;

/** Unit tests for bearer-token extraction and context population. */
@ExtendWith(MockitoExtension.class)
class JwtAuthenticationFilterTest {

  private final JwtService jwtService = new JwtService(TestKeys.signingKey("jwt-filter"), 3600);
  private final JwtAuthenticationFilter filter = new JwtAuthenticationFilter(jwtService);

  @Mock private FilterChain chain;

  @AfterEach
  void clearContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  @DisplayName("a valid bearer token authenticates the request")
  void validTokenAuthenticates() throws Exception {
    MockHttpServletRequest request = new MockHttpServletRequest();
    request.addHeader("Authorization", "Bearer " + jwtService.issue("operator"));
    HttpServletResponse response = new MockHttpServletResponse();

    filter.doFilter(request, response, chain);

    assertThat(SecurityContextHolder.getContext().getAuthentication()).isNotNull();
    assertThat(SecurityContextHolder.getContext().getAuthentication().getName())
        .isEqualTo("operator");
    verify(chain).doFilter((HttpServletRequest) request, response);
  }

  @Test
  @DisplayName("an authenticated request grants ROLE_USER")
  void validTokenGrantsRole() throws Exception {
    MockHttpServletRequest request = new MockHttpServletRequest();
    request.addHeader("Authorization", "Bearer " + jwtService.issue("operator"));

    filter.doFilter(request, new MockHttpServletResponse(), chain);

    assertThat(SecurityContextHolder.getContext().getAuthentication().getAuthorities())
        .extracting("authority")
        .containsExactly("ROLE_USER");
  }

  @Test
  @DisplayName("a request without an Authorization header stays anonymous")
  void noHeaderStaysAnonymous() throws Exception {
    MockHttpServletRequest request = new MockHttpServletRequest();
    HttpServletResponse response = new MockHttpServletResponse();

    filter.doFilter(request, response, chain);

    assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
    verify(chain).doFilter((HttpServletRequest) request, response);
  }

  @Test
  @DisplayName("a non-Bearer authorization scheme is ignored")
  void nonBearerSchemeIgnored() throws Exception {
    MockHttpServletRequest request = new MockHttpServletRequest();
    request.addHeader("Authorization", "Basic dXNlcjpwYXNz");
    HttpServletResponse response = new MockHttpServletResponse();

    filter.doFilter(request, response, chain);

    assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
  }

  @Test
  @DisplayName("an invalid bearer token leaves the request anonymous and does not throw")
  void invalidTokenStaysAnonymous() throws Exception {
    MockHttpServletRequest request = new MockHttpServletRequest();
    request.addHeader("Authorization", "Bearer garbage.token.value");
    HttpServletResponse response = new MockHttpServletResponse();

    filter.doFilter(request, response, chain);

    assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
    verify(chain).doFilter((HttpServletRequest) request, response);
  }

  @Test
  @DisplayName("a token signed with a foreign key does not authenticate")
  void foreignTokenRejected() throws Exception {
    String foreign = new JwtService(TestKeys.foreignKey(), 3600).issue("intruder");
    MockHttpServletRequest request = new MockHttpServletRequest();
    request.addHeader("Authorization", "Bearer " + foreign);

    filter.doFilter(request, new MockHttpServletResponse(), chain);

    assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
  }
}
