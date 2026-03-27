package com.nutriflow.config;

import org.springframework.amqp.core.*;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.amqp.support.converter.Jackson2JsonMessageConverter;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Declares RabbitMQ topology: topic exchange, task queue, result queue,
 * and their bindings.
 */
@Configuration
public class RabbitMQConfig {

    @Value("${mq.exchange.food-analysis}")
    private String exchangeName;

    @Value("${mq.queue.food-analysis-task}")
    private String taskQueueName;

    @Value("${mq.queue.food-analysis-result}")
    private String resultQueueName;

    @Value("${mq.routing-key.task}")
    private String taskRoutingKey;

    @Value("${mq.routing-key.result}")
    private String resultRoutingKey;

    // ── Exchange ──────────────────────────────────────────────────────────

    @Bean
    public TopicExchange foodAnalysisExchange() {
        return ExchangeBuilder
                .topicExchange(exchangeName)
                .durable(true)
                .build();
    }

    // ── Queues ────────────────────────────────────────────────────────────

    @Bean
    public Queue foodAnalysisTaskQueue() {
        return QueueBuilder.durable(taskQueueName).build();
    }

    @Bean
    public Queue foodAnalysisResultQueue() {
        return QueueBuilder.durable(resultQueueName).build();
    }

    // ── Bindings ──────────────────────────────────────────────────────────

    @Bean
    public Binding taskQueueBinding() {
        return BindingBuilder
                .bind(foodAnalysisTaskQueue())
                .to(foodAnalysisExchange())
                .with(taskRoutingKey);
    }

    @Bean
    public Binding resultQueueBinding() {
        return BindingBuilder
                .bind(foodAnalysisResultQueue())
                .to(foodAnalysisExchange())
                .with(resultRoutingKey);
    }

    // ── Message converter (JSON) ──────────────────────────────────────────

    @Bean
    public MessageConverter jsonMessageConverter() {
        return new Jackson2JsonMessageConverter();
    }

    @Bean
    public RabbitTemplate rabbitTemplate(ConnectionFactory connectionFactory) {
        RabbitTemplate template = new RabbitTemplate(connectionFactory);
        template.setMessageConverter(jsonMessageConverter());
        template.setMandatory(true);
        return template;
    }
}
