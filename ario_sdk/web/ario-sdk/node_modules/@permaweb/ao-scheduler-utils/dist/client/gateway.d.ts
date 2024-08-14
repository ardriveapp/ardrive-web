export function loadProcessSchedulerWith({ fetch, GRAPHQL_URL }: {
    fetch: any;
    GRAPHQL_URL: any;
}): (process: any) => Promise<{
    url: any;
    ttl: any;
    address: any;
}>;
export function loadSchedulerWith({ fetch, GRAPHQL_URL }: {
    fetch: any;
    GRAPHQL_URL: any;
}): (walletAddress: any) => Promise<{
    url: any;
    ttl: any;
    address: any;
}>;
