#! /bin/bash
#SBATCH --job-name=proc_ico    # Specify job name
#SBATCH --partition=shared     # Specify partition name
#SBATCH --ntasks=12             # Specify max. number of tasks to be invoked
#SBATCH --mem-per-cpu=5120     # Specify real memory required per CPU in MegaBytes
#SBATCH --time=2:00:00        # Set a limit on the total run time
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
# Run using bash
#

source /sw/rhel6-x64/etc/profile.mistral
module swap cdo cdo/1.9.6-magicsxx-gcc64

export GRIB_DEFINITION_PATH=/mnt/lustre01/sw/rhel6-x64/eccodes/definitions

## 0. User specified variables

resol_target=0.2
input_dir="/work/ka1081/DYAMOND/ICON-2.5km"
output_dir="/scratch/b/b381215/CG/${resol_target}"
output_dir_nat="/scratch/b/b381215/CG/native"
vgrid_dir="/work/bk1040/experiments/input/2.5km/"
# Required dates: NB. do not span month break.
day_start=20160811
day_end=20160813
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

###time invariant fields
if [[  -f ${output_dir}/dyamond_R2B10_lkm1007_${resol_target}_vgrid_${region}.nc ]]; then
  # regridded height data already exists
  echo "regridded height data exists exists"
else
  # create regridded height data
  echo "create regridded height data for ${resol_target} grid"
  cdo -P 4 -O -f nc remap,${resol_target}_grid.nc,ICON_${resol_target}_grid_wghts.nc ${vgrid_dir}/dyamond_R2B10_lkm1007_vgrid.grb ${output_dir}/dyamond_R2B10_lkm1007_${resol_target}_vgrid.nc
  echo "extract vgrid desired region"
  cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/dyamond_R2B10_lkm1007_${resol_target}_vgrid.nc ${output_dir}/${region}/dyamond_R2B10_lkm1007_${resol_target}_vgrid_${region}.nc
fi

############################################
#>> 3D fields
#pres t w u v qv tot_qc_dia tot_qi_dia
for vari in pres t w u v qv tot_qc_dia tot_qi_dia
do
for ((i=${day_start};i<=${day_end};i++)); do
  echo "regridding ${i} for ${vari}"
  cdo -P 4 -O -f nc remap,${resol_target}_grid.nc,ICON_${resol_target}_grid_wghts.nc ${input_dir}/nwp_R2B10_lkm1007_atm_3d_${vari}_ml_${i}T000000Z.grb ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_${vari}_ml_${i}T000000Z.nc
  echo "extract desired region"
  cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_${vari}_ml_${i}T000000Z.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_${vari}_ml_${i}T000000Z_${region}.nc
done
done

for vari in omega
  do
  for ((i=${day_start};i<=${day_end};i++)); do
    echo "regridding ${i} for ${vari}"
    cdo -P 4 -O -f nc remap,${resol_target}_grid.nc,ICON_${resol_target}_grid_wghts.nc ${input_dir}/nwp_R2B10_lkm1007_atm_${vari}_3d_pl_${i}T000000Z.grb ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_${vari}_pl_${i}T000000Z.nc
    echo "extract desired region"
    cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_${vari}_pl_${i}T000000Z.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_${vari}_pl_${i}T000000Z_${region}.nc
  done
done

##########################################
#>> 2D fields atm2
## lhfl_s shfl_s prs_sfc tot_prec
#>> 2D fields atm4
## t_g ufml_s vfml_s
for ((i=${day_start};i<=${day_end};i++)); do
  echo "regridding ${i} for atm2 and atm4"
  cdo -P 4 -O -f nc remap,${resol_target}_grid.nc,ICON_${resol_target}_grid_wghts.nc ${input_dir}/nwp_R2B10_lkm1007_atm2_2d_ml_${i}T000000Z.grb ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm2_2d_ml_${i}T000000Z.nc
  cdo -P 4 -O -f nc remap,${resol_target}_grid.nc,ICON_${resol_target}_grid_wghts.nc ${input_dir}/nwp_R2B10_lkm1007_atm4_2d_ml_${i}T000000Z.grb ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm4_2d_ml_${i}T000000Z.nc

  echo "extract desired region"
  cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm2_2d_ml_${i}T000000Z.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm2_2d_ml_${i}T000000Z_${region}.nc
  cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm4_2d_ml_${i}T000000Z.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm4_2d_ml_${i}T000000Z_${region}.nc
  
  echo "extract desired variables"
  module add nco
  for vari in LHFL_S SHFL_S PS TOT_PREC CLCT; do
    ncks -v ${vari} ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm2_2d_ml_${i}T000000Z_${region}.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm2_2d_${vari}_ml_${i}T000000Z_${region}.nc
  done
  
  for vari in T_G QV_S UMFL_S VMFL_S; do
    ncks -v ${vari} ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm4_2d_ml_${i}T000000Z_${region}.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm4_2d_${vari}_ml_${i}T000000Z_${region}.nc
  done

done


#########################################
###>> theta computation

# create grid definition file if it doesn't exist
if [[  -f ${output_dir_nat}/grid_cell_area.nc ]]; then
  # grid definition file already exists
  echo "${output_dir_nat}/grid_cell_area.nc exists"
else
  # create grid definition file
  cdo -selname,cell_area ${input_dir}/grid.nc ${output_dir_nat}/grid_cell_area.nc
fi

for ((i=${day_start};i<=${day_end};i++)); do

   # extract sub region and convert to netcdf
   cdo -f nc -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} -setgrid,${output_dir_nat}/grid_cell_area.nc ${input_dir}/nwp_R2B10_lkm1007_atm_3d_pres_ml_${i}T000000Z.grb ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_pres_ml_${i}T000000Z_${region}.nc
   cdo -f nc -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} -setgrid,${output_dir_nat}/grid_cell_area.nc ${input_dir}/nwp_R2B10_lkm1007_atm_3d_t_ml_${i}T000000Z.grb ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_t_ml_${i}T000000Z_${region}.nc

   # merge two files
   cdo merge ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_pres_ml_${i}T000000Z_${region}.nc ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_t_ml_${i}T000000Z_${region}.nc ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_pres_t_ml_${i}T000000Z_${region}.nc

   # compute theta
   cdo -expr,'theta=T*((100000/P)^0.286)' ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_pres_t_ml_${i}T000000Z_${region}.nc ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_theta_ml_${i}T000000Z_${region}.nc

   # select region of weight files
   cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${resol_target}_grid.nc ${resol_target}_grid_${region}.nc
   cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} -setgrid,${output_dir_nat}/grid_cell_area.nc ICON_${resol_target}_grid_wghts.nc ICON_${resol_target}_grid_wghts_${region}.nc

   # regrid
   cdo -P 4 -O -f nc remap,${resol_target}_grid_${region}.nc,ICON_${resol_target}_grid_wghts_${region}.nc ${output_dir_nat}/nwp_R2B10_lkm1007_atm_3d_theta_ml_${i}T000000Z_${region}.nc ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_theta_ml_${i}T000000Z_${region}.nc

done





