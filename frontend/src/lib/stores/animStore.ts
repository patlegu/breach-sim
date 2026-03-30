import { writable } from 'svelte/store'

export type AnimPhase = 'idle' | 'attacking' | 'defended'

export interface AnimState {
  activeStepId: string | null
  phase: AnimPhase
}

// Edges Cytoscape à animer par step (IDs définis dans NetworkTopology)
export const STEP_ATTACK_EDGES: Record<string, string[]> = {
  step_1: ['e-atk-net', 'e-net-fw', 'e-fw-cs'],
  step_2: ['e-atk-net', 'e-net-fw'],
  step_3: ['e-atk-net', 'e-net-fw', 'e-fw-dmz'],
  step_4: ['e-fw-wg'],
}

function createAnimStore() {
  const { subscribe, set, update } = writable<AnimState>({ activeStepId: null, phase: 'idle' })
  return {
    subscribe,
    setAttacking(stepId: string) {
      set({ activeStepId: stepId, phase: 'attacking' })
    },
    setDefended(stepId: string) {
      update(s => ({ ...s, phase: 'defended' }))
    },
    reset() {
      set({ activeStepId: null, phase: 'idle' })
    },
  }
}

export const animStore = createAnimStore()
