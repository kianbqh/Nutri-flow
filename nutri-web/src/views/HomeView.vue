<template>
  <div class="page home-view">
    <section class="home-primary">
      <div class="home-primary__copy">
        <span class="home-eyebrow">Nutri-Flow</span>
        <h2>拍一餐，快速看懂吃了什么</h2>
        <p>识别食物、估算热量，并结合你的目标给出简短建议。</p>
        <RouterLink to="/upload" class="button button--primary">开始分析</RouterLink>
      </div>

      <div class="home-tip">
        <strong>拍摄要点</strong>
        <p>尽量拍完整餐盘，减少遮挡和强反光。</p>
      </div>
    </section>

    <section class="home-actions" aria-label="常用功能">
      <RouterLink to="/history">
        <strong>历史记录</strong>
        <span>回看每餐结果</span>
      </RouterLink>
      <RouterLink to="/goals">
        <strong>目标设置</strong>
        <span>调整热量和饮食目标</span>
      </RouterLink>
      <RouterLink to="/profile">
        <strong>我的账户</strong>
        <span>管理手机号与资料</span>
      </RouterLink>
    </section>
  </div>
</template>

<script setup>
import { RouterLink } from 'vue-router'
</script>

<style scoped>
.home-primary {
  width: 100%;
  min-width: 0;
  min-height: 420px;
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(240px, 0.38fr);
  align-items: end;
  gap: 24px;
  padding: clamp(28px, 6vw, 72px);
  border-radius: 8px;
  color: #fff;
  background: #934f27;
}

.home-primary__copy {
  min-width: 0;
  max-width: 700px;
}

.home-eyebrow {
  display: block;
  margin-bottom: 14px;
  font-size: 0.8rem;
  font-weight: 800;
  text-transform: uppercase;
}

.home-primary h2 {
  max-width: 620px;
  font-size: clamp(2rem, 5vw, 4rem);
  line-height: 1.08;
  letter-spacing: 0;
  overflow-wrap: anywhere;
}

.home-primary__copy p {
  max-width: 560px;
  margin: 18px 0 26px;
  color: rgba(255, 255, 255, 0.88);
  line-height: 1.7;
}

.home-primary .button--primary {
  background: #fff;
  color: #713817;
}

.home-tip {
  padding: 18px;
  border-left: 3px solid rgba(255, 255, 255, 0.72);
  background: rgba(255, 255, 255, 0.1);
}

.home-tip p {
  margin-top: 6px;
  color: rgba(255, 255, 255, 0.82);
  line-height: 1.55;
}

.home-actions {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  border: 1px solid var(--line);
  border-radius: 8px;
  background: #fff;
}

.home-actions a {
  display: grid;
  gap: 5px;
  min-height: 88px;
  padding: 20px;
  min-width: 0;
}

.home-actions a + a {
  border-left: 1px solid var(--line);
}

.home-actions a:hover {
  background: #fff8f1;
}

.home-actions span {
  color: var(--muted);
  font-size: 0.9rem;
}

@media (max-width: 720px) {
  .home-primary {
    min-height: 360px;
    grid-template-columns: 1fr;
    align-items: end;
    overflow: hidden;
  }

  .home-primary h2,
  .home-primary p {
    max-width: 100%;
  }

  .home-actions {
    grid-template-columns: 1fr;
  }

  .home-actions a + a {
    border-left: 0;
    border-top: 1px solid var(--line);
  }
}
</style>
