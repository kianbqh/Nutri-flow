<template>
  <div class="page home-view">
    <section class="page-hero home-hero">
      <div class="page-hero__copy">
        <span class="page-hero__eyebrow">桌面端营养分析台</span>
        <h2 class="page-hero__title">把一次餐食分析，拆成更顺手的上传、判断和回看流程</h2>
        <p class="page-hero__subtitle">
          这里延续移动端的暖色卡片语言，但更强调桌面端的模块排布、双列信息密度和稳定导航，让分析结果更适合停下来阅读与比较。
        </p>
        <div class="page-actions">
          <RouterLink to="/upload" class="button button--primary">开始一轮分析</RouterLink>
          <RouterLink to="/profile" class="button button--secondary">先设置目标</RouterLink>
          <RouterLink to="/history" class="button button--soft">查看历史记录</RouterLink>
        </div>
      </div>

      <aside class="hero-aside">
        <div class="metric-card">
          <span>识别主线</span>
          <strong>Swin Transformer 分割</strong>
          <p>围绕真实餐图做区域识别和营养估算，先拿到可读结果，再延展到建议生成。</p>
        </div>
        <div class="metric-card">
          <span>建议主线</span>
          <strong>历史 + 目标 + RAG</strong>
          <p>不只看这顿饭，还会参考近期记录和用户目标，给出更贴近当前状态的建议。</p>
        </div>
        <div class="metric-card">
          <span>适配方向</span>
          <strong>保留产品感，但更像工作台</strong>
          <p>网页端不照搬手机页面，而是把结构、留白和信息层级重新整理成桌面阅读节奏。</p>
        </div>
      </aside>
    </section>

    <section class="feature-grid">
      <article class="surface-card feature-card">
        <div class="feature-kicker">01</div>
        <h3>上传区更聚焦</h3>
        <p>把拖拽、预览、餐次和分析按钮聚到一块，减少页面切换感，适合桌面连续操作。</p>
      </article>
      <article class="surface-card feature-card">
        <div class="feature-kicker">02</div>
        <h3>结果区更清晰</h3>
        <p>总热量、识别项、分割图和建议分层展示，不再把所有信息堆在一个白板里。</p>
      </article>
      <article class="surface-card feature-card">
        <div class="feature-kicker">03</div>
        <h3>历史与目标一体化</h3>
        <p>从记录回看再到目标调整，视觉风格保持统一，避免不同页面像不同产品。</p>
      </article>
    </section>

    <section class="home-lower">
      <article class="surface-card">
        <header class="section-head">
          <h3 class="section-title">标准流程</h3>
          <p class="section-subtitle">网页端把分析链路拆成更容易理解的四步，适合演示和连续对比。</p>
        </header>
        <ol class="process-list">
          <li>
            <strong>上传餐图</strong>
            <span>支持点击选择和拖拽导入，先确认照片内容与餐次。</span>
          </li>
          <li>
            <strong>等待分析</strong>
            <span>轮询任务状态，并在结果到达后直接留在当前页继续阅读。</span>
          </li>
          <li>
            <strong>查看结构化结果</strong>
            <span>用总热量、识别表格和分割区域把这顿饭的结构先讲清楚。</span>
          </li>
          <li>
            <strong>结合目标做判断</strong>
            <span>再往下看 AI 建议和历史记录，让“是什么”过渡到“接下来怎么吃”。</span>
          </li>
        </ol>
      </article>

      <article class="surface-card editorial-card">
        <header class="section-head">
          <h3 class="section-title">这次网页端同步的原则</h3>
          <p class="section-subtitle">不是把手机页面等比放大，而是把视觉语言和信息气质迁到更适合大屏的节奏里。</p>
        </header>
        <div class="editorial-copy">
          <p>保留移动端已经建立起来的暖色渐变、柔和卡片和产品化语气。</p>
          <p>改成更适合桌面的顶部导航、双列布局、宽边距和更明确的模块层级。</p>
          <p>让首页、分析台、历史和目标页能自然串起来，而不是只有首页好看。</p>
        </div>
      </article>
    </section>
  </div>
</template>

<script setup>
import { RouterLink } from 'vue-router'
</script>

<style scoped>
.hero-aside {
  display: grid;
  gap: 14px;
}

.feature-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 18px;
}

.feature-card {
  min-height: 220px;
}

.feature-kicker {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 48px;
  height: 32px;
  border-radius: 999px;
  background: rgba(255, 241, 227, 0.95);
  color: var(--accent-strong);
  font-size: 0.8rem;
  font-weight: 800;
  letter-spacing: 0.1em;
}

.feature-card h3 {
  margin-top: 18px;
  font-size: 1.25rem;
  font-weight: 800;
  letter-spacing: -0.02em;
}

.feature-card p {
  margin-top: 12px;
  color: var(--muted);
  line-height: 1.7;
}

.home-lower {
  display: grid;
  grid-template-columns: minmax(0, 1.15fr) minmax(280px, 0.85fr);
  gap: 18px;
}

.process-list {
  display: grid;
  gap: 14px;
  list-style: none;
  counter-reset: flow-step;
}

.process-list li {
  display: grid;
  gap: 6px;
  padding: 18px 18px 18px 62px;
  position: relative;
  border-radius: 22px;
  background: linear-gradient(180deg, rgba(255, 248, 241, 0.98), rgba(255, 255, 255, 0.98));
  border: 1px solid rgba(238, 224, 213, 0.95);
}

.process-list li::before {
  counter-increment: flow-step;
  content: counter(flow-step);
  position: absolute;
  left: 18px;
  top: 18px;
  width: 30px;
  height: 30px;
  display: grid;
  place-items: center;
  border-radius: 50%;
  background: linear-gradient(135deg, var(--accent-strong), var(--accent));
  color: #fffaf6;
  font-weight: 800;
}

.process-list strong {
  font-size: 1rem;
}

.process-list span {
  color: var(--muted);
  line-height: 1.6;
}

.editorial-card {
  background: linear-gradient(180deg, rgba(255, 252, 248, 0.98), rgba(249, 238, 227, 0.92));
}

.editorial-copy {
  display: grid;
  gap: 12px;
}

.editorial-copy p {
  padding: 14px 16px;
  border-radius: 20px;
  background: rgba(255, 255, 255, 0.76);
  color: var(--muted);
  line-height: 1.7;
}

@media (max-width: 1024px) {
  .feature-grid,
  .home-lower {
    grid-template-columns: 1fr;
  }
}
</style>
