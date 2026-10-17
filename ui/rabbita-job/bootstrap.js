import '/styles.css'
import { installBookOutcome } from './book-outcome.js'

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
installBookOutcome(document)

import { installProcedures } from './procedure-controls.js'
installProcedures(document)

import { installBlockedRecovery } from './blocked-recovery-controls.js'
installBlockedRecovery(document)

import { installRework } from "./artifact-rework-controls.js"
installRework(document)

import { installSourceBrief } from './source-brief-controls.js'
installSourceBrief(document)

import { installObservedCases } from './observed-case-controls.js'
installObservedCases(document)

import { installTableInput } from './table-input-controls.js'
installTableInput(document)
import { installTableChanges } from './table-changes-controls.js'
installTableChanges(document)

import { installJSONInput } from './json-input-controls.js'
installJSONInput(document)

import { installJSONChanges } from './json-changes-controls.js'
installJSONChanges(document)
