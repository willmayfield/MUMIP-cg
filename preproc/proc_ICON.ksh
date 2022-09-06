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


echo "compute CG files for ${day_start}"
echo "================================="

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
if [[  -f ${output_dir}/$region/dyamond_R2B10_lkm1007_${resol_target}_vgrid_${region}.nc ]]; then
  # regridded height data already exists
  echo "regridded height data exists exists"
else
  # create regridded height data
  echo "create regridded height data for ${resol_target} grid"
  cdo -P 4 -O -f nc remap,${resol_target}_grid.nc,ICON_${resol_target}_grid_wghts.nc ${vgrid_dir}/dyamond_R2B10_lkm1007_vgrid.grb ${output_dir}/dyamond_R2B10_lkm1007_${resol_target}_vgrid.nc
  echo "    extract vgrid desired region"
  cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/dyamond_R2B10_lkm1007_${resol_target}_vgrid.nc ${output_dir}/${region}/dyamond_R2B10_lkm1007_${resol_target}_vgrid_${region}.nc
fi

############################################
##>> 3D fields
##pres t w u v qv tot_qc_dia tot_qi_dia
for vari in pres t w u v qv tot_qc_dia tot_qi_dia
do
for ((i=${day_start};i<=${day_end};i++)); do
  echo "regridding ${i} for ${vari}"
  cdo -P 4 -O -f nc remap,${resol_target}_grid.nc,ICON_${resol_target}_grid_wghts.nc ${input_dir}/nwp_R2B10_lkm1007_atm_3d_${vari}_ml_${i}T000000Z.grb ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_${vari}_ml_${i}T000000Z.nc
  echo "   extract desired region"
  cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_${vari}_ml_${i}T000000Z.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_${vari}_ml_${i}T000000Z_${region}.nc
done
done

### not considering Omega at the moment: 23/8/22
#for vari in omega
#  do
#  for ((i=${day_start};i<=${day_end};i++)); do
#    echo "regridding ${i} for ${vari}"
#    cdo -P 4 -O -f nc remap,${resol_target}_grid.nc,ICON_${resol_target}_grid_wghts.nc ${input_dir}/nwp_R2B10_lkm1007_atm_${vari}_3d_pl_${i}T000000Z.grb ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_${vari}_pl_${i}T000000Z.nc
#    echo "   extract desired region"
#    cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_${vari}_pl_${i}T000000Z.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm_3d_${vari}_pl_${i}T000000Z_${region}.nc
#  done
#done

############################################
##>> 2D fields atm2
### lhfl_s shfl_s prs_sfc tot_prec
##>> 2D fields atm4
### t_g ufml_s vfml_s
for ((i=${day_start};i<=${day_end};i++)); do
  echo "regridding ${i} for atm2 and atm4"
  cdo -P 4 -O -f nc remap,${resol_target}_grid.nc,ICON_${resol_target}_grid_wghts.nc ${input_dir}/nwp_R2B10_lkm1007_atm2_2d_ml_${i}T000000Z.grb ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm2_2d_ml_${i}T000000Z.nc
  cdo -P 4 -O -f nc remap,${resol_target}_grid.nc,ICON_${resol_target}_grid_wghts.nc ${input_dir}/nwp_R2B10_lkm1007_atm4_2d_ml_${i}T000000Z.grb ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm4_2d_ml_${i}T000000Z.nc

  echo "   reduce temporal frequency to 3 hourly"
  ncks -d time,0,95,12 ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm2_2d_ml_${i}T000000Z.nc ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm2_2d_ml_${i}T000000Z_3hr.nc
  ncks -d time,0,95,12 ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm4_2d_ml_${i}T000000Z.nc ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm4_2d_ml_${i}T000000Z_3hr.nc

  echo "   extract desired region"
  cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm2_2d_ml_${i}T000000Z_3hr.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm2_2d_ml_${i}T000000Z_${region}.nc
  cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/nwp_R2B10_lkm1007_${resol_target}_atm4_2d_ml_${i}T000000Z_3hr.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm4_2d_ml_${i}T000000Z_${region}.nc
  
  echo "   extract desired variables"
  # this line changed due to GRIB issues
  #for vari in LHFL_S SHFL_S sp tp CLCT; do
  for vari in hfls hfss ps pr clt; do
    ncks -v ${vari} ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm2_2d_ml_${i}T000000Z_${region}.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm2_2d_${vari}_ml_${i}T000000Z_${region}.nc
  done
  
  # this line changed due to GRIB issues
  #for vari in T_G QV_S UMFL_S VMFL_S;
  for vari in ts hus tauu tauv; do
    ncks -v ${vari} ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm4_2d_ml_${i}T000000Z_${region}.nc ${output_dir}/${region}/nwp_R2B10_lkm1007_${resol_target}_atm4_2d_${vari}_ml_${i}T000000Z_${region}.nc
  done

done







