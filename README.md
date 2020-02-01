# cmp_benchmarks

The `cmp_benchmarks.sh` provides a wrapper around google/benchmark/tools/compare.py. It can be used to compare benchmarks between versions and to filter out significant differences in runtime. 

**NOTE**: the compare.py utility relies on the scipy package which can be installed using [these instructions](https://www.scipy.org/install.html).

The program is invoked like:
``` bash
$ ./cmp_benchmarks.sh -m <mode> -n <name_tag> -b <baseline> -c <contender> \
[-s </source/code/path> [-r relative/benchm/suite/path] [-t threshold] [-o /results/path] [-g compiler] 
```

The arguments `<baseline>` and `<contender>` are `<mode>` dependend.
    `<name_tag>` should be set to an identifier for the comparison, e.g. `3.0.0-vs-3.0.1`.

## Modes of operation

There are three modes of operation:

1. Compare benchmarks for two versions given their git tags: mode `build`.
2. Compare benchmarks given benchmark executables: mode `execs`.
3. Compare benchmarks based on stored benchmark results: mode `results`.

### 1. Mode `build`

In build mode, `<baseline>` and `<contender>` should be the tags to use in `git checkout <tag>`. 
    In this mode, setting the option `-s` is required and should be set to `/full/path/to/source/code` (git repository). 

Build mode uses two additional, optional arguments: `-g` and `-r`. 
`-g` can be used to set the `/path/to/executable/compiler`. Defaults to g++-7.
`-r` can be used to set the `relative/path/from/-s/to/benchmark/suite`. Defaults to `./test/performance`.

The respective tags are checked out (submodules are updated), build using `Cmake` and `make`, and run to obtain the results. 

### 2. Mode `execs`

In execs mode, `<baseline>` and `<contender>` should be `full/paths/to/built/benchmark/suites` (containing the executables).
    Hence, the directories where the respective `source_code/test/performance` were built.

The executables are run to obtain the results.

### 3. Mode `results`

In results mode, `<baseline>` and `<contender>` should be `full/paths/to/benchmark/results`. 
    These results should be JSON output files. The results will simply be loaded from the output file.

**NOTE**:  This mode was not yet tested.

## Optional Arguments

`-f` can be used to set a threshold `[0, 1]` for filtering significant results, e.g. 0.2 . Defaults to 0.05 (5% difference).
`-o` can be used to set the `/full/path/to/save/results`. Defaults to the current directory.


## Output

`compare.py` compares all identically named benchmarks in both runs. If the names differ between runs, the benchmark is omitted 
from the diff. The diff values in Time and CPU are calculated as `( contender - baseline) / |baseline|`.

`cmp_benchmark.sh` filters and stores all these diffs. Four types of files are created and all are
stored both as `;`-delimited `.csv` file, and formatted as a readable table `.txt` file:

* **all_diffs**, containing the diffs for all common benchmarks.
* **significant_diffs**, containing the benchmarks with a significant time diff.
    all_diffs is filtered based on `-t <threshold>` which defaults to 0.05 (5% difference), see section Optional Arguments.
* **significant_decr**, containing the benchmarks for which there was a significant decrease in time. 
* **significant_incr**, containing the benchmarks for which there was a significant increase in time. 

Example `all_diffs.txt` output:
```
Benchmarkfile                               Benchmark                                                              Time     CPU
bit_manipulation_benchmark                  is_power_of_two_popcount<unsigned>                                     -0.0658  -0.0657
bit_manipulation_benchmark                  is_power_of_two_popcount<unsigned long>                                +0.0554  +0.0543
bit_manipulation_benchmark                  is_power_of_two_popcount<unsigned long long>                           +0.0047  +0.0040
bit_manipulation_benchmark                  is_power_of_two_arithmetic                                             +0.0099  +0.0090
bit_manipulation_benchmark                  is_power_of_two_seqan3                                                 -0.0186  -0.0186
bit_manipulation_benchmark                  next_power_of_two_seqan3                                               +0.0514  +0.0520
charconv_from_chars_benchmark               from_char<int8_t>                                                      -0.0043  -0.0043
charconv_from_chars_benchmark               from_char<uint8_t>                                                     -0.0135  -0.0130
...
```
The results are stored in the folder `/result/path/<name_tag>`.
Additionally, for each benchmark file the full output of `compare.py` is stored in the folder `/result/path/<name_tag>/indiv_benchmrks`.

## Requirements

The `cmp_benchmarks.sh` requires that:
* benchmarks are uniquely defined by their name
* benchmark executables do not have an extension
* benchmark names do not contain the character `;`.

The `cmp_benchmarks.sh` was tested on Ubuntu 18.04.3 LTS.

