package com.example.azure.controller;

import org.springframework.web.bind.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/users")
public class UserController {
    private final JdbcTemplate jdbc;

    public UserController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping
    public List<Map<String,Object>> listUsers() {
        return jdbc.queryForList("SELECT id, name, email FROM users ORDER BY id");
    }

    @PostMapping
    public Map<String,Object> createUser(@RequestBody Map<String,String> body) {
        jdbc.update("INSERT INTO users(name,email) VALUES (?, ?)", body.get("name"), body.get("email"));
        return jdbc.queryForMap("SELECT id, name, email FROM users WHERE email = ?", body.get("email"));
    }
}
