import { writable } from 'svelte/store'

export type NodeStatus = 'normal' | 'attacked' | 'defended'

export interface TopologyState {
  nodes: Record<string, NodeStatus>
}

const INITIAL: TopologyState = {
  nodes: {
    attacker:  'normal',
    internet:  'normal',
    firewall:  'normal',
    crowdsec:  'normal',
    wireguard: 'normal',
    dmz:       'normal',
    'srv-web': 'normal',
    'srv-db':  'normal',
  },
}

const EVENT_MAP: Record<string, Partial<Record<string, NodeStatus>>> = {
  crowdsec_ban:      { attacker: 'attacked', crowdsec: 'defended' },
  firewall_block:    { attacker: 'attacked', firewall: 'defended' },
  filter_rule_added: { attacker: 'attacked', firewall: 'defended', dmz: 'defended' },
  wireguard_rotate:  { wireguard: 'defended' },
}

function createTopologyStore() {
  const { subscribe, update, set } = writable<TopologyState>(structuredClone(INITIAL))

  return {
    subscribe,
    applyEvent(event: string) {
      const changes = EVENT_MAP[event]
      if (!changes) return
      update(s => ({
        nodes: { ...s.nodes, ...changes },
      }))
    },
    reset() {
      set(structuredClone(INITIAL))
    },
  }
}

export const topologyStore = createTopologyStore()
