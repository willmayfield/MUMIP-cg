# README.txt

Original Author: Hannah Christensen, 5 September 2022
Revised by: Xia Sun, Sep 12, 2023

===

Two different scripts need to be run to pre-process UFS LAM data ready for coarse graining

proc_UFS.ksh

- this coarse grains the main 3D variables of state together with assorted 2D driving 
  and diagnostic fields

===

Two further scripts are provided. These two scripts compute additional variables 
"accurately" (i.e. on the fine grid).

These two scripts must be run if the following flags are set 'true' in coarsen_ufs_manyt.ncl
 flag_accurate_r      = True
 flag_accurate_thetal = True


proc_UFS_derived.ksh

- this computes mixing ratios (rv, ql, qi, qt, and rt) on the fine resolution UFS LAM grid before 
  coarse-graining to the desired resolution

proc_UFS_derived_2.ksh

- as for proc_UFS_derived.ksh, except it computes theta and theta_l.
- proc_UFS_derived_2.ksh assumes proc_UFS_derived.ksh has been run first, as some files
  are re-used