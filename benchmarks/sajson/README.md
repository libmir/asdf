## ASDF vs [sajson](https://github.com/chadaustin/sajson) Benchmark

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

| Test | Avg sajson t | Avg ASDF t | Speedup |
|---|---|---|---|
| apache_builds | 142 μs | 119 μs | 19 % |
| github_events | 78 μs | 64 μs | 22 % |
| instruments | 272 μs | 260 μs | 5 % |
| mesh | 1844 μs | 1099 μs | 68 % |
| mesh.pretty | 2728 μs | 1631 μs | 67 % |
| nested | 93 μs | 147 μs | -37 % |
| svg_menu | 2 μs | 1 μs | 100 % |
| truenull | 18 μs | 17 μs | 6 % |
| twitter | 919 μs | 626 μs | 47 % |
| update-center | 838 μs | 531 μs | 58 % |
| whitespace | 9 μs | 8 μs | 13 % |
