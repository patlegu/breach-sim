<script lang="ts">
  import { onMount, onDestroy } from 'svelte'
  import NetworkTopology from './lib/components/NetworkTopology.svelte'
  import StepCard from './lib/components/StepCard.svelte'
  import { scenarioStore } from './lib/stores/scenarioStore'
  import { connectDemoSSE, triggerScenario, resetScenario, fetchHealth } from './lib/utils/demoApi'

  let ready = false
  let loadedModels: string[] = []
  let pendingModels: string[] = []
  let errorMsg = ''
  let disconnectSSE: (() => void) | null = null

  const STEPS = [
    {
      id: 'step_1',
      index: 1,
      title: 'Brute-force SSH détecté',
      agent: 'crowdsec',
      description: '847 tentatives de connexion SSH en 60s depuis 185.220.101.47',
      cap: {
        directive: 'add_decision',
        entities: { IP_ADDRESS: ['185.220.101.47'], PORT_NUMBER: ['22'], HOSTNAME: [] },
        context: { source: 'siem', reason: 'brute_force_ssh', confidence: 0.97 },
      },
    },
    {
      id: 'step_2',
      index: 2,
      title: 'IP toujours active — blocage firewall',
      agent: 'opnsense',
      description: "L'IP contourne le bouncer CrowdSec — blocage au niveau firewall",
      cap: {
        directive: 'block_ip',
        entities: { IP_ADDRESS: ['185.220.101.47'], INTERFACE: ['wan'], PORT_NUMBER: [], HOSTNAME: [], IP_SUBNET: [] },
        context: { source: 'crowdsec', reason: 'ban_evasion', confidence: 0.95 },
      },
    },
    {
      id: 'step_3',
      index: 3,
      title: 'Scan de ports détecté',
      agent: 'opnsense',
      description: 'Scan SYN stealth sur les ports 1-1024 depuis 185.220.101.0/24',
      cap: {
        directive: 'add_filter_rule',
        entities: { IP_ADDRESS: ['185.220.101.47'], INTERFACE: ['wan'], PORT_NUMBER: ['1-1024'], IP_SUBNET: ['185.220.101.0/24'] },
        context: { source: 'ids', reason: 'port_scan', confidence: 0.88 },
      },
    },
  ]

  async function pollHealth() {
    while (!ready) {
      try {
        const h = await fetchHealth()
        loadedModels = h.loaded
        pendingModels = h.pending
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
        <div class="text-xs text-zinc-500 font-mono">
          Chargement des modèles ONNX…
          <span class="text-amber-400">{loadedModels.length}/3</span>
          ({loadedModels.join(', ') || '…'})
        </div>
      {/if}
      {#if errorMsg}
        <span class="text-xs text-red-400">{errorMsg}</span>
      {/if}
      {#if scenarioStatus === 'done' || scenarioStatus === 'idle'}
        <button
          on:click={scenarioStatus === 'done' ? handleReset : handleRun}
          disabled={!ready}
          class="px-4 py-2 rounded text-sm font-semibold transition-colors
            {ready
              ? scenarioStatus === 'done'
                ? 'bg-zinc-700 hover:bg-zinc-600 text-zinc-100'
                : 'bg-red-600 hover:bg-red-500 text-white'
              : 'bg-zinc-800 text-zinc-600 cursor-not-allowed'}">
          {scenarioStatus === 'done' ? '↺ Rejouer' : '▶ Lancer le scénario'}
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
          />
        {/each}

        {#if scenarioStatus === 'idle'}
          <div class="text-center text-zinc-600 text-sm pt-4">
            Cliquez sur "Lancer le scénario" pour démarrer la simulation
          </div>
        {/if}
      {/if}
    </div>

  </main>

</div>
