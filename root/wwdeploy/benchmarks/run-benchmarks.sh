#!/usr/bin/env bash
# run-benchmarks.sh — HPC benchmark launcher
# Supports: HPL, HPCG, STREAM, NCCL, GEMM, SHARP, all-cpu, all-gpu
# Runtimes: Singularity/Apptainer
# Launch modes: Slurm (auto-detected) or standalone via mpirun + SSH

set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIF_CPU="${SCRIPT_DIR}/hpc-bench-cpu.sif"
SIF_GPU="${SCRIPT_DIR}/hpc-bench-gpu.sif"
TEST=""
HOSTFILE=""
NODES=""
PPN=2                       # MPI ranks per node (CPU tests)
NGPU=0                      # GPUs per node (GPU tests; 0 = auto-detect)
OUTPUT_DIR="./bench-results/$(date +%Y%m%d-%H%M%S)"
SINGULARITY_BIN=""          # Auto-detected if empty
IB_BIND=""                  # Set to "--bind /dev/infiniband" if IB present
SHARP=false
MPI_EXTRA_ARGS=""           # Pass-through to mpirun

# HPL tuning
HPL_MEM_FRACTION=0.80       # Fraction of RAM to use for N
HPL_NB=192                  # Block size (tune per architecture)

# HPCG local problem size per rank
HPCG_NX=104
HPCG_NY=104
HPCG_NZ=104
HPCG_RUNTIME=60             # Seconds (minimum 60 for official results)

# NCCL test settings
NCCL_MIN_BYTES="1M"
NCCL_MAX_BYTES="8G"
NCCL_STEP_FACTOR=2

# GEMM settings
GEMM_MATRIX_SIZE=16384
GEMM_ITERS=20

# ─── Colors ──────────────────────────────────────────────────────────────────
BLUE='\033[36m'
YELLOW='\033[33m'
GREEN='\033[32m'
RED='\033[31m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${BLUE}→ $*${RESET}"; }
success() { echo -e "${GREEN}✔ $*${RESET}"; }
warn()    { echo -e "${YELLOW}⚠ $*${RESET}"; }
error()   { echo -e "${RED}✖ $*${RESET}" >&2; }
header()  { echo -e "\n${BOLD}${BLUE}=== $* ===${RESET}"; }

# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Tests:
  --test <name>         Benchmark to run (required)
                        cpu:  hpl | hpcg | stream | all-cpu
                        gpu:  nccl | gemm | all-gpu
                        net:  sharp
                        all:  all

Node selection (pick one):
  --hostfile <file>     File with one hostname per line
  --nodes <list>        Comma-separated node list (e.g. node01,node02)
  --local               Single-node run on localhost only

MPI / resource options:
  --ppn <n>             MPI ranks per node for CPU tests (default: $PPN)
  --ngpu <n>            GPUs per node for GPU tests (default: auto-detect)
  --mpi-args <str>      Extra arguments passed to mpirun

Container options:
  --sif-cpu <path>      Path to CPU SIF image (default: $SIF_CPU)
  --sif-gpu <path>      Path to GPU SIF image (default: $SIF_GPU)
  --singularity <path>  Path to singularity/apptainer binary

Benchmark tuning:
  --hpl-mem <frac>      Fraction of RAM for HPL N (default: $HPL_MEM_FRACTION)
  --hpl-nb <n>          HPL block size NB (default: $HPL_NB)
  --hpcg-nx/ny/nz <n>  HPCG local problem size (default: ${HPCG_NX})
  --hpcg-time <s>       HPCG runtime seconds (default: $HPCG_RUNTIME)
  --nccl-min <bytes>    NCCL min message size (default: $NCCL_MIN_BYTES)
  --nccl-max <bytes>    NCCL max message size (default: $NCCL_MAX_BYTES)
  --gemm-size <n>       GEMM matrix dimension (default: $GEMM_MATRIX_SIZE)
  --sharp               Enable SHARP for NCCL/collective tests

Output:
  --output <dir>        Results directory (default: bench-results/<timestamp>)

Examples:
  # Single-node STREAM
  $(basename "$0") --test stream --local

  # Multi-node HPL, 32 ranks per node
  $(basename "$0") --test hpl --hostfile nodes.txt --ppn 32

  # Multi-node NCCL, 8 GPUs per node
  $(basename "$0") --test nccl --hostfile nodes.txt --ngpu 8

  # All CPU benchmarks on 4 nodes
  $(basename "$0") --test all-cpu --nodes node01,node02,node03,node04 --ppn 64

EOF
    exit 0
}

# ─── Argument Parsing ────────────────────────────────────────────────────────
[[ $# -eq 0 ]] && usage

LOCAL_ONLY=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --test)         TEST="$2";               shift 2 ;;
        --hostfile)     HOSTFILE="$2";           shift 2 ;;
        --nodes)        NODES="$2";              shift 2 ;;
        --local)        LOCAL_ONLY=true;         shift   ;;
        --ppn)          PPN="$2";                shift 2 ;;
        --ngpu)         NGPU="$2";               shift 2 ;;
        --mpi-args)     MPI_EXTRA_ARGS="$2";     shift 2 ;;
        --sif-cpu)      SIF_CPU="$2";            shift 2 ;;
        --sif-gpu)      SIF_GPU="$2";            shift 2 ;;
        --singularity)  SINGULARITY_BIN="$2";    shift 2 ;;
        --hpl-mem)      HPL_MEM_FRACTION="$2";   shift 2 ;;
        --hpl-nb)       HPL_NB="$2";             shift 2 ;;
        --hpcg-nx)      HPCG_NX="$2";            shift 2 ;;
        --hpcg-ny)      HPCG_NY="$2";            shift 2 ;;
        --hpcg-nz)      HPCG_NZ="$2";            shift 2 ;;
        --hpcg-time)    HPCG_RUNTIME="$2";       shift 2 ;;
        --nccl-min)     NCCL_MIN_BYTES="$2";     shift 2 ;;
        --nccl-max)     NCCL_MAX_BYTES="$2";     shift 2 ;;
        --gemm-size)    GEMM_MATRIX_SIZE="$2";   shift 2 ;;
        --sharp)        SHARP=true;              shift   ;;
        --output)       OUTPUT_DIR="$2";         shift 2 ;;
        -h|--help)      usage ;;
        *) error "Unknown option: $1"; usage ;;
    esac
done

[[ -z "$TEST" ]] && { error "--test is required"; usage; }

# ─── Environment Detection ───────────────────────────────────────────────────
detect_singularity() {
    if [[ -n "$SINGULARITY_BIN" ]]; then
        return
    fi
    for bin in apptainer singularity; do
        if command -v "$bin" &>/dev/null; then
            SINGULARITY_BIN="$bin"
            return
        fi
    done
    error "Neither 'apptainer' nor 'singularity' found in PATH."
    error "Install one or specify with --singularity <path>"
    exit 1
}

detect_mpi() {
    for mpi in mpirun mpiexec; do
        if command -v "$mpi" &>/dev/null; then
            MPIRUN="$mpi"
            return
        fi
    done
    error "No MPI launcher (mpirun/mpiexec) found in PATH."
    exit 1
}

detect_slurm() {
    if command -v srun &>/dev/null && [[ -n "${SLURM_JOB_ID:-}" ]]; then
        USE_SLURM=true
    else
        USE_SLURM=false
    fi
}

detect_ib() {
    if [[ -d /dev/infiniband ]] && ls /dev/infiniband/uverbs* &>/dev/null 2>&1; then
        IB_BIND="--bind /dev/infiniband"
        info "InfiniBand devices detected — binding /dev/infiniband"
    else
        warn "No /dev/infiniband found — using TCP transport"
        export UCX_TLS=tcp,sm,self
    fi
}

detect_gpus() {
    if [[ "$NGPU" -gt 0 ]]; then
        return
    fi
    if command -v nvidia-smi &>/dev/null; then
        NGPU=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l)
        info "Detected $NGPU GPUs on local node"
    else
        NGPU=0
        warn "nvidia-smi not found — GPU count set to 0"
    fi
}

# ─── Node List Management ────────────────────────────────────────────────────
build_hostfile() {
    EFFECTIVE_HOSTFILE=$(mktemp /tmp/bench-hostfile.XXXXXX)

    if $LOCAL_ONLY; then
        hostname >> "$EFFECTIVE_HOSTFILE"
        NNODES=1
    elif [[ -n "$HOSTFILE" ]]; then
        [[ -f "$HOSTFILE" ]] || { error "Hostfile not found: $HOSTFILE"; exit 1; }
        grep -v '^\s*#' "$HOSTFILE" | grep -v '^\s*$' > "$EFFECTIVE_HOSTFILE"
        NNODES=$(wc -l < "$EFFECTIVE_HOSTFILE")
    elif [[ -n "$NODES" ]]; then
        tr ',' '\n' <<< "$NODES" > "$EFFECTIVE_HOSTFILE"
        NNODES=$(wc -l < "$EFFECTIVE_HOSTFILE")
    elif [[ -n "${SLURM_NODELIST:-}" ]]; then
        scontrol show hostnames "$SLURM_NODELIST" > "$EFFECTIVE_HOSTFILE"
        NNODES=$(wc -l < "$EFFECTIVE_HOSTFILE")
    else
        warn "No node list provided — running locally"
        hostname >> "$EFFECTIVE_HOSTFILE"
        NNODES=1
    fi

    info "Nodes ($NNODES): $(paste -sd, "$EFFECTIVE_HOSTFILE")"
}

# ─── MPI Launch Wrapper ──────────────────────────────────────────────────────
# Handles Slurm vs standalone transparently
launch_mpi() {
    local np="$1"; shift
    local sif="$1"; shift
    local nv_flag="$1"; shift   # "--nv" for GPU, "" for CPU
    local cmd=("$@")

    local sing_exec=(
        "$SINGULARITY_BIN" exec
        $IB_BIND
        $nv_flag
        "$sif"
        "${cmd[@]}"
    )

    if $USE_SLURM; then
        srun --ntasks="$np" \
             --ntasks-per-node="$PPN" \
             "${sing_exec[@]}"
    else
        $MPIRUN \
            -np "$np" \
            --hostfile "$EFFECTIVE_HOSTFILE" \
            --map-by "ppr:${PPN}:node" \
            --bind-to core \
            --mca pml ucx \
            --mca btl ^openib \
            $MPI_EXTRA_ARGS \
            "${sing_exec[@]}"
    fi
}

# ─── HPL ─────────────────────────────────────────────────────────────────────
run_hpl() {
    header "HPL (High Performance LINPACK)"
    local rundir="${OUTPUT_DIR}/hpl"
    mkdir -p "$rundir"

    local total_procs=$(( NNODES * PPN ))

    # Auto-calculate N from available RAM on first node
    local first_node
    first_node=$(head -1 "$EFFECTIVE_HOSTFILE")
    local ram_kb
    ram_kb=$(ssh -o BatchMode=yes "$first_node" "grep MemTotal /proc/meminfo | awk '{print \$2}'" 2>/dev/null \
             || grep MemTotal /proc/meminfo | awk '{print $2}')
    local ram_bytes=$(( ram_kb * 1024 * NNODES ))

    # N = sqrt(fraction * total_RAM / 8 bytes per double)
    local N
    N=$(python3 -c "import math; print(int(math.sqrt(${HPL_MEM_FRACTION} * ${ram_bytes} / 8) // ${HPL_NB} * ${HPL_NB}))")
    info "Total RAM across nodes: $(( ram_bytes / 1024 / 1024 / 1024 )) GB — using N=${N}"

    # Calculate P x Q process grid (prefer P <= Q, both close to sqrt)
    local P Q
    P=$(python3 -c "
import math
p = int(math.sqrt(${total_procs}))
while ${total_procs} % p != 0:
    p -= 1
print(p)
")
    Q=$(( total_procs / P ))
    info "Process grid: P=${P} x Q=${Q} = ${total_procs} total"

    # Generate HPL.dat
    sed \
        -e "s/__N__/${N}/g" \
        -e "s/__P__/${P}/g" \
        -e "s/__Q__/${Q}/g" \
        "${SCRIPT_DIR}/hpl.dat.template" 2>/dev/null \
        || sed \
            -e "s/__N__/${N}/g" \
            -e "s/__P__/${P}/g" \
            -e "s/__Q__/${Q}/g" \
            <(cat << 'HPLDAT'
HPLinpack benchmark input file
Innovative Computing Laboratory, University of Tennessee
HPL.out      output file name (if any)
6            device out (6=stdout,7=stderr,file)
1            # of problems sizes (N)
__N__        Ns
1            # of NBs
192          NBs
0            PMAP process mapping (0=Row-,1=Column-major)
1            # of process grids (P x Q)
__P__        Ps
__Q__        Qs
16.0         threshold
1            # of panel fact
2            PFACTs (0=left, 1=Crout, 2=Right)
1            # of recursive stopping criterium
4            NBMINs (>= 1)
1            # of panels in recursion
2            NDIVs
1            # of recursive panel fact.
1            RFACTs (0=left, 1=Crout, 2=Right)
1            # of broadcast
1            BCASTs (0=1rg,1=1rM,2=2rg,3=2rM,4=Lng,5=LnM)
1            # of lookahead depth
1            DEPTHs (>=0)
2            SWAP (0=bin-exch,1=long,2=mix)
64           swapping threshold
0            L1 in (0=transposed,1=no-transposed) form
0            U  in (0=transposed,1=no-transposed) form
1            Equilibration (0=no,1=yes)
8            memory alignment in double (> 0)
HPLDAT
) > "$rundir/HPL.dat"

    info "Running HPL (${NNODES} nodes x ${PPN} ranks = ${total_procs} total)..."
    local log="${rundir}/hpl_$(date +%H%M%S).log"

    (
        cd "$rundir"
        launch_mpi "$total_procs" "$SIF_CPU" "" xhpl
    ) 2>&1 | tee "$log"

    # Extract result
    if grep -q "WR" "$log"; then
        local result
        result=$(grep "WR" "$log" | awk '{print $7}' | sort -n | tail -1)
        success "HPL Result: ${result} Gflops"
        echo "HPL_GFLOPS=${result}" >> "${OUTPUT_DIR}/summary.txt"
    else
        warn "HPL did not produce a result — check ${log}"
    fi
}

# ─── HPCG ────────────────────────────────────────────────────────────────────
run_hpcg() {
    header "HPCG (High Performance Conjugate Gradient)"
    local rundir="${OUTPUT_DIR}/hpcg"
    mkdir -p "$rundir"

    local total_procs=$(( NNODES * PPN ))

    cat > "$rundir/hpcg.dat" << EOF
HPCG benchmark input file
Sandia National Laboratories; University of Tennessee, Knoxville
${HPCG_NX} ${HPCG_NY} ${HPCG_NZ}
${HPCG_RUNTIME}
EOF

    info "Local problem size per rank: ${HPCG_NX}x${HPCG_NY}x${HPCG_NZ}"
    info "Runtime: ${HPCG_RUNTIME}s per rank"

    local log="${rundir}/hpcg_$(date +%H%M%S).log"

    (
        cd "$rundir"
        launch_mpi "$total_procs" "$SIF_CPU" "" xhpcg
    ) 2>&1 | tee "$log"

    # HPCG writes results to HPCG-Benchmark*.yaml or hpcg_log*.txt
    local result_file
    result_file=$(find "$rundir" -name "HPCG-Benchmark*.yaml" 2>/dev/null | head -1)
    if [[ -n "$result_file" ]]; then
        local gflops
        gflops=$(grep "GFLOP/s Summary::Total" "$result_file" | awk -F= '{print $2}' | tr -d ' ')
        success "HPCG Result: ${gflops} GF/s"
        echo "HPCG_GFLOPS=${gflops}" >> "${OUTPUT_DIR}/summary.txt"
    else
        warn "HPCG result file not found — check ${rundir}"
    fi
}

# ─── STREAM ──────────────────────────────────────────────────────────────────
run_stream() {
    header "STREAM Memory Bandwidth"
    local rundir="${OUTPUT_DIR}/stream"
    mkdir -p "$rundir"

    local log="${rundir}/stream_$(date +%H%M%S).log"
    local cores_per_node
    cores_per_node=$(nproc 2>/dev/null || echo "$PPN")

    info "Running STREAM (OMP_NUM_THREADS=${cores_per_node}) on ${NNODES} node(s)..."

    if $LOCAL_ONLY || [[ "$NNODES" -eq 1 ]]; then
        OMP_NUM_THREADS="$cores_per_node" \
        "$SINGULARITY_BIN" exec $IB_BIND "$SIF_CPU" stream 2>&1 | tee "$log"
    else
        # Run on all nodes in parallel via SSH, collect results
        while IFS= read -r node; do
            info "  Node: ${node}"
            ssh -o BatchMode=yes "$node" \
                "OMP_NUM_THREADS=${cores_per_node} \
                 $SINGULARITY_BIN exec $IB_BIND $SIF_CPU stream" \
                2>&1 | sed "s/^/[${node}] /" | tee -a "$log" &
        done < "$EFFECTIVE_HOSTFILE"
        wait
    fi

    # Extract Triad from local/last run
    if grep -q "Triad" "$log"; then
        local triad
        triad=$(grep "Triad" "$log" | awk '{print $2}' | sort -n | tail -1)
        success "STREAM Triad (best): ${triad} MB/s"
        echo "STREAM_TRIAD_MB_S=${triad}" >> "${OUTPUT_DIR}/summary.txt"
    fi
}

# ─── NCCL ────────────────────────────────────────────────────────────────────
run_nccl() {
    header "NCCL AllReduce Benchmark"
    check_gpu_sif

    local rundir="${OUTPUT_DIR}/nccl"
    mkdir -p "$rundir"

    local total_gpus=$(( NNODES * NGPU ))
    local log="${rundir}/nccl_allreduce_$(date +%H%M%S).log"

    local sharp_env=""
    if $SHARP; then
        info "SHARP enabled"
        sharp_env="-x NCCL_ALGO=SHARP -x SHARP_COLL_ENABLE_SAT=1"
    fi

    info "Running NCCL allreduce: ${NNODES} node(s) x ${NGPU} GPU(s) = ${total_gpus} total"
    info "Message range: ${NCCL_MIN_BYTES} → ${NCCL_MAX_BYTES}"

    local nv_ppn="$NGPU"
    local orig_ppn="$PPN"
    PPN="$NGPU"

    (
        cd "$rundir"
        NCCL_IB_DISABLE=0 \
        NCCL_DEBUG=WARN \
        $sharp_env \
        launch_mpi "$total_gpus" "$SIF_GPU" "--nv" \
            all_reduce_perf \
            -b "$NCCL_MIN_BYTES" \
            -e "$NCCL_MAX_BYTES" \
            -f "$NCCL_STEP_FACTOR" \
            -g 1
    ) 2>&1 | tee "$log"

    PPN="$orig_ppn"

    # Extract peak busbw
    if grep -q "busbw" "$log"; then
        local peak_busbw
        peak_busbw=$(grep -v "#" "$log" | grep -v "^$" | awk '{print $11}' | sort -n | tail -1)
        success "NCCL AllReduce peak busbw: ${peak_busbw} GB/s"
        echo "NCCL_ALLREDUCE_BUSBW_GB_S=${peak_busbw}" >> "${OUTPUT_DIR}/summary.txt"
    fi

    # Also run allgather and reduce_scatter if doing full GPU suite
    if [[ "${RUN_ALL_NCCL:-false}" == "true" ]]; then
        for test in all_gather_perf reduce_scatter_perf broadcast_perf; do
            info "Running ${test}..."
            local tlog="${rundir}/${test}_$(date +%H%M%S).log"
            PPN="$nv_ppn"
            (
                cd "$rundir"
                launch_mpi "$total_gpus" "$SIF_GPU" "--nv" \
                    "$test" \
                    -b "$NCCL_MIN_BYTES" \
                    -e "$NCCL_MAX_BYTES" \
                    -f "$NCCL_STEP_FACTOR" \
                    -g 1
            ) 2>&1 | tee "$tlog"
            PPN="$orig_ppn"
        done
    fi
}

# ─── GEMM ────────────────────────────────────────────────────────────────────
run_gemm() {
    header "GEMM (cuBLAS FP16 Tensor)"
    check_gpu_sif

    local rundir="${OUTPUT_DIR}/gemm"
    mkdir -p "$rundir"

    info "Matrix size: ${GEMM_MATRIX_SIZE}x${GEMM_MATRIX_SIZE}x${GEMM_MATRIX_SIZE}, iterations: ${GEMM_ITERS}"

    if $LOCAL_ONLY || [[ "$NNODES" -eq 1 ]]; then
        # Run per-GPU on local node
        for (( g=0; g<NGPU; g++ )); do
            local log="${rundir}/gemm_gpu${g}_$(date +%H%M%S).log"
            CUDA_VISIBLE_DEVICES="$g" \
            "$SINGULARITY_BIN" exec --nv $IB_BIND "$SIF_GPU" \
                gemm_bench "$GEMM_MATRIX_SIZE" "$GEMM_ITERS" \
                2>&1 | tee "$log"
            if grep -q "TFLOPS" "$log"; then
                local tflops
                tflops=$(grep "TFLOPS" "$log" | awk '{print $2}')
                success "GPU ${g}: ${tflops} TFLOPS (FP16)"
                echo "GEMM_GPU${g}_TFLOPS=${tflops}" >> "${OUTPUT_DIR}/summary.txt"
            fi
        done
    else
        # Multi-node: run on each node in parallel
        while IFS= read -r node; do
            info "Running GEMM on ${node}..."
            local log="${rundir}/gemm_${node}_$(date +%H%M%S).log"
            ssh -o BatchMode=yes "$node" \
                "for g in \$(seq 0 $((NGPU-1))); do
                    CUDA_VISIBLE_DEVICES=\$g \
                    $SINGULARITY_BIN exec --nv $IB_BIND $SIF_GPU \
                        gemm_bench $GEMM_MATRIX_SIZE $GEMM_ITERS
                done" 2>&1 | sed "s/^/[${node}] /" | tee -a "$log" &
        done < "$EFFECTIVE_HOSTFILE"
        wait
    fi
}

# ─── SHARP ───────────────────────────────────────────────────────────────────
run_sharp() {
    header "SHARP In-Network Computing Test"
    local rundir="${OUTPUT_DIR}/sharp"
    mkdir -p "$rundir"

    # Verify SHARP is available
    if ! command -v sharp_hello &>/dev/null; then
        warn "sharp_hello not found on host — SHARP stack may not be installed"
        warn "Ensure sharpd is running and sharp_am is configured"
        warn "Falling back to NCCL allreduce with SHARP_COLL env vars"
    else
        info "Testing SHARP connectivity..."
        local hello_log="${rundir}/sharp_hello_$(date +%H%M%S).log"
        SHARP_COLL_ENABLE_SAT=1 sharp_hello 2>&1 | tee "$hello_log"
        if grep -q "sharp_hello Passed" "$hello_log"; then
            success "SHARP hello test passed"
        else
            warn "SHARP hello test failed — check sharp_am and sharpd"
        fi
    fi

    # Run OSU allreduce with and without SHARP for comparison
    local total_procs=$(( NNODES * PPN ))
    local log_base="${rundir}/osu_allreduce"

    info "Running OSU allreduce WITHOUT SHARP (baseline)..."
    local log_no_sharp="${log_base}_no_sharp_$(date +%H%M%S).log"
    (
        cd "$rundir"
        launch_mpi "$total_procs" "$SIF_CPU" "" osu_allreduce
    ) 2>&1 | tee "$log_no_sharp"

    info "Running OSU allreduce WITH SHARP..."
    local log_sharp="${log_base}_sharp_$(date +%H%M%S).log"
    (
        export HCOLL_ENABLE_SHARP=1
        export SHARP_COLL_ENABLE_SAT=1
        export HCOLL_BCOL=sharp
        cd "$rundir"
        launch_mpi "$total_procs" "$SIF_CPU" "" osu_allreduce
    ) 2>&1 | tee "$log_sharp"

    # Compare latencies
    if grep -qE "^[0-9]" "$log_no_sharp" && grep -qE "^[0-9]" "$log_sharp"; then
        echo ""
        echo "Size(bytes)   No-SHARP(us)   SHARP(us)   Improvement"
        echo "──────────────────────────────────────────────────────"
        paste \
            <(grep -E "^[0-9]" "$log_no_sharp" | awk '{print $1, $2}') \
            <(grep -E "^[0-9]" "$log_sharp"    | awk '{print $2}') \
        | awk '{
            imp = ($2 - $3) / $2 * 100;
            printf "%-14s %-15s %-12s %.1f%%\n", $1, $2, $3, imp
          }'
    fi
}

# ─── Compound Test Groups ─────────────────────────────────────────────────────
run_all_cpu() {
    run_stream
    run_hpcg
    run_hpl
}

run_all_gpu() {
    RUN_ALL_NCCL=true run_nccl
    run_gemm
}

# ─── Guards ──────────────────────────────────────────────────────────────────
check_gpu_sif() {
    [[ -f "$SIF_GPU" ]] || {
        error "GPU SIF not found: $SIF_GPU"
        error "Build it with: $SINGULARITY_BIN build hpc-bench-gpu.sif hpc-bench-gpu.def"
        exit 1
    }
}

check_cpu_sif() {
    [[ -f "$SIF_CPU" ]] || {
        error "CPU SIF not found: $SIF_CPU"
        error "Build it with: $SINGULARITY_BIN build hpc-bench-cpu.sif hpc-bench-cpu.def"
        exit 1
    }
}

# ─── Summary ─────────────────────────────────────────────────────────────────
print_summary() {
    if [[ -f "${OUTPUT_DIR}/summary.txt" ]]; then
        header "Results Summary"
        cat "${OUTPUT_DIR}/summary.txt"
    fi
    success "All output saved to: ${OUTPUT_DIR}"
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
    header "HPC Benchmark Suite"

    detect_singularity
    detect_mpi
    detect_slurm
    detect_ib
    build_hostfile
    mkdir -p "$OUTPUT_DIR"

    info "Test:      ${TEST}"
    info "Nodes:     ${NNODES}"
    info "Launcher:  ${USE_SLURM:+Slurm}${USE_SLURM:-standalone mpirun}"
    info "Runtime:   ${SINGULARITY_BIN}"
    info "Output:    ${OUTPUT_DIR}"
    echo ""

    case "$TEST" in
        hpl)      check_cpu_sif; run_hpl   ;;
        hpcg)     check_cpu_sif; run_hpcg  ;;
        stream)   check_cpu_sif; run_stream ;;
        nccl)     detect_gpus;   run_nccl  ;;
        gemm)     detect_gpus;   run_gemm  ;;
        sharp)    check_cpu_sif; run_sharp  ;;
        all-cpu)  check_cpu_sif; run_all_cpu ;;
        all-gpu)  detect_gpus;   run_all_gpu ;;
        all)      check_cpu_sif; detect_gpus; run_all_cpu; run_all_gpu; run_sharp ;;
        *)
            error "Unknown test: ${TEST}"
            error "Valid: hpl hpcg stream nccl gemm sharp all-cpu all-gpu all"
            exit 1
            ;;
    esac

    print_summary
}

main "$@"
