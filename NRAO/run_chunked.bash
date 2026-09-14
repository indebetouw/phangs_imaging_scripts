#!/bin/bash
#SBATCH --account=rindebet
#SBATCH --time=24:00:00
#SBATCH --job-name=phangs_chunk
#SBATCH --output=%x_%A_%a.out
#SBATCH --error=%x_%A_%a.err
#SBATCH --ntasks=4      # number of MPI processes
#SBATCH --mem=126G      # memory; default unit is megabytes; was 32G/core
#SBATCH --cpus-per-task=1
#SBATCH --mail-user=rindebet@nrao.edu
#SBATCH --mail-type=ALL
#SBATCH --partition=plwg,batch2

script_dir="$(cd "$(dirname "$0")" && pwd)"

assembled_products_exist() {
    local target_name="$1"
    local product_name="$2"
    local config_name="12m+7m"
    local master_key="${script_dir}/master_key_sscales.txt"
    local dir_key="${script_dir}/dir_key.txt"
    local imaging_root
    local target_dir
    local imaging_dir
    local cube_root
    local root_tag
    local p_tclean
    local p_sdint

    if [[ ! -f "$master_key" ]]; then
        return 1
    fi

    imaging_root=$(awk '$1=="imaging_root" {print $2; exit}' "$master_key")
    if [[ -z "$imaging_root" ]]; then
        return 1
    fi

    if [[ -f "$dir_key" ]]; then
        target_dir=$(awk -v tgt="$target_name" '$1==tgt && $1 !~ /^#/ {print $2; exit}' "$dir_key")
    fi
    if [[ -z "$target_dir" ]]; then
        target_dir="$target_name"
    fi

    imaging_dir="${imaging_root%/}/${target_dir}"
    cube_root="${target_name}_${config_name}_${product_name}"

    # Only require final assembled cube products. The "dirty" cube is
    # diagnostic/intermediate for many runs and may not be preserved.
    for root_tag in "" "_singlescale" "_multiscale"; do
        p_tclean="${imaging_dir}/${cube_root}${root_tag}.image"
        p_sdint="${imaging_dir}/${cube_root}${root_tag}.joint.cube.image"
        if [[ -d "$p_tclean" || -d "$p_sdint" ]]; then
            :
        else
            echo "Missing assembled product path: $p_tclean or $p_sdint" >&2
            return 1
        fi
    done

    return 0
}


# Read target/product from CLI and submit with dynamic job naming when run
# outside of an allocated Slurm job.
if [[ -z "${SLURM_JOB_ID:-}" ]]; then
	if [[ $# -lt 2 ]]; then
		echo "Usage: $0 <target> <product> [sbatch options]"
		echo "Example: $0 ngc5236_5 13co21 --array=0-5"
        exit 0
	fi
	target_cli="$1"
	product_cli="$2"
	job_tag="${target_cli}_${product_cli}"
	shift 2
	sbatch_opts=("$@")
    skip_imaging=false

    if assembled_products_exist "${target_cli}" "${product_cli}"; then
        echo "Final assembled products already exist for ${job_tag}; skipping I and AP submissions."
        skip_imaging=true
    fi

    if [[ "$skip_imaging" == "true" ]]; then
        echo "Skipping S, I, and AP for ${job_tag}. Submitting D with no dependencies."
        export stagestring='D'
        sbatch --parsable --ntasks=1 --job-name="${job_tag}" "$0" "${target_cli}" "${product_cli}"
        exit $?
    fi

    # Edit to do correct stage string
    # S = staging
    # I = imaging
    # A = assemble
    # P = postprocess
    # D = derived
    export stagestring='S'
    echo "Submitting Stage job '${job_tag}_stage'"
    STAGE_ID=$(sbatch --parsable --ntasks=1 --job-name="${job_tag}_stage" "$0" "${target_cli}" "${product_cli}")

    export stagestring='I'
	echo "Submitting Imaging job '${job_tag}'"
	ARRAY_ID=$(sbatch --parsable --dependency=afterok:${STAGE_ID} "${sbatch_opts[@]}" --job-name="${job_tag}" "$0" "${target_cli}" "${product_cli}")

    export stagestring='AP'
    echo "Submitting Assemble job '${job_tag}'"
    AP_ID=$(sbatch --parsable --dependency=afterok:${ARRAY_ID} --ntasks=1 --job-name="${job_tag}" "$0" "${target_cli}" "${product_cli}")
    # for post-processing previously imaged data - comment out the imaging above and run this:
    #sbatch --parsable --ntasks=1 --job-name="${job_tag}" "$0" "${target_cli}" "${product_cli}"

    export stagestring='D'
    echo "Submitting Derived job '${job_tag}'"
    sbatch --parsable --dependency=afterok:${AP_ID} --ntasks=1 --job-name="${job_tag}" "$0" "${target_cli}" "${product_cli}"


	exit $?
fi

# Edit these lines to point to correct directory and galaxy name
export code_dir='/lustre/cv/users/rindebet/local/github/phangs_imaging_scripts/NRAO/'
# export casadir='/lustre/cv/users/rindebet/casa/casa-6.7.5-10-pipeline-2026.1.1.7-py3.12.el8/'
# Target and product are read from command line as:
#   run_chunked.bash <target> <product>
# Example target: m83_5
export target="$1"
export config="12m+7m"
export product="$2"

# call this file with
# run_chunked.bash m83_5 13co21 --array=0-5


#### you shouldn't need to edit below this line
# srun bash
#ls -l /idia/software/containers/casa-modular-v6.6.4.sif
#module load casa/6.6.4
# do this in the CASA installation before starting this script
# pip install spectral-cube, uvcombine

if [ -z ${SLURM_ARRAY_TASK_ID+x} ]; then export SLURM_ARRAY_TASK_ID=-1; fi
echo "Job array ID is set to '$SLURM_ARRAY_TASK_ID'"

# how to pass arguments to the -c command of casa
#${casadir}/bin/casa --log2term --logfile casa_{$SLURM_ARRAY_TASK_ID}.log -c "${code_dir}/run_chunk.py $target $stagestring $SLURM_ARRAY_TASK_ID"
. /users/rindebet/miniforge3/etc/profile.d/conda.sh
conda activate phclean
# Normalize any accidental whitespace so stage selection is exact.
stage_mode="${stagestring:-}"
stage_mode="${stage_mode//[[:space:]]/}"

if [[ "$stage_mode" == "I" ]]; then
    OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 mpirun --mca btl_vader_single_copy_mechanism none -x OMP_NUM_THREADS -x OPENBLAS_NUM_THREADS -n 4 python ${code_dir}/run_chunk.py $target $config $product $stagestring $SLURM_ARRAY_TASK_ID
else
    OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 python ${code_dir}/run_chunk.py $target $config $product $stagestring $SLURM_ARRAY_TASK_ID    
fi
