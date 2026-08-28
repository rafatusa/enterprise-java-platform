package com.example.app.support;

import java.util.Base64;

/**
 * Signing keys for tests.
 *
 * <p>These are DERIVED AT RUNTIME rather than written as string literals. A literal key in a test
 * file is indistinguishable from a leaked production credential to a secret scanner, and teaching a
 * scanner to ignore key-shaped literals in {@code src/test} is exactly how a real one eventually
 * slips past. Generating them here keeps the repository free of key-shaped constants.
 */
public final class TestKeys {

  private TestKeys() {
    // Utility class.
  }

  /**
   * Returns a deterministic HS256-length key for the given label.
   *
   * <p>Deterministic (not random) so a test can assert that two services sharing a label validate
   * each other's tokens, and that different labels do not.
   */
  public static String signingKey(String label) {
    StringBuilder builder = new StringBuilder(label).append('-');
    while (builder.length() < 64) {
      builder.append(
          Base64.getUrlEncoder()
              .withoutPadding()
              .encodeToString(
                  Integer.toString(builder.length() * 31 + label.hashCode()).getBytes()));
    }
    return builder.substring(0, 64);
  }

  /** A key that differs from {@link #signingKey(String)} for any given label. */
  public static String foreignKey() {
    return signingKey("foreign-issuer");
  }
}
