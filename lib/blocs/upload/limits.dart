// SECURITY WARNING: READ BEFORE INCREASING THIS LIMIT!
// This must be limited to 64 GiB as the AES Counter bytes are shared with the
// nonce. Since file revisions reuse the same key, it is critical that the nonce
// is unique. We assign 12 bytes to the nonce to keep the chance of a collision
// for random generation acceptably low.
// This leaves 4 bytes for the block counter, so it can encrypt 2^32 blocks.
// Since each block is 16 bytes, the total data limit is 64 GiB.
// In the future, this limit can be increased by updating the key/nonce
// generation algorithm that so it never reuses the same key/nonce combination.
const privateFileSizeLimit = 64 * 1024 * 1024 * 1024; // 64 GiB.

// Same as web 
const mobilePrivateFileSizeLimit = privateFileSizeLimit;

// Set arbitrarily
const publicFileSizeLimit = 1024 * 1024 * 1024 * 1024; // 1 TiB!

