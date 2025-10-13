# Unix-Time Milliseconds Bug Fix

## Problem

There was a bug where some transactions had their `Unix-Time` tag written as milliseconds instead of seconds. The ArFS specification states that `Unix-Time` should be in seconds for most versions, with ArFS version 0.10 being an exception that uses milliseconds.

## Root Cause

The `Unix-Time` tag parsing logic in `lib/services/arweave/graphql/graphql.dart` had version-specific handling:
- ArFS 0.10: value is in milliseconds
- All other ArFS versions: value is in seconds (multiply by 1000)

However, due to a bug in some transaction creation code, some transactions were written with millisecond timestamps regardless of ArFS version, causing incorrect parsing.

## Solution

Replaced version-specific logic with generic automatic detection that identifies when a `Unix-Time` value is abnormally large (indicating it's already in milliseconds). This handles all cases uniformly, regardless of ArFS version.

### Detection Threshold

The fix uses a threshold of `10000000000` (10 billion):
- Values **below** this threshold are treated as seconds (normal case)
- Values **above** this threshold are treated as milliseconds (buggy case)

This threshold represents approximately November 2286 when interpreted as seconds. Since:
- Current timestamps in seconds are around 1.7 billion (year 2024)
- Year 2100 in seconds is ~4.1 billion
- Any value > 10 billion is clearly in milliseconds, not seconds

### Code Changes

**File:** `lib/services/arweave/graphql/graphql.dart`

```dart
DateTime getCommitTime() {
  final unixTimeValue = int.parse(getTag(EntityTag.unixTime)!);
  
  // Check if the value is abnormally large (likely already in milliseconds)
  // Unix timestamp in seconds for year 2100 is ~4102444800
  // If value > 10000000000 (Nov 2286 in seconds), it's likely milliseconds
  final isAlreadyMilliseconds = unixTimeValue > 10000000000;
  
  final milliseconds = isAlreadyMilliseconds ? unixTimeValue : unixTimeValue * 1000;

  return DateTime.fromMillisecondsSinceEpoch(milliseconds);
}
```

**Key improvement:** The logic no longer checks the ArFS version. Instead, it uses a simple threshold-based detection that works for all versions, making it more robust and future-proof.

## Testing

Comprehensive tests were added in `test/services/arweave/graphql/graphql_test.dart` covering:

1. **Normal seconds parsing** - ArFS != 0.10 with seconds timestamp
2. **Normal milliseconds parsing** - ArFS 0.10 with milliseconds timestamp
3. **Buggy milliseconds detection** - ArFS != 0.10 with milliseconds timestamp (the bug case)
4. **Threshold boundary testing** - Values just above/below the detection threshold
5. **Realistic timestamp handling** - Current date timestamps

All tests pass, confirming the fix handles both normal and buggy timestamps correctly.

## Impact

This fix ensures that:
- Normal transactions (with seconds) continue to work correctly
- Buggy transactions (with milliseconds) are now parsed correctly
- ArFS 0.10 transactions (with milliseconds) continue to work correctly
- No breaking changes to existing functionality
- Backward compatible with all ArFS versions
- More robust and future-proof by removing version-specific logic

## Files Modified

1. `lib/services/arweave/graphql/graphql.dart` - Added millisecond detection logic
2. `test/services/arweave/graphql/graphql_test.dart` - Added comprehensive tests (new file)

## Verification

Run tests:
```bash
flutter test test/services/arweave/graphql/graphql_test.dart
```

All existing tests continue to pass:
```bash
flutter test
```
