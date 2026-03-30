import { writable, derived } from 'svelte/store'

export type StepStatus = 'idle' | 'running' | 'done' | 'error'

export interface StepState {
  id: string
  status: StepStatus
  tokens: string[]
  toolCall: object | null
  raw: string
  latency: number | null
}

export interface ScenarioStatus {
  status: 'idle' | 'running' | 'done' | 'error'
  steps: Record<string, StepState>
}

const INITIAL_STEPS: Record<string, StepState> = {
  step_1: { id: 'step_1', status: 'idle', tokens: [], toolCall: null, raw: '', latency: null },
  step_2: { id: 'step_2', status: 'idle', tokens: [], toolCall: null, raw: '', latency: null },
  step_3: { id: 'step_3', status: 'idle', tokens: [], toolCall: null, raw: '', latency: null },
}

function createScenarioStore() {
  const { subscribe, set, update } = writable<ScenarioStatus>({
    status: 'idle',
    steps: structuredClone(INITIAL_STEPS),
  })

  return {
    subscribe,
    setRunning() {
      update(s => ({ ...s, status: 'running' }))
    },
    setStepRunning(stepId: string) {
      update(s => ({
        ...s,
        steps: { ...s.steps, [stepId]: { ...s.steps[stepId], status: 'running', tokens: [] } },
      }))
    },
    appendToken(stepId: string, text: string) {
      update(s => ({
        ...s,
        steps: {
          ...s.steps,
          [stepId]: { ...s.steps[stepId], tokens: [...s.steps[stepId].tokens, text] },
        },
      }))
    },
    setStepDone(stepId: string, toolCall: object, raw: string, latency: number) {
      update(s => ({
        ...s,
        steps: { ...s.steps, [stepId]: { ...s.steps[stepId], status: 'done', toolCall, raw, latency } },
      }))
    },
    setDone() {
      update(s => ({ ...s, status: 'done' }))
    },
    setError(message: string) {
      update(s => ({ ...s, status: 'error' }))
    },
    reset() {
      set({ status: 'idle', steps: structuredClone(INITIAL_STEPS) })
    },
  }
}

export const scenarioStore = createScenarioStore()
