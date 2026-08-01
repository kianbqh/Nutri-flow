<template>
  <div id="app-root">
    <div v-if="route.meta.admin" class="admin-shell">
      <header class="admin-topbar">
        <div>
          <span>Nutri-Flow</span>
          <strong>运行数据看板</strong>
        </div>
        <RouterLink to="/" class="admin-topbar__back">返回应用</RouterLink>
      </header>
      <main class="admin-main">
        <RouterView />
      </main>
    </div>

    <div v-else class="app-shell">
      <header class="shell-header">
        <RouterLink to="/" class="shell-brand" aria-label="灵动食迹首页">
          <span class="shell-brand__mark">N</span>
          <span><strong>灵动食迹</strong><small>Nutri-Flow</small></span>
        </RouterLink>

        <nav class="shell-nav" aria-label="主导航">
          <RouterLink
            v-for="item in navItems"
            :key="item.to"
            :to="item.to"
            class="shell-nav__link"
            :class="{ 'is-active': route.path === item.to }"
          >
            <span class="shell-nav__label">{{ item.label }}</span>
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
  { to: '/', label: '首页' },
  { to: '/upload', label: '分析' },
  { to: '/history', label: '历史' },
  { to: '/goals', label: '目标' },
  { to: '/profile', label: '我的' },
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
  width: 100%;
  overflow-x: hidden;
}

body {
  font-family: 'Source Han Sans SC', 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', sans-serif;
  color: var(--text);
  background: #f7f6f3;
}

body::before,
body::after {
  display: none;
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
  border-radius: 8px;
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
  width: 100%;
  min-width: 0;
  max-width: 1240px;
  margin: 0 auto;
}

.admin-shell {
  width: 100%;
  max-width: 1380px;
  margin: 0 auto;
}

.admin-topbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 20px;
  margin-bottom: 18px;
  padding: 14px 18px;
  border: 1px solid #d9ddd9;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.94);
  box-shadow: 0 8px 20px rgba(52, 62, 55, 0.07);
}

.admin-topbar > div {
  display: flex;
  align-items: baseline;
  gap: 12px;
}

.admin-topbar span {
  color: #647268;
  font-size: 0.8rem;
  font-weight: 700;
  text-transform: uppercase;
}

.admin-topbar strong {
  color: #233129;
  font-size: 1.05rem;
}

.admin-topbar__back {
  padding: 9px 12px;
  border: 1px solid #cdd5cf;
  border-radius: 6px;
  color: #32463a;
  background: #fff;
  font-weight: 700;
}

.admin-main {
  min-width: 0;
}

.shell-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 24px;
  margin-bottom: 20px;
  padding: 10px 12px;
  border: 1px solid var(--line);
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.94);
  box-shadow: 0 6px 18px rgba(50, 44, 39, 0.05);
}

.shell-brand {
  display: flex;
  align-items: center;
  gap: 10px;
  flex: 0 0 auto;
}

.shell-brand__mark {
  width: 38px;
  height: 38px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: var(--accent);
  color: white;
  font-weight: 900;
}

.shell-brand > span:last-child {
  display: grid;
  gap: 1px;
}

.shell-brand strong {
  font-size: 1rem;
}

.shell-brand small {
  color: var(--muted);
  font-size: 0.72rem;
}

.shell-nav {
  display: flex;
  align-items: center;
  gap: 4px;
}

.shell-nav__link {
  display: grid;
  place-items: center;
  min-height: 40px;
  border-radius: 6px;
  padding: 0 13px;
  border: 1px solid transparent;
  transition: transform 0.2s ease, border-color 0.2s ease, box-shadow 0.2s ease, background 0.2s ease;
}

.shell-nav__link:hover {
  transform: translateY(-2px);
  border-color: rgba(155, 91, 46, 0.34);
  box-shadow: 0 16px 32px rgba(86, 53, 26, 0.08);
}

.shell-nav__link.is-active {
  background: var(--accent-wash);
  border-color: rgba(155, 91, 46, 0.28);
  box-shadow: none;
}

.shell-nav__label {
  font-size: 1rem;
  font-weight: 800;
  color: var(--text);
}

.shell-main {
  display: flex;
  flex-direction: column;
  gap: 24px;
  min-width: 0;
}

.page {
  display: flex;
  flex-direction: column;
  gap: 22px;
  min-width: 0;
}

.page-hero {
  display: grid;
  grid-template-columns: minmax(0, 1.2fr) minmax(280px, 0.8fr);
  gap: 20px;
  padding: clamp(24px, 3vw, 36px);
  border-radius: 8px;
  border: 1px solid rgba(234, 215, 202, 0.9);
  background: linear-gradient(135deg, rgba(255, 246, 237, 0.96), rgba(255, 255, 255, 0.88) 62%, rgba(246, 229, 214, 0.92));
  box-shadow: var(--shadow);
  min-width: 0;
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
  min-width: 0;
  padding: 24px;
  border-radius: 8px;
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
  border-radius: 8px;
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
    padding: 12px 12px 82px;
  }

  .page-hero,
  .surface-card {
    border-radius: 8px;
  }

  .shell-header {
    padding: 8px 10px;
  }

  .shell-nav {
    position: fixed;
    z-index: 20;
    left: 10px;
    right: 10px;
    bottom: 10px;
    display: grid;
    grid-template-columns: repeat(5, minmax(0, 1fr));
    padding: 6px;
    border: 1px solid var(--line);
    border-radius: 8px;
    background: rgba(255, 255, 255, 0.97);
    box-shadow: 0 8px 24px rgba(50, 44, 39, 0.12);
  }

  .shell-nav__link {
    min-height: 42px;
    min-width: 0;
    padding: 0 6px;
    font-size: 0.78rem;
  }

  .page-hero__title {
    font-size: 1.85rem;
  }
}

@media (max-width: 560px) {
  .shell-brand small {
    display: none;
  }

  .page-actions {
    flex-direction: column;
  }

  .button {
    width: 100%;
  }

  .surface-card {
    padding: 18px;
  }

  .admin-topbar {
    align-items: flex-start;
  }

  .admin-topbar > div {
    display: grid;
    gap: 2px;
  }
}
</style>
