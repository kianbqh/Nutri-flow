<template>
  <div class="page home-view">
    <section class="page-hero home-hero">
      <div class="page-hero__copy">
        <span class="page-hero__eyebrow">营养记录与分析</span>
        <h2 class="page-hero__title">上传一餐，快速看到热量估算、识别明细和可执行建议</h2>
        <p class="page-hero__subtitle">
          灵动食迹会把图片识别、热量估算、历史记录和个人目标串起来，帮助你更快判断这顿饭吃得是否合适，以及下一餐怎么调整。
        </p>
        <div class="page-actions">
          <RouterLink to="/upload" class="button button--primary">开始一轮分析</RouterLink>
          <RouterLink to="/goals" class="button button--secondary">进入目标设置</RouterLink>
          <RouterLink to="/history" class="button button--soft">查看历史记录</RouterLink>
        </div>
      </div>

      <aside class="hero-aside">
        <div class="metric-card">
          <span>你会得到</span>
          <strong>热量估算与识别明细</strong>
          <p>系统会按图片内容给出食物识别结果、预估重量和热量合计，帮助你快速判断这一餐的结构。</p>
        </div>
        <div class="metric-card">
          <span>建议来源</span>
          <strong>历史记录 + 当前目标</strong>
          <p>建议不只看这一餐，也会参考你的历史饮食记录和当前目标，让提醒更贴近你自己的状态。</p>
        </div>
        <div class="metric-card">
          <span>个人数据</span>
          <strong>跟随账号持续保存</strong>
          <p>完成手机号验证后，历史记录、昵称和个人目标都会持续绑定到你的账号，便于长期回看和对比。</p>
        </div>
      </aside>
    </section>

    <section class="feature-grid">
      <article class="surface-card feature-card">
        <div class="feature-kicker">01</div>
        <h3>上传更顺手</h3>
        <p>选图、预览和开始分析集中在同一区域，上手更直接。</p>
      </article>
      <article class="surface-card feature-card">
        <div class="feature-kicker">02</div>
        <h3>结果更好读</h3>
        <p>热量、识别明细、图像区域和建议分开呈现，阅读更轻松。</p>
      </article>
      <article class="surface-card feature-card">
        <div class="feature-kicker">03</div>
        <h3>记录更连贯</h3>
        <p>从历史回看到目标调整可以顺着完成，方便长期记录和比较。</p>
      </article>
    </section>

    <section class="home-lower">
      <article class="surface-card">
        <header class="section-head">
          <h3 class="section-title">如何开始</h3>
          <p class="section-subtitle">从上传到回看，四步完成一轮完整的个人饮食记录。</p>
        </header>
        <ol class="process-list">
          <li>
            <strong>上传餐图</strong>
            <span>支持点击选择和拖拽导入，先确认照片内容与餐次。</span>
          </li>
          <li>
            <strong>等待分析</strong>
            <span>提交后稍等片刻，结果准备好后会直接显示在当前页面。</span>
          </li>
          <li>
            <strong>查看本餐结果</strong>
            <span>先看总热量、识别明细和图像区域，快速了解这一餐。</span>
          </li>
          <li>
            <strong>结合目标做调整</strong>
            <span>再看建议和历史记录，判断下一餐怎么吃更合适。</span>
          </li>
        </ol>
      </article>

      <article class="surface-card editorial-card">
        <header class="section-head">
          <h3 class="section-title">为什么建议先设置目标，再完善资料</h3>
          <p class="section-subtitle">目标和个人资料补充完整后，后续每一次记录都会更容易长期追踪。</p>
        </header>
        <div class="editorial-copy">
          <p>完成手机号验证后，新的上传记录和历史数据都会保存到你的个人账号下，方便后续持续回看。</p>
          <p>补充昵称和基础资料后，多次回看记录时会更容易识别自己当前的阶段变化。</p>
          <p>目标设置页会长期影响建议内容，让系统更清楚你是想减脂、维持，还是更关注整体均衡。</p>
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
