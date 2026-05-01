package com.nutriflow.service;

import com.nutriflow.model.User;
import com.nutriflow.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.util.concurrent.ThreadLocalRandom;

@Service
@RequiredArgsConstructor
public class UserNicknameService {

    private static final String NICKNAME_PREFIX = "食迹用户";
    private static final int MAX_ATTEMPTS = 64;

    private final UserRepository userRepository;

    public User ensureNickname(User user) {
        if (StringUtils.hasText(user.getNickname())) {
            return user;
        }

        for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
            String candidate = nextCandidate();
            if (userRepository.existsByNickname(candidate)) {
                continue;
            }

            user.setNickname(candidate);
            try {
                return userRepository.saveAndFlush(user);
            } catch (DataIntegrityViolationException ex) {
                user.setNickname(null);
            }
        }

        throw new IllegalStateException("Unable to generate a unique nickname");
    }

    private String nextCandidate() {
        int value = ThreadLocalRandom.current().nextInt(0, 1_000_000);
        return NICKNAME_PREFIX + String.format("%06d", value);
    }
}