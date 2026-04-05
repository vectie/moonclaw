import '/styles.css'

const app = document.getElementById('app')

if (app) {
  app.innerHTML = `
    <div class="shell">
      <header class="topbar">
        <div>
          <p class="eyebrow">MoonClaw Console</p>
          <h1 class="headline">Loading Rabbita</h1>
          <p class="subline">Preparing cowork, jobs, and ACP surfaces.</p>
        </div>
      </header>
    </div>
  `
}

import('/main.js')
