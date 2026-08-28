package com.example.app.support;

import java.security.SecureRandom;
import java.util.Base64;
import org.springframework.boot.test.util.TestPropertyValues;
import org.springframework.context.ApplicationContextInitializer;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

/**
 * Test credentials, consistent by construction and generated at runtime.
 *
 * <p>Both halves of the credential pair are derived from a single value that is GENERATED when the
 * test JVM starts: the plaintext is random, and the bcrypt hash is computed from that same
 * plaintext and injected as a property before the context starts.
 *
 * <p>Two bugs are designed out by this:
 *
 * <ul>
 *   <li><b>Drift.</b> Copying a bcrypt hash from elsewhere and assuming its plaintext is how an
 *       integration suite ends up asserting against a pair that cannot match — every request
 *       returns 401 and it looks like a security misconfiguration rather than a bad fixture.
 *   <li><b>Credential-shaped literals.</b> A hardcoded test password is indistinguishable from a
 *       real one to a secret scanner, and teaches the habit that puts a real one in a repository
 *       later. Generating it means no credential literal exists here to review, leak, or reuse.
 * </ul>
 */
public class TestCredentials
    implements ApplicationContextInitializer<ConfigurableApplicationContext> {

  /** The username every integration test logs in with. Not a credential. */
  public static final String USERNAME = "operator";

  /** The plaintext every integration test logs in with, generated per JVM. */
  public static final String SECRET = generate();

  private static String generate() {
    byte[] bytes = new byte[24];
    new SecureRandom().nextBytes(bytes);
    return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
  }

  @Override
  public void initialize(ConfigurableApplicationContext context) {
    String hash = new BCryptPasswordEncoder().encode(SECRET);
    TestPropertyValues.of("app.auth.username=" + USERNAME, "app.auth.password-hash=" + hash)
        .applyTo(context.getEnvironment());
  }
}
