FROM maven:3.9.13-eclipse-temurin-21-alpine AS build

WORKDIR /workspace

COPY pom.xml .
RUN mvn -B -q dependency:go-offline

COPY src ./src
RUN mvn -B -q -DskipTests package

FROM eclipse-temurin:21-jre-alpine

RUN addgroup -S nutri && adduser -S -G nutri -u 10001 nutri

WORKDIR /app
COPY --from=build /workspace/target/nutri-business-*.jar /app/app.jar

LABEL org.opencontainers.image.version="1.1.0"

ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/urandom"

USER nutri
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
