# =============================================================================
# Multi-Stage Dockerfile for Spring Boot Application
# Stage 1 : Build  (Maven + JDK 17)
# Stage 2 : Runtime (JRE 17 slim — minimal attack surface)
# =============================================================================

# ── Stage 1: Build ───────────────────────────────────────────────────────────
FROM maven:3.9.6-eclipse-temurin-17 AS builder

WORKDIR /build

# Copy dependency descriptor first — Docker layer cache reuses this
# unless pom.xml changes, so subsequent builds are faster.
COPY pom.xml .
RUN mvn dependency:go-offline -B --quiet

# Copy source and build the fat JAR
COPY src ./src
RUN mvn clean package -DskipTests -B --quiet

# ── Stage 2: Runtime ─────────────────────────────────────────────────────────
FROM eclipse-temurin:17-jre-jammy AS runtime

# Security: run as non-root
RUN groupadd --gid 1001 appgroup && \
    useradd  --uid 1001 --gid appgroup --shell /bin/false --no-create-home appuser

WORKDIR /app

# Copy only the fat JAR from the build stage
COPY --from=builder /build/target/*.jar app.jar

# Correct ownership
RUN chown appuser:appgroup app.jar

USER appuser

# Spring Boot default port
EXPOSE 8080

# JVM tuning: use container-aware memory settings
ENV JAVA_OPTS="-XX:+UseContainerSupport \
               -XX:MaxRAMPercentage=75.0 \
               -XX:+ExitOnOutOfMemoryError \
               -Djava.security.egd=file:/dev/./urandom"

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
