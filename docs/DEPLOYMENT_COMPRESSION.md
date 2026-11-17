# Compressing deployments

A folder with a root `index.html`, uploaded to a **public** drive, has its text and code uploaded gzipped. The data item carries `Content-Encoding: gzip` and the file's own `Content-Type`; a gateway serves it with that header and the browser decodes it, the same as a site deployed with `@ar.io/deploy --compress gzip`. A typical site goes up at about a third of its size.

Switch: `compressDeployments` in `AppConfig` (`assets/config/*.json`). On in development and staging. Production is off until it is turned on deliberately; remember that an edit to the JSON only reaches a user who already ran the app once if `configVersion` is bumped. The switch affects new uploads only: files already uploaded stay readable either way, because the readers below handle them with the switch off.

## What is compressed

Decided in one place, `CompressionPolicy` (`packages/ardrive_uploader/lib/src/compression_policy.dart`), called from `prepareDataItems`, which both Turbo and direct-to-node uploads go through.

- Only when the upload is a **folder upload** with an `index.html` directly in the picked folder (`isDeploymentUpload`, `lib/core/upload/deployment_upload.dart`), to a **public** drive. Single-file uploads, private drives, thumbnails, the manifest, snapshots, drive state and licences never are.
- Never an extension `@ar.io/deploy` 2.1.2 leaves alone: `.7z .avif .br .bz2 .gif .gz .heic .jpeg .jpg .m4a .mp3 .mp4 .ogg .opus .png .rar .webm .webp .woff .woff2 .xz .zip .zst`. ArDrive adds what is read by byte range or is compressed already: all audio and video, `.pdf`, every image except SVG, and archives (`.tgz .lz .lzma .jar .apk .dmg .iso .svgz` and the like). The content type is read too, and whichever says no wins.
- Never a file over 32 MiB (the gzip is built in memory, and a data item's size is signed before it is sent), and never one that is a gzip already.
- The gzip is kept only when it is **smaller**.
- Level 9, with the header's modification time set to 0 and a fixed OS byte, so a retried upload signs the same bytes.
- `ArFS` `size` stays the original byte count, so every reader that compares a decoded stream with `size` (previews, zip entries, share links) is unchanged.
- The upload review still prices the **uncompressed** size in 3.0.0. It can only be higher than what is paid, and a batch the review calls not free may in fact fit the free allowance. Pricing the stored size is planned for 3.0.1.

## Readers

`lib/download/ardrive_downloader.dart`:

- A browser or `dart:io` client decodes the body before the downloader sees it, but a `Range` request asks for **stored** bytes, so the count of delivered bytes is not an offset. A resume of a file stored with a `Content-Encoding` is not attempted (`DownloadResumeNotSupportedException`: the download restarts). It is known from the response header, or, when the client does not expose it, from the data item's tags, read once when a resume is about to be made.
- A download from byte 0 is a plain `GET`, with no `Range` header (it used to send `Range: bytes=0-`). Chrome answers any ranged request for a file stored with a `Content-Encoding` with `net::ERR_CONTENT_DECODING_FAILED`, whatever the range and the cache mode (measured against turbo-gateway.com with Chrome 130 and 158; Firefox 131 decodes it). Without this, every download of a compressed file fails in Chrome. Only a resume sends a range, and a resume is not attempted for such a file.
- A body that starts with gzip magic for a file whose type is not gzip, and whose length is not the file's, was not decoded. It is reported (`DownloadNotDecodedException`), never saved as the file.

## Testing

To check a deployment end to end, deploy a small site to a public drive with the switch on and read the data items: each text file's item carries `Content-Encoding: gzip`, the original `Content-Type` and a gzip that decodes to the file; the png carries neither. No e2e helper is added to `docs/WEB_E2E_TESTING.md`.
