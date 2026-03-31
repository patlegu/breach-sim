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
          animStore.setAttacking(event.step_id, event.attack_edges ?? [])
          break
        case 'token':
          scenarioStore.appendToken(event.step_id, event.text)
          break
        case 'step_done':
          scenarioStore.setStepDone(event.step_id, event.tool_call, event.raw, event.latency_s, event.execution ?? null)
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

export async function triggerScenario(scenarioId: string): Promise<void> {
  const res = await fetch('/api/scenario/run', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ scenario_id: scenarioId }),
  })
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

export interface ScenarioMeta {
  id: string
  title: string
  description: string
  tags: string[]
  step_count: number
  agents: string[]
}

export interface ScenarioStep {
  id: string
  title: string
  agent: string
  description: string
  cap: object
  mitre: { tactic: string; technique: string; name: string; cve: string | null } | null
  attack_edges: string[]
}

export interface ScenarioDetail extends ScenarioMeta {
  steps: ScenarioStep[]
}

export interface LabConfig {
  live: boolean
  lab_type: string
  instance: number
  opnsense_ip: string
  infected_ip: string
  srv_web_ip: string
  srv_db_ip: string
  k3s_cp_ip: string | null
  crowdsec_ip: string
}

export async function fetchLab(): Promise<LabConfig> {
  const res = await fetch('/api/lab')
  return res.json()
}

export async function fetchScenarios(): Promise<ScenarioMeta[]> {
  const res = await fetch('/api/scenarios')
  const data = await res.json()
  return data.scenarios
}

export async function fetchScenario(id: string): Promise<ScenarioDetail> {
  const res = await fetch(`/api/scenarios/${id}`)
  return res.json()
}
