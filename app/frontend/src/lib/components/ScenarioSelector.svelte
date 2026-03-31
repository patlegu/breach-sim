<script lang="ts">
  import type { ScenarioMeta } from '../utils/demoApi'

  export let scenarios: ScenarioMeta[] = []
  export let selectedId: string | null = null
  export let disabled = false

  function select(id: string) {
    if (!disabled) selectedId = id
  }

  const agentColors: Record<string, string> = {
    crowdsec:  'text-purple-400 border-purple-800 bg-purple-950',
    opnsense:  'text-blue-400 border-blue-800 bg-blue-950',
    wireguard: 'text-emerald-400 border-emerald-800 bg-emerald-950',
  }

  const tagColors: Record<string, string> = {
    'ssh':            'bg-zinc-800 text-zinc-400',
    'brute-force':    'bg-red-950 text-red-400',
    'rce':            'bg-red-950 text-red-300',
    'log4shell':      'bg-orange-950 text-orange-400',
    'jndi':           'bg-orange-950 text-orange-300',
    'ddos':           'bg-yellow-950 text-yellow-400',
    'udp':            'bg-yellow-950 text-yellow-300',
    'amplification':  'bg-yellow-950 text-yellow-300',
    'ransomware':     'bg-rose-950 text-rose-400',
    'c2':             'bg-violet-950 text-violet-400',
    'lateral-movement': 'bg-violet-950 text-violet-300',
  }

  const scenarioIcons: Record<string, string> = {
    ssh_brute_force: '🔑',
    log4shell:       '💥',
    ddos_udp:        '🌊',
    ransomware_c2:   '☠️',
  }
</script>

<div class="grid grid-cols-2 gap-3">
  {#each scenarios as s}
    <button
      on:click={() => select(s.id)}
      {disabled}
      class="text-left rounded-lg border p-3 transition-all duration-150 focus:outline-none
        {selectedId === s.id
          ? 'border-red-500 bg-red-950/20 shadow-md shadow-red-900/20'
          : 'border-zinc-700 bg-zinc-900 hover:border-zinc-500 hover:bg-zinc-800'}
        {disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}">

      <div class="flex items-start gap-2 mb-2">
        <span class="text-lg leading-none mt-0.5">{scenarioIcons[s.id] ?? '⚡'}</span>
        <div class="flex-1 min-w-0">
          <p class="text-sm font-semibold text-zinc-100 leading-tight">{s.title}</p>
          <p class="text-xs text-zinc-500 mt-0.5 line-clamp-2">{s.description}</p>
        </div>
        {#if selectedId === s.id}
          <span class="text-red-400 text-xs font-mono shrink-0">✓</span>
        {/if}
      </div>

      <div class="flex flex-wrap gap-1 mt-2">
        {#each s.agents as agent}
          <span class="text-xs px-1.5 py-0.5 rounded border font-mono {agentColors[agent] ?? 'text-zinc-400 border-zinc-600 bg-zinc-800'}">
            {agent}
          </span>
        {/each}
        <span class="text-xs px-1.5 py-0.5 rounded bg-zinc-800 text-zinc-500 font-mono">
          {s.step_count} steps
        </span>
      </div>

      <div class="flex flex-wrap gap-1 mt-1.5">
        {#each s.tags.slice(0, 4) as tag}
          <span class="text-xs px-1.5 py-0.5 rounded font-mono {tagColors[tag] ?? 'bg-zinc-800 text-zinc-500'}">
            #{tag}
          </span>
        {/each}
      </div>
    </button>
  {/each}
</div>
