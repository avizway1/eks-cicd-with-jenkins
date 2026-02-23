package com.avizway.app.controller;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.Map;

@RestController
public class AppController {

    @Value("${spring.application.name:eks-cicd-app}")
    private String appName;

    @Value("${APP_VERSION:1.0.0}")
    private String version;

    @GetMapping("/")
    public Map<String, String> home() {
        return Map.of(
            "app",       appName,
            "version",   version,
            "status",    "running",
            "timestamp", Instant.now().toString()
        );
    }

    @GetMapping("/info")
    public Map<String, String> info() {
        return Map.of(
            "app",     appName,
            "version", version,
            "java",    System.getProperty("java.version"),
            "os",      System.getProperty("os.name")
        );
    }
}
