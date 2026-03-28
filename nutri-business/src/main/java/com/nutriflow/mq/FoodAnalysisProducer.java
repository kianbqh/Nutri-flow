package com.nutriflow.mq;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Publishes image-analysis tasks to RabbitMQ.
 * Java business layer is the sole producer; nutri-agent is the sole consumer.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class FoodAnalysisProducer {

    private final RabbitTemplate rabbitTemplate;

    @Value("${mq.exchange.food-analysis}")
    private String exchange;

    @Value("${mq.routing-key.task}")
    private String taskRoutingKey;

    /**
     * Publishes an {@link ImageAnalysisTaskMessage} to the food-analysis exchange.
     *
     * @param message the task payload
     */
    public void publishTask(ImageAnalysisTaskMessage message) {
        log.info("Publishing food-analysis task: taskId={}, userId={}", message.getTaskId(), message.getUserId());
        rabbitTemplate.convertAndSend(exchange, taskRoutingKey, message);
        log.debug("Task published successfully: {}", message.getTaskId());
    }
}
