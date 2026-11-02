# PR 6: Mac benchmark evidence

The candidate used lower process CPU in all four tested batches of 1,000 method calls. These measurements do not represent whole-app CPU. The disabled-gates candidate is near the timing floor.

| Scenario | Side | CPU ms, median [min, max] | Wall ms, median [min, max] |
|---|---|---:|---:|
| disabled-gates | baseline | 228.712 [224.654, 234.044] | 519.089 [508.341, 539.534] |
| disabled-gates | candidate | 0.010 [0.007, 0.010] | 0.007 [0.006, 0.008] |
| identical-profile-settings | baseline | 65.749 [63.482, 77.698] | 123.995 [118.225, 157.328] |
| identical-profile-settings | candidate | 1.079 [1.060, 1.117] | 1.079 [1.058, 1.146] |
| profile-switch | baseline | 74.461 [73.683, 76.218] | 195.050 [182.883, 262.596] |
| profile-switch | candidate | 16.669 [16.491, 16.920] | 73.295 [70.036, 76.510] |
| unchanged-profile-rename | baseline | 60.360 [60.180, 60.525] | 115.084 [114.527, 125.772] |
| unchanged-profile-rename | candidate | 0.810 [0.807, 0.815] | 0.810 [0.807, 0.814] |

Six measured samples per side alternate AB/BA after a warmup. Warmups and separate resource runs are excluded from medians. All 48 measured runs passed with checksum 1,000; all 64 runs passed. The harness uses five fake profiles and real system APIs for disabled gates. It checks settings data by reading it back. Expected provider queries in disabled gates are 1,000 each on baseline and zero on candidate.

The production sources were built in Swift 5 mode with `-O -wmo` (Release). `getrusage` measures the benchmark process itself and excludes downstream work such as cfprefsd. Background load was busy during the experiment.

**Battery: INCONCLUSIVE.** Battery readings were 100% before and after the approximately 37-second mixed experiment, with the same raw capacity counter. They do not measure a battery saving or distinguish the two sides.

[Raw structured results](mac-results.json) · [CPU comparison](cpu-comparison.png) · [Benchmark driver](../../../Scripts/benchmark-optimizations.py) · [Harness](../../../Scripts/OptimizationBenchmark.swift)

Reproduce on a Mac with Xcode and Swift installed:

```sh
python3 Scripts/benchmark-optimizations.py --baseline b53797a96f36f3ff22e960d6f3583b306f5b6a0c --candidate 609100bb56edda0f4c2a64814158f1b47931e088 --iterations 1000
```
