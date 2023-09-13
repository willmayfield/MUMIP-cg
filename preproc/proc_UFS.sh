#!/bin/bash
#! /bin/bash
#SBATCH --job-name=proc_ufs    # Specify job name
#SBATCH --partition=hera    # Specify partition name
#SBATCH --ntasks=12             # Specify max. number of tasks to be invoked
#SBATCH --mem-per-cpu=8000     # Specify real memory required per CPU in MegaBytes
#SBATCH --time=8:00:00        # Set a limit on the total run time
#SBATCH --mail-type=FAIL       # Notify user by email in case of job failure
#SBATCH --account=gmtb       # Charge resources on this project account
#SBATCH --output=my_job.o%j    # File name for standard output
#SBATCH --error=my_job.e%j     # File name for standard error output

# Original Author: Hannah Christensen
# Date: Jan 2021
# Purpose: pre-process ICON DYAMOND output to produce area-weighted coarse grained fields
# These fields will be further processed to produce SCM inut files
# [obtain time averaged fields on 0.1x0.1deg lat lon grid]

# Modified by Xia Sun
# Date: Sep 2023
# Purpose: pre-process UFS LAM 3km-runs output to produce distance-weighted coarse grained fields
# These fields will be further processed to produce CCPP-SCM inut files
# [obtain time averaged fields on 0.2x0.2deg lat lon grid]

# Run using bash
#

set -x # echo on
module load cdo
module load nco

## 0. User specified variables

resol_target=0.2
# Resolution of UFS LAM runs
ufs_resol="3km"
# Experiment name for UFS LAM runs
ufs_exp="DYAMOND_3km"
# UFS LAM outputs needs to be staaged in input_dir, with naming convention of rrfs.t00z.natlev.f006.YYYYMMMDDHH.${ufs_exp}.grib2
input_dir="/home/Xia.Sun/scratch1/MU-MIP/cg-ufs/playground/ufs_${ufs_resol}"
output_dir="/home/Xia.Sun/scratch1/MU-MIP/cg-ufs/playground/CG/ufs_${resol_target}"
output_dir_nat="/home/Xia.Sun/scratch1/MU-MIP/cg-ufs/playground/CG/ufs_native"
vgrid_dir="/home/Xia.Sun/scratch1/MU-MIP/cg-ufs/playground/ufs_input/${ufs_resol}/"
preproc_dir="/home/Xia.Sun/scratch1/MU-MIP/cg-ufs/playground/preproc_ufs"
# Required dates: NB. do not span month break.
day_start=2016081100
day_end=2016081103
# for looping over levels
lev_start=0
lev_end=63

domain_minlon=-77.98
domain_maxlon=-26.85
domain_minlat=-4.54587
domain_maxlat=30.5055

# Required region
region="IO"
# minlon=51.0
# maxlon=95.0
# minlat=-35.0
# maxlat=5.0
# Below is a test region, needs to change back to IO region later
minlon=-63.04
maxlon=-30.723
minlat=1.44661
maxlat=25.6965


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
  cdo -sellonlatbox,${domain_minlon},${domain_maxlon},${domain_minlat},${domain_maxlat} ${resol_target}_grid.nc ${resol_target}_grid_domain.nc
fi

if [[  -f UFS_${resol_target}_grid_wghts.nc ]]; then
  # weight file already exists
  echo "UFS_${resol_target}_grid_remapdis_wghts.nc exists"
else
  # create weight file
  # We don't have grid area or cell corner lats and lons for UFS LAM at this time, we are using Distance-weighted average remapping
  echo "create UFS_${resol_target}_grid_remapdis_wghts.nc"
  wgrib2  rrfs.t00z.natlev.f006.${ufs_exp}.grib2 -match '^(1335):' -netcdf rrfs.t00z.natlev.f006.${ufs_exp}.gh.nc
  # cdo -P 16 --cellsearchmethod spherepart gencon,${resol_target}_grid.nc -selname,cell_area ${generic_path}/grid_area.nc UFS_${resol_target}_grid_wghts.nc
  cdo gendis,${resol_target}_grid_domain.nc rrfs.t00z.natlev.f006.${ufs_exp}.gh.nc UFS_${resol_target}_grid_domain_remapdis_wghts.nc

fi


# repeat the above for a particular region (needed for theta computation)
if [[  -f ${resol_target}_grid_${region}.nc ]]; then
  echo "${resol_target}_grid_${region}.nc exists"
else
  # create subsetted target grid file
  echo "create ${resol_target}_grid_${region}.nc"
  cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${resol_target}_grid.nc ${resol_target}_grid_${region}.nc
fi

if [[  -f UFS_${resol_target}_grid_${region}_remapdis_wghts.nc ]]; then
  echo "UFS_${resol_target}_grid_${region}_remapdis_wghts.nc exists"
else
  # create subsetted weight file
  echo "UFS_${resol_target}_grid_${region}_remapdis_wghts.nc"
  # cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} -setgrid,${output_dir_nat}/grid_cell_area.nc ${generic_path}/grid_area.nc UFS_grid_${region}.nc
  # create grid description file UFS_grid
  cdo griddes ${resol_target}_grid_${region}.nc > UFS_grid
  cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} rrfs.t00z.natlev.f006.${ufs_exp}.gh.nc rrfs.t00z.natlev.f006.${ufs_exp}.gh.${region}.nc
  # cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} -setgrid,${preproc_dir}/UFS_grid_latlon ${preproc_dir}/grid_area.nc UFS_grid_${region}.nc 
  # cdo -P 16 --cellsearchmethod spherepart gencon,${resol_target}_grid_${region}.nc -selname,cell_area UFS_grid_${region}.nc UFS_${resol_target}_grid_wghts_${region}.nc
  cdo gendis,${resol_target}_grid_${region}.nc rrfs.t00z.natlev.f006.${ufs_exp}.gh.${region}.nc UFS_${resol_target}_grid_${region}_remapdis_wghts.nc
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
if [[  -f ${output_dir}/${region}/rrfs.t00z.natlev.f006.${ufs_exp}_${resol_target}_VGRID_${region}.nc ]]; then
  # regridded height data already exists
  echo "regridded height data exists exists"
else
  # create regridded height data
  # we have to create height data for UFS LAM from scratch
  # extract all variables with HGT
  wgrib2  rrfs.t00z.natlev.f006.${ufs_exp}.grib2 -match ":(HGT):" -grib rrfs.t00z.natlev.f006.${ufs_exp}.HGT.grib2.tmp
  wgrib2 rrfs.t00z.natlev.f006.${ufs_exp}.HGT.grib2.tmp -for_n 1:64 -grib rrfs.t00z.natlev.f006.${ufs_exp}.HGT.grib2
  cdo -f nc4 copy rrfs.t00z.natlev.f006.${ufs_exp}.HGT.grib2 rrfs.t00z.natlev.f006.${ufs_exp}_HGT.nc
  wgrib2  rrfs.t00z.natlev.f006.${ufs_exp}.grib2 -match '^(1335|1394|1551):' -netcdf rrfs.t00z.natlev.f006.${ufs_exp}_vgrid.nc
  # cdo -merge rrfs.t00z.natlev.f006.eurec4a_${ufs_resol}_vgrid.nc rrfs.t00z.natlev.f006.eurec4a_${ufs_resol}.HGT.nc rrfs.t00z.natlev.f006.eurec4a_${ufs_resol}_VGIRD.nc

 # create regrided height data
echo "create regridded height data for ${resol_target} grid"
cdo -P 4 -O -f nc remap,${resol_target}_grid_domain.nc,UFS_${resol_target}_grid_domain_remapdis_wghts.nc rrfs.t00z.natlev.f006.${ufs_exp}_vgrid.nc rrfs.t00z.natlev.f006.${ufs_exp}_${resol_target}_vgrid.nc
cdo -P 4 -O -f nc remap,${resol_target}_grid_domain.nc,UFS_${resol_target}_grid_domain_remapdis_wghts.nc rrfs.t00z.natlev.f006.${ufs_exp}_HGT.nc rrfs.t00z.natlev.f006.${ufs_exp}_${resol_target}_HGT.nc
cdo -merge rrfs.t00z.natlev.f006.eurec4a_${ufs_resol}_${resol_target}_vgrid.nc rrfs.t00z.natlev.f006.${ufs_exp}_${resol_target}_HGT.nc ${output_dir}/rrfs.t00z.natlev.f006.${ufs_exp}_${resol_target}_VGRID.nc
#cdo -P 4 -O -f nc remap,${resol_target}_grid_domain.nc,UFS_${resol_target}_grid_domain_remapdis_wghts.nc rrfs.t00z.natlev.f006.eurec4a_${ufs_resol}_VGIRD.nc rrfs.t00z.natlev.f006.eurec4a_${ufs_resol}_${resol_target}_VGIRD.nc
echo "    extract vgrid desired region"
cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} rrfs.t00z.natlev.f006.${ufs_exp}}_${resol_target}_VGRID.nc ${output_dir}/${region}/rrfs.t00z.natlev.f006.${ufs_exp}_${resol_target}_VGRID_${region}.nc
fi
#clean up
rm -r  rrfs.t00z.natlev.f006.${ufs_exp}.HGT.grib2.tmp
rm -r rrfs.t00z.natlev.f006.${ufs_exp}.HGT.grib2
rm -r rrfs.t00z.natlev.f006.${ufs_exp}_vgrid.nc
rm -r rrfs.t00z.natlev.f006.${ufs_exp}_HGT.nc

############################################
##>> 3D fields
##pres t w u v qv tot_qc_dia tot_qi_dia

# for vari in pres t w u v qv tot_qc_dia tot_qi_dia
for vari in PRES TMP VVEL DZDT UGRD VGRD SPFH CLMR ICMR
do
for ((i=${day_start};i<=${day_end};i+=3)); do
  # extract variable first
  echo "extracting ${i} for ${vari} from grib2 file"
  wgrib2 ${input_dir}/rrfs.t00z.natlev.f006.${i}.${ufs_exp}.grib2 -match ":(${vari}):" -grib ${output_dir}/rrfs.t00z.natlev.f006.${i}.${vari}.${ufs_exp}.grib2.tmp
  wgrib2 ${output_dir}/rrfs.t00z.natlev.f006.${i}.${vari}.${ufs_exp}.grib2.tmp -for_n 1:64 -grib ${output_dir}/rrfs.t00z.natlev.f006.${i}.${vari}.${ufs_exp}.grib2
  rm -r ${output_dir}/rrfs.t00z.natlev.f006.${i}.${vari}.${ufs_exp}.grib2.tmp


  echo "regridding ${i} for ${vari}"
  cdo -P 4 -O -f nc remap,${resol_target}_grid_domain.nc,UFS_${resol_target}_grid_domain_remapdis_wghts.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${vari}.${ufs_exp}.grib2  ${output_dir}/rrfs.t00z.natlev.f006.${i}.${vari}.${resol_target}.${ufs_exp}.nc
  echo "extract desired region"
  cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/rrfs.t00z.natlev.f006.${i}.${vari}.${resol_target}.${ufs_exp}.nc ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.${vari}.${ufs_exp}.${region}.nc
done
done

############################################
##>> 2D fields atm2
# ICON: hfls(surface latent heat flux, positive upwards)  hfss(surface sensible heat flux, DEPHY sign convention: postive upwards) ps (surface pressure) pr(precipitation) clt(cloud cover)
# UFS: LHTFL:surface (883),SHTFL:surface (882), PRES:surface (807), APCP Total Precipitation (kh m-2, 851) ,TCDC (920)
# ICON: ts(surface temp) hus(qv_s) tauu(u momentum flux, ustar) tauv (v momentum flux)
# UFS:TMP:surface (809),SPFH:surface (811),UFLX:surface (880),VFLX:surface (881)

for ((i=${day_start};i<=${day_end};i+=3)); do
  grib_ids=(883 882 807 851 920 809 811 880 881)
  vars=("LHTFL" "SHTFL" "ps" "APCP" "TCDC" "ts" "qv_s" "UFLX" "VFLX")

  for index in "${!grib_ids[@]}";do
    grib_id="${grib_ids[$index]}"
    var="${vars[$index]}"
    echo $var
    echo "extracting ${i} for ${var} from grib2 file"
    wgrib2  ${input_dir}/rrfs.t00z.prslev.f006.${i}.${ufs_exp}.grib2 -for ${grib_id}:${grib_id} -grib ${output_dir}/rrfs.t00z.prslev.f006.${i}.${var}.${ufs_exp}.grib2

    echo "regridding ${i} for ${var}"
    cdo -P 4 -O -f nc remap,${resol_target}_grid_domain.nc,UFS_${resol_target}_grid_domain_remapdis_wghts.nc ${output_dir}/rrfs.t00z.prslev.f006.${i}.${var}.${ufs_exp}.grib2  ${output_dir}/rrfs.t00z.prslev.f006.${i}.${var}.${resol_target}.${ufs_exp}.nc

    echo "extract desired region"   
    cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/rrfs.t00z.prslev.f006.${i}.${var}.${resol_target}.${ufs_exp}.nc ${output_dir}/${region}/rrfs.t00z.prslev.f006.${i}.${resol_target}.${var}.${ufs_exp}.${region}.nc
  done
done


