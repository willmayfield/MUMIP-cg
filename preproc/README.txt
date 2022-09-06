# README.txt

5 September 2022

Hannah Christensen

===

Two different scripts need to be re-run to pre-process ICON data ready for coarse graining

proc_ICON.ksh

- this coarse grains the main 3D variables of state together with assorted 2D driving 
  and diagnostic fields

proc_ICON_theta.ksh

- this computes theta (potential temperature) on the fine resolution ICON grid before 
  coarse-graining to the desired resolution

===

Two further scripts are provided. These two scripts compute additional variables 
"accurately" (i.e. on the fine grid).

These two scripts must be run if the following flags are set 'true' in coarsen_icon_manyt.ncl
 flag_accurate_r      = True
 flag_accurate_thetal = True


proc_ICON_derived.ksh

- this computes mixing ratios (rv, rl, ri, rt) on the fine resolution ICON grid before 
  coarse-graining to the desired resolution

proc_ICON_derived_2.ksh

- as for proc_ICON_derived.ksh, except it computes theta and theta_l.
- proc_ICON_derived_2.ksh assumes proc_ICON_derived.ksh has been run first, as some files
  are re-used




