<script lang="ts">
  import { onMount, onDestroy } from 'svelte'
  import { topologyStore, type NodeStatus } from '../stores/topologyStore'
  import { animStore } from '../stores/animStore'
  import cytoscape from 'cytoscape'

  export let attackerIp: string = '?'
  export let attackerRole: string = 'Attaquant externe'

  let container: HTMLDivElement
  let tooltipEl: HTMLDivElement
  let cy: cytoscape.Core
  let pulseInterval: ReturnType<typeof setInterval> | null = null
  let tooltipVisible = false
  let tooltipText = ''
  let tooltipX = 0
  let tooltipY = 0

  const NODE_COLORS: Record<NodeStatus, { bg: string; border: string }> = {
    normal:   { bg: '#27272a', border: '#52525b' },
    attacked: { bg: '#7f1d1d', border: '#ef4444' },
    defended: { bg: '#064e3b', border: '#10b981' },
  }

  const NODE_INFO: Record<string, { ip: string; role: string; service: string }> = {
    attacker:  { ip: attackerIp, role: attackerRole, service: '' },
    internet:  { ip: 'WAN',               role: 'Périmètre réseau',     service: 'Transit' },
    firewall:  { ip: '192.168.1.1',       role: 'Gateway / IDS',        service: 'OPNsense 24.x' },
    crowdsec:  { ip: '192.168.1.10',      role: 'IDPS',                 service: 'CrowdSec LAPI' },
    wireguard: { ip: '10.0.0.1',          role: 'VPN Gateway',          service: 'WireGuard 1.0' },
    dmz:       { ip: '192.168.2.0/24',    role: 'Zone démilitarisée',   service: 'Réseau isolé' },
    'srv-web': { ip: '192.168.2.10',      role: 'Serveur web',          service: 'Nginx 1.24' },
    'srv-db':  { ip: '192.168.2.20',      role: 'Base de données',      service: 'PostgreSQL 16' },
  }

  const NODES = [
    { id: 'attacker',  label: `🔴 Attaquant\n${attackerIp}`, x: 300, y: 35  },
    { id: 'internet',  label: '🌐 Internet',                  x: 300, y: 130 },
    { id: 'firewall',  label: '🛡 OPNsense\nFirewall',        x: 300, y: 250 },
    { id: 'crowdsec',  label: '⚔ CrowdSec\nIDPS',            x: 110, y: 370 },
    { id: 'wireguard', label: '🔐 WireGuard\nVPN',            x: 490, y: 370 },
    { id: 'dmz',       label: '🔒 DMZ',                       x: 300, y: 370 },
    { id: 'srv-web',   label: '💻 srv-web',                   x: 210, y: 470 },
    { id: 'srv-db',    label: '🗄 srv-db',                    x: 390, y: 470 },
  ]

  const EDGES = [
    { id: 'e-atk-net', source: 'attacker',  target: 'internet'  },
    { id: 'e-net-fw',  source: 'internet',  target: 'firewall'  },
    { id: 'e-fw-cs',   source: 'firewall',  target: 'crowdsec'  },
    { id: 'e-fw-wg',   source: 'firewall',  target: 'wireguard' },
    { id: 'e-fw-dmz',  source: 'firewall',  target: 'dmz'       },
    { id: 'e-dmz-web', source: 'dmz',       target: 'srv-web'   },
    { id: 'e-dmz-db',  source: 'dmz',       target: 'srv-db'    },
  ]

  const NORMAL_EDGE_STYLE = { 'line-color': '#3f3f46', 'target-arrow-color': '#3f3f46', 'width': 2 }
  const ATTACK_EDGE_BRIGHT = { 'line-color': '#f97316', 'target-arrow-color': '#f97316', 'width': 3 }
  const ATTACK_EDGE_DIM    = { 'line-color': '#7c2d12', 'target-arrow-color': '#7c2d12', 'width': 2 }
  const DEFEND_EDGE_STYLE  = { 'line-color': '#10b981', 'target-arrow-color': '#10b981', 'width': 3 }

  function stopPulse() {
    if (pulseInterval !== null) {
      clearInterval(pulseInterval)
      pulseInterval = null
    }
  }

  function resetAllEdges() {
    if (!cy) return
    EDGES.forEach(e => cy.$(`#${e.id}`).style(NORMAL_EDGE_STYLE))
  }

  function startPulse(edgeIds: string[]) {
    stopPulse()
    let bright = true
    pulseInterval = setInterval(() => {
      if (!cy) return
      const style = bright ? ATTACK_EDGE_BRIGHT : ATTACK_EDGE_DIM
      edgeIds.forEach(id => cy.$(`#${id}`).style(style))
      bright = !bright
    }, 350)
  }

  function flashDefended(edgeIds: string[]) {
    stopPulse()
    if (!cy) return
    edgeIds.forEach(id => cy.$(`#${id}`).style(DEFEND_EDGE_STYLE))
    setTimeout(() => {
      edgeIds.forEach(id => cy.$(`#${id}`).style(NORMAL_EDGE_STYLE))
    }, 1500)
  }

  // Mettre à jour le label de l'attaquant quand l'IP change
  $: if (cy) {
    cy.$('#attacker').data('label', `🔴 Attaquant\n${attackerIp}`)
    cy.$('#attacker').style('label', `🔴 Attaquant\n${attackerIp}`)
    NODE_INFO.attacker.ip = attackerIp
    NODE_INFO.attacker.role = attackerRole
  }

  // Réagir aux changements du store de couleurs de nœuds
  const unsubTopology = topologyStore.subscribe(state => {
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

  // Réagir aux changements d'animation
  const unsubAnim = animStore.subscribe(state => {
    if (!cy) return
    if (state.phase === 'idle') {
      resetAllEdges()
      return
    }
    const edges = state.activeEdges
    if (state.phase === 'attacking') {
      startPulse(edges)
    } else if (state.phase === 'defended') {
      flashDefended(edges)
    }
  })

  onMount(() => {
    cy = cytoscape({
      container,
      elements: [
        ...NODES.map(n => ({
          data: { id: n.id, label: n.label },
          position: { x: n.x, y: n.y },
        })),
        ...EDGES.map(e => ({
          data: { id: e.id, source: e.source, target: e.target },
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

    cy.fit(cy.nodes(), 20)

    // Tooltips sur hover
    cy.on('mouseover', 'node', (e) => {
      const id = e.target.id()
      const info = NODE_INFO[id]
      if (!info) return
      const pos = e.target.renderedBoundingBox()
      tooltipX = (pos.x1 + pos.x2) / 2
      tooltipY = pos.y1 - 8
      tooltipText = `${info.ip} · ${info.role}\n${info.service}`
      tooltipVisible = true
    })

    cy.on('mouseout', 'node', () => {
      tooltipVisible = false
    })
  })

  onDestroy(() => {
    stopPulse()
    unsubTopology()
    unsubAnim()
    cy?.destroy()
  })
</script>

<div class="relative w-full h-full">
  <div bind:this={container} class="w-full h-full rounded-lg bg-zinc-900" />

  {#if tooltipVisible}
    <div
      bind:this={tooltipEl}
      class="absolute z-10 pointer-events-none px-2 py-1.5 rounded bg-zinc-800 border border-zinc-600 text-xs font-mono text-zinc-200 whitespace-pre shadow-lg"
      style="left: {tooltipX}px; top: {tooltipY}px; transform: translate(-50%, -100%);"
    >
      {tooltipText}
    </div>
  {/if}
</div>
