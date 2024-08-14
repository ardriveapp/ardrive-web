/**
 * @typedef Env1
 * @property {fetch} fetch
 * @property {string} GRAPHQL_URL
 *
 * @callback LoadTransactionMeta
 * @param {string} id - the id of the contract whose src is being loaded
 * @returns {Async<z.infer<typeof transactionConnectionSchema>['data']['transactions']['edges'][number]['node']>}
 *
 * @param {Env1} env
 * @returns {LoadTransactionMeta}
 */
export function loadTransactionMetaWith({ fetch, GRAPHQL_URL, logger }: Env1): LoadTransactionMeta;
export type Env1 = {
    fetch: typeof globalThis.fetch;
    GRAPHQL_URL: string;
};
export type LoadTransactionMeta = (id: string) => Async<Record<string, any>>;
