[sajson](https://github.com/chadaustin/sajson) Benchmark
===================

## Benchmark results

### Platform
Intel Haswell (AVX2),


### sajson Results

```
clang++ -O2 -std=c++14 benchmark/benchmark.cpp -Iinclude
```

```
                       file -      avg -      min
                       ---- -      --- -      ---
testdata/apache_builds.json - 0.158 ms - 0.137 ms
testdata/github_events.json - 0.089 ms - 0.080 ms
  testdata/instruments.json - 0.308 ms - 0.289 ms
         testdata/mesh.json - 2.258 ms - 2.151 ms
  testdata/mesh.pretty.json - 3.150 ms - 2.906 ms
       testdata/nested.json - 0.163 ms - 0.140 ms
     testdata/svg_menu.json - 0.004 ms - 0.002 ms
     testdata/truenull.json - 0.021 ms - 0.017 ms
      testdata/twitter.json - 1.190 ms - 0.847 ms
testdata/update-center.json - 0.894 ms - 0.851 ms
   testdata/whitespace.json - 0.009 ms - 0.007 ms
```

### ASDF Results

```
dub --build=release-nobounds --compiler=ldmd2
```

```
                       file -      avg -      min
                       ---- -      --- -      ---
testdata/apache_builds.json - 0.196 ms - 0.170 ms
testdata/github_events.json - 0.088 ms - 0.079 ms
  testdata/instruments.json - 0.419 ms - 0.373 ms
         testdata/mesh.json - 2.277 ms - 1.976 ms
  testdata/mesh.pretty.json - 2.869 ms - 2.336 ms
       testdata/nested.json - 0.244 ms - 0.207 ms
     testdata/svg_menu.json - 0.002 ms - 0.002 ms
     testdata/truenull.json - 0.055 ms - 0.048 ms
      testdata/twitter.json - 1.082 ms - 0.898 ms
testdata/update-center.json - 1.214 ms - 0.968 ms
   testdata/whitespace.json - 0.006 ms - 0.005 ms
```
