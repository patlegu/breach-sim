<script lang="ts">
  import { onMount, onDestroy } from 'svelte'
  import NetworkTopology from './lib/components/NetworkTopology.svelte'
  import StepCard from './lib/components/StepCard.svelte'
  import ScenarioSelector from './lib/components/ScenarioSelector.svelte'
  import TpotWidget from './lib/components/TpotWidget.svelte'
  import { scenarioStore } from './lib/stores/scenarioStore'
  import { topologyStore } from './lib/stores/topologyStore'
  import { animStore } from './lib/stores/animStore'
  import {
    connectDemoSSE, triggerScenario, resetScenario, fetchHealth, fetchLab,
    fetchScenarios, fetchScenario,
    type ScenarioMeta, type ScenarioDetail, type ScenarioStep, type LabConfig,
  } from './lib/utils/demoApi'

  import { tpotStore } from './lib/stores/tpotStore'

  // ── État modèles ──────────────────────────────────────────────────────────
  let ready = false
  let loadedModels: string[] = []
  let modelInfo: Record<string, { name: string; precision: string }> = {}
  let errorMsg = ''
  let disconnectSSE: (() => void) | null = null
  let labConfig: LabConfig | null = null

  // ── Scénarios ─────────────────────────────────────────────────────────────
  let scenarios: ScenarioMeta[] = []
  let selectedId: string | null = null
  let currentScenario: ScenarioDetail | null = null
  let steps: ScenarioStep[] = []
  let attackerIp = '?'
  let attackerRole = 'Attaquant externe'

  // Métadonnées attaquant par scénario
  const ATTACKER_META: Record<string, { ip: string; role: string }> = {
    ssh_brute_force: { ip: '185.220.101.47', role: 'Tor exit node' },
    log4shell:       { ip: '91.92.251.103',  role: 'Exploit scanner' },
    ddos_udp:        { ip: '45.95.147.88',   role: 'DDoS coordinator' },
    ransomware_c2:   { ip: '194.165.16.72',  role: 'C2 Cobalt Strike' },
  }

  async function loadScenario(id: string) {
    // Réinitialiser topologie et animation avant de charger le nouveau scénario
    topologyStore.reset()
    animStore.reset()
    currentScenario = await fetchScenario(id)
    steps = currentScenario.steps
    scenarioStore.init(steps.map(s => s.id))
    const meta = ATTACKER_META[id]
    if (meta) { attackerIp = meta.ip; attackerRole = meta.role }
  }

  $: if (selectedId && ready) {
    loadScenario(selectedId)
  }

  // ── Health poll ───────────────────────────────────────────────────────────
  async function pollHealth() {
    while (!ready) {
      try {
        const h = await fetchHealth()
        loadedModels = h.loaded
        modelInfo = h.models ?? {}
        ready = h.ready
      } catch { /* backend pas encore dispo */ }
      if (!ready) await new Promise(r => setTimeout(r, 1500))
    }
    // Charger la liste des scénarios et la config lab une fois les modèles prêts
    scenarios = await fetchScenarios()
    if (scenarios.length > 0) selectedId = scenarios[0].id
    labConfig = await fetchLab().catch(() => null)
  }

  // ── Actions ───────────────────────────────────────────────────────────────
  async function handleRun() {
    if (!selectedId) return
    errorMsg = ''
    try { await triggerScenario(selectedId) }
    catch (e: any) { errorMsg = e.message }
  }

  async function handleReset() {
    errorMsg = ''
    await resetScenario()
    if (selectedId) await loadScenario(selectedId)
  }

  async function handleReplay() {
    errorMsg = ''
    await resetScenario()
    if (selectedId) await loadScenario(selectedId)
    await new Promise(r => setTimeout(r, 200))
    try { await triggerScenario(selectedId!) }
    catch (e: any) { errorMsg = e.message }
  }

  function exportReport() {
    const state = $scenarioStore
    const report = {
      generated_at: new Date().toISOString(),
      scenario: currentScenario?.title ?? 'breach-sim',
      scenario_id: selectedId,
      duration_s: state.startedAt
        ? ((Date.now() - state.startedAt) / 1000).toFixed(1)
        : null,
      steps: steps.map(s => {
        const st = state.steps[s.id]
        return {
          id: s.id,
          title: s.title,
          agent: s.agent,
          mitre: s.mitre,
          cap: s.cap,
          status: st?.status,
          latency_s: st?.latency,
          token_count: st?.tokenCount,
          tokens_per_s: st?.latency && st?.tokenCount
            ? parseFloat((st.tokenCount / st.latency).toFixed(1))
            : null,
          tool_call: st?.toolCall,
          execution_result: st?.execution,
          raw_output: st?.raw,
        }
      }),
    }
    const blob = new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `breach-sim-${selectedId}-${Date.now()}.json`
    a.click()
    URL.revokeObjectURL(url)
  }

  onMount(() => {
    disconnectSSE = connectDemoSSE()
    pollHealth()
  })

  onDestroy(() => { disconnectSSE?.() })

  $: scenarioStatus = $scenarioStore.status
  $: isRunning = scenarioStatus === 'running'
  $: labCfgMap = labConfig ? (labConfig as unknown as Record<string, string>) : null
</script>

<div class="min-h-screen bg-zinc-950 flex flex-col">

  <!-- Header -->
  <header class="border-b border-zinc-800 px-6 py-3 flex items-center justify-between">
    <div class="flex items-center gap-3">
      <span class="text-red-500 text-xl">⚡</span>
      <h1 class="text-lg font-bold tracking-tight text-zinc-100">breach-sim</h1>
      <span class="text-xs text-zinc-500 font-mono">AI Cyber Defense Demo</span>
      {#if labConfig?.live}
        <span class="text-xs font-mono px-2 py-0.5 rounded border border-defend text-defend bg-emerald-950">
          live · lab-{labConfig.instance}
        </span>
        <span class="text-xs font-mono text-zinc-600" title="OPNsense">
          {labConfig.opnsense_ip}
        </span>
      {:else if labConfig}
        <span class="text-xs font-mono px-2 py-0.5 rounded border border-zinc-700 text-zinc-500 bg-zinc-900">
          simulé
        </span>
      {/if}
    </div>
    <div class="flex items-center gap-3">
      {#if !ready}
        <div class="text-xs text-zinc-500 font-mono flex items-center gap-2">
          <span>Chargement ONNX…</span>
          <span class="text-amber-400">{loadedModels.length}/3</span>
          {#each ['opnsense', 'wireguard', 'crowdsec'] as a}
            <span class="px-1.5 py-0.5 rounded border text-xs font-mono
              {loadedModels.includes(a) ? 'border-emerald-700 text-emerald-400 bg-emerald-950' : 'border-zinc-700 text-zinc-600 bg-zinc-900'}">
              {a}
            </span>
          {/each}
        </div>
      {:else}
        <div class="flex items-center gap-1">
          {#each Object.entries(modelInfo) as [agent, info]}
            <span title="{info.name}"
              class="text-xs px-1.5 py-0.5 rounded border font-mono
              {agent === 'crowdsec'  ? 'border-purple-800 text-purple-400 bg-purple-950' :
               agent === 'opnsense'  ? 'border-blue-800 text-blue-400 bg-blue-950' :
               agent === 'wireguard' ? 'border-emerald-800 text-emerald-400 bg-emerald-950' :
               'border-zinc-700 text-zinc-400'}">
              {agent} · {info.precision}
            </span>
          {/each}
        </div>
      {/if}

      {#if errorMsg}
        <span class="text-xs text-red-400">{errorMsg}</span>
      {/if}

      {#if scenarioStatus === 'done'}
        <button on:click={exportReport}
          class="px-3 py-1.5 rounded text-sm font-semibold bg-zinc-800 hover:bg-zinc-700 text-zinc-300 border border-zinc-600 transition-colors">
          ↓ Rapport
        </button>
        <button on:click={handleReplay} disabled={!ready}
          class="px-3 py-1.5 rounded text-sm font-semibold bg-amber-700 hover:bg-amber-600 text-white transition-colors">
          ⚡ Rejouer
        </button>
        <button on:click={handleReset}
          class="px-3 py-1.5 rounded text-sm font-semibold bg-zinc-700 hover:bg-zinc-600 text-zinc-100 transition-colors">
          ↺ Reset
        </button>
      {:else if scenarioStatus === 'idle'}
        <button on:click={handleRun} disabled={!ready || !selectedId}
          class="px-4 py-1.5 rounded text-sm font-semibold transition-colors
            {ready && selectedId ? 'bg-red-600 hover:bg-red-500 text-white' : 'bg-zinc-800 text-zinc-600 cursor-not-allowed'}">
          ▶ Lancer
        </button>
      {:else if isRunning}
        <button on:click={handleReset}
          class="px-4 py-1.5 rounded text-sm font-semibold bg-zinc-700 hover:bg-zinc-600 text-zinc-100 transition-colors">
          ■ Arrêter
        </button>
      {/if}
    </div>
  </header>

  <!-- Main -->
  <main class="flex flex-1 overflow-hidden">

    <!-- Colonne gauche : topologie + sélecteur -->
    <div class="w-2/5 border-r border-zinc-800 flex flex-col overflow-hidden">

      <!-- Topologie -->
      <div class="flex-1 min-h-0 overflow-hidden p-3 flex flex-col">
        <p class="text-xs text-zinc-500 uppercase tracking-wider mb-2 shrink-0">Topologie réseau</p>
        <div class="flex-1 min-h-0">
          <NetworkTopology
            {attackerIp} {attackerRole} scenarioId={selectedId ?? ''}
            live={labConfig?.live ?? false}
            labConfig={labCfgMap}
          />
        </div>
      </div>

      <!-- Sélecteur de scénario (masqué en mode live) -->
      {#if !labConfig?.live}
        <div class="shrink-0 min-h-0 overflow-y-auto p-4 border-t border-zinc-800">
          {#if ready && scenarios.length > 0}
            <p class="text-xs text-zinc-500 uppercase tracking-wider mb-3">Scénario</p>
            <ScenarioSelector
              {scenarios}
              bind:selectedId
              disabled={isRunning}
            />
          {:else if !ready}
            <p class="text-xs text-zinc-600 text-center pt-4">Chargement…</p>
          {/if}
        </div>
      {/if}
    </div>

    <!-- Colonne droite : T-Pot + timeline des steps -->
    <div class="w-3/5 flex flex-col overflow-hidden">

      <!-- T-Pot widget -->
      <div class="shrink-0 px-4 py-3 border-b border-zinc-800">
        <TpotWidget counts={$tpotStore.counts} feed={$tpotStore.feed} tpotIp={labConfig?.tpot_ip ?? ''} />
      </div>

      <!-- Timeline steps -->
      <div class="flex-1 overflow-y-auto p-4 space-y-3">
      <p class="text-xs text-zinc-500 uppercase tracking-wider mb-3">
        {#if currentScenario}
          {currentScenario.title}
        {:else}
          Scénario d'attaque
        {/if}
      </p>

      {#if !ready}
        <div class="flex flex-col gap-2 pt-8 items-center text-zinc-500">
          <div class="animate-spin text-2xl">⏳</div>
          <p class="text-sm">Chargement des modèles ONNX CPU…</p>
          <div class="flex gap-2 mt-2">
            {#each ['opnsense', 'wireguard', 'crowdsec'] as agent}
              <span class="text-xs px-2 py-1 rounded font-mono
                {loadedModels.includes(agent) ? 'bg-green-950 text-green-400 border border-green-800' : 'bg-zinc-800 text-zinc-500 border border-zinc-700'}">
                {agent}{loadedModels.includes(agent) ? ' ✓' : ' …'}
              </span>
            {/each}
          </div>
        </div>
      {:else if steps.length === 0}
        <div class="text-center text-zinc-600 text-sm pt-8">
          Sélectionne un scénario…
        </div>
      {:else}
        {#each steps as step}
          <StepCard
            stepId={step.id}
            index={steps.indexOf(step) + 1}
            title={step.title}
            agent={step.agent}
            description={step.description}
            cap={step.cap}
            mitre={step.mitre}
          />
        {/each}

        {#if scenarioStatus === 'idle'}
          <div class="text-center text-zinc-600 text-sm pt-2">
            Cliquez sur "Lancer" pour démarrer la simulation
          </div>
        {/if}

        {#if scenarioStatus === 'done'}
          <div class="text-center pt-3 pb-2">
            <p class="text-xs text-zinc-500">Simulation terminée</p>
            {#if $scenarioStore.startedAt}
              <p class="text-xs text-zinc-600 mt-0.5">
                Durée totale : {((Date.now() - $scenarioStore.startedAt) / 1000).toFixed(1)}s
              </p>
            {/if}
          </div>
        {/if}
      {/if}
      </div><!-- fin timeline -->
    </div><!-- fin colonne droite -->

  </main>

</div>
