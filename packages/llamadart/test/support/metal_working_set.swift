// Independent SDK read for the Dart Objective-C memory-budget contract.
import Metal

print(MTLCreateSystemDefaultDevice()?.recommendedMaxWorkingSetSize ?? 0)
