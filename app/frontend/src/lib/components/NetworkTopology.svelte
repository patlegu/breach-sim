<script lang="ts">
  import { onMount, onDestroy } from 'svelte'
  import { topologyStore, type NodeStatus } from '../stores/topologyStore'
  import { animStore, type AnimPhase } from '../stores/animStore'
  import { tpotStore } from '../stores/tpotStore'
  import cytoscape from 'cytoscape'

  export let attackerIp: string = '?'
  export let attackerRole: string = 'Attaquant externe'
  export let scenarioId: string = ''
  export let live: boolean = false
  export let labConfig: Record<string, string> | null = null

  let container: HTMLDivElement
  let cy: cytoscape.Core | null = null
  let pulseInterval: ReturnType<typeof setInterval> | null = null
  let tooltipVisible = false
  let tooltipText = ''
  let tooltipX = 0
  let tooltipY = 0

  const SCENARIO_COLORS: Record<string, string> = {
    ssh_brute_force: '#ef4444',
    log4shell:       '#f97316',
    ddos_udp:        '#a855f7',
    ransomware_c2:   '#dc2626',
  }
  const DEFEND_COLOR = '#10b981'

  let attackPathD = ''
  let attackColor = '#ef4444'
  let animPhase: AnimPhase = 'idle'

  function buildAttackPath(edgeIds: string[]): string {
    if (!cy || edgeIds.length === 0) return ''
    const nodeIds: string[] = []
    for (const eid of edgeIds) {
      const edge = cy.$(`#${eid}`)
      if (!edge.length) continue
      const src = edge.source().id()
      const tgt = edge.target().id()
      if (nodeIds.length === 0) nodeIds.push(src)
      if (nodeIds[nodeIds.length - 1] !== tgt) nodeIds.push(tgt)
    }
    const points = nodeIds.map(id => {
      const pos = cy!.$(`#${id}`).renderedPosition()
      return `${pos.x},${pos.y}`
    })
    if (points.length < 2) return ''
    return 'M ' + points.join(' L ')
  }

  const NODE_COLORS: Record<NodeStatus, { bg: string; border: string }> = {
    normal:   { bg: '#27272a', border: '#52525b' },
    attacked: { bg: '#7f1d1d', border: '#ef4444' },
    defended: { bg: '#064e3b', border: '#10b981' },
  }

  // ── Topologie live (KVM réel) ──────────────────────────────────────────────

  function getLiveConfig(cfg: Record<string, string>) {
    const fw   = cfg.opnsense_ip  ?? '192.168.1.1'
    const cs   = cfg.crowdsec_ip  ?? '192.168.1.1'
    const web  = cfg.srv_web_ip   ?? '192.168.1.10'
    const db   = cfg.srv_db_ip    ?? '192.168.21.10'
    const app  = cfg.infected_ip  ?? '192.168.21.20'
    const tpot = cfg.tpot_ip !== '127.0.0.1' ? cfg.tpot_ip : '192.168.1.50'
    return {
      nodes: [
        { id: 'attacker',  label: '🔴 Attaquant\n…',               x: 300, y: 50  },
        { id: 'internet',  label: '🌐 Internet\nWAN',              x: 300, y: 170 },
        { id: 'firewall',  label: `🛡 OPNsense\n${fw}`,            x: 300, y: 300 },
        { id: 'crowdsec',  label: '⚔ CrowdSec\nIDPS',             x: 50,  y: 430 },
        { id: 'dmz',       label: '🔒 DMZ\n192.168.1.0/24',        x: 190, y: 430 },
        { id: 'lan',       label: '🏠 LAN\n192.168.21.0/24',       x: 390, y: 430 },
        { id: 'wireguard', label: '🔐 WireGuard\nVPN',             x: 545, y: 430 },
        { id: 'srv-web',   label: `💻 srv-web\n${web}`,            x: 110, y: 560 },
        { id: 'tpot',      label: `🍯 T-Pot\n${tpot}`,             x: 265, y: 560 },
        { id: 'srv-db',    label: `🗄 srv-db\n${db}`,              x: 390, y: 560 },
        { id: 'srv-app',   label: `⚙ srv-app\n${app}`,            x: 510, y: 560 },
      ],
      edges: [
        { id: 'e-atk-net',  source: 'attacker',  target: 'internet'  },
        { id: 'e-net-fw',   source: 'internet',  target: 'firewall'  },
        { id: 'e-fw-cs',    source: 'firewall',  target: 'crowdsec'  },
        { id: 'e-fw-dmz',   source: 'firewall',  target: 'dmz'       },
        { id: 'e-fw-lan',   source: 'firewall',  target: 'lan'       },
        { id: 'e-fw-wg',    source: 'firewall',  target: 'wireguard' },
        { id: 'e-dmz-web',  source: 'dmz',       target: 'srv-web'   },
        { id: 'e-dmz-tpot', source: 'dmz',       target: 'tpot'      },
        { id: 'e-lan-db',   source: 'lan',       target: 'srv-db'    },
        { id: 'e-lan-app',  source: 'lan',       target: 'srv-app'   },
      ],
      info: {
        attacker:  { ip: '?',  role: 'Dernière IP attaquante', service: 'T-Pot feed' },
        internet:  { ip: 'WAN', role: 'Périmètre réseau', service: 'Transit' },
        firewall:  { ip: fw,   role: 'Gateway / IDS', service: 'OPNsense 24.x' },
        crowdsec:  { ip: cs,   role: 'IDPS', service: 'CrowdSec LAPI' },
        dmz:       { ip: '192.168.1.0/24', role: 'Zone démilitarisée', service: 'Réseau isolé' },
        lan:       { ip: '192.168.21.0/24', role: 'Réseau local', service: 'LAN interne' },
        wireguard: { ip: '10.0.0.1', role: 'VPN Gateway', service: 'WireGuard 1.0' },
        'srv-web': { ip: web,  role: 'Serveur web', service: 'Nginx 1.24' },
        tpot:      { ip: tpot, role: 'Honeypot T-Pot CE', service: 'Cowrie · Dionaea · …' },
        'srv-db':  { ip: db,   role: 'Base de données', service: 'PostgreSQL 16' },
        'srv-app': { ip: app,  role: 'Serveur applicatif', service: '' },
      },
    }
  }

  // ── Configurations topologie par scénario ──────────────────────────────────

  function getConfig(sid: string, ip: string) {
    if (sid === 'ransomware_c2') {
      return {
        nodes: [
          { id: 'attacker',  label: `☠️ C2 Server\n${ip}`,           x: 300, y: 35  },
          { id: 'internet',  label: '🌐 Internet',                    x: 300, y: 130 },
          { id: 'firewall',  label: '🛡 OPNsense\nFirewall',          x: 300, y: 250 },
          { id: 'crowdsec',  label: '⚔ CrowdSec\nIDPS',              x: 80,  y: 370 },
          { id: 'wireguard', label: '🔐 WireGuard\nVPN',              x: 520, y: 370 },
          { id: 'dmz',       label: '🔒 DMZ',                         x: 210, y: 370 },
          { id: 'lan',       label: '🏠 LAN\n192.168.2.0/24',         x: 390, y: 370 },
          { id: 'srv-web',   label: '💻 srv-web',                     x: 120, y: 470 },
          { id: 'srv-db',    label: '🗄 srv-db',                      x: 270, y: 470 },
          { id: 'tpot',      label: '🍯 T-Pot\n192.168.1.50',         x: 390, y: 470 },
          { id: 'infected',  label: `👤 192.168.2.15\nPoste infecté`, x: 520, y: 470 },
        ],
        edges: [
          { id: 'e-atk-net',  source: 'internet',  target: 'attacker'  }, // sortant vers C2
          { id: 'e-net-fw',   source: 'firewall',  target: 'internet'  }, // sortant
          { id: 'e-fw-cs',    source: 'firewall',  target: 'crowdsec'  },
          { id: 'e-fw-wg',    source: 'firewall',  target: 'wireguard' },
          { id: 'e-fw-dmz',   source: 'firewall',  target: 'dmz'       },
          { id: 'e-fw-lan',   source: 'lan',       target: 'firewall'  }, // sortant
          { id: 'e-dmz-web',  source: 'dmz',       target: 'srv-web'   },
          { id: 'e-dmz-db',   source: 'dmz',       target: 'srv-db'    },
          { id: 'e-dmz-tpot', source: 'dmz',       target: 'tpot'      },
          { id: 'e-lan-inf',  source: 'infected',  target: 'lan'       }, // sortant du poste
          { id: 'e-inf-wg',   source: 'infected',  target: 'wireguard' },
        ],
        hiddenEdges: ['e-inf-wg'],
        info: {
          attacker:  { ip, role: 'Serveur C2 Cobalt Strike', service: 'HTTPS beacon 443' },
          internet:  { ip: 'WAN', role: 'Périmètre réseau', service: 'Transit' },
          firewall:  { ip: '192.168.1.1', role: 'Gateway / IDS', service: 'OPNsense 24.x' },
          crowdsec:  { ip: '192.168.1.10', role: 'IDPS', service: 'CrowdSec LAPI' },
          wireguard: { ip: '10.0.0.1', role: 'VPN Gateway', service: 'WireGuard 1.0' },
          dmz:       { ip: '192.168.2.0/24', role: 'Zone démilitarisée', service: 'Réseau isolé' },
          lan:       { ip: '192.168.2.0/24', role: 'Réseau local', service: 'LAN interne' },
          'srv-web': { ip: '192.168.2.10', role: 'Serveur web', service: 'Nginx 1.24' },
          'srv-db':  { ip: '192.168.2.20', role: 'Base de données', service: 'PostgreSQL 16' },
          tpot:      { ip: '192.168.1.50', role: 'Honeypot T-Pot CE', service: 'Cowrie · Dionaea · …' },
          infected:  { ip: '192.168.2.15', role: 'Poste compromis', service: 'Ransomware beacon' },
        },
      }
    }

    // Topologie standard (SSH, Log4Shell, DDoS)
    return {
      nodes: [
        { id: 'attacker',  label: `🔴 Attaquant\n${ip}`,        x: 300, y: 35  },
        { id: 'internet',  label: '🌐 Internet',                 x: 300, y: 130 },
        { id: 'firewall',  label: '🛡 OPNsense\nFirewall',       x: 300, y: 250 },
        { id: 'crowdsec',  label: '⚔ CrowdSec\nIDPS',           x: 110, y: 370 },
        { id: 'wireguard', label: '🔐 WireGuard\nVPN',           x: 490, y: 370 },
        { id: 'dmz',       label: '🔒 DMZ',                      x: 300, y: 370 },
        { id: 'srv-web',   label: '💻 srv-web',                  x: 180, y: 470 },
        { id: 'srv-db',    label: '🗄 srv-db',                   x: 300, y: 470 },
        { id: 'tpot',      label: '🍯 T-Pot\n192.168.1.50',      x: 420, y: 470 },
      ],
      edges: [
        { id: 'e-atk-net',  source: 'attacker',  target: 'internet'  },
        { id: 'e-net-fw',   source: 'internet',  target: 'firewall'  },
        { id: 'e-fw-cs',    source: 'firewall',  target: 'crowdsec'  },
        { id: 'e-fw-wg',    source: 'firewall',  target: 'wireguard' },
        { id: 'e-fw-dmz',   source: 'firewall',  target: 'dmz'       },
        { id: 'e-dmz-web',  source: 'dmz',       target: 'srv-web'   },
        { id: 'e-dmz-db',   source: 'dmz',       target: 'srv-db'    },
        { id: 'e-dmz-tpot', source: 'dmz',       target: 'tpot'      },
      ],
      info: {
        attacker:  { ip, role: attackerRole, service: '' },
        internet:  { ip: 'WAN', role: 'Périmètre réseau', service: 'Transit' },
        firewall:  { ip: '192.168.1.1', role: 'Gateway / IDS', service: 'OPNsense 24.x' },
        crowdsec:  { ip: '192.168.1.10', role: 'IDPS', service: 'CrowdSec LAPI' },
        wireguard: { ip: '10.0.0.1', role: 'VPN Gateway', service: 'WireGuard 1.0' },
        dmz:       { ip: '192.168.2.0/24', role: 'Zone démilitarisée', service: 'Réseau isolé' },
        'srv-web': { ip: '192.168.2.10', role: 'Serveur web', service: 'Nginx 1.24' },
        'srv-db':  { ip: '192.168.2.20', role: 'Base de données', service: 'PostgreSQL 16' },
        tpot:      { ip: '192.168.1.50', role: 'Honeypot T-Pot CE', service: 'Cowrie · Dionaea · …' },
      },
    }
  }

  // ── Styles edges ───────────────────────────────────────────────────────────
  const NORMAL_EDGE  = { 'line-color': '#3f3f46', 'target-arrow-color': '#3f3f46', 'width': 2 }
  const ATTACK_BRIGHT = { 'line-color': '#f97316', 'target-arrow-color': '#f97316', 'width': 3 }
  const ATTACK_DIM    = { 'line-color': '#7c2d12', 'target-arrow-color': '#7c2d12', 'width': 2 }
  const DEFEND_EDGE   = { 'line-color': '#10b981', 'target-arrow-color': '#10b981', 'width': 3 }

  let nodeInfo: Record<string, { ip: string; role: string; service: string }> = {}

  function stopPulse() {
    if (pulseInterval !== null) { clearInterval(pulseInterval); pulseInterval = null }
  }

  function resetEdges(edges: { id: string }[]) {
    if (!cy) return
    edges.forEach(e => cy!.$(`#${e.id}`).style(NORMAL_EDGE))
  }

  function startPulse(edgeIds: string[]) {
    stopPulse()
    let bright = true
    pulseInterval = setInterval(() => {
      if (!cy) return
      const style = bright ? ATTACK_BRIGHT : ATTACK_DIM
      edgeIds.forEach(id => cy!.$(`#${id}`).style(style))
      bright = !bright
    }, 350)
  }

  function flashDefended(edgeIds: string[]) {
    stopPulse()
    if (!cy) return
    edgeIds.forEach(id => cy!.$(`#${id}`).style(DEFEND_EDGE))
    setTimeout(() => edgeIds.forEach(id => cy!.$(`#${id}`).style(NORMAL_EDGE)), 1500)
  }

  // ── Construire / reconstruire Cytoscape ────────────────────────────────────
  function buildCy(sid: string, ip: string) {
    stopPulse()
    if (cy) { cy.destroy(); cy = null }

    const cfg = live && labConfig ? getLiveConfig(labConfig) : getConfig(sid, ip)
    nodeInfo = cfg.info as typeof nodeInfo

    cy = cytoscape({
      container,
      elements: [
        ...cfg.nodes.map(n => ({ data: { id: n.id, label: n.label }, position: { x: n.x, y: n.y } })),
        ...cfg.edges.map(e => ({ data: { id: e.id, source: e.source, target: e.target } })),
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

    // Cacher les edges masqués par défaut pour ce scénario
    if ('hiddenEdges' in cfg) {
      (cfg as any).hiddenEdges.forEach((id: string) => cy!.$(`#${id}`).style('display', 'none'))
    }

    // Tooltips
    cy.on('mouseover', 'node', (e) => {
      const id = e.target.id()
      const info = nodeInfo[id]
      if (!info) return
      const pos = e.target.renderedBoundingBox()
      tooltipX = (pos.x1 + pos.x2) / 2
      tooltipY = pos.y1 - 8
      tooltipText = `${info.ip} · ${info.role}${info.service ? '\n' + info.service : ''}`
      tooltipVisible = true
    })
    cy.on('mouseout', 'node', () => { tooltipVisible = false })
  }

  // Reconstruire quand le scénario/IP change, ou quand labConfig arrive en mode live
  $: if (container && (scenarioId || live)) buildCy(scenarioId, attackerIp)

  // Réagir aux changements de couleur de nœuds + edge overrides
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
    for (const [edgeId, visibility] of Object.entries(state.edgeOverrides)) {
      cy.$(`#${edgeId}`).style('display', visibility === 'hidden' ? 'none' : 'element')
    }
  })

  // Réagir aux animations
  const unsubAnim = animStore.subscribe(state => {
    animPhase = state.phase
    const cfg = live && labConfig ? getLiveConfig(labConfig) : getConfig(scenarioId, attackerIp)
    if (state.phase === 'idle') {
      if (cy) resetEdges(cfg.edges)
      attackPathD = ''
      return
    }
    const edges = state.activeEdges
    attackColor = state.phase === 'defended'
      ? DEFEND_COLOR
      : (SCENARIO_COLORS[scenarioId] ?? '#ef4444')
    if (cy) attackPathD = buildAttackPath(edges)
    if (state.phase === 'attacking') {
      if (cy) startPulse(edges)
    } else if (state.phase === 'defended') {
      if (cy) flashDefended(edges)
      setTimeout(() => { attackPathD = '' }, 1500)
    }
  })

  // En mode live : mettre à jour le label du nœud attaquant avec la dernière IP T-Pot
  const unsubTpot = tpotStore.subscribe(state => {
    if (!cy || !live) return
    const lastIp = state.feed[0]?.src_ip
    if (!lastIp) return
    const node = cy.$('#attacker')
    if (node.length) {
      node.data('label', `🔴 Attaquant\n${lastIp}`)
      nodeInfo['attacker'] = { ip: lastIp, role: 'Dernière IP attaquante', service: 'T-Pot feed' }
    }
  })

  onMount(() => {
    if (scenarioId || live) buildCy(scenarioId, attackerIp)
  })

  onDestroy(() => {
    stopPulse()
    unsubTopology()
    unsubAnim()
    unsubTpot()
    cy?.destroy()
  })
</script>

<div class="relative w-full h-full">
  <div bind:this={container} class="w-full h-full rounded-lg bg-zinc-900" />

  <!-- SVG overlay : flèche d'attaque animée -->
  <svg class="absolute inset-0 w-full h-full pointer-events-none">
    <defs>
      <marker id="atk-arrow" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto">
        <polygon points="0 0, 8 3, 0 6" style="fill: {attackColor}" />
      </marker>
    </defs>
    {#if attackPathD && animPhase !== 'idle'}
      <!-- halo -->
      <path d={attackPathD} fill="none"
        stroke={attackColor} stroke-width="10" stroke-opacity="0.12"
        stroke-linecap="round" stroke-linejoin="round" />
      <!-- trait animé -->
      <path d={attackPathD} fill="none"
        stroke={attackColor} stroke-width="2.5"
        stroke-dasharray="12 8" stroke-linecap="round" stroke-linejoin="round"
        marker-end="url(#atk-arrow)"
        class={animPhase === 'attacking' ? 'anim-attack' : 'anim-defend'} />
    {/if}
  </svg>

  {#if tooltipVisible}
    <div
      class="absolute z-10 pointer-events-none px-2 py-1.5 rounded bg-zinc-800 border border-zinc-600 text-xs font-mono text-zinc-200 whitespace-pre shadow-lg"
      style="left: {tooltipX}px; top: {tooltipY}px; transform: translate(-50%, -100%);"
    >
      {tooltipText}
    </div>
  {/if}
</div>

<style>
  @keyframes flow-dash {
    to { stroke-dashoffset: -20; }
  }
  .anim-attack { animation: flow-dash 0.45s linear infinite; }
  .anim-defend { animation: flow-dash 0.7s linear infinite; }
</style>
