<template>
  <div class="home-view">
    <section class="hero">
      <h2>智慧饮食管家</h2>
      <p>上传您的餐食照片，AI 将自动识别食物、计算营养，并为您提供个性化膳食建议。</p>
      <div class="hero-actions">
        <RouterLink to="/upload" class="btn-primary">开始分析 →</RouterLink>
        <RouterLink to="/profile" class="btn-secondary">设置目标</RouterLink>
        <RouterLink to="/history" class="btn-secondary">历史记录</RouterLink>
      </div>
    </section>

    <section class="features">
      <div class="feature-card">
        <span class="feature-icon">🔬</span>
        <h3>Swin Transformer 精准分割</h3>
        <p>基于改进的 BiFPN + Coordinate Attention 模型，精准识别每道菜肴。</p>
      </div>
      <div class="feature-card">
        <span class="feature-icon">🤖</span>
        <h3>LangGraph 智能体建议</h3>
        <p>结合 RAG 知识库与个人饮食历史，生成个性化营养建议报告。</p>
      </div>
      <div class="feature-card">
        <span class="feature-icon">📊</span>
        <h3>全方位营养追踪</h3>
        <p>实时记录热量、蛋白质、脂肪、碳水化合物，助力健康目标。</p>
      </div>
    </section>
  </div>
</template>

<script setup>
import { RouterLink } from 'vue-router'
</script>

<style scoped>
.home-view {
  max-width: 960px;
  margin: 0 auto;
}

.hero {
  text-align: center;
  padding: 3rem 1rem;
}

.hero h2 {
  font-size: 2rem;
  margin-bottom: 1rem;
  color: #2e7d32;
}

.hero p {
  font-size: 1.1rem;
  color: #555;
  margin-bottom: 1.5rem;
}

.btn-primary {
  display: inline-block;
  background: linear-gradient(135deg, #4caf50, #2196f3);
  color: white;
  padding: 0.75rem 2rem;
  border-radius: 24px;
  text-decoration: none;
  font-weight: bold;
  transition: opacity 0.2s;
}

.hero-actions {
  display: flex;
  gap: 0.75rem;
  justify-content: center;
  flex-wrap: wrap;
}

.btn-secondary {
  display: inline-block;
  background: #ffffff;
  color: #2e7d32;
  border: 1px solid #2e7d32;
  padding: 0.75rem 2rem;
  border-radius: 24px;
  text-decoration: none;
  font-weight: bold;
}

.btn-primary:hover {
  opacity: 0.85;
}

.features {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
  gap: 1.5rem;
  padding: 1rem 0 2rem;
}

.feature-card {
  background: white;
  border-radius: 12px;
  padding: 1.5rem;
  box-shadow: 0 2px 8px rgba(0,0,0,0.08);
  text-align: center;
}

.feature-icon {
  font-size: 2rem;
}

.feature-card h3 {
  margin: 0.75rem 0 0.5rem;
  color: #333;
}

.feature-card p {
  font-size: 0.9rem;
  color: #666;
}
</style>
