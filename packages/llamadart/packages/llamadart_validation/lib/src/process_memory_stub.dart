/// Names the footprint counter so a report states what produced its numbers.
const memoryFootprintSource = 'unavailable: dart:io is absent on this platform';

/// Always null: no footprint counter exists without `dart:io`.
int? memoryFootprintBytes() => null;
