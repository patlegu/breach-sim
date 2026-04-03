import { writable } from 'svelte/store'

export type NodeStatus = 'normal' | 'attacked' | 'defended'

export interface TopologyState {
  nodes: Record<string, NodeStatus>
  edgeOverrides: Record<string, 'hidden' | 'visible'>
}

interface EventEffect {
  nodes?: Partial<Record<string, NodeStatus>>
  edgeOverrides?: Record<string, 'hidden' | 'visible'>
}

const INITIAL: TopologyState = {
  nodes: {
    attacker:  'normal',
    internet:  'normal',
    firewall:  'normal',
    crowdsec:  'normal',
    wireguard: 'normal',
    dmz:       'normal',
    lan:       'normal',
    infected:  'normal',
    'srv-web': 'normal',
    'srv-db':  'normal',
    tpot:      'normal',
  },
  edgeOverrides: {},
}

const EVENT_MAP: Record<string, EventEffect> = {
  // Scénarios externes
  crowdsec_ban:      { nodes: { attacker: 'attacked', crowdsec: 'defended' } },
  firewall_block:    { nodes: { attacker: 'attacked', firewall: 'defended' } },
  filter_rule_added: { nodes: { attacker: 'attacked', firewall: 'defended', dmz: 'defended' } },
  wireguard_rotate:  { nodes: { wireguard: 'defended' } },
  // Scénario ransomware C2
  infected_beacon:   { nodes: { infected: 'attacked', crowdsec: 'defended' } },
  egress_blocked:    { nodes: { infected: 'attacked', firewall: 'defended' } },
  lateral_blocked:   { nodes: { infected: 'attacked', firewall: 'defended', lan: 'defended' } },
  wireguard_client:  {
    nodes: { wireguard: 'defended' },
    edgeOverrides: { 'e-lan-inf': 'hidden', 'e-inf-wg': 'visible' },
  },
  // T-Pot live hits
  tpot_hit: { nodes: { tpot: 'attacked' } },
}

function createTopologyStore() {
  const { subscribe, update, set } = writable<TopologyState>(structuredClone(INITIAL))

  return {
    subscribe,
    applyEvent(event: string) {
      const effect = EVENT_MAP[event]
      if (!effect) return
      update(s => ({
        nodes: { ...s.nodes, ...(effect.nodes ?? {}) } as Record<string, NodeStatus>,
        edgeOverrides: { ...s.edgeOverrides, ...(effect.edgeOverrides ?? {}) },
      }))
    },
    resetNode(nodeId: string) {
      update(s => ({
        ...s,
        nodes: { ...s.nodes, [nodeId]: 'normal' as NodeStatus },
      }))
    },
    reset() {
      set(structuredClone(INITIAL))
    },
  }
}

export const topologyStore = createTopologyStore()
