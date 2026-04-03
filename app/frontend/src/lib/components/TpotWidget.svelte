<script lang="ts">
  import type { TpotContainer, TpotEvent } from '../stores/tpotStore'

  export let counts: TpotContainer[] = []
  export let feed: TpotEvent[] = []
  export let tpotIp: string = ''

  $: maxHits = counts.length > 0 ? Math.max(...counts.map(c => c.hits)) : 1

  const COLORS: Record<string, string> = {
    cowrie:    'bg-orange-500',
    dionaea:   'bg-purple-500',
    honeytrap: 'bg-blue-500',
    suricata:  'bg-yellow-500',
    mailoney:  'bg-pink-500',
    rdpy:      'bg-red-500',
    heralding: 'bg-teal-500',
    glutton:   'bg-indigo-500',
  }

  const DOT_COLORS: Record<string, string> = {
    cowrie:    'text-orange-400',
    dionaea:   'text-purple-400',
    honeytrap: 'text-blue-400',
    suricata:  'text-yellow-400',
    mailoney:  'text-pink-400',
    rdpy:      'text-red-400',
    heralding: 'text-teal-400',
    glutton:   'text-indigo-400',
  }

  function barColor(name: string): string {
    return COLORS[name.toLowerCase()] ?? 'bg-zinc-400'
  }

  function dotColor(name: string): string {
    return DOT_COLORS[name.toLowerCase()] ?? 'text-zinc-400'
  }

  function fmt(n: number): string {
    return n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(n)
  }

  function fmtTs(iso: string): string {
    try {
      return new Date(iso).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit', second: '2-digit' })
    } catch {
      return iso.slice(11, 19)
    }
  }
</script>

<div class="flex flex-col gap-3">

  <!-- Header -->
  <div class="flex items-center justify-between">
    <p class="text-xs text-zinc-500 uppercase tracking-wider">T-Pot · honeypots live</p>
    {#if tpotIp}
      <span class="text-xs font-mono text-zinc-600">{tpotIp}</span>
    {/if}
  </div>

  <!-- Leaderboard -->
  {#if counts.length === 0}
    <p class="text-xs text-zinc-600 italic">En attente de données…</p>
  {:else}
    <div class="flex flex-col gap-1">
      {#each counts.slice(0, 6) as c}
        <div class="flex items-center gap-2">
          <span class="text-xs font-mono text-zinc-400 w-20 truncate" title={c.name}>{c.name}</span>
          <div class="flex-1 h-1.5 rounded bg-zinc-800 overflow-hidden">
            <div
              class="h-full rounded transition-all duration-300 {barColor(c.name)}"
              style="width: {Math.max(2, (c.hits / maxHits) * 100)}%"
            />
          </div>
          <span class="text-xs font-mono text-zinc-400 w-8 text-right">{fmt(c.hits)}</span>
        </div>
      {/each}
    </div>
  {/if}

  <!-- Feed événements live -->
  {#if feed.length > 0}
    <div class="border-t border-zinc-800 pt-2 flex flex-col gap-0.5 max-h-28 overflow-hidden">
      {#each feed.slice(0, 8) as ev}
        <div class="flex items-center gap-1.5 text-xs font-mono leading-tight">
          <span class="text-zinc-600 w-16 shrink-0">{fmtTs(ev.ts)}</span>
          <span class="w-18 shrink-0 {dotColor(ev.honeypot)} truncate" style="width:4.5rem">{ev.honeypot}</span>
          <span class="text-zinc-400 truncate flex-1">{ev.src_ip}</span>
          <span class="text-zinc-600 shrink-0">:{ev.port}</span>
        </div>
      {/each}
    </div>
  {/if}

</div>
