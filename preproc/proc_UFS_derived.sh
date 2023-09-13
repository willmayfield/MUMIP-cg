#! /bin/bash

#SBATCH --job-name=proc_ufs_derived    # Specify job name
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
# This script computes derived variables on the fine resolution grid
#    >> mixinf ratios
#    >> follow with proc_ICON_derived_2.ksh to calculate theta and theta_l
#

# Modified by Xia Sun
# Date: Sep 2023
# Purpose: pre-process UFS DYAMOND output to produce distance-weighted coarse grained fields
# These fields will be further processed to produce CCPP-SCM inut files
# [obtain time averaged fields on 0.2x0.2deg lat lon grid]
# This script computes derived variables on the fine resolution grid
#    >> mixinf ratios
#    >> follow with proc_UFS_derived_2.ksh to calculate theta and theta_l

# Run using bash
#

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
vgrid_dir="/home/Xia.Sun/scratch1/MU-MIP/cg-ufs/playground/ufs_input/${ufs_resol}"
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

if [[  -f UFS_${resol_target}_grid_domain_remapdis_wghts.nc ]]; then
  # weight file already exists
  echo "UFS_${resol_target}_grid_domain_remapdis_wghts.nc exists"
else
  # create weight file
  # We don't have grid area or cell corner lats and lons for UFS LAM at this time, we are using Distance-weighted average remapping
  echo "create UFS_${resol_target}_grid_domain_remapdis_wghts.nc"
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
  echo "UFS_${resol_target}_grid_${region}_remapdis_wghts.nc"
else
  # create subsetted weight file
  echo "create UFS_${resol_target}_grid_${region}_remapdis_wghts.nc"
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

if [[ ! -d $output_dir_nat ]]; then
  echo "create output_dir directory"
  mkdir ${output_dir_nat}
fi


#########################################
###>> mixing ratio computation
echo "mixing ratio computation"

for ((i=${day_start};i<=${day_end};i+=3)) ; do

    # convert full resolution grb -> netcdf; calculate at high resolution, then coarse grain
    cdo -f nc4 copy ${output_dir}/rrfs.t00z.natlev.f006.${i}.SPFH.${ufs_exp}.grib2  ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.SPFH.${ufs_exp}.nc
    cdo -f nc4 copy ${output_dir}/rrfs.t00z.natlev.f006.${i}.CLMR.${ufs_exp}.grib2  ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.CLMR.${ufs_exp}.nc   
    cdo -f nc4 copy ${output_dir}/rrfs.t00z.natlev.f006.${i}.ICMR.${ufs_exp}.grib2  ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.ICMR.${ufs_exp}.nc  

    # loop over vertical levels
    for j in $(seq -f "%03g" ${lev_start} ${lev_end}) ; do
        echo "starting level ${j}"

        # extract vertical level
        ncks -d lev,${j} ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.SPFH.${ufs_exp}.nc ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.SPFH.${ufs_exp}.${j}.nc
        ncks -d lev,${j} ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.CLMR.${ufs_exp}.nc ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.CLMR.${ufs_exp}.${j}.nc
        ncks -d lev,${j} ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.ICMR.${ufs_exp}.nc ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.ICMR.${ufs_exp}.${j}.nc

      # merge
        cdo merge  ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.SPFH.${ufs_exp}.${j}.nc ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.CLMR.${ufs_exp}.${j}.nc ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.ICMR.${ufs_exp}.${j}.nc ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.qv_rl_ri.${ufs_exp}.${j}.nc

        #compute mixing ratio at full resolution
        cdo -expr,'rv=q/(1.0-q)' ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.qv_rl_ri.${ufs_exp}.${j}.nc ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.rv.${ufs_exp}.${j}.nc
        cdo merge ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.rv.${ufs_exp}.${j}.nc ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.qv_rl_ri.${ufs_exp}.${j}.nc ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.qv_all_r.${ufs_exp}.${j}.nc 
        cdo -expr,'ql=clwmr/(1.0+rv+icmr+clwmr)' ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.qv_all_r.${ufs_exp}.${j}.nc ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.ql.${ufs_exp}.${j}.nc
        cdo -expr,'qi=icmr/(1.0+rv+icmr+clwmr)' ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.qv_all_r.${ufs_exp}.${j}.nc ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.qi.${ufs_exp}.${j}.nc

         # regrid
        cdo -f nc4 -P 4 -O remap,${resol_target}_grid_domain.nc,UFS_${resol_target}_grid_domain_remapdis_wghts.nc ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.rv.${ufs_exp}.${j}.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.rv.${ufs_exp}.${j}.tmp.nc
        cdo -f nc4 -P 4 -O remap,${resol_target}_grid_domain.nc,UFS_${resol_target}_grid_domain_remapdis_wghts.nc ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.ql.${ufs_exp}.${j}.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ql.${ufs_exp}.${j}.tmp.nc
        cdo -f nc4 -P 4 -O remap,${resol_target}_grid_domain.nc,UFS_${resol_target}_grid_domain_remapdis_wghts.nc ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.qi.${ufs_exp}.${j}.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.qi.${ufs_exp}.${j}.tmp.nc
        cdo -f nc4 -P 4 -O remap,${resol_target}_grid_domain.nc,UFS_${resol_target}_grid_domain_remapdis_wghts.nc ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.SPFH.${ufs_exp}.${j}.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.SPFH.${ufs_exp}.${j}.tmp.nc
        cdo -f nc4 -P 4 -O remap,${resol_target}_grid_domain.nc,UFS_${resol_target}_grid_domain_remapdis_wghts.nc ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.CLMR.${ufs_exp}.${j}.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.CLMR.${ufs_exp}.${j}.tmp.nc
        cdo -f nc4 -P 4 -O remap,${resol_target}_grid_domain.nc,UFS_${resol_target}_grid_domain_remapdis_wghts.nc ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.ICMR.${ufs_exp}.${j}.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ICMR.${ufs_exp}.${j}.tmp.nc


         # convert height to record dimension
        ncpdq -a lev,time ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.rv.${ufs_exp}.${j}.tmp.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.rv.${ufs_exp}.${j}.nc
        ncpdq -a lev,time ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ql.${ufs_exp}.${j}.tmp.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ql.${ufs_exp}.${j}.nc
        ncpdq -a lev,time ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.qi.${ufs_exp}.${j}.tmp.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.qi.${ufs_exp}.${j}.nc
        ncpdq -a lev,time ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.SPFH.${ufs_exp}.${j}.tmp.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.SPFH.${ufs_exp}.${j}.nc
        ncpdq -a lev,time ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.CLMR.${ufs_exp}.${j}.tmp.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.CLMR.${ufs_exp}.${j}.nc
        ncpdq -a lev,time ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ICMR.${ufs_exp}.${j}.tmp.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ICMR.${ufs_exp}.${j}.nc
   
        # tidy a little
        rm ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.rv.${ufs_exp}.${j}.tmp.nc
        rm ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ql.${ufs_exp}.${j}.tmp.nc
        rm ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.qi.${ufs_exp}.${j}.tmp.nc
        rm ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.SPFH.${ufs_exp}.${j}.tmp.nc
        rm ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.CLMR.${ufs_exp}.${j}.tmp.nc
        rm ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ICMR.${ufs_exp}.${j}.tmp.nc       

        rm ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.rv.${ufs_exp}.${j}.nc
        rm ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.ql.${ufs_exp}.${j}.nc
        rm ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.qi.${ufs_exp}.${j}.nc
        rm ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.qv_all_r.${ufs_exp}.${j}.nc 
        rm ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.qv_rl_ri.${ufs_exp}.${j}.nc

        rm ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.SPFH.${ufs_exp}.${j}.nc
        # rm ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.CLMR.${ufs_exp}.${j}.nc # needed for theta_l calculation
        rm ${output_dir_nat}/rrfs.t00z.natlev.f006.${i}.ICMR.${ufs_exp}.${j}.nc

    done

# merge all levels
ncrcat ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.rv.${ufs_exp}.*.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.rv.${ufs_exp}.tmp.nc
ncrcat ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ql.${ufs_exp}.*.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ql.${ufs_exp}.tmp.nc
ncrcat ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.qi.${ufs_exp}.*.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.qi.${ufs_exp}.tmp.nc
ncrcat ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.SPFH.${ufs_exp}.*.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.SPFH.${ufs_exp}.tmp.nc
ncrcat ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.CLMR.${ufs_exp}.*.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.CLMR.${ufs_exp}.tmp.nc
ncrcat ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ICMR.${ufs_exp}.*.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ICMR.${ufs_exp}.tmp.nc

# restore time as record dimension
ncpdq -a time,lev ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.rv.${ufs_exp}.tmp.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.rv.${ufs_exp}.nc
ncpdq -a time,lev ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ql.${ufs_exp}.tmp.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ql.${ufs_exp}.nc
ncpdq -a time,lev ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.qi.${ufs_exp}.tmp.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.qi.${ufs_exp}.nc
ncpdq -a time,lev ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.SPFH.${ufs_exp}.tmp.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.SPFH.${ufs_exp}.nc
ncpdq -a time,lev ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.CLMR.${ufs_exp}.tmp.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.CLMR.${ufs_exp}.nc
ncpdq -a time,lev ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ICMR.${ufs_exp}.tmp.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ICMR.${ufs_exp}.nc

# extract desired region
cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.rv.${ufs_exp}.nc ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.rv.${ufs_exp}.${region}.nc
cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ql.${ufs_exp}.nc ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ql.${ufs_exp}.${region}.nc
cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.qi.${ufs_exp}.nc ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.qi.${ufs_exp}.${region}.nc
cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.SPFH.${ufs_exp}.nc ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.SPFH.${ufs_exp}.${region}.nc
cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.CLMR.${ufs_exp}.nc ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.CLMR.${ufs_exp}.${region}.nc
cdo -sellonlatbox,${minlon},${maxlon},${minlat},${maxlat} ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ICMR.${ufs_exp}.nc ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ICMR.${ufs_exp}.${region}.nc


# And compute r_t for completeness (linearity holds)
cdo merge ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.rv.${ufs_exp}.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.CLMR.${ufs_exp}.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ICMR.${ufs_exp}.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.all_r.${ufs_exp}.nc
cdo -expr,'rt=rv+clwmr+icmr' ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.all_r.${ufs_exp}.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.rt.${ufs_exp}.nc
rm -r ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.all_r.${ufs_exp}.nc 

cdo merge ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.rv.${ufs_exp}.${region}.nc ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.CLMR.${ufs_exp}.${region}.nc ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ICMR.${ufs_exp}.${region}.nc ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.all_r.${ufs_exp}.${region}.nc
cdo -expr,'rt=rv+clwmr+icmr' ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.all_r.${ufs_exp}.${region}.nc ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.rt.${ufs_exp}.${region}.nc
rm -r ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.all_r.${ufs_exp}.${region}.nc


# compute q_t
cdo merge ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.SPFH.${ufs_exp}.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ql.${ufs_exp}.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.qi.${ufs_exp}.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.all_q.${ufs_exp}.nc
cdo -expr,'qt=q+ql+qi' ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.all_q.${ufs_exp}.nc ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.qt.${ufs_exp}.nc
rm -r ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.all_q.${ufs_exp}.nc


cdo merge ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.SPFH.${ufs_exp}.${region}.nc ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ql.${ufs_exp}.${region}.nc ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.qi.${ufs_exp}.${region}.nc ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.all_q.${ufs_exp}.${region}.nc
cdo -expr,'qt=q+ql+qi' ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.all_q.${ufs_exp}.${region}.nc ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.qt.${ufs_exp}.${region}.nc
rm -r ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.all_q.${ufs_exp}.${region}.nc

# tidy: delete individual level files
# rm ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.rv.${ufs_exp}.*.nc
# rm ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.rv.${ufs_exp}.${region}.*.nc

rm ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ql.${ufs_exp}.*.nc
rm ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ql.${ufs_exp}.${region}.*.nc 

rm ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.qi.${ufs_exp}.*.nc
rm ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.qi.${ufs_exp}.${region}.*.nc

rm ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.SPFH.${ufs_exp}.*.nc
rm ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.SPFH.${ufs_exp}.${region}.*.nc

rm ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.CLMR.${ufs_exp}.*.nc
rm ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.CLMR.${ufs_exp}.${region}.*.nc

rm ${output_dir}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ICMR.${ufs_exp}.*.nc
rm ${output_dir}/${region}/rrfs.t00z.natlev.f006.${i}.${resol_target}.ICMR.${ufs_exp}.${region}.*.nc 

done

    