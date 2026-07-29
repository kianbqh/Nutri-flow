package com.nutriflow.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nutriflow.service.GoalAssistantService.GoalParseInput;
import com.nutriflow.service.GoalAssistantService.GoalParseResult;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class GoalAssistantServiceTest {

    private final GoalAssistantService service = new GoalAssistantService(
            new ObjectMapper(),
            "",
            "https://api.moonshot.cn/v1",
            "moonshot-v1-8k",
            0.3,
            40
    );

    @Test
    void parsesChineseProfileAndGoalFieldsWithoutLlm() {
        GoalParseResult result = service.parse(new GoalParseInput(
                "我是23岁男生，身高178厘米，体重70公斤，每周运动3次，想减脂，每天2000大卡，不吃花生",
                null,
                null,
                null,
                null,
                null
        ));

        assertThat(result.healthGoal()).isEqualTo("WEIGHT_LOSS");
        assertThat(result.age()).isEqualTo(23);
        assertThat(result.heightCm()).isEqualTo(178);
        assertThat(result.weightKg()).isEqualTo(70.0);
        assertThat(result.gender()).isEqualTo("MALE");
        assertThat(result.activityLevel()).isEqualTo("MEDIUM");
        assertThat(result.dailyCalorieTarget()).isEqualTo(2000);
        assertThat(result.dietaryRestrictions()).containsExactly("nuts");
    }

    @Test
    void convertsMetersAndJinAndCalculatesTarget() {
        GoalParseResult result = service.parse(new GoalParseInput(
                "女生，22岁，身高1.65米，体重110斤，平时久坐，想维持体重",
                null,
                null,
                null,
                null,
                null
        ));

        assertThat(result.healthGoal()).isEqualTo("MAINTENANCE");
        assertThat(result.age()).isEqualTo(22);
        assertThat(result.heightCm()).isEqualTo(165);
        assertThat(result.weightKg()).isEqualTo(55.0);
        assertThat(result.gender()).isEqualTo("FEMALE");
        assertThat(result.activityLevel()).isEqualTo("LOW");
        assertThat(result.dailyCalorieTarget()).isBetween(1200, 2200);
    }
}
