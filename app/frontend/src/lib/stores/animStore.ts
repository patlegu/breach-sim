import { writable } from 'svelte/store'

export type AnimPhase = 'idle' | 'attacking' | 'defended'

export interface AnimState {
  activeStepId: string | null
  activeEdges: string[]
  phase: AnimPhase
}

function createAnimStore() {
  const { subscribe, set, update } = writable<AnimState>({ activeStepId: null, activeEdges: [], phase: 'idle' })
  return {
    subscribe,
    setAttacking(stepId: string, edges: string[]) {
      set({ activeStepId: stepId, activeEdges: edges, phase: 'attacking' })
    },
    setDefended(stepId: string) {
      update(s => ({ ...s, phase: 'defended' }))
    },
    reset() {
      set({ activeStepId: null, activeEdges: [], phase: 'idle' })
    },
  }
}

export const animStore = createAnimStore()
