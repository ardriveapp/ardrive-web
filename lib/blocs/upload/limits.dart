import 'package:ardrive_utils/ardrive_utils.dart';

// Maximum file size supported by ArDrive (20 GiB)
// Files larger than this will be rejected with an error message
// This ensures reasonable upload times and guarantees atomicity via bundled uploads
final maxSingleFileSize = const GiB(20).size;

// Backward compatibility alias
final fileSizeLimit = maxSingleFileSize;

// Warning threshold for large files (5 GiB)
final fileSizeWarning = const GiB(5).size;

// Bundle limits for D2N uploads
// Tiered approach for optimal bundling:
// - Files < 500MB: Batch together (up to 500 files per bundle)
// - Files >= 500MB and <= 20GB: Individual atomic bundles
// - Files > 20GB: Rejected (not supported)
const maxBundleDataItemCount = 500;
const maxFilesPerBundle = 500;

// Turbo upload limits (unchanged - keep 1 file per upload)
const maxFilesSizePerBundleUsingTurbo = 1;

// Bundle size thresholds for D2N uploads
// BATCH_THRESHOLD: Files below this are batched together
// Files above this get individual bundles for atomicity
final batchBundleThreshold = const MiB(500).size;  // 500 MB

// Maximum bundle size limits
// D2N: 500MB for batch bundles
// Individual file bundles (>= 500MB) are capped by maxSingleFileSize (20GB)
final d2nBatchBundleSizeLimit = const MiB(500).size;
final turboBundleSizeLimit = const GiB(10).size;

int getBundleSizeLimit(bool isTurbo) =>
    isTurbo ? turboBundleSizeLimit : d2nBatchBundleSizeLimit;
