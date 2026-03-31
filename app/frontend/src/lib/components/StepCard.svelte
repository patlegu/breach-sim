<script lang="ts">
  import { scenarioStore, type StepState } from '../stores/scenarioStore'

  export let stepId: string
  export let index: number
  export let title: string
  export let agent: string
  export let description: string
  export let cap: object
  export let mitre: { tactic: string; technique: string; name: string; cve: string | null } | null = null

  $: step = $scenarioStore.steps[stepId] as StepState
  $: tokens = step?.tokens ?? []
  $: tokenCount = step?.tokenCount ?? 0
  $: status = step?.status ?? 'idle'
  $: toolCall = step?.toolCall
  $: execution = step?.execution
  $: executionError = execution && 'error' in (execution as object)
  $: latency = step?.latency
  $: tokensPerSec = latency && latency > 0 && tokenCount > 0
    ? (tokenCount / latency).toFixed(1)
    : null

  const agentColors: Record<string, string> = {
    crowdsec:  'text-purple-400 border-purple-700 bg-purple-950',
    opnsense:  'text-blue-400 border-blue-700 bg-blue-950',
    wireguard: 'text-emerald-400 border-emerald-700 bg-emerald-950',
  }

  const tacticColors: Record<string, string> = {
    'Credential Access': 'text-red-300 bg-red-950 border-red-800',
    'Defense Evasion':   'text-orange-300 bg-orange-950 border-orange-800',
    'Discovery':         'text-yellow-300 bg-yellow-950 border-yellow-800',
    'Command and Control': 'text-violet-300 bg-violet-950 border-violet-800',
  }

  function expandJson(v: unknown): unknown {
    if (typeof v === 'string') {
      try { return expandJson(JSON.parse(v)) } catch { return v }
    }
    if (Array.isArray(v)) return v.map(expandJson)
    if (v && typeof v === 'object')
      return Object.fromEntries(Object.entries(v).map(([k, val]) => [k, expandJson(val)]))
    return v
  }

  function formatJson(obj: object): string {
    return JSON.stringify(expandJson(obj), null, 2)
  }

  // Passage unique : évite que le regex des nombres matche les chiffres des class CSS
  const JSON_RE = /("(?:\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*"(?=\s*:))|("(?:\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*")|([-]?\b\d+\.?\d*\b)|\b(true|false|null)\b/g

  function highlightJson(str: string): string {
    return str.replace(JSON_RE, (m, key, val, num, _kw) => {
      if (key !== undefined) return `<span class="text-blue-300">${m}</span>`
      if (val !== undefined) return `<span class="text-green-300">${m}</span>`
      if (num !== undefined) return `<span class="text-amber-300">${m}</span>`
      return `<span class="text-red-300">${m}</span>`
    })
  }
</script>

<div class="rounded-lg border border-zinc-700 bg-zinc-900 overflow-hidden transition-all duration-300
  {status === 'running' ? 'border-amber-500 shadow-lg shadow-amber-900/30' : ''}
  {status === 'done' ? 'border-defend' : ''}">

  <!-- Header -->
  <div class="flex items-center justify-between px-4 py-3 border-b border-zinc-700 bg-zinc-800">
    <div class="flex items-center gap-3">
      <span class="text-zinc-500 text-sm font-mono">#{index}</span>
      <span class="font-semibold text-zinc-100">{title}</span>
      <span class="text-xs px-2 py-0.5 rounded border font-mono {agentColors[agent] ?? 'text-zinc-400 border-zinc-600 bg-zinc-800'}">
        {agent}
      </span>
    </div>
    <div class="flex items-center gap-3">
      {#if status === 'running'}
        <span class="text-xs text-amber-400 font-mono">{tokenCount} tok</span>
      {/if}
      {#if latency !== null}
        <span class="text-xs text-zinc-400 font-mono">{latency}s</span>
      {/if}
      {#if tokensPerSec !== null}
        <span class="text-xs text-zinc-500 font-mono">{tokensPerSec} tok/s</span>
      {/if}
      {#if status === 'idle'}
        <span class="w-2 h-2 rounded-full bg-zinc-600" />
      {:else if status === 'running'}
        <span class="w-2 h-2 rounded-full bg-amber-400 animate-pulse" />
      {:else if status === 'done'}
        <span class="w-2 h-2 rounded-full bg-defend" />
      {/if}
    </div>
  </div>

  <!-- Description -->
  <p class="px-4 py-2 text-sm text-zinc-400 border-b border-zinc-800">{description}</p>

  <!-- MITRE ATT&CK -->
  {#if mitre}
    <div class="px-4 py-2 border-b border-zinc-800 flex items-center gap-2 flex-wrap">
      <span class="text-xs text-zinc-600 uppercase tracking-wider">MITRE ATT&CK</span>
      <span class="text-xs font-mono px-2 py-0.5 rounded border {tacticColors[mitre.tactic] ?? 'text-zinc-400 bg-zinc-800 border-zinc-700'}">
        {mitre.technique}
      </span>
      <span class="text-xs text-zinc-400">{mitre.name}</span>
      <span class="text-xs text-zinc-600">·</span>
      <span class="text-xs text-zinc-500">{mitre.tactic}</span>
      {#if mitre.cve}
        <span class="text-xs font-mono px-1.5 py-0.5 rounded bg-zinc-800 border border-zinc-700 text-red-400">{mitre.cve}</span>
      {/if}
    </div>
  {/if}

  <!-- Body : CAP + Output -->
  {#if status !== 'idle'}
    <div class="grid grid-cols-2 divide-x divide-zinc-700">

      <!-- Paquet CAP v1 -->
      <div class="p-3">
        <p class="text-xs text-zinc-500 mb-2 uppercase tracking-wider">Paquet CAP v1</p>
        <pre class="text-xs font-mono text-zinc-300 overflow-auto max-h-48 scrollbar-thin">{@html highlightJson(formatJson(cap))}</pre>
      </div>

      <!-- Sortie ONNX -->
      <div class="p-3">
        <p class="text-xs text-zinc-500 mb-2 uppercase tracking-wider">
          Inférence ONNX · <span class="text-zinc-600 normal-case">int4 CPU</span>
          {#if status === 'running'}<span class="text-amber-400 ml-1">● en cours</span>{/if}
        </p>
        <pre class="text-xs font-mono text-green-400 overflow-auto max-h-48 scrollbar-thin whitespace-pre-wrap">{tokens.join('')}{#if status === 'running'}<span class="animate-pulse">▋</span>{/if}</pre>
      </div>

    </div>

    <!-- Tool call + résultat d'exécution -->
    {#if toolCall && status === 'done'}
      <div class="border-t border-zinc-800">

        {#if execution}
          <!-- Mode live : grille tool call | résultat API -->
          <div class="grid grid-cols-2 divide-x divide-zinc-800">
            <div class="px-3 py-3">
              <p class="text-xs text-zinc-500 mb-2 uppercase tracking-wider">Tool call</p>
              <pre class="text-xs font-mono text-emerald-300 bg-zinc-950 rounded p-2 overflow-auto max-h-48 scrollbar-thin whitespace-pre-wrap break-all">{formatJson(toolCall)}</pre>
            </div>
            <div class="px-3 py-3">
              <p class="text-xs mb-2 uppercase tracking-wider {executionError ? 'text-red-500' : 'text-defend'}">
                Exécution live
                {#if executionError}
                  <span class="ml-1 normal-case">✗ erreur</span>
                {:else}
                  <span class="ml-1 normal-case">✓ appliqué</span>
                {/if}
              </p>
              <pre class="text-xs font-mono {executionError ? 'text-red-400' : 'text-defend'} bg-zinc-950 rounded p-2 overflow-auto max-h-48 scrollbar-thin whitespace-pre-wrap break-all">{formatJson(execution)}</pre>
            </div>
          </div>
        {:else}
          <!-- Mode simulé : tool call seul -->
          <div class="px-3 py-3">
            <p class="text-xs text-zinc-500 mb-2 uppercase tracking-wider">Tool call</p>
            <pre class="text-xs font-mono text-emerald-300 bg-zinc-950 rounded p-2 overflow-auto max-h-64 scrollbar-thin whitespace-pre-wrap break-all">{formatJson(toolCall)}</pre>
          </div>
        {/if}

      </div>
    {/if}
  {/if}

</div>
