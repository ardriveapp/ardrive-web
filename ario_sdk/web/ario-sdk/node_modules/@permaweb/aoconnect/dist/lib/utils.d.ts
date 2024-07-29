/**
* Parse tags into a object with key-value pairs of name -> values.
*
* If multiple tags with the same name exist, it's value will be the array of tag values
* in order of appearance
*/
export function parseTags(rawTags: any): any;
/**
 * Remove tags from the array by name. If value is provided,
 * then only remove tags whose both name and value matches.
 *
 * @param {string} name - the name of the tags to be removed
 * @param {string} [value] - the value of the tags to be removed
 */
export function removeTagsByNameMaybeValue(name: string, value?: string): (tags: any) => any;
export function eqOrIncludes(val: any): any;
export function trimSlash(str?: string): string;
export function errFrom(err: any): any;
export function joinUrl({ url, path }: {
    url: any;
    path: any;
}): any;
