import { writable } from 'svelte/store'

export interface TpotContainer {
  name: string
  hits: number
}

export interface TpotEvent {
  ts: string        // @timestamp ISO
  honeypot: string
  src_ip: string
  port: number
}

const FEED_MAX = 50  // nombre max d'événements conservés dans le feed

function createTpotStore() {
  const { subscribe, update, set } = writable<{
    counts: TpotContainer[]
    feed: TpotEvent[]
  }>({ counts: [], feed: [] })

  return {
    subscribe,
    setCounts(containers: TpotContainer[]) {
      update(s => ({ ...s, counts: containers }))
    },
    addEvent(ev: TpotEvent) {
      update(s => {
        const feed = [ev, ...s.feed].slice(0, FEED_MAX)
        return { ...s, feed }
      })
    },
    reset() {
      set({ counts: [], feed: [] })
    },
  }
}

export const tpotStore = createTpotStore()
