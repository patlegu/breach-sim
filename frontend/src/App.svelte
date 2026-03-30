<script lang="ts">
  import { onMount, onDestroy } from 'svelte'
  import NetworkTopology from './lib/components/NetworkTopology.svelte'
  import StepCard from './lib/components/StepCard.svelte'
  import { scenarioStore } from './lib/stores/scenarioStore'
  import { connectDemoSSE, triggerScenario, resetScenario, fetchHealth } from './lib/utils/demoApi'

  let ready = false
  let loadedModels: string[] = []
  let pendingModels: string[] = []
  let modelInfo: Record<string, { name: string; precision: string }> = {}
  let errorMsg = ''
  let disconnectSSE: (() => void) | null = null

  const STEPS = [
    {
      id: 'step_1',
      index: 1,
      title: 'Brute-force SSH détecté',
      agent: 'crowdsec',
      description: '847 tentatives de connexion SSH en 60s depuis 185.220.101.47',
      mitre: { tactic: 'Credential Access', technique: 'T1110', name: 'Brute Force', cve: null },
      cap: {
        directive: 'add_decision',
        entities: { IP_ADDRESS: ['185.220.101.47'], PORT_NUMBER: ['22'], HOSTNAME: [] },
        context: { source: 'siem', reason: 'brute_force_ssh', confidence: 0.97, attempts: 847, timewindow: '60s' },
      },
    },
    {
      id: 'step_2',
      index: 2,
      title: 'IP toujours active — blocage firewall',
      agent: 'opnsense',
      description: "L'IP contourne le bouncer CrowdSec — blocage au niveau firewall",
      mitre: { tactic: 'Defense Evasion', technique: 'T1562.004', name: 'Disable or Modify System Firewall', cve: null },
      cap: {
        directive: 'block_ip',
        entities: { IP_ADDRESS: ['185.220.101.47'], INTERFACE: ['wan'], PORT_NUMBER: [], HOSTNAME: [], IP_SUBNET: [] },
        context: { source: 'crowdsec', reason: 'ban_evasion', confidence: 0.95, previous_action: 'add_decision' },
      },
    },
    {
      id: 'step_3',
      index: 3,
      title: 'Scan de ports détecté',
      agent: 'opnsense',
      description: 'Scan SYN stealth sur les ports 1-1024 depuis 185.220.101.0/24',
      mitre: { tactic: 'Discovery', technique: 'T1046', name: 'Network Service Discovery', cve: null },
      cap: {
        directive: 'add_filter_rule',
        entities: { IP_ADDRESS: ['185.220.101.47'], INTERFACE: ['wan'], PORT_NUMBER: ['1-1024'], IP_SUBNET: ['185.220.101.0/24'] },
        context: { source: 'ids', reason: 'port_scan', confidence: 0.88, scan_type: 'syn_stealth' },
      },
    },
    {
      id: 'step_4',
      index: 4,
      title: 'Rotation des clés VPN',
      agent: 'wireguard',
      description: 'Pivot VPN détecté — rotation préventive des clés WireGuard',
      mitre: { tactic: 'Command and Control', technique: 'T1572', name: 'Protocol Tunneling', cve: null },
      cap: {
        directive: 'generate_wireguard_keypair',
        entities: { HOSTNAME: ['vpn.lan'], IP_ADDRESS: [], IP_SUBNET: [] },
        context: { source: 'opnsense', reason: 'vpn_pivot_detected', confidence: 0.84, trigger: 'port_scan_subnet' },
      },
    },
  ]

  async function pollHealth() {
    while (!ready) {
      try {
        const h = await fetchHealth()
        loadedModels = h.loaded
        pendingModels = h.pending
        modelInfo = h.models ?? {}
        ready = h.ready
      } catch {
        // backend pas encore dispo
      }
      if (!ready) await new Promise(r => setTimeout(r, 1500))
    }
  }

  async function handleRun() {
    errorMsg = ''
    try {
      await triggerScenario()
    } catch (e: any) {
      errorMsg = e.message
    }
  }

  async function handleReset() {
    errorMsg = ''
    await resetScenario()
  }

  async function handleReplay() {
    errorMsg = ''
    await resetScenario()
    await new Promise(r => setTimeout(r, 200))
    try {
      await triggerScenario()
    } catch (e: any) {
      errorMsg = e.message
    }
  }

  function exportReport() {
    const state = $scenarioStore
    const report = {
      generated_at: new Date().toISOString(),
      scenario: 'breach-sim · AI Cyber Defense Demo',
      duration_s: state.startedAt
        ? ((Date.now() - state.startedAt) / 1000).toFixed(1)
        : null,
      steps: STEPS.map(s => {
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
          tokens_per_s: st?.latency && st.tokenCount
            ? parseFloat((st.tokenCount / st.latency).toFixed(1))
            : null,
          tool_call: st?.toolCall,
          raw_output: st?.raw,
        }
      }),
    }
    const blob = new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `breach-sim-report-${Date.now()}.json`
    a.click()
    URL.revokeObjectURL(url)
  }

  onMount(() => {
    disconnectSSE = connectDemoSSE()
    pollHealth()
  })

  onDestroy(() => {
    disconnectSSE?.()
  })

  $: scenarioStatus = $scenarioStore.status
</script>

<div class="min-h-screen bg-zinc-950 flex flex-col">

  <!-- Header -->
  <header class="border-b border-zinc-800 px-6 py-4 flex items-center justify-between">
    <div class="flex items-center gap-3">
      <span class="text-red-500 text-xl">⚡</span>
      <h1 class="text-lg font-bold tracking-tight text-zinc-100">breach-sim</h1>
      <span class="text-xs text-zinc-500 font-mono">AI Cyber Defense Demo</span>
    </div>
    <div class="flex items-center gap-3">
      {#if !ready}
        <div class="text-xs text-zinc-500 font-mono flex items-center gap-2">
          <span>Chargement modèles ONNX…</span>
          <span class="text-amber-400">{loadedModels.length}/3</span>
          <div class="flex gap-1">
            {#each ['opnsense', 'wireguard', 'crowdsec'] as a}
              <span class="px-1.5 py-0.5 rounded border text-xs font-mono
                {loadedModels.includes(a)
                  ? 'border-emerald-700 text-emerald-400 bg-emerald-950'
                  : 'border-zinc-700 text-zinc-600 bg-zinc-900'}">
                {a}
              </span>
            {/each}
          </div>
        </div>
      {:else}
        <!-- Infos modèles chargés -->
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
          class="px-3 py-2 rounded text-sm font-semibold bg-zinc-800 hover:bg-zinc-700 text-zinc-300 border border-zinc-600 transition-colors">
          ↓ Rapport
        </button>
        <button on:click={handleReplay}
          disabled={!ready}
          class="px-4 py-2 rounded text-sm font-semibold bg-amber-700 hover:bg-amber-600 text-white transition-colors">
          ⚡ Rejouer
        </button>
        <button on:click={handleReset}
          class="px-4 py-2 rounded text-sm font-semibold bg-zinc-700 hover:bg-zinc-600 text-zinc-100 transition-colors">
          ↺ Réinitialiser
        </button>
      {:else if scenarioStatus === 'idle'}
        <button
          on:click={handleRun}
          disabled={!ready}
          class="px-4 py-2 rounded text-sm font-semibold transition-colors
            {ready
              ? 'bg-red-600 hover:bg-red-500 text-white'
              : 'bg-zinc-800 text-zinc-600 cursor-not-allowed'}">
          ▶ Lancer le scénario
        </button>
      {:else if scenarioStatus === 'running'}
        <button on:click={handleReset}
          class="px-4 py-2 rounded text-sm font-semibold bg-zinc-700 hover:bg-zinc-600 text-zinc-100 transition-colors">
          ■ Arrêter
        </button>
      {/if}
    </div>
  </header>

  <!-- Main -->
  <main class="flex flex-1 overflow-hidden">

    <!-- Topologie réseau -->
    <div class="w-2/5 border-r border-zinc-800 p-4">
      <p class="text-xs text-zinc-500 uppercase tracking-wider mb-3">Topologie réseau</p>
      <div class="h-[calc(100vh-10rem)]">
        <NetworkTopology />
      </div>
    </div>

    <!-- Timeline -->
    <div class="w-3/5 p-4 overflow-y-auto scrollbar-thin space-y-4">
      <p class="text-xs text-zinc-500 uppercase tracking-wider mb-3">Scénario d'attaque</p>

      {#if !ready}
        <div class="flex flex-col gap-2 pt-8 items-center text-zinc-500">
          <div class="animate-spin text-2xl">⏳</div>
          <p class="text-sm">Chargement des modèles ONNX CPU…</p>
          <div class="flex gap-2 mt-2">
            {#each ['opnsense', 'wireguard', 'crowdsec'] as agent}
              <span class="text-xs px-2 py-1 rounded font-mono
                {loadedModels.includes(agent) ? 'bg-defend/20 text-defend border border-defend/40' : 'bg-zinc-800 text-zinc-500 border border-zinc-700'}">
                {agent}
                {loadedModels.includes(agent) ? ' ✓' : ' …'}
              </span>
            {/each}
          </div>
        </div>
      {:else}
        {#each STEPS as step}
          <StepCard
            stepId={step.id}
            index={step.index}
            title={step.title}
            agent={step.agent}
            description={step.description}
            cap={step.cap}
            mitre={step.mitre}
          />
        {/each}

        {#if scenarioStatus === 'idle'}
          <div class="text-center text-zinc-600 text-sm pt-4">
            Cliquez sur "Lancer le scénario" pour démarrer la simulation
          </div>
        {/if}

        {#if scenarioStatus === 'done'}
          <div class="text-center pt-4">
            <p class="text-xs text-zinc-500 mb-1">Simulation terminée</p>
            <p class="text-xs text-zinc-600">
              {#if $scenarioStore.startedAt}
                Durée totale : {((Date.now() - $scenarioStore.startedAt) / 1000).toFixed(1)}s
              {/if}
            </p>
          </div>
        {/if}
      {/if}
    </div>

  </main>

</div>
