; add_to_file.ncl

procedure add_to_file(fout:file,data,data_name)

local fout,data,data_name


begin

    setfileoption(fout,"DefineMode",True)
    filevardef(   fout, data_name(0) , typeof(data) , getvardims(data))
    filevarattdef(fout, data_name(0) , data)
    setfileoption(fout,"DefineMode",False)
    fout->$data_name(0)$ = (/data/)

end
