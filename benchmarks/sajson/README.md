[sajson](https://github.com/chadaustin/sajson) Benchmark
===================

## Benchmark: ASDF vs sajson

### Platform
Intel Haswell (AVX2),

### ASDF
```
dub build --build=release-nobounds --compiler=ldmd2
```

#### sajson
```
// sources are in sajson GitHub repository
clang++ -O3 -march=native -std=c++14 benchmark/benchmark.cpp -Iinclude
```

### Results

| Test | Avg ASDF | Avg sajson | Speedup |
|---|---|---|---|
| apache_builds | 142 | 119 | 19 % |
| github_events | 78 | 64 | 22 % |
| instruments | 272 | 260 | 5 % |
| mesh | 1844 | 1099 | 68 % |
| mesh.pretty | 2728 | 1631 | 67 % |
| nested | 93 | 147 | -37 % |
| svg_menu | 2 | 1 | 100 % |
| truenull | 18 | 17 | 6 % |
| twitter | 919 | 626 | 47 % |
| update-center | 838 | 531 | 58 % |
| whitespace | 9 | 8 | 13 % |
