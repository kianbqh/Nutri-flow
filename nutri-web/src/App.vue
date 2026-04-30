<template>
  <div id="app-root">
    <div class="app-shell">
      <header class="shell-header">
        <section class="brand-block">
          <div class="brand-kicker">
            <span class="brand-kicker__dot"></span>
            Nutri-Flow Web
          </div>
          <div class="brand-copy">
            <h1>灵动食迹</h1>
            <p>把移动端的暖色产品感延展到更适合桌面阅读和操作的营养分析工作台。</p>
          </div>
        </section>

        <nav class="shell-nav" aria-label="主导航">
          <RouterLink
            v-for="item in navItems"
            :key="item.to"
            :to="item.to"
            class="shell-nav__link"
            :class="{ 'is-active': route.path === item.to }"
          >
            <span class="shell-nav__label">{{ item.label }}</span>
            <span class="shell-nav__hint">{{ item.hint }}</span>
          </RouterLink>
        </nav>
      </header>

      <main class="shell-main">
        <RouterView />
      </main>
    </div>
  </div>
</template>

<script setup>
import { RouterLink, RouterView, useRoute } from 'vue-router'

const route = useRoute()

const navItems = [
  { to: '/', label: '首页', hint: '整体入口' },
  { to: '/upload', label: '分析台', hint: '上传与结果' },
  { to: '/history', label: '历史', hint: '记录回看' },
  { to: '/profile', label: '目标', hint: '个性化设置' },
]
</script>

<style>
:root {
  --page-bg: #fbf5ef;
  --surface: rgba(255, 255, 255, 0.82);
  --surface-strong: #fffdfa;
  --line: #ead7ca;
  --text: #2f251d;
  --muted: #76685d;
  --muted-soft: #9a887a;
  --accent: #9b5b2e;
  --accent-strong: #7c4723;
  --accent-soft: #f4c8a8;
  --accent-wash: #fff1e3;
  --success: #41715b;
  --warning: #ba7a2b;
  --danger: #bd4f40;
  --shadow: 0 20px 52px rgba(86, 53, 26, 0.1);
  --shadow-soft: 0 12px 28px rgba(86, 53, 26, 0.08);
}

* {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

html,
body,
#app {
  min-height: 100%;
}

body {
  font-family: 'Source Han Sans SC', 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', sans-serif;
  color: var(--text);
  background:
    radial-gradient(circle at top right, rgba(244, 200, 168, 0.4), transparent 24%),
    radial-gradient(circle at left 30%, rgba(221, 170, 131, 0.18), transparent 22%),
    linear-gradient(180deg, #fcf7f1 0%, #f7efe7 48%, #f8f1ea 100%);
}

body::before,
body::after {
  content: '';
  position: fixed;
  z-index: -1;
  border-radius: 999px;
  filter: blur(12px);
}

body::before {
  top: 72px;
  right: -60px;
  width: 220px;
  height: 220px;
  background: radial-gradient(circle, rgba(255, 223, 196, 0.9), rgba(255, 223, 196, 0));
}

body::after {
  left: -70px;
  bottom: 80px;
  width: 240px;
  height: 240px;
  background: radial-gradient(circle, rgba(233, 164, 112, 0.22), rgba(233, 164, 112, 0));
}

a {
  color: inherit;
  text-decoration: none;
}

button,
input,
select,
textarea {
  font: inherit;
}

input,
select,
textarea {
  width: 100%;
  border: 1px solid var(--line);
  border-radius: 18px;
  padding: 14px 16px;
  color: var(--text);
  background: rgba(255, 255, 255, 0.92);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.85);
  transition: border-color 0.2s ease, box-shadow 0.2s ease, transform 0.2s ease;
}

input:focus,
select:focus,
textarea:focus {
  outline: none;
  border-color: rgba(155, 91, 46, 0.72);
  box-shadow: 0 0 0 4px rgba(236, 186, 148, 0.28);
}

#app-root {
  min-height: 100vh;
  padding: 28px clamp(16px, 3.5vw, 40px) 40px;
}

.app-shell {
  max-width: 1240px;
  margin: 0 auto;
}

.shell-header {
  display: grid;
  grid-template-columns: minmax(0, 1.25fr) minmax(360px, 0.95fr);
  gap: 20px;
  align-items: stretch;
  margin-bottom: 28px;
}

.brand-block {
  position: relative;
  overflow: hidden;
  border-radius: 32px;
  padding: 26px 28px;
  color: #fffaf6;
  background: linear-gradient(135deg, rgba(124, 71, 35, 0.98), rgba(214, 134, 73, 0.94) 58%, rgba(243, 206, 174, 0.92));
  box-shadow: 0 28px 56px rgba(139, 82, 43, 0.2);
}

.brand-block::after {
  content: '';
  position: absolute;
  width: 240px;
  height: 240px;
  right: -70px;
  bottom: -120px;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(255, 245, 236, 0.66), rgba(255, 245, 236, 0));
}

.brand-kicker {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  padding: 10px 14px;
  border-radius: 999px;
  border: 1px solid rgba(255, 255, 255, 0.32);
  background: rgba(255, 255, 255, 0.12);
  color: rgba(255, 250, 245, 0.94);
  font-size: 0.83rem;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.brand-kicker__dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #fff6ee;
  box-shadow: 0 0 0 6px rgba(255, 246, 238, 0.14);
}

.brand-copy {
  position: relative;
  z-index: 1;
  margin-top: 18px;
}

.brand-copy h1 {
  font-size: clamp(2rem, 4vw, 3.35rem);
  line-height: 1.05;
  letter-spacing: -0.04em;
  font-weight: 800;
}

.brand-copy p {
  max-width: 640px;
  margin-top: 12px;
  line-height: 1.7;
  color: rgba(255, 249, 244, 0.88);
  font-size: 1rem;
}

.shell-nav {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 14px;
  padding: 16px;
  border-radius: 32px;
  background: rgba(255, 255, 255, 0.62);
  border: 1px solid rgba(255, 255, 255, 0.58);
  backdrop-filter: blur(18px);
  box-shadow: var(--shadow-soft);
}

.shell-nav__link {
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-height: 96px;
  border-radius: 24px;
  padding: 16px 18px;
  border: 1px solid rgba(234, 215, 202, 0.9);
  background: rgba(255, 252, 248, 0.85);
  transition: transform 0.2s ease, border-color 0.2s ease, box-shadow 0.2s ease, background 0.2s ease;
}

.shell-nav__link:hover {
  transform: translateY(-2px);
  border-color: rgba(155, 91, 46, 0.34);
  box-shadow: 0 16px 32px rgba(86, 53, 26, 0.08);
}

.shell-nav__link.is-active {
  background: linear-gradient(180deg, rgba(255, 244, 233, 0.96), rgba(255, 255, 255, 0.96));
  border-color: rgba(155, 91, 46, 0.42);
  box-shadow: 0 16px 32px rgba(139, 82, 43, 0.12);
}

.shell-nav__label {
  font-size: 1rem;
  font-weight: 800;
  color: var(--text);
}

.shell-nav__hint {
  color: var(--muted);
  line-height: 1.45;
  font-size: 0.9rem;
}

.shell-main {
  display: flex;
  flex-direction: column;
  gap: 24px;
}

.page {
  display: flex;
  flex-direction: column;
  gap: 22px;
}

.page-hero {
  display: grid;
  grid-template-columns: minmax(0, 1.2fr) minmax(280px, 0.8fr);
  gap: 20px;
  padding: clamp(24px, 3vw, 36px);
  border-radius: 32px;
  border: 1px solid rgba(234, 215, 202, 0.9);
  background: linear-gradient(135deg, rgba(255, 246, 237, 0.96), rgba(255, 255, 255, 0.88) 62%, rgba(246, 229, 214, 0.92));
  box-shadow: var(--shadow);
}

.page-hero__copy {
  display: flex;
  flex-direction: column;
  justify-content: center;
}

.page-hero__eyebrow {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  align-self: flex-start;
  border-radius: 999px;
  padding: 9px 14px;
  background: var(--accent-wash);
  color: var(--accent-strong);
  font-size: 0.84rem;
  font-weight: 700;
}

.page-hero__title {
  margin-top: 16px;
  font-size: clamp(2rem, 3.4vw, 3rem);
  line-height: 1.08;
  letter-spacing: -0.04em;
  font-weight: 800;
}

.page-hero__subtitle {
  margin-top: 12px;
  max-width: 60ch;
  color: var(--muted);
  line-height: 1.75;
  font-size: 1rem;
}

.page-actions {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
  margin-top: 20px;
}

.surface-card {
  padding: 24px;
  border-radius: 28px;
  background: var(--surface-strong);
  border: 1px solid rgba(234, 215, 202, 0.92);
  box-shadow: var(--shadow-soft);
}

.section-head {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin-bottom: 18px;
}

.section-title {
  font-size: 1.22rem;
  font-weight: 800;
  letter-spacing: -0.02em;
}

.section-subtitle {
  color: var(--muted);
  line-height: 1.6;
}

.metric-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  gap: 14px;
}

.metric-card {
  padding: 18px 20px;
  border-radius: 22px;
  border: 1px solid rgba(238, 224, 213, 0.95);
  background: linear-gradient(180deg, rgba(255, 249, 242, 0.98), rgba(255, 255, 255, 0.98));
}

.metric-card span {
  display: block;
  color: var(--muted-soft);
  font-size: 0.85rem;
  margin-bottom: 8px;
}

.metric-card strong {
  display: block;
  font-size: 1.15rem;
  line-height: 1.3;
  font-weight: 800;
}

.metric-card p {
  margin-top: 8px;
  color: var(--muted);
  line-height: 1.55;
  font-size: 0.93rem;
}

.button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  min-height: 48px;
  padding: 12px 20px;
  border: 1px solid transparent;
  border-radius: 999px;
  font-weight: 700;
  transition: transform 0.2s ease, box-shadow 0.2s ease, border-color 0.2s ease, background 0.2s ease;
  cursor: pointer;
}

.button:hover:not(:disabled) {
  transform: translateY(-1px);
}

.button:disabled {
  opacity: 0.58;
  cursor: not-allowed;
}

.button--primary {
  color: #fffaf6;
  background: linear-gradient(135deg, var(--accent-strong), var(--accent));
  box-shadow: 0 16px 26px rgba(124, 71, 35, 0.2);
}

.button--secondary {
  color: var(--text);
  background: rgba(255, 255, 255, 0.82);
  border-color: rgba(234, 215, 202, 0.92);
}

.button--soft {
  color: var(--accent-strong);
  background: var(--accent-wash);
  border-color: rgba(242, 200, 168, 0.8);
}

.soft-note {
  padding: 16px 18px;
  border-radius: 22px;
  border: 1px solid rgba(234, 215, 202, 0.92);
  background: rgba(255, 251, 247, 0.88);
  color: var(--muted);
  line-height: 1.6;
}

.soft-note--error {
  color: var(--danger);
  border-color: rgba(189, 79, 64, 0.18);
  background: rgba(253, 241, 239, 0.88);
}

.status-pill {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 78px;
  padding: 8px 12px;
  border-radius: 999px;
  font-size: 0.84rem;
  font-weight: 700;
}

.status-pill--completed {
  color: #204a3b;
  background: rgba(206, 233, 219, 0.9);
}

.status-pill--pending {
  color: #7f561e;
  background: rgba(251, 228, 188, 0.95);
}

.status-pill--failed {
  color: #893d32;
  background: rgba(249, 214, 209, 0.92);
}

.empty-state {
  text-align: center;
  color: var(--muted);
  padding: 48px 24px;
}

@media (max-width: 1024px) {
  .shell-header,
  .page-hero {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 720px) {
  #app-root {
    padding: 18px 14px 28px;
  }

  .brand-block,
  .shell-nav,
  .page-hero,
  .surface-card {
    border-radius: 24px;
  }

  .shell-nav {
    grid-template-columns: 1fr 1fr;
  }

  .shell-nav__link {
    min-height: 82px;
    padding: 14px;
  }

  .page-hero__title {
    font-size: 1.85rem;
  }
}

@media (max-width: 560px) {
  .shell-nav {
    grid-template-columns: 1fr;
  }

  .page-actions {
    flex-direction: column;
  }

  .button {
    width: 100%;
  }
}
</style>
