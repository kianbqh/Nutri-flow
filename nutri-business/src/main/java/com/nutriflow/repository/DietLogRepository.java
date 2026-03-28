package com.nutriflow.repository;

import com.nutriflow.model.DietLog;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface DietLogRepository extends JpaRepository<DietLog, Long> {

    /**
     * Look up a diet-log entry by its unique task UUID.
     * Used by the status polling endpoint and the result consumer.
     */
    Optional<DietLog> findByTaskId(String taskId);
}
