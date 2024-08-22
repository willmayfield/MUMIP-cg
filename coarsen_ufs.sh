#!/bin/bash
#! /bin/bash
#SBATCH --job-name=coarse_grain_ufs    # Specify job name
#SBATCH --partition=hera    # Specify partition name
#SBATCH --ntasks=1             # Specify max. number of tasks to be invoked
#SBATCH --mem-per-cpu=8000     # Specify real memory required per CPU in MegaBytes
#SBATCH --time=01:59:00        # Set a limit on the total run time
#SBATCH --mail-type=FAIL       # Notify user by email in case of job failure
#SBATCH --account=wrfruc       # Charge resources on this project account
#SBATCH --output=out.cg_UFS    # File name for standard output
#SBATCH --error=err.cg_UFS    # File name for standard error output
module load gnu
module load intel/2023.2.0
module load netcdf/4.7.0
module load wgrib2
module load ncl

# Define the file path
file="coarsen_ufs_t"

# Define the start and end dates
start_date="20160812"
end_date="20160821"

# Convert start and end dates to UNIX timestamps for easier comparison
start_timestamp=$(date -d "$start_date" +"%s")
end_timestamp=$(date -d "$end_date" +"%s")

# Loop through each day within the specified range
current_timestamp=$start_timestamp
while [ $current_timestamp -le $end_timestamp ]; do
    # Convert the current timestamp back to date format
    current_date=$(date -d "@$current_timestamp" +"%Y%m%d")
    # Loop through the hours from 0 to 7 with a step of 1
    for ((idx=0; idx<=7; idx+=1)); do
        # Replace the strings in the file
        cp -r $file.ncl ./ncls/${file}_${current_date}_$idx.ncl
        sed -i "s/YYYYMMDD/${current_date}/g" "./ncls/${file}_${current_date}_$idx.ncl"
        sed -i "s/TIME_IDX/$idx/g" "./ncls/${file}_${current_date}_$idx.ncl"
        ncl ./ncls/"${file}_${current_date}_$idx.ncl"
    done
    
    # Move to the next day
    current_timestamp=$((current_timestamp + 86400))  # 86400 seconds in a day
done
