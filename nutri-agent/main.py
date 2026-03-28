"""
nutri-agent – entry point.

Starts the async RabbitMQ consumer that drives the LangGraph dietary-advice
agent for each incoming food-analysis task.
"""

import asyncio
import logging

import structlog

from app.mq_consumer import start_consumer

structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.dev.ConsoleRenderer(),
    ],
    wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
    context_class=dict,
    logger_factory=structlog.PrintLoggerFactory(),
)

logger = structlog.get_logger(__name__)


async def main() -> None:
    logger.info("nutri-agent starting up …")
    await start_consumer()


if __name__ == "__main__":
    asyncio.run(main())
