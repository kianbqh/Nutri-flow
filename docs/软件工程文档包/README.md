# Software Engineering Document Pack

This directory contains the stable engineering documents for Nutri-flow. It is
the best entry point for reviewers who want to understand the product scope,
architecture, data model, API contracts, test plan, agent workflow, and model
release baseline.

## Documents

1. `01_需求规格说明书.md` - product goals and functional scope
2. `02_用户故事与验收标准.md` - user stories and acceptance criteria
3. `03_系统架构设计文档.md` - service architecture and integration design
4. `04_数据库设计文档.md` - data model and table design
5. `05_接口文档.md` - API behavior and request/response examples
6. `06_技术选型报告.md` - technology choices and trade-offs
7. `07_开发任务分解与实现路线.md` - implementation plan
8. `08_状态机与错误码规范.md` - task states and error handling
9. `09_测试计划与用例矩阵.md` - test strategy and cases
10. `10_UI交互与视觉规范.md` - UI flow and visual rules
11. `11_OpenAPI接口契约.yaml` - OpenAPI contract
12. `12_信息架构与页面流程.md` - page and navigation structure
13. `13_模型现状评估与能力边界.md` - model capability boundaries
14. `14_Agent工作流设计.md` - LangGraph agent workflow
15. `15_本地启动说明与注意事项.md` - local startup guide
16. `16_实验设计与结果归档总报告.md` - experiment summary
17. `17_端到端性能与稳定性验证报告.md` - E2E validation report
18. `18_模型版本基线与默认发布说明.md` - released model baseline
19. `19_毕业论文写作素材提炼.md` - thesis writing material
20. `20_公网用户视角验收测试报告.md` - public-site user acceptance findings

## Reading Path

For a quick project review, read documents 03, 05, 14, 16, and 18 first.
For implementation details, continue with 04, 08, 09, 10, and 15.

## Boundary

Nutri-flow estimates dietary intake for feedback and education. It does not
provide medical diagnosis or clinical nutrition measurement.
