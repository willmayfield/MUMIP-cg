; func_advtend.ncl

procedure func_advtend(fout:file,var_name_in:string,var_name_out:string,long_name_out:string,units_out:string)

local fout, var_name_in, var_name_out, long_name_out, units_out,\
      var_data_out, u_data_out, v_data_out, vartend_data_out

begin

  ;==================================================================================
  ; derive advective tendency

    print("procedure advective tendency")

    ;=====================
    ; load required variables in from file
    var_data_out         = fout->$var_name_in$
    u_data_out           = fout->u_t
    v_data_out           = fout->v_t

    ;=====================
    ; calculation

    vartend_data_out = func_advection(var_data_out,u_data_out,v_data_out)

    vartend_data_out@long_name =long_name_out
    vartend_data_out@units     =units_out

    ;-- save to file
    add_to_file(fout,vartend_data_out  , var_name_out)

    delete([/var_data_out, u_data_out, v_data_out, vartend_data_out/])

end
