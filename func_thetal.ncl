; func_thetal.ncl

procedure func_thetal(fout:file)

local fout, theta_data_out, t_data_out, rl_data_out, Lv, c_pd,\
      thetal_data_out, thetal_data_out_flt

begin

  ;==================================================================================
  ; derive thetal

    print("procedure thetal")

    ;=====================
    ; load required variables in from file
    theta_data_out           = fout->theta_t
    t_data_out               = fout->temp_t
    rl_data_out              = fout->rl_t

    ;constants
    Lv   = 2.501*10^6
    c_pd = 1005.7

    ;=====================
    ; calculation : https://glossary.ametsoc.org/wiki/Liquid_water_potential_temperature
    
    thetal_data_out = theta_data_out - (Lv/c_pd)*(theta_data_out/t_data_out)*rl_data_out
 
    ;====================
    ; ensure saved as float not double
    thetal_data_out_flt = tofloat(thetal_data_out)

    copy_VarAtts(t_data_out,thetal_data_out_flt)
    copy_VarCoords(t_data_out,thetal_data_out_flt)

    thetal_data_out_flt@long_name = "liquid water potential temperature"
    thetal_data_out_flt@units     = "K"

    ;-- save to file
    add_to_file(fout,thetal_data_out_flt  , "thetal_t")

    delete([/theta_data_out, t_data_out, rl_data_out, Lv, c_pd/])
    delete([/thetal_data_out, thetal_data_out_flt/])

end
