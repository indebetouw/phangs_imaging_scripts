#!/bin/bash
#SBATCH --account=rindebet
#SBATCH --time=48:00:00
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

postprocessed_derived_input_exists() {
    local target_name="$1"
    local product_name="$2"
    local config_name="12m+7m"
    local master_key="${script_dir}/master_key_sscales.txt"
    local dir_key="${script_dir}/dir_key.txt"
    local postprocess_root
    local target_dir
    local postprocess_dir
    local cube_root
    local cube_path

    if [[ ! -f "$master_key" ]]; then
        return 1
    fi

    postprocess_root=$(awk '$1=="postprocess_root" {print $2; exit}' "$master_key")
    if [[ -z "$postprocess_root" ]]; then
        return 1
    fi

    if [[ -f "$dir_key" ]]; then
        target_dir=$(awk -v tgt="$target_name" '$1==tgt && $1 !~ /^#/ {print $2; exit}' "$dir_key")
    fi
    if [[ -z "$target_dir" ]]; then
        target_dir="$target_name"
    fi

    postprocess_dir="${postprocess_root%/}/${target_dir}"
    cube_root="${target_name}_${config_name}_${product_name}"
    cube_path="${postprocess_dir}/${cube_root}_pbcorr_trimmed_k.fits"

    if [[ -f "$cube_path" ]]; then
        return 0
    fi

    echo "Missing postprocessed derived input: $cube_path" >&2
    return 1
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
    # The assembly stage requires the final assembled image/cube products.
    # The postprocess stage requires the final assembled cube and creates the
    # pbcorr_trimmed_k input that the derived stage consumes.
    if postprocessed_derived_input_exists "${target_cli}" "${product_cli}"; then
        echo "Final postprocessed product already exists for ${job_tag}; skipping S, I, A, and P submissions."
        export stagestring='D'
        DERIVED_ID=$(sbatch --parsable --ntasks=1 --job-name="${job_tag}" "$0" "${target_cli}" "${product_cli}")
        echo "Submitted Derived job '${job_tag}' ${DERIVED_ID}"
        exit $?
    fi

    if assembled_products_exist "${target_cli}" "${product_cli}"; then
        echo "Final assembled products already exist for ${job_tag}; skipping S, I, and A submissions."
        export stagestring='P'
        POST_ID=$(sbatch --parsable --ntasks=1 --job-name="${job_tag}_post" "$0" "${target_cli}" "${product_cli}")
        echo "Submitted Postprocess job '${job_tag}_post' ${POST_ID}"

        export stagestring='D'
        DERIVED_ID=$(sbatch --parsable --dependency=afterok:${POST_ID} --ntasks=1 --job-name="${job_tag}" "$0" "${target_cli}" "${product_cli}")
        echo "Submitted Derived job '${job_tag}' ${DERIVED_ID}"
        exit $?
    fi

    # Edit to do correct stage string
    # S = staging
    # I = imaging
    # A = assemble
    # P = postprocess
    # D = derived
    export stagestring='S'
    STAGE_ID=$(sbatch --parsable --ntasks=1 --job-name="${job_tag}_stage" "$0" "${target_cli}" "${product_cli}")
    echo "Submitted Stage job '${job_tag}_stage' ${STAGE_ID}"

    export stagestring='I'
    ARRAY_ID=$(sbatch --parsable --dependency=afterok:${STAGE_ID} "${sbatch_opts[@]}" --job-name="${job_tag}" "$0" "${target_cli}" "${product_cli}")
    echo "Submitted Imaging job '${job_tag}' ${ARRAY_ID}"

    export stagestring='A'
    ASSEMBLY_ID=$(sbatch --parsable --dependency=afterok:${ARRAY_ID} --ntasks=1 --job-name="${job_tag}_assemble" "$0" "${target_cli}" "${product_cli}")
    echo "Submitted Assembly job '${job_tag}_assemble' ${ASSEMBLY_ID}"

    export stagestring='P'
    POST_ID=$(sbatch --parsable --dependency=afterok:${ASSEMBLY_ID} --ntasks=1 --job-name="${job_tag}_post" "$0" "${target_cli}" "${product_cli}")
    echo "Submitted Postprocess job '${job_tag}_post' ${POST_ID}"

    export stagestring='D'
    DERIVED_ID=$(sbatch --parsable --dependency=afterok:${POST_ID} --ntasks=1 --job-name="${job_tag}" "$0" "${target_cli}" "${product_cli}")
    echo "Submitted Derived job '${job_tag}' ${DERIVED_ID}"


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
