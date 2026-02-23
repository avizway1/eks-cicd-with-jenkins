package com.avizway.app.controller;

import org.springframework.web.bind.annotation.*;

import java.time.Year;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * REST endpoints consumed by the Thymeleaf UI via fetch().
 * All responses are JSON — no view resolution here.
 */
@RestController
@RequestMapping("/api")
public class ApiController {

    // ── /api/info ────────────────────────────────────────────────────────────
    @GetMapping("/info")
    public Map<String, String> info() {
        return Map.of(
            "app",     "eks-cicd-app",
            "version", System.getenv().getOrDefault("APP_VERSION", "1.0.0"),
            "java",    System.getProperty("java.version"),
            "os",      System.getProperty("os.name")
        );
    }

    // ── POST /api/bmi ─────────────────────────────────────────────────────────
    // Params: weight (kg), height (cm)
    @PostMapping("/bmi")
    public Map<String, Object> bmi(@RequestParam double weight,
                                   @RequestParam double height) {
        Map<String, Object> res = new LinkedHashMap<>();
        if (weight <= 0 || height <= 0) {
            res.put("error", "Weight and height must be positive numbers.");
            return res;
        }
        double heightM = height / 100.0;
        double bmi     = weight / (heightM * heightM);
        String category;
        String tip;
        if      (bmi < 18.5) { category = "Underweight"; tip = "Consider a nutritious, calorie-rich diet."; }
        else if (bmi < 25.0) { category = "Normal";      tip = "Great! Maintain your healthy lifestyle.";  }
        else if (bmi < 30.0) { category = "Overweight";  tip = "Regular exercise and balanced diet help."; }
        else                  { category = "Obese";       tip = "Consult a healthcare professional.";       }

        res.put("bmi",      Math.round(bmi * 10.0) / 10.0);
        res.put("category", category);
        res.put("tip",      tip);
        return res;
    }

    // ── POST /api/interest ────────────────────────────────────────────────────
    // Params: principal, rate (% per annum), years
    @PostMapping("/interest")
    public Map<String, Object> interest(@RequestParam double principal,
                                        @RequestParam double rate,
                                        @RequestParam int    years) {
        Map<String, Object> res = new LinkedHashMap<>();
        if (principal <= 0 || rate <= 0 || years <= 0) {
            res.put("error", "All values must be positive.");
            return res;
        }
        double interest = (principal * rate * years) / 100.0;
        double total    = principal + interest;

        res.put("principal", Math.round(principal * 100.0) / 100.0);
        res.put("interest",  Math.round(interest  * 100.0) / 100.0);
        res.put("total",     Math.round(total     * 100.0) / 100.0);
        return res;
    }

    // ── POST /api/age ─────────────────────────────────────────────────────────
    // Params: birthYear
    @PostMapping("/age")
    public Map<String, Object> age(@RequestParam int birthYear) {
        Map<String, Object> res = new LinkedHashMap<>();
        int currentYear = Year.now().getValue();
        if (birthYear < 1900 || birthYear > currentYear) {
            res.put("error", "Please enter a valid birth year (1900 – " + currentYear + ").");
            return res;
        }
        int age          = currentYear - birthYear;
        int daysLived    = age * 365;
        int heartbeats   = age * 365 * 24 * 60 * 70; // ~70 bpm average

        res.put("age",        age);
        res.put("daysLived",  daysLived);
        res.put("heartbeats", heartbeats);
        res.put("nextYear",   birthYear + age + 1);
        return res;
    }
}
