README.txt

Hannah Christensen, 5 September 2022

NCL files to produce DEPHY-standard SCM input for the MUMIP project

====

Changes for v2.0
- bug removed in surface fields:
       These fields were saved in DYAMOND every 15 min not every 3 hr 
       so have a different time coordinate to the other variables.
       Correction made in preprocessing scripts and safety flag added 
       to check time coordinate in func_read_hires.ncl

- all variables saved as floats not double
       Changes made in func_advtend.ncl and func_grostrophic.ncl


====

Version 1.0
- perform initial coarsening using cdo
- consider small region over Indian Ocean
- only first few timesteps
- resultant files not yet tested on SCM


