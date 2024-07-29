/**
 * @typedef ConnectParams
 * @property {number} [cacheSize] - the size of the internal LRU cache
 * @property {boolean} [followRedirects] - whether to follow redirects and cache that url instead
 * @property {string} [GRAPHQL_URL] - the url of the gateway to be used
 *
 * Build the apis using the provided configuration. You can currently specify
 *
 * - a GRAPHQL_URL. Defaults to https://arweave.net/graphql
 * - a cache size for the internal LRU cache. Defaults to 100
 * - whether or not to follow redirects when locating a scheduler. Defaults to false
 *
 * If either value is not provided, a default will be used.
 * Invoking connect() with no parameters or an empty object is functionally equivalent
 * to using the top-lvl exports
 *
 * @param {ConnectParams} [params]
 */
export function connect({ cacheSize, GRAPHQL_URL, followRedirects }?: ConnectParams): {
    locate: (process: string, schedulerHint?: string) => Promise<{
        url: string;
        address: string;
    }>;
    validate: (address: string) => Promise<boolean>;
    raw: (address: string) => Promise<{
        url: string;
    }>;
};
export * from "./err.js";
export type ConnectParams = {
    /**
     * - the size of the internal LRU cache
     */
    cacheSize?: number;
    /**
     * - whether to follow redirects and cache that url instead
     */
    followRedirects?: boolean;
    /**
     * - the url of the gateway to be used
     *
     * Build the apis using the provided configuration. You can currently specify
     *
     * - a GRAPHQL_URL. Defaults to https://arweave.net/graphql
     * - a cache size for the internal LRU cache. Defaults to 100
     * - whether or not to follow redirects when locating a scheduler. Defaults to false
     *
     * If either value is not provided, a default will be used.
     * Invoking connect() with no parameters or an empty object is functionally equivalent
     * to using the top-lvl exports
     */
    GRAPHQL_URL?: string;
};
