import { writable } from 'svelte/store'

export type StepStatus = 'idle' | 'running' | 'done' | 'error'

export interface StepState {
  id: string
  status: StepStatus
  tokens: string[]
  tokenCount: number
  toolCall: object | null
  raw: string
  latency: number | null
  startedAt: number | null
}

export interface ScenarioStatus {
  status: 'idle' | 'running' | 'done' | 'error'
  startedAt: number | null
  steps: Record<string, StepState>
}

const STEP_IDS = ['step_1', 'step_2', 'step_3', 'step_4']

function makeInitialSteps(): Record<string, StepState> {
  return Object.fromEntries(
    STEP_IDS.map(id => [
      id,
      { id, status: 'idle', tokens: [], tokenCount: 0, toolCall: null, raw: '', latency: null, startedAt: null },
    ])
  )
}

function createScenarioStore() {
  const { subscribe, set, update } = writable<ScenarioStatus>({
    status: 'idle',
    startedAt: null,
    steps: makeInitialSteps(),
  })

  return {
    subscribe,
    setRunning() {
      update(s => ({ ...s, status: 'running', startedAt: Date.now() }))
    },
    setStepRunning(stepId: string) {
      update(s => ({
        ...s,
        steps: {
          ...s.steps,
          [stepId]: { ...s.steps[stepId], status: 'running', tokens: [], tokenCount: 0, startedAt: Date.now() },
        },
      }))
    },
    appendToken(stepId: string, text: string) {
      update(s => ({
        ...s,
        steps: {
          ...s.steps,
          [stepId]: {
            ...s.steps[stepId],
            tokens: [...s.steps[stepId].tokens, text],
            tokenCount: s.steps[stepId].tokenCount + 1,
          },
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
    setError(_message: string) {
      update(s => ({ ...s, status: 'error' }))
    },
    reset() {
      set({ status: 'idle', startedAt: null, steps: makeInitialSteps() })
    },
  }
}

export const scenarioStore = createScenarioStore()
