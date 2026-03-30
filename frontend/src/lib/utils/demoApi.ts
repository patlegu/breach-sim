import { scenarioStore } from '../stores/scenarioStore'
import { topologyStore } from '../stores/topologyStore'
import { animStore } from '../stores/animStore'

let _es: EventSource | null = null

export function connectDemoSSE(): () => void {
  if (_es) _es.close()

  _es = new EventSource('/api/scenario/stream')

  _es.onmessage = (e: MessageEvent) => {
    try {
      const event = JSON.parse(e.data)
      switch (event.type) {
        case 'scenario_start':
          scenarioStore.setRunning()
          break
        case 'step_start':
          scenarioStore.setStepRunning(event.step_id)
          animStore.setAttacking(event.step_id)
          break
        case 'token':
          scenarioStore.appendToken(event.step_id, event.text)
          break
        case 'step_done':
          scenarioStore.setStepDone(event.step_id, event.tool_call, event.raw, event.latency_s)
          animStore.setDefended(event.step_id)
          break
        case 'topology_update':
          topologyStore.applyEvent(event.event)
          break
        case 'scenario_done':
          scenarioStore.setDone()
          animStore.reset()
          break
        case 'scenario_reset':
          scenarioStore.reset()
          topologyStore.reset()
          animStore.reset()
          break
        case 'scenario_error':
          scenarioStore.setError(event.message)
          animStore.reset()
          break
        case 'ping':
          break
      }
    } catch (err) {
      console.error('SSE parse error', err)
    }
  }

  _es.onerror = () => {
    console.warn('SSE disconnected, reconnecting...')
    setTimeout(connectDemoSSE, 2000)
  }

  return () => { _es?.close(); _es = null }
}

export async function triggerScenario(): Promise<void> {
  const res = await fetch('/api/scenario/run', { method: 'POST' })
  if (!res.ok) {
    const err = await res.json().catch(() => ({}))
    throw new Error(err.detail || `HTTP ${res.status}`)
  }
}

export async function resetScenario(): Promise<void> {
  await fetch('/api/scenario/reset', { method: 'POST' })
  scenarioStore.reset()
  topologyStore.reset()
  animStore.reset()
}

export async function fetchHealth(): Promise<{
  ready: boolean
  loaded: string[]
  pending: string[]
  models: Record<string, { name: string; precision: string; repo: string }>
}> {
  const res = await fetch('/api/health')
  return res.json()
}
