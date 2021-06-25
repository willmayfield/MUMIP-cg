; func_reduce_area.ncl

function func_reduce_area(data_in:float,flag_subset:logical,set_lat_min:float,set_lat_max:float,set_lon_min:float,set_lon_max:float,no_dims:integer)

local    data_in,flag_subset, set_lat_min, set_lat_max, set_lon_min, set_lon_max,no_dims

begin

    if (flag_subset) then
       if (no_dims.eq.3) then
          data_out = data_in(time|:,{lat|set_lat_min:set_lat_max},{lon|set_lon_min:set_lon_max})
       else
          if (no_dims.eq.4) then
             data_out = data_in(time|:,lev|:,{lat|set_lat_min:set_lat_max},{lon|set_lon_min:set_lon_max})
          else
             print("WRONG NUMBER DIMS")
          end if
       end if
    else
       data_out = data_in
    end if  

    return(data_out)

end
