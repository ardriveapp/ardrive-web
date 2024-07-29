export function createProcessMetaCache({ MAX_SIZE }: {
    MAX_SIZE: any;
}): LruMap<any, any>;
export function loadProcessMetaWith({ logger, fetch, cache }: {
    logger: any;
    fetch: any;
    cache?: LruMap<any, any>;
}): ({ suUrl, processId }: {
    suUrl: any;
    processId: any;
}) => Promise<any>;
import LruMap from 'mnemonist/lru-map.js';
