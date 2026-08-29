# syntax=docker/dockerfile:1

# ---- Build stage -------------------------------------------------------------
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /build

# Dependency layer: cached until the POM itself changes.
COPY pom.xml .
RUN mvn -B -ntp dependency:go-offline

COPY src ./src
COPY config ./config
RUN mvn -B -ntp clean package -DskipTests

# ---- Runtime stage -----------------------------------------------------------
FROM eclipse-temurin:17-jre-jammy

# Base-image package patches BEFORE anything else.
#
# Published base images are rebuilt on a cadence, so between rebuilds they carry
# distro CVEs (openssl, libgcrypt, zlib, …) that already HAVE a fix in the Ubuntu
# archive. The container scan runs with --ignore-unfixed, meaning every finding
# it reports is one an upgrade can clear — so `apt-get upgrade` here is the
# direct remedy for the gate rather than a workaround for it.
# Kept in the same layer as the install + cache cleanup so no apt lists remain.
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && apt-get install -y --no-install-recommends curl \
 && groupadd --system --gid 1001 appuser \
 && useradd --system --uid 1001 --gid appuser --home /app --shell /usr/sbin/nologin appuser \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build --chown=appuser:appuser /build/target/app.jar /app/app.jar

# Run as an unprivileged user: a container that never needs root should not have it.
USER appuser

# In-container the app listens on all interfaces; network isolation is the
# container boundary, not the bind address (unlike the VM deployment where nginx
# is the only public entry point).
ENV SERVER_ADDRESS=0.0.0.0 \
    SERVER_PORT=8080 \
    JAVA_OPTS="-XX:MaxRAMPercentage=75.0 -XX:+UseContainerSupport"

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl --fail --silent http://127.0.0.1:8080/actuator/health || exit 1

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
