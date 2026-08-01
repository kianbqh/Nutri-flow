package com.nutriflow.service;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class TaskTraceServiceTest {

    @Test
    void recentTasksDoesNotSortOrGroupByAnalysisPayload() {
        JdbcTemplate jdbcTemplate = mock(JdbcTemplate.class);
        when(jdbcTemplate.query(any(String.class), any(RowMapper.class), anyInt()))
                .thenReturn(List.of());

        new TaskTraceService(jdbcTemplate).recentTasks(12);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbcTemplate).query(sql.capture(), any(RowMapper.class), anyInt());
        assertThat(sql.getValue())
                .contains("JSON_EXTRACT", "SELECT MAX(e.occurred_at)")
                .doesNotContain(
                        "GROUP BY",
                        "SELECT d.task_id, d.meal_type, d.logged_at, d.analysis_result"
                );
    }
}
