package com.avizway.app.controller;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

import java.time.Instant;

/**
 * Serves the Thymeleaf HTML dashboard at GET /.
 * REST endpoints live in ApiController under /api/*.
 */
@Controller
public class AppController {

    @Value("${spring.application.name:eks-cicd-app}")
    private String appName;

    @Value("${APP_VERSION:1.0.0}")
    private String version;

    @GetMapping("/")
    public String home(Model model) {
        model.addAttribute("appName",   appName);
        model.addAttribute("version",   version);
        model.addAttribute("java",      System.getProperty("java.version"));
        model.addAttribute("os",        System.getProperty("os.name"));
        model.addAttribute("timestamp", Instant.now().toString());
        return "index";   // resolves to src/main/resources/templates/index.html
    }
}
