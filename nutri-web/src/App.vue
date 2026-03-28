<template>
  <div id="app-root">
    <header class="app-header">
      <h1>🥗 灵动食迹 · Nutri-Flow</h1>
    </header>
    <main>
      <RouterView />
    </main>
  </div>
</template>

<script setup>
import { RouterView } from 'vue-router'
</script>

<style>
* {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

body {
  font-family: 'PingFang SC', 'Microsoft YaHei', sans-serif;
  background: #f5f7fa;
  color: #333;
}

.app-header {
  background: linear-gradient(135deg, #4caf50, #2196f3);
  color: white;
  padding: 1rem 2rem;
}

.app-header h1 {
  font-size: 1.5rem;
}

main {
  padding: 2rem;
}
</style>
