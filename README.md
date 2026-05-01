# Nutri-flow
Nutri-Flow (灵动食迹) —— 全栈智慧饮食管理系统

Nutri-Flow 是一款将前沿计算机视觉技术与大模型智能体深度结合的智慧健康应用。系统通过高性能的实例分割技术准确“感知”食物，并利用基于状态机的工作流引擎提供“有温度”的膳食建议。
✨ 核心特性

    多模态感知：采用改进的 Swin Transformer 架构，引入 BiFPN 与坐标注意力机制（Coordinate Attention），实现复杂背景下高精度的食物实例分割。

    智能决策大脑：基于 LangGraph 构建多层 Agent 工作流，集成 RAG（检索增强生成）技术与用户长期记忆模块，提供科学且个性化的营养分析。

    工业级微服务：采用 Spring Boot 与 FastAPI 构建异步解耦架构，通过 RabbitMQ 实现高性能推理任务调度，并遵循 MCP (Model Context Protocol) 协议实现算法与逻辑的标准化通信。

    交互式前端：基于 Vue 3 打造动态 Canvas 蒙版交互，支持实时渲染与用户在线微调分割结果。


Nutri-Flow: A Full-Stack AI-Powered Dietary Management System

Nutri-Flow is an intelligent health application that seamlessly integrates cutting-edge Computer Vision with Large Language Model (LLM) Agents. It "perceives" dietary intake via high-performance instance segmentation and "reasons" through an advanced state-machine workflow engine.
✨ Key Features

    Multimodal Perception: Powered by an enhanced Swin Transformer with BiFPN and Coordinate Attention, delivering high-precision food instance segmentation in complex environments.

    Agentic Decision Brain: A multi-layer workflow built on LangGraph, integrating RAG (Retrieval-Augmented Generation) and long-term user memory for evidence-based, personalized nutritional coaching.

    Industrial Microservices: An asynchronous decoupled architecture using Spring Boot and FastAPI, orchestrated by RabbitMQ for task scheduling, and following the MCP (Model Context Protocol) for standardized tool calling.

    Interactive Frontend: A Vue 3-based interface featuring dynamic Canvas mask rendering, allowing users to interact with and refine segmentation results in real-time.

## Local Dev Quick Start (Windows PowerShell)

Use the following scripts to avoid manual multi-terminal startup and reduce timeout issues caused by missing consumers.

1. Start local stack (infra + inference + business + agent):

    `powershell -ExecutionPolicy Bypass -File scripts/dev-up.ps1`

    If Docker infra is already running:

    `powershell -ExecutionPolicy Bypass -File scripts/dev-up.ps1 -SkipDocker`

2. Health check (HTTP endpoints + RabbitMQ task consumer):

    `powershell -ExecutionPolicy Bypass -File scripts/dev-health.ps1`

3. Stop managed services started by dev-up:

    `powershell -ExecutionPolicy Bypass -File scripts/dev-down.ps1`

Managed logs are written to:

`./.runtime/logs`
