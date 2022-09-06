#! /bin/bash
#SBATCH --job-name=proc_ico    # Specify job name
#SBATCH --partition=compute    # Specify partition name
#SBATCH --ntasks=12             # Specify max. number of tasks to be invoked
#SBATCH --mem-per-cpu=8000     # Specify real memory required per CPU in MegaBytes
#SBATCH --time=8:00:00        # Set a limit on the total run time
#SBATCH --mail-type=FAIL       # Notify user by email in case of job failure
#SBATCH --account=bb1153       # Charge resources on this project account
#SBATCH --output=my_job.o%j    # File name for standard output
#SBATCH --error=my_job.e%j     # File name for standard error output

# Author: Hannah Christensen
# Date: Jan 2021
# Purpose: pre-process ICON DYAMOND output to produce area-weighted coarse grained fields
# These fields will be further processed to produce SCM inut files
# [obtain time averaged fields on 0.1x0.1deg lat lon grid]
#
# This script computes derived variables on the fine resolution grid
#    >> mixinf ratios
#    >> follow with proc_ICON_derived_2.ksh to calculate theta and theta_l
#
# Run using bash
#

set -x # echo on

source /sw/etc/profile.levante
module add cdo
module add nco
module add eccodes

export GRIB_DEFINITION_PATH=/mnt/lustre01/sw/rhel6-x64/eccodes/definitions


## 0. User specified variables

resol_target=0.2
input_dir="/work/ka1081/DYAMOND/ICON-2.5km"
output_dir="/work/bb1153/b381215/CG/${resol_target}"
output_dir_nat="/work/bb1153/b381215/CG/native"
vgrid_dir="/work/bk1040/experiments/input/2.5km/"
# Required dates: NB. do not span month break.
day_start=20160811
day_end=20160811
# for looping over levels
lev_start=0
lev_end=76
## Required region
#region="WPac"
#minlon=40.0
#maxlon=180.0
#minlat=-22.0
#maxlat=22.0
# Required region
region="IO"
minlon=51.0
maxlon=95.0
minlat=-35.0
maxlat=5.0

## 1. we will compute one weight file which can be used for all remappings - this is the time consuming part of the regridding.
if [[  -f ${resol_target}_grid.nc ]]; then
  # target grid file already exists
  echo "${resol_target}_grid.nc exists"
else
  # create target grid file
  echo "create ${resol_target}_grid.nc"
  cdo -O -f nc -topo,global_${resol_target} ${resol_target}_grid.nc
fi

if [[  -f ICON_${resol_target}_grid_wghts.nc ]]; then
  # weight file already exists
  echo "ICON_${resol_target}_grid_wghts.nc exists"
else
  # create weight file
  echo "create ICON_${resol_target}_grid_wghts.nc"
  cdo -P 16 --cellsearchmethod spherepart gencon,${resol_target}_grid.nc -selname,cell_area /work/ka1081/DYAMOND/ICON-2.5km/grid.nc ICON_${resol_target}_grid_wghts.nc
fi

# repeat the above for a particular region (needed for theta computation)
if [[  -f ${resol_target}_grid_${region}.nc ]]; then
  echo "${resol_target}_grid_${region}.nc exists"
else
  # create subsetted target grid file
  echo "create ${resol_target}_grid_${region}.nc"
  cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${resol_target}_grid.nc ${resol_target}_grid_${region}.nc
fi

if [[  -f ICON_${resol_target}_grid_wghts_${region}.nc ]]; then
  echo "ICON_${resol_target}_grid_wghts_${region}.nc exists"
else
  # create subsetted weight file
  echo "create ICON_${resol_target}_grid_wghts_${region}.nc"
  cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} -setgrid,${output_dir_nat}/grid_cell_area.nc /work/ka1081/DYAMOND/ICON-2.5km/grid.nc ICON_grid_${region}.nc 
  cdo -P 16 --cellsearchmethod spherepart gencon,${resol_target}_grid_${region}.nc -selname,cell_area ICON_grid_${region}.nc ICON_${resol_target}_grid_wghts_${region}.nc
fi


## 2. Regrid using these weights.

# create output directory if needed
if [[ ! -d $output_dir ]]; then
  echo "create output directory"
  mkdir ${output_dir}
fi
if [[ ! -d $output_dir/$region ]]; then
  echo "create region output directory"
  mkdir ${output_dir}/$region
fi

#########################################
###>> mixing ratio computation
echo "mixing ratio computation"
# create grid definition file if it doesn't exist
if [[  -f ${output_dir_nat}/grid_cell_area.nc ]]; then
  # grid definition file already exists
  echo "${output_dir_nat}/grid_cell_area.nc exists"
else
  # create grid definition file
  cdo -selname,cell_area ${input_dir}/grid.nc ${output_dir_nat}/grid_cell_area.nc
fi

for ((i=${day_start};i<=${day_end};i++)) ; do

    # convert full resolution grb -> netcdf
    cdo -f nc4 copy ${input_dir}/nwp_R2B10_lkm1007_atm_3d_qv_ml_${i}T000000Z.grb ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_qv_ml_${i}T000000Z.nc
    cdo -f nc4 -chname,param212.1.0,ql ${input_dir}/nwp_R2B10_lkm1007_atm_3d_tot_qc_dia_ml_${i}T000000Z.grb ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_tot_qc_dia_ml_${i}T000000Z.nc
    cdo -f nc4 -chname,param213.1.0,qi ${input_dir}/nwp_R2B10_lkm1007_atm_3d_tot_qi_dia_ml_${i}T000000Z.grb ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_tot_qi_dia_ml_${i}T000000Z.nc

    # loop over vertical levels
    for j in $(seq -f "%03g" ${lev_start} ${lev_end}) ; do
    #for j in $(seq -w ${lev_end}) ; do
    #for ((j=${lev_start};j<=${lev_end};j++)); do

            echo "   starting level ${j}"

	    # extract vertical level
	    ncks -d height,${j} ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_qv_ml_${i}T000000Z.nc ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_qv_ml_${i}T000000Z_${j}.nc
            ncks -d height,${j} ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_tot_qc_dia_ml_${i}T000000Z.nc ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_tot_qc_dia_ml_${i}T000000Z_${j}.nc
            ncks -d height,${j} ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_tot_qi_dia_ml_${i}T000000Z.nc ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_tot_qi_dia_ml_${i}T000000Z_${j}.nc

	    # merge
            cdo merge ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_qv_ml_${i}T000000Z_${j}.nc ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_tot_qc_dia_ml_${i}T000000Z_${j}.nc ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_tot_qi_dia_ml_${i}T000000Z_${j}.nc ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_all_q_ml_${i}T000000Z_${j}.nc 

            # compute mixing ratio at full resolution
	    cdo -expr,'rv=hus/(1.0-hus-ql-qi)' ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_all_q_ml_${i}T000000Z_${j}.nc ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_rv_ml_${i}T000000Z_${j}.nc
	    cdo -expr,'rl=ql/(1.0-hus-ql-qi)' ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_all_q_ml_${i}T000000Z_${j}.nc ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_rl_ml_${i}T000000Z_${j}.nc
	    cdo -expr,'ri=qi/(1.0-hus-ql-qi)' ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_all_q_ml_${i}T000000Z_${j}.nc ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_ri_ml_${i}T000000Z_${j}.nc

	    # regrid
	    cdo -f nc4 -P 4 -O remap,${resol_target}_grid.nc,ICON_${resol_target}_grid_wghts.nc ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_rv_ml_${i}T000000Z_${j}.nc ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rv_ml_${i}T000000Z_${j}_tmp.nc
	    cdo -f nc4 -P 4 -O remap,${resol_target}_grid.nc,ICON_${resol_target}_grid_wghts.nc ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_rl_ml_${i}T000000Z_${j}.nc ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rl_ml_${i}T000000Z_${j}_tmp.nc
	    cdo -f nc4 -P 4 -O remap,${resol_target}_grid.nc,ICON_${resol_target}_grid_wghts.nc ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_ri_ml_${i}T000000Z_${j}.nc ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_ri_ml_${i}T000000Z_${j}_tmp.nc

	    # convert height to record dimension
	    ncpdq -a height,time ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rv_ml_${i}T000000Z_${j}_tmp.nc ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rv_ml_${i}T000000Z_${j}.nc
	    ncpdq -a height,time ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rl_ml_${i}T000000Z_${j}_tmp.nc ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rl_ml_${i}T000000Z_${j}.nc
	    ncpdq -a height,time ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_ri_ml_${i}T000000Z_${j}_tmp.nc ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_ri_ml_${i}T000000Z_${j}.nc

	    # extract desired region
	    cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rv_ml_${i}T000000Z_${j}.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rv_ml_${i}T000000Z_${region}_${j}.nc
	    cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rl_ml_${i}T000000Z_${j}.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rl_ml_${i}T000000Z_${region}_${j}.nc
	    cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_ri_ml_${i}T000000Z_${j}.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_ri_ml_${i}T000000Z_${region}_${j}.nc

	    # tidy a little
	    rm ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rv_ml_${i}T000000Z_${j}_tmp.nc
            rm ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rl_ml_${i}T000000Z_${j}_tmp.nc
	    rm ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_ri_ml_${i}T000000Z_${j}_tmp.nc

	    rm ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_qv_ml_${i}T000000Z_${j}.nc
	    rm ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_tot_qc_dia_ml_${i}T000000Z_${j}.nc
	    rm ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_tot_qi_dia_ml_${i}T000000Z_${j}.nc
	    rm ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_all_q_ml_${i}T000000Z_${j}.nc

	    rm ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_rv_ml_${i}T000000Z_${j}.nc
	    ##rm ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_rl_ml_${i}T000000Z_${j}.nc # needed for theta_l calculation
	    rm ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_ri_ml_${i}T000000Z_${j}.nc

    done

    # merge all levels
    ncrcat ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rv_ml_${i}T000000Z_*.nc ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rv_ml_${i}T000000Z_tmp.nc
    ncrcat ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rv_ml_${i}T000000Z_${region}_*.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rv_ml_${i}T000000Z_${region}_tmp.nc

    ncrcat ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rl_ml_${i}T000000Z_*.nc ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rl_ml_${i}T000000Z_tmp.nc
    ncrcat ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rl_ml_${i}T000000Z_${region}_*.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rl_ml_${i}T000000Z_${region}_tmp.nc

    ncrcat ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_ri_ml_${i}T000000Z_*.nc ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_ri_ml_${i}T000000Z_tmp.nc
    ncrcat ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_ri_ml_${i}T000000Z_${region}_*.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_ri_ml_${i}T000000Z_${region}_tmp.nc

    # restore time as record dimension
    ncpdq -a time,height ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rv_ml_${i}T000000Z_tmp.nc ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rv_ml_${i}T000000Z.nc
    ncpdq -a time,height ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rv_ml_${i}T000000Z_${region}_tmp.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rv_ml_${i}T000000Z_${region}.nc

    ncpdq -a time,height ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rl_ml_${i}T000000Z_tmp.nc ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rl_ml_${i}T000000Z.nc
    ncpdq -a time,height ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rl_ml_${i}T000000Z_${region}_tmp.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rl_ml_${i}T000000Z_${region}.nc

    ncpdq -a time,height ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_ri_ml_${i}T000000Z_tmp.nc ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_ri_ml_${i}T000000Z.nc
    ncpdq -a time,height ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_ri_ml_${i}T000000Z_${region}_tmp.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_ri_ml_${i}T000000Z_${region}.nc

    # And compute r_t for completeness (linearity holds)
    cdo merge ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rv_ml_${i}T000000Z.nc ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rl_ml_${i}T000000Z.nc ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_ri_ml_${i}T000000Z.nc ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_all_r_ml_${i}T000000Z.nc
    cdo -expr,'rt=rv+rl+ri' ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_all_r_ml_${i}T000000Z.nc ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rt_ml_${i}T000000Z.nc
    rm ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_all_r_ml_${i}T000000Z.nc

    cdo merge ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rv_ml_${i}T000000Z_${region}.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rl_ml_${i}T000000Z_${region}.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_ri_ml_${i}T000000Z_${region}.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_all_r_ml_${i}T000000Z_${region}.nc
    cdo -expr,'rt=rv+rl+ri' ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_all_r_ml_${i}T000000Z_${region}.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rt_ml_${i}T000000Z_${region}.nc
    rm ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_all_r_ml_${i}T000000Z_${region}.nc


    # tidy: delete individual level files
    rm ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rv_ml_${i}T000000Z_*.nc
    rm ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rv_ml_${i}T000000Z_${region}_*.nc

    rm ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rl_ml_${i}T000000Z_*.nc
    rm ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_rl_ml_${i}T000000Z_${region}_*.nc

    rm ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_ri_ml_${i}T000000Z_*.nc
    rm ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_ri_ml_${i}T000000Z_${region}_*.nc

done
###################################


