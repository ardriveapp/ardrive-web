export const dryrunResultSchema: z.ZodFunction<z.ZodTuple<[z.ZodObject<{
    Id: z.ZodString;
    Target: z.ZodString;
    Owner: z.ZodString;
    Anchor: z.ZodOptional<z.ZodString>;
    Data: z.ZodDefault<z.ZodAny>;
    Tags: z.ZodArray<z.ZodObject<{
        name: z.ZodString;
        value: z.ZodString;
    }, "strip", z.ZodTypeAny, {
        name?: string;
        value?: string;
    }, {
        name?: string;
        value?: string;
    }>, "many">;
}, "strip", z.ZodTypeAny, {
    Id?: string;
    Target?: string;
    Owner?: string;
    Anchor?: string;
    Data?: any;
    Tags?: {
        name?: string;
        value?: string;
    }[];
}, {
    Id?: string;
    Target?: string;
    Owner?: string;
    Anchor?: string;
    Data?: any;
    Tags?: {
        name?: string;
        value?: string;
    }[];
}>], z.ZodUnknown>, z.ZodPromise<z.ZodAny>>;
export const loadResultSchema: z.ZodFunction<z.ZodTuple<[z.ZodObject<{
    id: z.ZodString;
    processId: z.ZodString;
}, "strip", z.ZodTypeAny, {
    id?: string;
    processId?: string;
}, {
    id?: string;
    processId?: string;
}>], z.ZodUnknown>, z.ZodPromise<z.ZodAny>>;
export const queryResultsSchema: z.ZodFunction<z.ZodTuple<[z.ZodObject<{
    process: z.ZodString;
    from: z.ZodOptional<z.ZodString>;
    to: z.ZodOptional<z.ZodString>;
    sort: z.ZodDefault<z.ZodEnum<["ASC", "DESC"]>>;
    limit: z.ZodOptional<z.ZodNumber>;
}, "strip", z.ZodTypeAny, {
    process?: string;
    from?: string;
    to?: string;
    sort?: "ASC" | "DESC";
    limit?: number;
}, {
    process?: string;
    from?: string;
    to?: string;
    sort?: "ASC" | "DESC";
    limit?: number;
}>], z.ZodUnknown>, z.ZodPromise<z.ZodObject<{
    edges: z.ZodArray<z.ZodObject<{
        cursor: z.ZodString;
        node: z.ZodObject<{
            Output: z.ZodOptional<z.ZodAny>;
            Messages: z.ZodOptional<z.ZodArray<z.ZodAny, "many">>;
            Spawns: z.ZodOptional<z.ZodArray<z.ZodAny, "many">>;
            Error: z.ZodOptional<z.ZodAny>;
        }, "strip", z.ZodTypeAny, {
            Output?: any;
            Messages?: any[];
            Spawns?: any[];
            Error?: any;
        }, {
            Output?: any;
            Messages?: any[];
            Spawns?: any[];
            Error?: any;
        }>;
    }, "strip", z.ZodTypeAny, {
        cursor?: string;
        node?: {
            Output?: any;
            Messages?: any[];
            Spawns?: any[];
            Error?: any;
        };
    }, {
        cursor?: string;
        node?: {
            Output?: any;
            Messages?: any[];
            Spawns?: any[];
            Error?: any;
        };
    }>, "many">;
}, "strip", z.ZodTypeAny, {
    edges?: {
        cursor?: string;
        node?: {
            Output?: any;
            Messages?: any[];
            Spawns?: any[];
            Error?: any;
        };
    }[];
}, {
    edges?: {
        cursor?: string;
        node?: {
            Output?: any;
            Messages?: any[];
            Spawns?: any[];
            Error?: any;
        };
    }[];
}>>>;
export const deployMessageSchema: z.ZodFunction<z.ZodTuple<[z.ZodObject<{
    processId: z.ZodString;
    data: z.ZodAny;
    tags: z.ZodArray<z.ZodObject<{
        name: z.ZodString;
        value: z.ZodString;
    }, "strip", z.ZodTypeAny, {
        name?: string;
        value?: string;
    }, {
        name?: string;
        value?: string;
    }>, "many">;
    anchor: z.ZodOptional<z.ZodString>;
    signer: z.ZodAny;
}, "strip", z.ZodTypeAny, {
    processId?: string;
    data?: any;
    tags?: {
        name?: string;
        value?: string;
    }[];
    anchor?: string;
    signer?: any;
}, {
    processId?: string;
    data?: any;
    tags?: {
        name?: string;
        value?: string;
    }[];
    anchor?: string;
    signer?: any;
}>], z.ZodUnknown>, z.ZodPromise<z.ZodObject<{
    messageId: z.ZodString;
}, "passthrough", z.ZodTypeAny, z.objectOutputType<{
    messageId: z.ZodString;
}, z.ZodTypeAny, "passthrough">, z.objectInputType<{
    messageId: z.ZodString;
}, z.ZodTypeAny, "passthrough">>>>;
export const deployProcessSchema: z.ZodFunction<z.ZodTuple<[z.ZodObject<{
    data: z.ZodAny;
    tags: z.ZodArray<z.ZodObject<{
        name: z.ZodString;
        value: z.ZodString;
    }, "strip", z.ZodTypeAny, {
        name?: string;
        value?: string;
    }, {
        name?: string;
        value?: string;
    }>, "many">;
    signer: z.ZodAny;
}, "strip", z.ZodTypeAny, {
    data?: any;
    tags?: {
        name?: string;
        value?: string;
    }[];
    signer?: any;
}, {
    data?: any;
    tags?: {
        name?: string;
        value?: string;
    }[];
    signer?: any;
}>], z.ZodUnknown>, z.ZodPromise<z.ZodObject<{
    processId: z.ZodString;
}, "passthrough", z.ZodTypeAny, z.objectOutputType<{
    processId: z.ZodString;
}, z.ZodTypeAny, "passthrough">, z.objectInputType<{
    processId: z.ZodString;
}, z.ZodTypeAny, "passthrough">>>>;
export const deployAssignSchema: z.ZodFunction<z.ZodTuple<[z.ZodObject<{
    process: z.ZodString;
    message: z.ZodString;
    baseLayer: z.ZodOptional<z.ZodBoolean>;
    exclude: z.ZodOptional<z.ZodArray<z.ZodString, "many">>;
}, "strip", z.ZodTypeAny, {
    process?: string;
    message?: string;
    baseLayer?: boolean;
    exclude?: string[];
}, {
    process?: string;
    message?: string;
    baseLayer?: boolean;
    exclude?: string[];
}>], z.ZodUnknown>, z.ZodPromise<z.ZodObject<{
    assignmentId: z.ZodString;
}, "passthrough", z.ZodTypeAny, z.objectOutputType<{
    assignmentId: z.ZodString;
}, z.ZodTypeAny, "passthrough">, z.objectInputType<{
    assignmentId: z.ZodString;
}, z.ZodTypeAny, "passthrough">>>>;
/**
 * Same contract shape
 */
export const deployMonitorSchema: z.ZodFunction<z.ZodTuple<[z.ZodObject<{
    processId: z.ZodString;
    data: z.ZodAny;
    tags: z.ZodArray<z.ZodObject<{
        name: z.ZodString;
        value: z.ZodString;
    }, "strip", z.ZodTypeAny, {
        name?: string;
        value?: string;
    }, {
        name?: string;
        value?: string;
    }>, "many">;
    anchor: z.ZodOptional<z.ZodString>;
    signer: z.ZodAny;
}, "strip", z.ZodTypeAny, {
    processId?: string;
    data?: any;
    tags?: {
        name?: string;
        value?: string;
    }[];
    anchor?: string;
    signer?: any;
}, {
    processId?: string;
    data?: any;
    tags?: {
        name?: string;
        value?: string;
    }[];
    anchor?: string;
    signer?: any;
}>], z.ZodUnknown>, z.ZodPromise<z.ZodObject<{
    messageId: z.ZodString;
}, "passthrough", z.ZodTypeAny, z.objectOutputType<{
    messageId: z.ZodString;
}, z.ZodTypeAny, "passthrough">, z.objectInputType<{
    messageId: z.ZodString;
}, z.ZodTypeAny, "passthrough">>>>;
export const loadProcessMetaSchema: z.ZodFunction<z.ZodTuple<[z.ZodObject<{
    suUrl: z.ZodString;
    processId: z.ZodString;
}, "strip", z.ZodTypeAny, {
    suUrl?: string;
    processId?: string;
}, {
    suUrl?: string;
    processId?: string;
}>], z.ZodUnknown>, z.ZodPromise<z.ZodObject<{
    tags: z.ZodArray<z.ZodObject<{
        name: z.ZodString;
        value: z.ZodString;
    }, "strip", z.ZodTypeAny, {
        name?: string;
        value?: string;
    }, {
        name?: string;
        value?: string;
    }>, "many">;
}, "passthrough", z.ZodTypeAny, z.objectOutputType<{
    tags: z.ZodArray<z.ZodObject<{
        name: z.ZodString;
        value: z.ZodString;
    }, "strip", z.ZodTypeAny, {
        name?: string;
        value?: string;
    }, {
        name?: string;
        value?: string;
    }>, "many">;
}, z.ZodTypeAny, "passthrough">, z.objectInputType<{
    tags: z.ZodArray<z.ZodObject<{
        name: z.ZodString;
        value: z.ZodString;
    }, "strip", z.ZodTypeAny, {
        name?: string;
        value?: string;
    }, {
        name?: string;
        value?: string;
    }>, "many">;
}, z.ZodTypeAny, "passthrough">>>>;
export const locateSchedulerSchema: z.ZodFunction<z.ZodTuple<[z.ZodString], z.ZodUnknown>, z.ZodPromise<z.ZodObject<{
    url: z.ZodString;
}, "strip", z.ZodTypeAny, {
    url?: string;
}, {
    url?: string;
}>>>;
export const validateSchedulerSchema: z.ZodFunction<z.ZodTuple<[z.ZodString], z.ZodUnknown>, z.ZodPromise<z.ZodBoolean>>;
export const loadTransactionMetaSchema: z.ZodFunction<z.ZodTuple<[z.ZodString], z.ZodUnknown>, z.ZodPromise<z.ZodObject<{
    tags: z.ZodArray<z.ZodObject<{
        name: z.ZodString;
        value: z.ZodString;
    }, "strip", z.ZodTypeAny, {
        name?: string;
        value?: string;
    }, {
        name?: string;
        value?: string;
    }>, "many">;
}, "passthrough", z.ZodTypeAny, z.objectOutputType<{
    tags: z.ZodArray<z.ZodObject<{
        name: z.ZodString;
        value: z.ZodString;
    }, "strip", z.ZodTypeAny, {
        name?: string;
        value?: string;
    }, {
        name?: string;
        value?: string;
    }>, "many">;
}, z.ZodTypeAny, "passthrough">, z.objectInputType<{
    tags: z.ZodArray<z.ZodObject<{
        name: z.ZodString;
        value: z.ZodString;
    }, "strip", z.ZodTypeAny, {
        name?: string;
        value?: string;
    }, {
        name?: string;
        value?: string;
    }>, "many">;
}, z.ZodTypeAny, "passthrough">>>>;
export const signerSchema: z.ZodFunction<z.ZodTuple<[z.ZodObject<{
    data: z.ZodAny;
    tags: z.ZodArray<z.ZodObject<{
        name: z.ZodString;
        value: z.ZodString;
    }, "strip", z.ZodTypeAny, {
        name?: string;
        value?: string;
    }, {
        name?: string;
        value?: string;
    }>, "many">;
    /**
     * target must be set with writeMessage,
     * but not for createProcess
     */
    target: z.ZodOptional<z.ZodString>;
    anchor: z.ZodOptional<z.ZodString>;
}, "strip", z.ZodTypeAny, {
    data?: any;
    tags?: {
        name?: string;
        value?: string;
    }[];
    target?: string;
    anchor?: string;
}, {
    data?: any;
    tags?: {
        name?: string;
        value?: string;
    }[];
    target?: string;
    anchor?: string;
}>], z.ZodUnknown>, z.ZodPromise<z.ZodObject<{
    id: z.ZodString;
    raw: z.ZodAny;
}, "strip", z.ZodTypeAny, {
    id?: string;
    raw?: any;
}, {
    id?: string;
    raw?: any;
}>>>;
/**
 * A hack to get reuse JSDoc types in other files
 * See https://stackoverflow.com/questions/49836644/how-to-import-a-typedef-from-one-file-to-another-in-jsdoc-using-node-js
 *
 * We can simply define types here as needed
 */
export type Types = {
    signer: z.infer<typeof signerSchema>;
};
/**
 * A hack to get reuse JSDoc types in other files
 * See https://stackoverflow.com/questions/49836644/how-to-import-a-typedef-from-one-file-to-another-in-jsdoc-using-node-js
 *
 * We can simply define types here as needed
 *
 * @typedef Types
 * @property {z.infer<typeof signerSchema>} signer
 */
export const Types: {};
import { z } from 'zod';
