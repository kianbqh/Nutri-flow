package com.nutriflow.mq;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nutriflow.model.DietLog;
import com.nutriflow.repository.DietLogRepository;
import com.nutriflow.service.TaskTraceService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;

/**
 * RabbitMQ consumer for AI analysis results.
 *
 * <p>Listens on {@code nutri.food.analysis.result} and writes the payload
 * back into the corresponding {@link DietLog} row so the frontend status
 * endpoint can report {@code COMPLETED}.
 *
 * <p>The queue / binding is declared in {@code RabbitMQConfig}.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class FoodAnalysisResultConsumer {

    private final DietLogRepository dietLogRepository;
    private final ObjectMapper objectMapper;
    private final TaskTraceService taskTraceService;

    /**
     * Handle an inbound analysis-result message from nutri-agent.
     *
     * <p>Expected JSON payload:
     * <pre>
     * {
     *   "taskId": "uuid",
     *   "userId": "1",
     *   "status": "COMPLETED | FAILED",
     *   "adviceReport": "...",
     *   "segmentationResult": { ... }
     * }
     * </pre>
     *
    * @param message raw AMQP message delivered by RabbitMQ
     */
    @RabbitListener(
            queues = "${mq.queue.food-analysis-result}",
            containerFactory = "autoAckContainerFactory"
    )
    public void onAnalysisResult(Message message) {
        String taskId = "unknown";
        try {
            String payloadJson = new String(message.getBody(), StandardCharsets.UTF_8);

            var node = objectMapper.readTree(payloadJson);
            taskId = node.path("taskId").asText("unknown");
            log.info("Received analysis result for task_id={}", taskId);

            final String finalTaskId = taskId;
            dietLogRepository.findByTaskId(taskId).ifPresentOrElse(log_ -> {
                log_.setAnalysisResult(payloadJson);
                dietLogRepository.save(log_);
                String status = node.path("status").asText("COMPLETED");
                taskTraceService.recordEvent(
                        finalTaskId,
                        "DATABASE",
                        "FAILED".equals(status) ? "FAILED" : "COMPLETED",
                        "business",
                        "分析结果已写入 MySQL",
                        null
                );
                log.info("Diet log updated for task_id={}", finalTaskId);
            }, () -> log.warn("No DietLog found for task_id={} – result discarded", finalTaskId));

        } catch (Exception e) {
            log.error("Failed to process analysis result for task_id={}: {}", taskId, e.getMessage(), e);
            // Do NOT re-throw: Spring AMQP will ack the message; unprocessable
            // results should not poison the consumer loop.
        }
    }
}
