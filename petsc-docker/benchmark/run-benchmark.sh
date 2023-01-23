#!/bin/bash
#
# Script is expected to be in, and executed from, the root directory
# of the HPC_Benchmark directory
cd ${0%/*} || exit 1    # Run from this directory
CDIR=`pwd`
# enabling PETSC options
PETSC_OPTIONS='-use_gpu_aware_mpi 0'
# set the benchmark case
benchmark_case='ksp_performance (3D Poisson Solve)'
benchmark_src_dir=ksp/ksp/tutorials
benchmark_src_file=bench_kspsolve.c
benchmark_exec=bench_kspsolve

function setup()
{
    # setting the env
    case "${DEVICE_OFFLOADING}" in
        hip|HIP|Hip)
            platform=HIP
            aij_type=mpiaijhipsparse
            vec_type=mpihip
            ;;
        cuda|CUDA|Cuda)
            platform=CUDA
            aij_type=mpiaijcusparse
            vec_type=mpicuda
            ;;
        *|--*=|*) # unsupported offloading
            echo "
==============================================================
    Error: Unsupported offloading type - ${DEVICE_OFFLOADING}
           Available Options: HIP or CUDA
==============================================================" >&2
            exit 1
            ;;
    esac

    case "${NGPUS}" in
        0)
                echo "
==============================================================
    Error: #GPUs were set to 0. Update the variable ngpus to
            use between 1-10 GPUs. To use more than 10 GPUs
            modify the script accrodingly.
==============================================================" >&2
            exit 1
            ;;
        1)
        export ${platform}_VISIBLE_DEVICES=0
        ;;
        2)
        export ${platform}_VISIBLE_DEVICES=0,1
        ;;
        3)
        export ${platform}_VISIBLE_DEVICES=0,1,2
        ;;
        4)
        export ${platform}_VISIBLE_DEVICES=0,1,2,3
        ;;
        5)
        export ${platform}_VISIBLE_DEVICES=0,1,2,3,4
        ;;
        6)
        export ${platform}_VISIBLE_DEVICES=0,1,2,3,4,5
        ;;
        7)
        export ${platform}_VISIBLE_DEVICES=0,1,2,3,4,5,6
        ;;
        8)
        export ${platform}_VISIBLE_DEVICES=0,1,2,3,4,5,6,7
        ;;
        9)
        export ${platform}_VISIBLE_DEVICES=0,1,2,3,4,5,6,7,8
        ;;
        10)
        export ${platform}_VISIBLE_DEVICES=0,1,2,3,4,5,6,7,8,9
        ;;
        *) # This script assume only 10 GPUs are available
            echo "
==============================================================
    Error: This script assumes that only 10 GPUs are present.
            Please modify the script if needed.
==============================================================" >&2
            exit 1
            ;;
    esac

    # setting up options to run the benchmark
    echo " "
        echo "--------------------
    SETUP
--------------------"

    if [[ $FLAG_D -eq 0 ]]; then
        echo "Using default device offloading support: $DEVICE_OFFLOADING"
    else
        echo "Using device offloading support: $DEVICE_OFFLOADING"
    fi

    if [[ $FLAG_G -eq 0 ]]; then
        echo "Using default #GPU for this benchmark: $NGPUS"
    else
        echo "Using #GPU for this benchmark: $NGPUS"
    fi

    if [[ $FLAG_N -eq 0 ]]; then
        echo "Using default matrix size (n) for this benchmark: $MATSIZE"
    else
        echo "Using matrix size (n) for this benchmark: $MATSIZE"
    fi

    echo "Using -mat_type: ${aij_type}"
    echo "Using -vec_type: ${vec_type}"

    if [[ $CUSTOM_OPT -eq 0 ]]; then
        PC_OPTIONS="-pc_type bjacobi -sub_pc_type ilu"
        echo "Using default -pc options: ${PC_OPTIONS}"
    else
        echo "Using custom -pc options: ${PC_OPTIONS}"
        echo "using custom -ksp options: ${KSP_OPTIONS}"
    fi

    if [[ $LOG_VIEW -eq 0 ]]; then
        echo "Using PETSC_OPTIONS: ${PETSC_OPTIONS}"
        export PETSC_OPTIONS="${PETSC_OPTIONS}"
    else
        PETSC_OPTIONS="${PETSC_OPTIONS} -log_view"
        echo "Using PETSC_OPTIONS: ${PETSC_OPTIONS}"
        export PETSC_OPTIONS="${PETSC_OPTIONS}"
    fi
}

function build()
{
    echo " "
    echo "--------------------
    CHECK BUILD
--------------------"
    # Lets build the performance (3D Poisson Solve) benchmark (M) case using the folloring commands:
    cd ${CDIR}/src/${benchmark_src_dir}/
    echo "In dir src/${benchmark_src_dir}/..."
    if [[ $RUN_ONLY -eq 0 ]]; then
        make PETSC_DIR=${CDIR} ${benchmark_exec}
    else
        if [ -x ${benchmark_exec} ]
        then
            echo " Skipping build..."
        else
            echo "
==============================================================
    Error: no ./${benchmark_exec} exists in src/${benchmark_src_dir}/
           Remove -r flag and re-run this script to build
           the benchmark with make first!
=============================================================="
            exit 1
       fi
    fi

}

function run()
{
    echo " "
    echo "--------------------
    RUN PERFORMANCE BENCHMARK
--------------------"
    if [[ ${NGPUS} -eq 1 ]]
    then
    echo "Running the benchmark with single GPU"
    ./${benchmark_exec} -n ${MATSIZE} -mat_type ${aij_type} -vec_type ${vec_type} ${PC_OPTIONS} ${KSP_OPTIONS} 2>&1 | tee log.${benchmark_exec}-${NGPUS}gpu
    elif [[ ${NGPUS} -gt 1 ]]
    then
    echo "Running the benchmark with multiple (${NGPUS}) GPUs"
    mpirun -np ${NGPUS} ./${benchmark_exec} -n ${MATSIZE} -mat_type ${aij_type} -vec_type ${vec_type} ${PC_OPTIONS} ${KSP_OPTIONS} 2>&1 | tee log.${benchmark_exec}-${NGPUS}gpu
    else
    echo "Error : nGPUS is not >1"
    fi
}

function cleanCase()
{
    # Clean the benchmark case using the folloring commands:
    cd ${CDIR}/src/${benchmark_src_dir}/
    echo "Cleaning ${CDIR}/src/${benchmark_src_dir}/ ..."
    if [ -x ${benchmark_exec} ]
    then
        make clean
    fi
}

function usage()
{
    echo "

This script is designed to setup and run PETSc ${benchmark_case} benchmark on GPUs.
=================================
usage: $0

       -h | --help      Prints the usage
       -c | --clean     Clean the case directory
       -r | --run-only  skip build, and directly run the benchmark
       -g | --ngpus     #GPUs to be used (between 1-10), defaults to 1
       -d | --gpu-support support for GPU offloading (e.g.: HIP or CUDA)
       -l | --log-view  Enables -log_view to see more details at end of PETSc solve
       -n | --mat-size  Prescribe a Mat size (e.g -n 200 will select a 200^3 matrix)
       -pc| --pc-type   Prescribe custom options for preconditioner
                        (default -pc_type bjacobi and -sub_pc_type ilu)
       -ksp|--ksp-options Prescribe custom options for KSP solvers
"
}

parse_args(){
    set +u
    while (( "$#" )); do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -c|--clean)
                cleanCase
                exit 1
                ;;
            -r|--run-only)
                RUN_ONLY=1
                shift 1
                ;;
            -g|--ngpus)
                NGPUS="$2"
                FLAG_G=1
                shift 2
                ;;
            -d|--gpu-support)
                DEVICE_OFFLOADING="$2"
                FLAG_D=1
                shift 2
                ;;
            -l|--log-view)
                LOG_VIEW=1
                shift 1
                ;;
            -n| --mat-size)
                MATSIZE="$2"
                FLAG_N=1
                shift 2
                ;;
            -pc| --pc-type)
                read -p "Prescribe custom options for preconditioner: " PC_OPTIONS
                CUSTOM_OPT=1
                shift 1
                ;;
            -ksp| --ksp-options)
                read -p "Prescribe custom options for KSP solver: " KSP_OPTIONS
                CUSTOM_OPT=1
                shift 1
                ;;
            -*|--*=|*) # unsupported flags
                echo "Error: Unsupported flag $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    if [[ -z "${DEVICE_OFFLOADING+x}" ]]; then
        DEVICE_OFFLOADING=HIP
        FLAG_D=0
    fi

    if [[ -z "${NGPUS+x}" ]]; then
        NGPUS=1
        FLAG_G=0
    fi

    if [[ -z "${RUN_ONLY+x}" ]]; then
        RUN_ONLY=0
    fi

    if [[ -z "${LOG_VIEW+x}" ]]; then
        LOG_VIEW=0
    fi

    if [[ -z "${MATSIZE+x}" ]]; then
        MATSIZE=200
        FLAG_N=0
    fi

    if [[ -z "${CUSTOM_OPT+x}" ]]; then
        CUSTOM_OPT=0
    fi
}

#*******************************************************
#
# This is the Main part of this bash script which calls
# the functions above based on user choices
#
#*******************************************************


parse_args $*
setup
build
run

#EOF
