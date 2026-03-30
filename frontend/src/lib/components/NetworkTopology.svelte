<script lang="ts">
  import { onMount, onDestroy } from 'svelte'
  import { topologyStore, type NodeStatus } from '../stores/topologyStore'
  import cytoscape from 'cytoscape'

  let container: HTMLDivElement
  let cy: cytoscape.Core

  const NODE_COLORS: Record<NodeStatus, { bg: string; border: string }> = {
    normal:   { bg: '#27272a', border: '#52525b' },
    attacked: { bg: '#7f1d1d', border: '#ef4444' },
    defended: { bg: '#064e3b', border: '#10b981' },
  }

  const NODES = [
    { id: 'attacker', label: '🔴 Attaquant\n185.220.101.47', x: 300, y: 40 },
    { id: 'internet', label: '🌐 Internet', x: 300, y: 140 },
    { id: 'firewall', label: '🛡 OPNsense\nFirewall', x: 300, y: 260 },
    { id: 'crowdsec', label: '⚔ CrowdSec\nIDPS', x: 100, y: 360 },
    { id: 'dmz', label: '🔒 DMZ', x: 500, y: 360 },
    { id: 'srv-web', label: '💻 srv-web', x: 420, y: 460 },
    { id: 'srv-db', label: '🗄 srv-db', x: 580, y: 460 },
  ]

  const EDGES = [
    { source: 'attacker', target: 'internet' },
    { source: 'internet', target: 'firewall' },
    { source: 'firewall', target: 'crowdsec' },
    { source: 'firewall', target: 'dmz' },
    { source: 'dmz',      target: 'srv-web' },
    { source: 'dmz',      target: 'srv-db' },
  ]

  onMount(() => {
    cy = cytoscape({
      container,
      elements: [
        ...NODES.map(n => ({
          data: { id: n.id, label: n.label },
          position: { x: n.x, y: n.y },
        })),
        ...EDGES.map((e, i) => ({
          data: { id: `e${i}`, source: e.source, target: e.target },
        })),
      ],
      style: [
        {
          selector: 'node',
          style: {
            'label': 'data(label)',
            'text-wrap': 'wrap',
            'text-valign': 'center',
            'text-halign': 'center',
            'font-size': '10px',
            'color': '#e4e4e7',
            'background-color': NODE_COLORS.normal.bg,
            'border-width': 2,
            'border-color': NODE_COLORS.normal.border,
            'width': 90,
            'height': 50,
            'shape': 'roundrectangle',
          },
        },
        {
          selector: 'edge',
          style: {
            'width': 2,
            'line-color': '#3f3f46',
            'target-arrow-color': '#3f3f46',
            'target-arrow-shape': 'triangle',
            'curve-style': 'bezier',
          },
        },
      ],
      layout: { name: 'preset' },
      userZoomingEnabled: false,
      userPanningEnabled: false,
    })
  })

  // Réagir aux changements du store
  const unsubscribe = topologyStore.subscribe(state => {
    if (!cy) return
    for (const [nodeId, status] of Object.entries(state.nodes)) {
      const node = cy.$(`#${nodeId}`)
      if (!node.length) continue
      node.style({
        'background-color': NODE_COLORS[status].bg,
        'border-color': NODE_COLORS[status].border,
        'border-width': status === 'normal' ? 2 : 3,
      })
    }
  })

  onDestroy(() => {
    unsubscribe()
    cy?.destroy()
  })
</script>

<div bind:this={container} class="w-full h-full rounded-lg bg-zinc-900" />
