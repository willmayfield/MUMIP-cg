; coarsen_icon_manyt.ncl

;================================================================================
;   Copyright 2021 Hannah M. Christensen
;
;   Licensed under the Apache License, Version 2.0 (the "License");
;   you may not use this file except in compliance with the License.
;   You may obtain a copy of the License at
;
;       http://www.apache.org/licenses/LICENSE-2.0
;
;   Unless required by applicable law or agreed to in writing, software
;   distributed under the License is distributed on an "AS IS" BASIS,
;   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;   See the License for the specific language governing permissions and
;   limitations under the License.
;================================================================================


load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_code.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/contributed.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/esmf/ESMF_regridding.ncl"
load "func_read_hires.ncl"
load "func_coords_in.ncl"
load "func_reduce_area.ncl"
load "add_to_file.ncl"
load "func_advection.ncl"
load "func_advtend.ncl"
load "func_geostrophic.ncl"


begin

  ;===================================;
  ; check input information from CLI  ;
  ;===================================;

    if (.not. isdefined("datein") .or. \
        .not. isdefined("hourin")) then
      print("usage: ncl coarsen_icon_manyt.ncl datein=yyyymmdd hourin=i")
      exit()
    end if

    if ((hourin .ne. 0) .and. (hourin .ne. 1) .and. (hourin .ne. 2) .and. (hourin .ne. 3) \
                        .and. (hourin .ne. 4) .and. (hourin .ne. 5) .and. (hourin .ne. 6) \
                        .and. (hourin .ne. 7)    ) then
      print("error: hourin must be integer between 0 and 7")
      exit()
    end if

  ;=======================================================
  ; User defined variables


  ;===================================;
  ; define coarsening resolution      ;
  ;===================================;

   ; define coarse graining resolution / degrees
   CG_resol = "0.2"
   
   ; define expected temporal resolution files in hours
   t_step_in = 3

  ;===================================;
  ; define temporal interpolation     ;
  ;===================================;

    t_step_out = t_step_in*60*60       ; in seconds.  Ensure integer.
    flag_interp_time   = False             ; for DEPHY, we will not perform interpolation

  ;===================================;
  ; define optional smoothing         ;
  ;===================================;

    flag_smooth = True

  ;====================================;
  ; define optional land interpolation ;
  ; - sets land points to Nan          ;
  ;  and interp from neighbouring sea  ;
  ;====================================;

    flag_land = True

  ;===================================;
  ; select subset data for testing    ;
  ;===================================;

;; cascade domain:
    region = "IO"
    set_lat_min = -35.0
    set_lat_max =   5.0
    set_lon_min =  51.0
    set_lon_max =  95.0

    flag_subset = True

  ;===================================;
  ; define code version               ;
  ;===================================;

  version = "v1.0"

  ;===================================;
  ; define paths to input variables   ;
  ;===================================;

    generic_path     = "/scratch/b/b381215/CG/"
;;    timestep_path    = (/ 20160811 , 20160811 , 20160811 , 20160811 , 20160811 , 20160811 , 20160811 , 20160811/) ; time in file name
;;    timestep_idx     = (/        0 ,        1 ,        2 ,        3 ,        4 ,        5 ,        6 ,        7 /) ; time idx in file
    timestep_path = (/ datein /)
    timestep_idx  = (/ hourin /)
    time_ref         = todouble(2016080100)      ; all times ref to this time
    filename         = "nwp_R2B10_lkm1007_"
    n_time_in = dimsizes(timestep_path)

  ;===================================;
  ; define paths to output files      ;
  ;===================================;

    path_out     = "/scratch/b/b381215/CG/SCM_in/"          ; Output directory
;;    file_out_tmp = (/filename, \
;;                     CG_resol,"_",\
;;                     tostring(timestep_path(0)),".",tostring(t_step_in*timestep_idx(0)),"-",\
;;                     tostring(timestep_path(n_time_in-1)),".",tostring(t_step_in*timestep_idx(n_time_in-1)),\
;;                     ".nc"/)                                                   ; Output file name
    file_out_tmp = (/"mumip_icon2.5_",region,"_",CG_resol,"_",\
                     tostring(timestep_path),".",tostring(t_step_in*timestep_idx),"_",version,".nc"/) 
    file_out = str_concat(file_out_tmp)
    delete([/file_out_tmp/])

  ;================================================;
  ; Read in input co-ordinates (high-res)           ;
  ;================================================;

    filetype = "atm_3d"
    variable = "pres"

    coords_in = func_coords_in(generic_path,timestep_path,timestep_idx,time_ref,filename,filetype,variable,CG_resol,region)
    lon_in    = coords_in[0]
    lat_in    = coords_in[1]
    lev_in_tmp   = coords_in[2]  ; level index
    time_in   = coords_in[3]

    n_lon_in    = dimsizes(lon_in)
    n_lat_in    = dimsizes(lat_in)
    n_lev_in    = dimsizes(lev_in_tmp)

    ;==============================
    print("read in static height, orography, and lsm")

    data_path_matr = (/generic_path,CG_resol,"/",region,"/dyamond_R2B10_lkm1007_",CG_resol,"_vgrid_",region,".nc"/)
    data_path      = str_concat(data_path_matr)

    ; Input variable dimensions: (time, latitude, longitude) ;
    in_file        = addfile(data_path,"r")
    lev_data_tmp   = in_file->HHL(0,:,:,:)
    height_data_tmp = lev_data_tmp
    lsm_data_tmp   = in_file->FR_LAND(0,:,:)
    zorog_data_tmp = in_file->HSURF(0,:,:)
    z0_data_tmp    = in_file->Z0(0,:,:)

    ; select a height profile characteristic of a sea point
    ; HMC! if we move to consider land points, will need to edit this
    do j=0,n_lon_in-1
      do i=0,n_lat_in-1
        if (lsm_data_tmp(i,j).eq.0).and.(zorog_data_tmp(i,j).eq.0) then
           ; use me for height coordinate
           levh_in_tmp = lev_data_tmp(:,i,j)
           break_me = True
           break
           print(j)
        end if
      end do
      if break_me then
        break
      end if
      print(i)
    end do

    delete_VarAtts(levh_in_tmp,(/"lat","lon"/))
    n_levh_in_tmp = dimsizes(levh_in_tmp)

    ; compute full levels from half levels: https://www.dwd.de/DWD/forschung/nwv/fepub/icon_database_main.pdf p115
    levf_in_tmp = 0.5*(levh_in_tmp(0:n_levh_in_tmp-2)+levh_in_tmp(1:n_levh_in_tmp-1))
    n_levf_in_tmp = dimsizes(levf_in_tmp)
    height_data_tmpf = 0.5*(height_data_tmp(0:n_levh_in_tmp-2,:,:)+height_data_tmp(1:n_levh_in_tmp-1,:,:))

    ; just select required levels (height file generic - all 91 levels)
    levh_in        = levh_in_tmp(n_levh_in_tmp-(n_lev_in+1):n_levh_in_tmp-1)
    levf_in        = levf_in_tmp(n_levf_in_tmp-n_lev_in:n_levf_in_tmp-1)
    height_data_in = height_data_tmpf(n_levf_in_tmp-n_lev_in:n_levf_in_tmp-1,:,:)

    ; follow dephy protocol for vertical coordinate
    levh_in!0 = "lev"
    levh_in&lev = levh_in
    levh_in@units = "m"
    levh_in@long_name = "altitude"

    levf_in!0 = "lev"
    levf_in&lev = levf_in
    levf_in@units = "m"
    levf_in@long_name = "altitude"

    delete([/lev_data_tmp,levh_in_tmp,levf_in_tmp,n_levh_in_tmp,n_levf_in_tmp,lev_in_tmp,i,j,break_me/])

    ; height variable (same as lev, but spatially varying)
    height_data_in!0 = "lev"
    height_data_in&lev = levf_in
    height_data_in@units = "m"
    height_data_in@long_name = "altitude"

    height_data_in!1 = "lat"
    height_data_in&lat = lat_in
    height_data_in!2 = "lon"
    height_data_in&lon = lon_in

  ;================================================;
  ; Erase land if required                         ;
  ;================================================;

    height_data_in@_FillValue = default_fillvalue("float")
    lsm_data_tmp@_FillValue   = default_fillvalue("float")
    zorog_data_tmp@_FillValue = default_fillvalue("float")
    z0_data_tmp@_FillValue    = default_fillvalue("float")

    if (flag_land) then
      ; any point where zorog ~= 0 exactly has some land
      tol = 10^(-12)
      land2d = zorog_data_tmp+lsm_data_tmp
      land3d = conform(height_data_in,land2d,(/1,2/))

      lsm_data_out    = where(land2d.ge.tol,lsm_data_tmp@_FillValue  ,lsm_data_tmp)
      height_data_out1 = where(land3d.ge.tol,height_data_in@_FillValue,height_data_in)
      zorog_data_out  = where(land2d.ge.tol,zorog_data_tmp@_FillValue,zorog_data_tmp)
      z0_data_out     = where(land2d.ge.tol,z0_data_tmp@_FillValue   ,z0_data_tmp) 

      copy_VarCoords(lsm_data_tmp,lsm_data_out)
      copy_VarAtts(  lsm_data_tmp,lsm_data_out)
      copy_VarCoords(height_data_in,height_data_out1)
      copy_VarAtts(  height_data_in,height_data_out1)
      copy_VarCoords(zorog_data_tmp,zorog_data_out)
      copy_VarAtts(  zorog_data_tmp,zorog_data_out)
      copy_VarCoords(z0_data_tmp,z0_data_out)
      copy_VarAtts(  z0_data_tmp,z0_data_out)

      ;======================
      ; use poisson grid fill to smoothly fill in missing values
      is_cyclic  = False     ; not cyclic data
      guess_type = 1         ; start with zonal means
      nscan      = 200       ; no. iterations
      eps        = 1.e-6     ; tolerance
      relc       = 0.6       ; relaxation const
      opt        = 0         ; dummy

      poisson_grid_fill(lsm_data_out    ,is_cyclic,guess_type,nscan,eps,relc,opt)
      poisson_grid_fill(height_data_out1,is_cyclic,guess_type,nscan,eps,relc,opt)
      poisson_grid_fill(zorog_data_out  ,is_cyclic,guess_type,nscan,eps,relc,opt)
      poisson_grid_fill(z0_data_out     ,is_cyclic,guess_type,nscan,eps,relc,opt)

      ;= create new variable to indicate where we have interpolated
      land_mask    = where(land2d.ge.tol,lsm_data_tmp@_FillValue  ,lsm_data_tmp)
      copy_VarCoords(lsm_data_tmp,land_mask)
      copy_VarAtts(  lsm_data_tmp,land_mask)
      land_mask@long_name = "Land erased if Fill Value"

    else

      lsm_data_out    = lsm_data_tmp
      height_data_out1 = height_data_in
      zorog_data_out  = zorog_data_tmp
      z0_data_out     = z0_data_tmp

      land_mask = lsm_data_out
      land_mask@long_name = "Land erased if Fill Value"

    end if

    delete([/lsm_data_tmp,height_data_in,zorog_data_tmp,z0_data_tmp,land3d/])

  ;================================================;
  ; Define output co-ordinates (low-res)           ;
  ;================================================;

  ; we will perform no horizontal regridding, but we do subset the data
  ; we will perform NO VERTICAL INTERPOLATION but leave on native grid.
    flag_interp_lev = False

    lat_out = lat_in({set_lat_min:set_lat_max})
    lon_out = lon_in({set_lon_min:set_lon_max})

    n_lon_out    = dimsizes(lon_out)
    n_lat_out    = dimsizes(lat_out)

    ; lev out = full levels input variables
    if (.not.flag_interp_lev) then
        lev_out = levf_in
        n_lev_out = n_lev_in
        height_data_out = height_data_out1
    else
       print("Error! assuming no vertical interpolation required")
    end if

    if (.not.flag_interp_time) then
       time_out   = time_in
       n_time_out = n_time_in
    else
       print("Error! assuming no temporal interpolation required")
    end if 


;;===============
;;  dummy arrays for output.
    array_4d_out = new((/n_time_out,n_lev_out,n_lat_out,n_lon_out/),float)
    array_4d_out!0 = "time"
    array_4d_out!1 = "lev"
    array_4d_out!2 = "lat"
    array_4d_out!3 = "lon"
    array_4d_out&time = time_out
    array_4d_out&lev  = lev_out
    array_4d_out&lat    = lat_out
    array_4d_out&lon    = lon_out

    array_4dh_out = new((/n_time_out,n_lev_out+1,n_lat_out,n_lon_out/),float)
    array_4dh_out!0 = "time"
    array_4dh_out!1 = "lev"
    array_4dh_out!2 = "lat"
    array_4dh_out!3 = "lon"
    array_4dh_out&time = time_out
    array_4dh_out&lev  = levh_in
    array_4dh_out&lat  = lat_out
    array_4dh_out&lon  = lon_out

    array_3d_out = new((/n_time_out,n_lat_out,n_lon_out/),float)
    array_3d_out!0 = "time"
    array_3d_out!1 = "lat"
    array_3d_out!2 = "lon"
    array_3d_out&time   = time_out
    array_3d_out&lat    = lat_out
    array_3d_out&lon    = lon_out

  ;=================================================================;
  ; SET UP SAVING DATA TO NCL FILE                                  ;

    print("=========================================")
    print(" **  OPEN NCL FILE AND DEFINE CO-ORDS ** ")
    print("=========================================")

  ;===================================================================
  ; Define dimensions of variables
  ;

    system("/bin/rm -f " + path_out + file_out)    ; remove if exists
    fout  = addfile (path_out + file_out, "c")  ; open output file - create

;    fout  = addfile (path_out + file_out, "w")  ; open output file - read and write

  ;===================================================================
  ; explicitly declare file definition mode. Improve efficiency.

    setfileoption(fout,"DefineMode",True)

;  ;===================================================================
;  ; create global attributes of the file
;
;    fAtt               = True            ; assign file attributes
;    fAtt@title         = "SCM input file derived from DYAMOND summer ICON 2.5 km simulation"
;    fAtt@Conventions   = "None"
;    fAtt@creation_date = systemfunc ("date")
;    fileattdef( fout, fAtt )            ; copy file attributes
;
  ;===================================================================
  ; predefine the coordinate variables and their dimensionality
  ; Note: to get an UNLIMITED record dimension, we set the dimensionality
  ; to -1 (or the actual size) and set the dimension name to True.

    dimNames = (/"time",      "lat",      "lon",     "lev"/)
    dimSizes = (/ -1   ,  n_lat_out,  n_lon_out, n_lev_out/)
    dimUnlim = (/ True ,      False,      False,     False/)
    filedimdef(fout,dimNames,dimSizes,dimUnlim)

  ;===================================================================
  ; start writing to file

    add_to_file(fout,time_out             ,"time")
    add_to_file(fout,lev_out              ,"lev")
    add_to_file(fout,lat_out              ,"lat")
    add_to_file(fout,lon_out              ,"lon")
    add_to_file(fout,height_data_out      ,"height_t")
    add_to_file(fout,lsm_data_out         ,"lsm")
    add_to_file(fout,zorog_data_out       ,"zorog")
    add_to_file(fout,z0_data_out          ,"z0")
    add_to_file(fout,land_mask            ,"land_erase_flag")
;    add_to_file(fout,date                 , "date")
;    add_to_file(fout,second               , "second")

    ;=============================================================
    delete([/file_out,path_out/])
    delete([/dimNames,dimSizes,dimUnlim/])

  ;==================================================================================
  ; param 1. pressure

    print("pressure calculation")

    filetype = "atm_3d"
    variable_file = "pres"  ; name of file
    variable_name = "P"     ; name in file

    ; initialise: time, lev, lat, lon
    pres_data_out = array_4d_out

    ; loop over vertical levels
    do lev_count = 0,n_lev_in-1
      pres_tmp = func_read_hires(generic_path,timestep_path,timestep_idx,time_in,filename,filetype,variable_file,variable_name,CG_resol,region,lev_count)
      pres_data_out(time|:,lev|lev_count,lat|:,lon|:) = func_reduce_area(pres_tmp,flag_subset,set_lat_min,set_lat_max,set_lon_min,set_lon_max,3)
      delete([/pres_tmp/])
    end do

    ; vertical coordinate. already on full levels

    ; Erase land if required ===========================;
    pres_data_out@_FillValue = default_fillvalue("float")
    if (flag_land) then

      land4d = conform(pres_data_out,land2d,(/2,3/))
      pres_data_out_lf = where(land4d.ge.tol,pres_data_out@_FillValue,pres_data_out)

      copy_VarCoords(pres_data_out,pres_data_out_lf)
      copy_VarAtts(  pres_data_out,pres_data_out_lf)

      poisson_grid_fill(pres_data_out_lf,is_cyclic,guess_type,nscan,eps,relc,opt)

      delete([/pres_data_out/])
      pres_data_out = pres_data_out_lf
      delete([/pres_data_out_lf,land4d/])

    end if

    ; smooth data to remove unresolved features
    if flag_smooth then
       pres_data_out_sm = smth9_Wrap(pres_data_out,0.5,0.25,False)
       delete([/pres_data_out/])
       pres_data_out = pres_data_out_sm
       delete([/pres_data_out_sm/])
    end if

    delete_VarAtts(pres_data_out,(/"param","time","height"/))
    add_to_file(fout,pres_data_out,"pressure_t")

    delete([/variable_file,variable_name,pres_data_out/])


  ;==================================================================================
  ; param 2. temperature

    print("temperature calculation")

    filetype = "atm_3d"
    variable_file = "t"  ; name of file
    variable_name = "T"     ; name in file

    ; initialise: time, lev, lat, lon
    t_data_out = array_4d_out

    ; loop over vertical levels
    do lev_count = 0,n_lev_in-1
      t_tmp = func_read_hires(generic_path,timestep_path,timestep_idx,time_in,filename,filetype,variable_file,variable_name,CG_resol,region,lev_count)
      t_data_out(time|:,lev|lev_count,lat|:,lon|:) = func_reduce_area(t_tmp,flag_subset,set_lat_min,set_lat_max,set_lon_min,set_lon_max,3)
      delete([/t_tmp/])
    end do

    ; vertical coordinate. already on full levels

    ; Erase land if required ===========================;
    t_data_out@_FillValue = default_fillvalue("float")
    if (flag_land) then

      land4d = conform(t_data_out,land2d,(/2,3/))
      t_data_out_lf = where(land4d.ge.tol,t_data_out@_FillValue,t_data_out)

      copy_VarCoords(t_data_out,t_data_out_lf)
      copy_VarAtts(  t_data_out,t_data_out_lf)

      poisson_grid_fill(t_data_out_lf,is_cyclic,guess_type,nscan,eps,relc,opt)

      delete([/t_data_out/])
      t_data_out = t_data_out_lf
      delete([/t_data_out_lf,land4d/])

    end if

    ; smooth data to remove unresolved features
    if flag_smooth then
       t_data_out_sm = smth9_Wrap(t_data_out,0.5,0.25,False)
       delete([/t_data_out/])
       t_data_out = t_data_out_sm
       delete([/t_data_out_sm/])
    end if

    delete_VarAtts(t_data_out,(/"param","standard_name","time","height"/))
    add_to_file(fout,t_data_out,"temp_t")

    delete([/variable_file,variable_name,t_data_out/])

  ;==================================================================================
  ; param 3. theta

    print("theta calculation")

    filetype = "atm_3d"
    variable_file = "theta"  ; name of file
    variable_name = "theta"     ; name in file

    ; initialise: time, lev, lat, lon
    theta_data_out = array_4d_out

    ; loop over vertical levels
    do lev_count = 0,n_lev_in-1
      theta_tmp = func_read_hires(generic_path,timestep_path,timestep_idx,time_in,filename,filetype,variable_file,variable_name,CG_resol,region,lev_count)
      theta_data_out(time|:,lev|lev_count,lat|:,lon|:) = func_reduce_area(theta_tmp,flag_subset,set_lat_min,set_lat_max,set_lon_min,set_lon_max,3)
      delete([/theta_tmp/])
    end do

    ; vertical coordinate. already on full levels

    ; Erase land if required ===========================;
    theta_data_out@_FillValue = default_fillvalue("float")
    if (flag_land) then

      land4d = conform(theta_data_out,land2d,(/2,3/))
      theta_data_out_lf = where(land4d.ge.tol,theta_data_out@_FillValue,theta_data_out)

      copy_VarCoords(theta_data_out,theta_data_out_lf)
      copy_VarAtts(  theta_data_out,theta_data_out_lf)

      poisson_grid_fill(theta_data_out_lf,is_cyclic,guess_type,nscan,eps,relc,opt)

      delete([/theta_data_out/])
      theta_data_out = theta_data_out_lf
      delete([/theta_data_out_lf,land4d/])

    end if

    ; smooth data to remove unresolved features
    if flag_smooth then
       theta_data_out_sm = smth9_Wrap(theta_data_out,0.5,0.25,False)
       delete([/theta_data_out/])
       theta_data_out = theta_data_out_sm
       delete([/theta_data_out_sm/])
    end if

    delete_VarAtts(theta_data_out,(/"time","height"/))
    theta_data_out@long_name="Potential temperature"
    theta_data_out@units="K"
    add_to_file(fout,theta_data_out,"theta_t")

    delete([/variable_file,variable_name,theta_data_out/])

  ;==================================================================================
  ; param 4. vertical velocity

    print("vertical velocity calculation")

    filetype = "atm_3d"
    variable_file = "w"  ; name of file
    variable_name = "W"     ; name in file

    ; initialise: time, lev, lat, lon
    wh_data_out = array_4dh_out

    ; loop over vertical half levels
    do lev_count = 0,n_lev_in
      w_tmp = func_read_hires(generic_path,timestep_path,timestep_idx,time_in,filename,filetype,variable_file,variable_name,CG_resol,region,lev_count)
      wh_data_out(time|:,lev|lev_count,lat|:,lon|:) = func_reduce_area(w_tmp,flag_subset,set_lat_min,set_lat_max,set_lon_min,set_lon_max,3)
      delete([/w_tmp/])
    end do

    ; vertical coordinate. on half levels. Interpolate to full levelsS
    w_data_out=0.5*(wh_data_out(:,0:n_lev_in-1,:,:)+wh_data_out(:,1:n_lev_in,:,:))
    copy_VarCoords(array_4d_out,w_data_out)
    w_data_out@long_name="Vertical Velocity (w)"
    w_data_out@units="m s-1"

    ; Erase land if required ===========================;
    w_data_out@_FillValue = default_fillvalue("float")
    if (flag_land) then

      land4d = conform(w_data_out,land2d,(/2,3/))
      w_data_out_lf = where(land4d.ge.tol,w_data_out@_FillValue,w_data_out)

      copy_VarCoords(w_data_out,w_data_out_lf)
      copy_VarAtts(  w_data_out,w_data_out_lf)

      poisson_grid_fill(w_data_out_lf,is_cyclic,guess_type,nscan,eps,relc,opt)

      delete([/w_data_out/])
      w_data_out = w_data_out_lf
      delete([/w_data_out_lf,land4d/])

    end if


    ; smooth data to remove unresolved features
    if flag_smooth then
       w_data_out_sm = smth9_Wrap(w_data_out,0.5,0.25,False)
       delete([/w_data_out/])
       w_data_out = w_data_out_sm
       delete([/w_data_out_sm/])
    end if

    add_to_file(fout,w_data_out,"w")

    delete([/variable_file,variable_name,wh_data_out,w_data_out/])

 ;==================================================================================
  ; param 4b. vertical pressure velocity

    print("HMC to do! omega = vertical pressure velocity calculation")

    ; now this parameter we need to compute from the ICON data.
    ; but the problem is we need to compute it from high resolution data
    ; before coarse graining for a more accurate estimate

    ; need high resolution w, pressure and t data

    ; the NCL function w_to_omega makes the hydrostatic approximation which is likely not good enough in our case
    ; so if this is needed, we'll have to compute it from definition of omega:
    ; omega = Dp/Dt = partial dp/dt + u.grad p   (last term in 3D)


  ;==================================================================================
  ; param 5. horizontal winds

    print("U wind calculation")

    filetype = "atm_3d"
    variable_file = "u"  ; name of file
    variable_name = "U"     ; name in file

    ; initialise: time, lev, lat, lon
    u_data_out = array_4d_out

    ; loop over vertical levels
    do lev_count = 0,n_lev_in-1
      u_tmp = func_read_hires(generic_path,timestep_path,timestep_idx,time_in,filename,filetype,variable_file,variable_name,CG_resol,region,lev_count)
      u_data_out(time|:,lev|lev_count,lat|:,lon|:) = func_reduce_area(u_tmp,flag_subset,set_lat_min,set_lat_max,set_lon_min,set_lon_max,3)
      delete([/u_tmp/])
    end do

    ; vertical coordinate. already on full levels

    ; Erase land if required ===========================;
    u_data_out@_FillValue = default_fillvalue("float")
    if (flag_land) then

      land4d = conform(u_data_out,land2d,(/2,3/))
      u_data_out_lf = where(land4d.ge.tol,u_data_out@_FillValue,u_data_out)

      copy_VarCoords(u_data_out,u_data_out_lf)
      copy_VarAtts(  u_data_out,u_data_out_lf)

      poisson_grid_fill(u_data_out_lf,is_cyclic,guess_type,nscan,eps,relc,opt)

      delete([/u_data_out/])
      u_data_out = u_data_out_lf
      delete([/u_data_out_lf,land4d/])

    end if


    ; smooth data to remove unresolved features
    if flag_smooth then
       u_data_out_sm = smth9_Wrap(u_data_out,0.5,0.25,False)
       delete([/u_data_out/])
       u_data_out = u_data_out_sm
       delete([/u_data_out_sm/])
    end if

    u_data_out@long_name = "Zonal wind"
    delete_VarAtts(u_data_out,(/"param","standard_name","time","height"/))
    add_to_file(fout,u_data_out,"u_t")

    delete([/variable_file,variable_name,u_data_out/])

    ;=====
    print("V wind calculation")

    filetype = "atm_3d"
    variable_file = "v"  ; name of file
    variable_name = "V"     ; name in file

    ; initialise: time, lev, lat, lon
    v_data_out = array_4d_out

    ; loop over vertical levels
    do lev_count = 0,n_lev_in-1
      v_tmp = func_read_hires(generic_path,timestep_path,timestep_idx,time_in,filename,filetype,variable_file,variable_name,CG_resol,region,lev_count)
      v_data_out(time|:,lev|lev_count,lat|:,lon|:) = func_reduce_area(v_tmp,flag_subset,set_lat_min,set_lat_max,set_lon_min,set_lon_max,3)
      delete([/v_tmp/])
    end do

    ; vertical coordinate. already on full levels

    ; Erase land if required ===========================;
    v_data_out@_FillValue = default_fillvalue("float")
    if (flag_land) then

      land4d = conform(v_data_out,land2d,(/2,3/))
      v_data_out_lf = where(land4d.ge.tol,v_data_out@_FillValue,v_data_out)

      copy_VarCoords(v_data_out,v_data_out_lf)
      copy_VarAtts(  v_data_out,v_data_out_lf)

      poisson_grid_fill(v_data_out_lf,is_cyclic,guess_type,nscan,eps,relc,opt)

      delete([/v_data_out/])
      v_data_out = v_data_out_lf
      delete([/v_data_out_lf,land4d/])

    end if


    ; smooth data to remove unresolved features
    if flag_smooth then
       v_data_out_sm = smth9_Wrap(v_data_out,0.5,0.25,False)
       delete([/v_data_out/])
       v_data_out = v_data_out_sm
       delete([/v_data_out_sm/])
    end if

    v_data_out@long_name="Meridional wind"
    delete_VarAtts(v_data_out,(/"param","standard_name","time","height"/))
    add_to_file(fout,v_data_out,"v_t")

    delete([/variable_file,variable_name,v_data_out/])

  ;==================================================================================
  ; param 6. moisture

    print("q/qi/ql calculation")

  ;  q: specific humidity         = mass of water vapour per unit mass of moist air (dry+vapour+liquid+ice)
  ;  r: water vapour mixing ratio = mass of water vapour per unit mass of dry air

  ; we can read in specific humidity (QV), specific cloud water content (QC_DIA) and specific cloud ice content (QI_DIA)
  ; must calculate qt, rv, rl, ri and rt

  ;==========================
    print("qv calculation")

    filetype = "atm_3d"
    variable_file = "qv"  ; name of file
    variable_name = "QV"     ; name in file

    ; initialise: time, lev, lat, lon
    qv_data_out = array_4d_out

    ; loop over vertical levels
    do lev_count = 0,n_lev_in-1
      qv_tmp = func_read_hires(generic_path,timestep_path,timestep_idx,time_in,filename,filetype,variable_file,variable_name,CG_resol,region,lev_count)
      qv_data_out(time|:,lev|lev_count,lat|:,lon|:) = func_reduce_area(qv_tmp,flag_subset,set_lat_min,set_lat_max,set_lon_min,set_lon_max,3)
      delete([/qv_tmp/])
    end do

    ; Erase land if required ===========================;
    qv_data_out@_FillValue = default_fillvalue("float")
    if (flag_land) then

      land4d = conform(qv_data_out,land2d,(/2,3/))
      qv_data_out_lf = where(land4d.ge.tol,qv_data_out@_FillValue,qv_data_out)

      copy_VarCoords(qv_data_out,qv_data_out_lf)
      copy_VarAtts(  qv_data_out,qv_data_out_lf)

      poisson_grid_fill(qv_data_out_lf,is_cyclic,guess_type,nscan,eps,relc,opt)

      delete([/qv_data_out/])
      qv_data_out = qv_data_out_lf
      delete([/qv_data_out_lf,land4d/])

    end if

    ; smooth data to remove unresolved features
    if flag_smooth then
       qv_data_out_sm = smth9_Wrap(qv_data_out,0.5,0.25,False)
       delete([/qv_data_out/])
       qv_data_out = qv_data_out_sm
       delete([/qv_data_out_sm/])
    end if

    delete_VarAtts(qv_data_out,(/"param","standard_name","time","height"/))

    delete([/variable_file,variable_name/])

  ;==========================
    print("ql calculation")

    filetype = "atm_3d"
    variable_file = "tot_qc_dia"  ; name of file
    variable_name = "QC_DIA"     ; name in file

    ; initialise: time, lev, lat, lon
    ql_data_out = array_4d_out

    ; loop over vertical levels
    do lev_count = 0,n_lev_in-1
      ql_tmp = func_read_hires(generic_path,timestep_path,timestep_idx,time_in,filename,filetype,variable_file,variable_name,CG_resol,region,lev_count)
      ql_data_out(time|:,lev|lev_count,lat|:,lon|:) = func_reduce_area(ql_tmp,flag_subset,set_lat_min,set_lat_max,set_lon_min,set_lon_max,3)
      delete([/ql_tmp/])
    end do

    ; Erase land if required ===========================;
    ql_data_out@_FillValue = default_fillvalue("float")
    if (flag_land) then

      land4d = conform(ql_data_out,land2d,(/2,3/))
      ql_data_out_lf = where(land4d.ge.tol,ql_data_out@_FillValue,ql_data_out)

      copy_VarCoords(ql_data_out,ql_data_out_lf)
      copy_VarAtts(  ql_data_out,ql_data_out_lf)

      poisson_grid_fill(ql_data_out_lf,is_cyclic,guess_type,nscan,eps,relc,opt)

      delete([/ql_data_out/])
      ql_data_out = ql_data_out_lf
      delete([/ql_data_out_lf,land4d/])

    end if


    ; smooth data to remove unresolved features
    if flag_smooth then
       ql_data_out_sm = smth9_Wrap(ql_data_out,0.5,0.25,False)
       delete([/ql_data_out/])
       ql_data_out = ql_data_out_sm
       delete([/ql_data_out_sm/])
    end if

    ql_data_out@long_name="Liquid water content"
    delete_VarAtts(ql_data_out,(/"param","time","height"/))
    delete([/variable_file,variable_name/])

  ;==========================
    print("qi calculation")

    filetype = "atm_3d"
    variable_file = "tot_qi_dia"  ; name of file
    variable_name = "QI_DIA"     ; name in file

    ; initialise: time, lev, lat, lon
    qi_data_out = array_4d_out

    ; loop over vertical levels
    do lev_count = 0,n_lev_in-1
      qi_tmp = func_read_hires(generic_path,timestep_path,timestep_idx,time_in,filename,filetype,variable_file,variable_name,CG_resol,region,lev_count)
      qi_data_out(time|:,lev|lev_count,lat|:,lon|:) = func_reduce_area(qi_tmp,flag_subset,set_lat_min,set_lat_max,set_lon_min,set_lon_max,3)
      delete([/qi_tmp/])
    end do

    ; Erase land if required ===========================;
    qi_data_out@_FillValue = default_fillvalue("float")
    if (flag_land) then

      land4d = conform(qi_data_out,land2d,(/2,3/))
      qi_data_out_lf = where(land4d.ge.tol,qi_data_out@_FillValue,qi_data_out)

      copy_VarCoords(qi_data_out,qi_data_out_lf)
      copy_VarAtts(  qi_data_out,qi_data_out_lf)

      poisson_grid_fill(qi_data_out_lf,is_cyclic,guess_type,nscan,eps,relc,opt)

      delete([/qi_data_out/])
      qi_data_out = qi_data_out_lf
      delete([/qi_data_out_lf,land4d/])

    end if

    ; smooth data to remove unresolved features
    if flag_smooth then
       qi_data_out_sm = smth9_Wrap(qi_data_out,0.5,0.25,False)
       delete([/qi_data_out/])
       qi_data_out = qi_data_out_sm
       delete([/qi_data_out_sm/])
    end if

    qi_data_out@long_name="Ice water content"
    delete_VarAtts(qi_data_out,(/"param","time","height"/))
    delete([/variable_file,variable_name/])

  ;==========================
    print("qt calculation")

    qt_data_out = qv_data_out+ql_data_out+qi_data_out
    copy_VarCoords(qv_data_out,qt_data_out)
    qt_data_out@long_name="Total water content"
    qt_data_out@units="kg kg-1"

    ; vertical coordinate. already on full levels

;  ;==========================
;    print("rv/rl/ri/rt calculation")
;
;    ; deduce specific mass of dry air
;    qd_data = 1 - qt_data_out
;
;    ; convert to m.r.
;    rv_data_out = qv_data_out/qd_data
;    rl_data_out = ql_data_out/qd_data
;    ri_data_out = qi_data_out/qd_data
;    rt_data_out = qt_data_out/qd_data
;
;    copy_VarCoords(qv_data_out,rv_data_out)
;    copy_VarCoords(qv_data_out,rl_data_out)
;    copy_VarCoords(qv_data_out,ri_data_out)
;    copy_VarCoords(qv_data_out,rt_data_out)
;
;    delete([/qd_data/])
;
;    rv_data_out@long_name = "Water vapour mixing ratio"
;    rv_data_out@units     = "kg kg-1"
;    rl_data_out@long_name = "Liquid water mixing ratio"
;    rl_data_out@units     = "kg kg-1"
;    ri_data_out@long_name = "Ice water mixing ratio"
;    ri_data_out@units     = "kg kg-1"
;    rt_data_out@long_name = "Total water mixing ratio"
;    rt_data_out@units     = "kg kg-1"

    add_to_file(fout,qv_data_out,"qv_t")
    add_to_file(fout,ql_data_out,"ql_t")
    add_to_file(fout,qi_data_out,"qi_t")
    add_to_file(fout,qt_data_out,"qt_t")
;    add_to_file(fout,rv_data_out,"rv_t")
;    add_to_file(fout,rl_data_out,"rl_t")
;    add_to_file(fout,ri_data_out,"ri_t")
;    add_to_file(fout,rt_data_out,"rt_t")
    delete([/qv_data_out,ql_data_out,qi_data_out/])
    delete([/qt_data_out/])
;    delete([/rv_data_out,rl_data_out,ri_data_out,rt_data_out/])

  ;==================================================================================
  ; param 7. Advective Tendencies
  ;          Calculate this from the coarse grained T, U, V fields

    func_advtend(fout, "temp_t", "temp_adv",              "Temperature large-scale advection","K s-1")
    func_advtend(fout,"theta_t","theta_adv",    "Potential temperature large-scale advection","K s-1")
    func_advtend(fout,    "u_t",    "u_adv",               "Zonal wind large-scale advection","m s-2")
    func_advtend(fout,    "v_t",    "v_adv",          "Meridional wind large-scale advection","m s-2")
    func_advtend(fout,   "qv_t",   "qv_adv",        "Specific humidity large-scale advection","kg kg-1 s-1")
    func_advtend(fout,   "qt_t",   "qt_adv",      "Total water content large-scale advection","kg kg-1 s-1")
;    func_advtend(fout,   "rv_t",   "rv_adv", "Water vapor mixing ratio large-scale advection","kg kg-1 s-1")
;    func_advtend(fout,   "rt_t",   "rt_adv", "Total water mixing ratio large-scale advection","kg kg-1 s-1")

  ;==================================================================================
  ; param 8. "geostrophic winds" : calculate forcing term from 
  ; pressure gradient and gradient in phi
  ; also computes and returns surface density, for ustar calculation
  ;

  rho_sfc=func_geostrophic(fout)

  ;==================================================================================
  ; param 9. surface sensible heat flux

    print("surface sensible heat flux calculation")

    filetype = "atm2_2d"
    variable_file = "SHFL_S"  ; name of file
    variable_name = "SHFL_S"  ; name in file

    ; initialise: time, lat, lon
    shfl_data_out = array_3d_out

    shfl_tmp = func_read_hires(generic_path,timestep_path,timestep_idx,time_in,filename,filetype,variable_file,variable_name,CG_resol,region,999)
    shfl_data_out(time|:,lat|:,lon|:) = func_reduce_area(shfl_tmp,flag_subset,set_lat_min,set_lat_max,set_lon_min,set_lon_max,3)
    delete([/shfl_tmp/])

    ; DEPHY sign convention: positive upwards
    shfl_data_out = -1.0*shfl_data_out

    ; Erase land if required ===========================;
    shfl_data_out@_FillValue = default_fillvalue("float")
    if (flag_land) then

      land3d = conform(shfl_data_out,land2d,(/1,2/))
      shfl_data_out_lf = where(land3d.ge.tol,shfl_data_out@_FillValue,shfl_data_out)

      copy_VarCoords(shfl_data_out,shfl_data_out_lf)
      copy_VarAtts(  shfl_data_out,shfl_data_out_lf)

      poisson_grid_fill(shfl_data_out_lf,is_cyclic,guess_type,nscan,eps,relc,opt)

      delete([/shfl_data_out/])
      shfl_data_out = shfl_data_out_lf
      delete([/shfl_data_out_lf,land3d/])

    end if

    ; smooth data to remove unresolved features
    if flag_smooth then
       shfl_data_out_sm = smth9_Wrap(shfl_data_out,0.5,0.25,False)
       delete([/shfl_data_out/])
       shfl_data_out = shfl_data_out_sm
       delete([/shfl_data_out_sm/])
    end if

    delete_VarAtts(shfl_data_out,(/"param","time"/))
    shfl_data_out@long_name="Surface sensible heat flux (positive upward)"
    add_to_file(fout,shfl_data_out,"sfc_sens_flx")

    delete([/variable_file,variable_name,shfl_data_out/])

  ;==================================================================================
  ; param 10. surface latent heat flux

    print("surface latent heat flux calculation")

    filetype = "atm2_2d"
    variable_file = "LHFL_S"  ; name of file
    variable_name = "LHFL_S"  ; name in file

    ; initialise: time, lat, lon
    lhfl_data_out = array_3d_out

    lhfl_tmp = func_read_hires(generic_path,timestep_path,timestep_idx,time_in,filename,filetype,variable_file,variable_name,CG_resol,region,999)
    lhfl_data_out(time|:,lat|:,lon|:) = func_reduce_area(lhfl_tmp,flag_subset,set_lat_min,set_lat_max,set_lon_min,set_lon_max,3)
    delete([/lhfl_tmp/])

    ; DEPHY sign convention: positive upwards
    lhfl_data_out = -1.0*lhfl_data_out

   ; Erase land if required ===========================;
    lhfl_data_out@_FillValue = default_fillvalue("float")
    if (flag_land) then

      land3d = conform(lhfl_data_out,land2d,(/1,2/))
      lhfl_data_out_lf = where(land3d.ge.tol,lhfl_data_out@_FillValue,lhfl_data_out)
       
      copy_VarCoords(lhfl_data_out,lhfl_data_out_lf)
      copy_VarAtts(  lhfl_data_out,lhfl_data_out_lf)
    
      poisson_grid_fill(lhfl_data_out_lf,is_cyclic,guess_type,nscan,eps,relc,opt)
    
      delete([/lhfl_data_out/])
      lhfl_data_out = lhfl_data_out_lf
      delete([/lhfl_data_out_lf,land3d/])
    
    end if

    ; smooth data to remove unresolved features
    if flag_smooth then
       lhfl_data_out_sm = smth9_Wrap(lhfl_data_out,0.5,0.25,False)
       delete([/lhfl_data_out/])
       lhfl_data_out = lhfl_data_out_sm
       delete([/lhfl_data_out_sm/])
    end if

    delete_VarAtts(lhfl_data_out,(/"param","time"/))
    lhfl_data_out@long_name="Surface latent heat flux (positive upward)"
    add_to_file(fout,lhfl_data_out,"sfc_lat_flx")

    delete([/variable_file,variable_name,lhfl_data_out/])

  ;==================================================================================
  ; param 11. surface temperature

    print("surface temperature calculation")

    filetype = "atm4_2d"
    variable_file = "T_G"  ; name of file
    variable_name = "T_G"  ; name in file

    ; initialise: time, lat, lon
    t_g_data_out = array_3d_out

    t_g_tmp = func_read_hires(generic_path,timestep_path,timestep_idx,time_in,filename,filetype,variable_file,variable_name,CG_resol,region,999)
    t_g_data_out(time|:,lat|:,lon|:) = func_reduce_area(t_g_tmp,flag_subset,set_lat_min,set_lat_max,set_lon_min,set_lon_max,3)
    delete([/t_g_tmp/])

   ; Erase land if required ===========================;
    t_g_data_out@_FillValue = default_fillvalue("float")
    if (flag_land) then

      land3d = conform(t_g_data_out,land2d,(/1,2/))
      t_g_data_out_lf = where(land3d.ge.tol,t_g_data_out@_FillValue,t_g_data_out)
       
      copy_VarCoords(t_g_data_out,t_g_data_out_lf)
      copy_VarAtts(  t_g_data_out,t_g_data_out_lf)
    
      poisson_grid_fill(t_g_data_out_lf,is_cyclic,guess_type,nscan,eps,relc,opt)
    
      delete([/t_g_data_out/])
      t_g_data_out = t_g_data_out_lf
      delete([/t_g_data_out_lf,land3d/])
    
    end if

    ; smooth data to remove unresolved features
    if flag_smooth then
       t_g_data_out_sm = smth9_Wrap(t_g_data_out,0.5,0.25,False)
       delete([/t_g_data_out/])
       t_g_data_out = t_g_data_out_sm
       delete([/t_g_data_out_sm/])
    end if

    delete_VarAtts(t_g_data_out,(/"param","time"/))
    t_g_data_out@long_name="Surface temperature"
    add_to_file(fout,t_g_data_out,"ts")

    delete([/variable_file,variable_name,t_g_data_out/])

  ;==================================================================================
  ; param 12. surface pressure

    print("surface pressure calculation")

    filetype = "atm2_2d"
    variable_file = "PS"  ; name of file
    variable_name = "PS"  ; name in file

    ; initialise: time, lat, lon
    ps_data_out = array_3d_out

    ps_tmp = func_read_hires(generic_path,timestep_path,timestep_idx,time_in,filename,filetype,variable_file,variable_name,CG_resol,region,999)
    ps_data_out(time|:,lat|:,lon|:) = func_reduce_area(ps_tmp,flag_subset,set_lat_min,set_lat_max,set_lon_min,set_lon_max,3)
    delete([/ps_tmp/])

   ; Erase land if required ===========================;
    ps_data_out@_FillValue = default_fillvalue("float")
    if (flag_land) then

      land3d = conform(ps_data_out,land2d,(/1,2/))
      ps_data_out_lf = where(land3d.ge.tol,ps_data_out@_FillValue,ps_data_out)
       
      copy_VarCoords(ps_data_out,ps_data_out_lf)
      copy_VarAtts(  ps_data_out,ps_data_out_lf)
    
      poisson_grid_fill(ps_data_out_lf,is_cyclic,guess_type,nscan,eps,relc,opt)
    
      delete([/ps_data_out/])
      ps_data_out = ps_data_out_lf
      delete([/ps_data_out_lf,land3d/])
    
    end if

    ; smooth data to remove unresolved features
    if flag_smooth then
       ps_data_out_sm = smth9_Wrap(ps_data_out,0.5,0.25,False)
       delete([/ps_data_out/])
       ps_data_out = ps_data_out_sm
       delete([/ps_data_out_sm/])
    end if

    delete_VarAtts(ps_data_out,(/"param","time"/))
    ps_data_out@long_name="Surface pressure"
    add_to_file(fout,ps_data_out,"ps_t")

    delete([/variable_file,variable_name,ps_data_out/])

  ;==================================================================================
  ; param 13. ustar: surface momentum fluxes
  ; Reference: https://glossary.ametsoc.org/wiki/Momentum_flux

    print("ustar calculation")

    ;;--- u momentum flux
    filetype = "atm4_2d"
    variable_file = "UMFL_S"  ; name of file
    variable_name = "UMFL_S"  ; name in file
  
    ; initialise: time, lat, lon
    umfl_data_out = array_3d_out

    umfl_tmp = func_read_hires(generic_path,timestep_path,timestep_idx,time_in,filename,filetype,variable_file,variable_name,CG_resol,region,999)
    umfl_data_out(time|:,lat|:,lon|:) = func_reduce_area(umfl_tmp,flag_subset,set_lat_min,set_lat_max,set_lon_min,set_lon_max,3)
    delete([/umfl_tmp/])

   ; Erase land if required ===========================;
    umfl_data_out@_FillValue = default_fillvalue("float")
    if (flag_land) then

      land3d = conform(umfl_data_out,land2d,(/1,2/))
      umfl_data_out_lf = where(land3d.ge.tol,umfl_data_out@_FillValue,umfl_data_out)
       
      copy_VarCoords(umfl_data_out,umfl_data_out_lf)
      copy_VarAtts(  umfl_data_out,umfl_data_out_lf)
    
      poisson_grid_fill(umfl_data_out_lf,is_cyclic,guess_type,nscan,eps,relc,opt)
    
      delete([/umfl_data_out/])
      umfl_data_out = umfl_data_out_lf
      delete([/umfl_data_out_lf,land3d/])
    
    end if

    ; smooth data to remove unresolved features
    if flag_smooth then
       umfl_data_out_sm = smth9_Wrap(umfl_data_out,0.5,0.25,False)
       delete([/umfl_data_out/])
       umfl_data_out = umfl_data_out_sm
       delete([/umfl_data_out_sm/])
    end if

    ;;--- v momentum flux
    filetype = "atm4_2d"
    variable_file = "VMFL_S"  ; name of file
    variable_name = "VMFL_S"  ; name in file

    ; initialise: time, lat, lon
    vmfl_data_out = array_3d_out

    vmfl_tmp = func_read_hires(generic_path,timestep_path,timestep_idx,time_in,filename,filetype,variable_file,variable_name,CG_resol,region,999)
    vmfl_data_out(time|:,lat|:,lon|:) = func_reduce_area(vmfl_tmp,flag_subset,set_lat_min,set_lat_max,set_lon_min,set_lon_max,3)
    delete([/vmfl_tmp/])

   ; Erase land if required ===========================;
    vmfl_data_out@_FillValue = default_fillvalue("float")
    if (flag_land) then

      land3d = conform(vmfl_data_out,land2d,(/1,2/))
      vmfl_data_out_lf = where(land3d.ge.tol,vmfl_data_out@_FillValue,vmfl_data_out)
       
      copy_VarCoords(vmfl_data_out,vmfl_data_out_lf)
      copy_VarAtts(  vmfl_data_out,vmfl_data_out_lf)
    
      poisson_grid_fill(vmfl_data_out_lf,is_cyclic,guess_type,nscan,eps,relc,opt)
    
      delete([/vmfl_data_out/])
      vmfl_data_out = vmfl_data_out_lf
      delete([/vmfl_data_out_lf,land3d/])
    
    end if

    ; smooth data to remove unresolved features
    if flag_smooth then
       vmfl_data_out_sm = smth9_Wrap(vmfl_data_out,0.5,0.25,False)
       delete([/vmfl_data_out/])
       vmfl_data_out = vmfl_data_out_sm
       delete([/vmfl_data_out_sm/])
    end if

    ustar2 = sqrt(umfl_data_out^2 + vmfl_data_out^2)/rho_sfc
    ustar  = sqrt(ustar2)

    copy_VarCoords(umfl_data_out,ustar)
    copy_VarAtts(umfl_data_out,ustar)

    delete_VarAtts(ustar,(/"param","time"/))
    ustar@long_name="Surface friction velocity"
    ustar@units="m s-1"
    add_to_file(fout,ustar,"ustar")

    delete([/variable_file,variable_name,umfl_data_out,vmfl_data_out,ustar,ustar2,rho_sfc/])

  ;==================================================================================
  ; Useful fields for verification

    print("assorted fields for verification")

    ;--- cloud cover
    filetype = "atm2_2d"
    variable_file = "CLCT"  ; name of file
    variable_name = "CLCT"  ; name in file

    ; initialise: time, lat, lon
    clct_data_out = array_3d_out

    clct_tmp = func_read_hires(generic_path,timestep_path,timestep_idx,time_in,filename,filetype,variable_file,variable_name,CG_resol,region,999)
    clct_data_out(time|:,lat|:,lon|:) = func_reduce_area(clct_tmp,flag_subset,set_lat_min,set_lat_max,set_lon_min,set_lon_max,3)
    delete([/clct_tmp/])

   ; Erase land if required ===========================;
    clct_data_out@_FillValue = default_fillvalue("float")
    if (flag_land) then

      land3d = conform(clct_data_out,land2d,(/1,2/))
      clct_data_out_lf = where(land3d.ge.tol,clct_data_out@_FillValue,clct_data_out)
       
      copy_VarCoords(clct_data_out,clct_data_out_lf)
      copy_VarAtts(  clct_data_out,clct_data_out_lf)
    
      poisson_grid_fill(clct_data_out_lf,is_cyclic,guess_type,nscan,eps,relc,opt)
    
      delete([/clct_data_out/])
      clct_data_out = clct_data_out_lf
      delete([/clct_data_out_lf,land3d/])
    
    end if

    ; smooth data to remove unresolved features
    if flag_smooth then
       clct_data_out_sm = smth9_Wrap(clct_data_out,0.5,0.25,False)
       delete([/clct_data_out/])
       clct_data_out = clct_data_out_sm
       delete([/clct_data_out_sm/])
    end if

    delete_VarAtts(clct_data_out,(/"param","time"/))
    add_to_file(fout,clct_data_out,"clct")

    delete([/variable_file,variable_name,clct_data_out/])

    ;--- precip
    filetype = "atm2_2d"
    variable_file = "TOT_PREC"  ; name of file
    variable_name = "TOT_PREC"  ; name in file

    ; initialise: time, lat, lon
    tot_prec_data_out = array_3d_out

    tot_prec_tmp = func_read_hires(generic_path,timestep_path,timestep_idx,time_in,filename,filetype,variable_file,variable_name,CG_resol,region,999)
    tot_prec_data_out(time|:,lat|:,lon|:) = func_reduce_area(tot_prec_tmp,flag_subset,set_lat_min,set_lat_max,set_lon_min,set_lon_max,3)
    delete([/tot_prec_tmp/])

   ; Erase land if required ===========================;
    tot_prec_data_out@_FillValue = default_fillvalue("float")
    if (flag_land) then

      land3d = conform(tot_prec_data_out,land2d,(/1,2/))
      tot_prec_data_out_lf = where(land3d.ge.tol,tot_prec_data_out@_FillValue,tot_prec_data_out)
       
      copy_VarCoords(tot_prec_data_out,tot_prec_data_out_lf)
      copy_VarAtts(  tot_prec_data_out,tot_prec_data_out_lf)
    
      poisson_grid_fill(tot_prec_data_out_lf,is_cyclic,guess_type,nscan,eps,relc,opt)
    
      delete([/tot_prec_data_out/])
      tot_prec_data_out = tot_prec_data_out_lf
      delete([/tot_prec_data_out_lf,land3d/])
    
    end if

    ; smooth data to remove unresolved features
    if flag_smooth then
       tot_prec_data_out_sm = smth9_Wrap(tot_prec_data_out,0.5,0.25,False)
       delete([/tot_prec_data_out/])
       tot_prec_data_out = tot_prec_data_out_sm
       delete([/tot_prec_data_out_sm/])
    end if

    delete_VarAtts(tot_prec_data_out,(/"param","time"/))
    add_to_file(fout,tot_prec_data_out,"tot_prec")

    delete([/variable_file,variable_name,tot_prec_data_out/])

    ;--- surface specific humidity
    filetype = "atm4_2d"
    variable_file = "QV_S"  ; name of file
    variable_name = "QV_S"  ; name in file

    ; initialise: time, lat, lon
    qv_s_data_out = array_3d_out

    qv_s_tmp = func_read_hires(generic_path,timestep_path,timestep_idx,time_in,filename,filetype,variable_file,variable_name,CG_resol,region,999)
    qv_s_data_out(time|:,lat|:,lon|:) = func_reduce_area(qv_s_tmp,flag_subset,set_lat_min,set_lat_max,set_lon_min,set_lon_max,3)
    delete([/qv_s_tmp/])

   ; Erase land if required ===========================;
    qv_s_data_out@_FillValue = default_fillvalue("float")
    if (flag_land) then

      land3d = conform(qv_s_data_out,land2d,(/1,2/))
      qv_s_data_out_lf = where(land3d.ge.tol,qv_s_data_out@_FillValue,qv_s_data_out)
       
      copy_VarCoords(qv_s_data_out,qv_s_data_out_lf)
      copy_VarAtts(  qv_s_data_out,qv_s_data_out_lf)
    
      poisson_grid_fill(qv_s_data_out_lf,is_cyclic,guess_type,nscan,eps,relc,opt)
    
      delete([/qv_s_data_out/])
      qv_s_data_out = qv_s_data_out_lf
      delete([/qv_s_data_out_lf,land3d/])
    
    end if

    ; smooth data to remove unresolved features
    if flag_smooth then
       qv_s_data_out_sm = smth9_Wrap(qv_s_data_out,0.5,0.25,False)
       delete([/qv_s_data_out/])
       qv_s_data_out = qv_s_data_out_sm
       delete([/qv_s_data_out_sm/])
    end if

    delete_VarAtts(qv_s_data_out,(/"param","time"/))
    qv_s_data_out@long_name="Specific Humidity at surface"
    add_to_file(fout,qv_s_data_out,"qv_s")

    delete([/variable_file,variable_name,qv_s_data_out/])

  ;==================================================================================
  ; Global file attributes

    globalAtt             = True

    globalAtt@case = "DYAMOND_SUMMER_ICON_2.5km_to_0.2deg_IO1/REF"
    globalAtt@title = "Forcing and initial conditions for DYAMOND_SUMMER_ICON_2.5km_to_0.2deg_IO1/REF case"

    globalAtt@reference = "https://mumip.web.ox.ac.uk/"
    globalAtt@author = "Hannah Christensen, Univ. Oxford, UK"

    globalAtt@version = "Created on " + systemfunc("date")
    globalAtt@format_version = "1.0"
    globalAtt@modifications = "n/a"
    globalAtt@script = ""
    globalAtt@comment = "    *******  MUMIP forcing file following pseudo-DEPHY format  *******"+\
                        "    The following steps will convert to DEPHY:"+\
                        " 0. Interpolate all files onto required vertical levels if neccessary"+\
                        " 1. Select the files corresponding to timestamps of interest"+\
                        " 2. Consider whether your model partitions water species differently "+\
                        "    and create extra humidity variables if necessary."+\
                        " 3. Copy the variables for the first timestamp, X_t -> X, "+\
                        "    where X = {ps, height, pressure, u, v, temp, theta, qv, ql, qi, qt, rv, rl, ri, rt} "+\
                        " 4. Rename X_t -> X_forc, where X = {ps, height, pressure} "+\
                        " 5. Rename remaining X_t -> X_nudging. The first file should have both X and X_nudging for all state vars"+\
                        " 6. Concatenate the files into a single file as a function of time."+\
                        " 7. Decide whether to use z0 or ustar surface forcing and set global attribute accordingly"+\
                        " 8. Decide whether to use surfaceFlux or surface temperature forcing and set global attribute accordingly"+\
                        " 9. Split the concatenated file into individual columns"+\
                        "10. Use variables [zorog] and [z0] to create global attributes [zorog] and [z0] for each column"+\
                        "11. Use variable [lsm] to create  global attribute [surfaceType = <<ocean>>/<<land>>] for each column"


    startDate_matr = (/tostring(timestep_path(0))          ,tostring_with_format(t_step_in*timestep_idx(0),"%2.2d"),"0000"/)
    globalAtt@startDate = tostring(timestep_path(0))+tostring_with_format(t_step_in*timestep_idx(0),"%2.2d")+"0000"
    endDate_matr   = (/tostring(timestep_path(n_time_in-1)),tostring_with_format(t_step_in*timestep_idx(n_time_in-1),"%2.2d"),"0000"/)
    globalAtt@endDate   = str_concat(endDate_matr)
    delete([/startDate_matr,endDate_matr/])

    ; advective tendencies supplied:
    globalAtt@adv_temp   = 1
    globalAtt@adv_theta  = 1
    globalAtt@adv_thetal = 0
    globalAtt@adv_u      = 1
    globalAtt@adv_v      = 1
    globalAtt@adv_qv     = 1
    globalAtt@adv_qt     = 1
    globalAtt@adv_rv     = 0
    globalAtt@adv_rt     = 0

    ; radiation scheme should be activated: no tendencies supplied
    globalAtt@rad_temp   = 0
    globalAtt@rad_theta  = 0
    globalAtt@rad_thetal = 0

    ; no vertical pressure velocity is given
    globalAtt@forc_omega = 0

    ; vertical velocity is prescribed and should be used to compute vertical advection
    globalAtt@forc_w     = 1

    ; geostrophic forcing of the wind is activated, using latitude in lat axis to compute the coriolis parameter
    globalAtt@forc_geo = 1

    ; no separate nudging variables are provided, but users may nudge to the observed profiles if desired
    globalAtt@nudging_temp   = 3600
    globalAtt@nudging_theta  = 3600
    globalAtt@nudging_thetal = 0
    globalAtt@nudging_qv     = 3600
    globalAtt@nudging_qt     = 3600
    globalAtt@nudging_rv     = 0
    globalAtt@nudging_rt     = 0
    globalAtt@nudging_u      = 3600
    globalAtt@nudging_v      = 3600

    ; surface forcing with sensible and latent heat fluxes provided (sfc_sens_flx and sfc_lat_flx)
    ; plus prescribed surface temperature (ts is a variable of the file)
    globalAtt@surfaceForcing = "surfaceFlux/ts"

    ; z0 roughness length provided as well as ustar
    globalAtt@surfaceForcingWind = "z0/ustar"

    ; finally, save flags used when running this script
    globalAtt@flag_land        = flag_land
    globalAtt@flag_smooth      = flag_smooth
    globalAtt@flag_interp_time = flag_interp_time
    globalAtt@code_version     = version

    ; save global attributes to file
    fileattdef(fout, globalAtt )


  end



