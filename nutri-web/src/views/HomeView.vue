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
          <p class="section-subtitle">从上传到回看，四步完成一轮完整的个人饮食记录。</p>
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
          <h3 class="section-title">为什么建议先设置目标，再完善主页</h3>
          <p class="section-subtitle">目标设置和个人主页已经拆成两个页面，各自更专注，后续每一次记录也会更容易长期追踪。</p>
        </header>
        <div class="editorial-copy">
          <p>完成手机号验证后，新的上传记录和历史数据都会归到你的个人账号下，不会再混到默认演示账号里。</p>
          <p>个人主页现在专门处理账号和昵称，称呼可以单独修改，不会和目标设置混在一起。</p>
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
