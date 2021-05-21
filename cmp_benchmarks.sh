#!/usr/bin/env bash
set -Eeuo pipefail

# default values
jobct=1
def_rel_perf_path="test/performance"
threshold=0.05


usage="Usage: ./cmp_bnchm.sh -m mode -n name_tag -b baseline -c contender \
[-s source/code/path] [-r relative/benchm/suite/path] [-t threshold] [-o results/path] [-g compiler] \n\
    \n\
    -m : 'results', 'execs', 'build' \n\
    -n : identifyer string for comparison results, e.g. 3.0.0-3.0.1 \n\
    \n\
    -b -c:
    \[-m results\] -b and -c should be full paths to directories containing SOLELY benchmark results in SJON format.\n\
                     Directories do may contain subdirectories.\n\
    \[-m execs\]:  -b and -c should be full/path/to/built/benchmark/suites (containing the executables).\n\
    \[-m build\]:  -b and -c should be tags to checkout using git.\n\
    \n\
    For \[-m build\]: -s is required. Set to full/path/to/source/code (git repository).\n\
                      -g is optional. /path/to/executable/compiler (e.g. g++-7). Defaults to g++-7.\n\
                      -r is optional. relative/path/from/-s/to/benchmark/suite. Defaults to ${def_rel_perf_path}.\n\
    \n\
    Optional arguments:\n\
    -f : a threshold [0, 1] for filtering significant results, e.g. 0.2 . Defaults to ${threshold} (5% difference).\n\
    -o : full/path/to/save/results . Defaults to current directory.\n\
    -j : number of jobs. This number is passed to make. Defaults to ${jobct}.\n"

while getopts ":m:n:b:c:s:t:o:r:g:j:" option ; do
    case "${option}"
        in
            m) mode=${OPTARG};;
            n) name_tag=${OPTARG};;
            b) baseline=${OPTARG%/};; # trailing backslash is removed for all paths
            c) contender=${OPTARG%/};;
            s) source_code=${OPTARG%/};;
            t) threshold=${OPTARG};;
            o) outpathp=${OPTARG%/};;
            r) rel_perf_path=${OPTARG%/};;
            g) compiler=${OPTARG};;
            j) jobct=${OPTARG};;
    esac
done

if [[ -z ${mode+x} || -z ${name_tag+x} || -z ${baseline+x} || -z ${contender+x} ]]; then
    echo -e "ERROR! Missing required arguments.\n"
    echo -e "$usage"
    exit 1
fi

shift $((OPTIND -1))
if [[ $# -ge 1 ]] ; then
    echo -e "ERROR! Unused arguments: $@\n"
    echo -e "$usage"
    exit 1
fi

if ! [[ "$mode" =~ ^(results|execs|build)$ ]]; then
    echo -e "ERROR! Invalid mode.\n"
    echo -e "$usage"
    exit 1
fi

if [[ "$jobct" -lt 1 ]]; then
    echo -e "ERROR! number of jobs must be at least 1.\n"
    echo -e "$usage"
    exit 1
fi


if [ $mode = "build" ]; then
    if [[ -z ${source_code+x} ]]; then
        echo -e "ERROR! Path to source code is required in 'build' mode.\n"
        echo -e "$usage"
        exit 1
    fi
    if [[ -z ${rel_perf_path+x} ]]; then
        echo "Relative path from source code to benchmark suite was not given (option -r )."
        echo "Relative path is set to: ${def_rel_perf_path}"
        if ! [[ -d $source_code/$def_rel_perf_path ]]; then
            echo "ERROR! $source_code/$def_rel_perf_path does not exist."
            exit 1
        else
            rel_perf_path=$def_rel_perf_path
        fi
    fi
    if [[ -z ${compiler+x} ]]; then
        echo "Compiler was not given (option -g ). Compiler is set to g++-7 by default."
        compiler="g++-7"
    fi
    command -v $compiler >/dev/null || { echo "ERROR! $compiler was not found in PATH."; exit 1; }

fi
#---------------------------------------------------------------------------------------------#
# save directory of cmp_benchmarks.sh
wrkdir=${PWD%/}
# In 'build' mode, checkout the respective tags, and build the benchmark executables
if [ $mode  = "build" ]; then
    mkdir -p {build/$baseline,build/$contender}

    cd $source_code
    git checkout $baseline
    git submodule update
    cd $wrkdir/build/$baseline
    cmake $source_code/$rel_perf_path -DCMAKE_CXX_COMPILER=$compiler -DCMAKE_BUILD_TYPE=Release
    make -j ${jobct}

    cd $source_code
    git checkout $contender
    git submodule update
    cd $wrkdir/build/$contender
    cmake $source_code/$rel_perf_path -DCMAKE_CXX_COMPILER=$compiler -DCMAKE_BUILD_TYPE=Release
    make -j ${jobct}

    baseline=$wrkdir/build/$baseline
    contender=$wrkdir/build/$contender
    cd $wrkdir
fi

# create output folder for given name_tag
if [[ -z ${outpathp+x} ]]; then outpathp=$wrkdir ; fi
outpath=$outpathp/$name_tag
[[ -d $outpath ]] || mkdir -p $outpath

#----------------------------------Find common benchmarks-------------------------------------#
if ! [ $mode = "results" ]; then
    find $baseline -type f -not -name "*.*" -executable -print \
        | awk -F/ '{print $NF}' \
        | sort > $outpath/baseline

    find $contender -type f -not -name "*.*" -executable -print \
        | awk -F/ '{print $NF}' \
        | sort > $outpath/contender
else
    find $baseline -type f -print \
        | awk -F/ '{print $NF}' \
        | sort > $outpath/baseline

    find $contender -type f -print \
        | awk -F/ '{print $NF}' \
        | sort > $outpath/contender
fi

comm -12 --nocheck-order $outpath/baseline $outpath/contender > $outpath/common
rm $outpath/baseline $outpath/contender

## No common benchmarks!
[[ -s $outpath/common ]] || { echo "No common benchmarks between Baseline and Contender were found. "; exit 1; }

#-------------------------------Compare benchmarks--------------------------------------------#

#find all benchmark executables in baseline and contender suite
[[ -d $outpath/indiv_benchmrks ]] || mkdir $outpath/indiv_benchmrks
while read benchmark ; do

    bench_bl=$(find $baseline -type f -name "$benchmark")
    bench_cp=$(find $contender -type f -name "$benchmark")

    # sed expression removes colorcodes from compare.py output
    python ./gbench-compare/compare.py benchmarks $bench_bl $bench_cp \
        | sed 's/\x1b\[[0-9;]*m//g' > $outpath/indiv_benchmrks/$benchmark

done < $outpath/common
rm $outpath/common

#-------------------------------------Summarize results---------------------------------------#

results=$outpath/all_diffs
signif=$outpath/significant_diffs
signif_decr=$outpath/significant_decr
signif_incr=$outpath/significant_incr

# write headers
echo "Benchmarkfile;Benchmark;Time;CPU" \
    |  tee ${results}.csv ${signif}.csv ${signif_incr}.csv ${signif_decr}.csv > /dev/null

# filter out the actual performance stats from compare.py output
for file in $outpath/indiv_benchmrks/* ; do
    fin=$( echo "$file" | awk -F/ '{print $NF}' ) #save name of benchmark file

    # diffs between benchmarks are summarized after fifth line of "-----" comp.py output
    # use multiple whitespaces as seperator in case benchmark names includes whitespaces
    cat $file \
        | awk 'x==5 {print ;next} /---/ {x++}' \
        | awk -v fin="$fin" 'BEGIN {FS ="  +"} {print fin";"$1";"$2";"$3 }' >> ${results}.csv
done

# split stats in signif/signif_incr/signif_decr based on threshold
# sed statement skips first header line of results file
cat "${results}.csv" | sed 1d | \
    awk -v thr=$threshold -v s="${signif}.csv" -v si="${signif_incr}.csv" -v sd="${signif_decr}.csv" \
    'BEGIN {FS =";"} $3 <= - thr { print >> s ; print >> sd } $3 >= thr { print >> s ; print >> si }'

for file in $results $signif $signif_incr $signif_decr; do
    column -t -s $';' "${file}.csv" > "${file}.txt"
done
