#file delete -force work
if ![file isdirectory ./work] { vlib ./work }
vmap work ./work

if [file isdirectory C:/modeltech64_10.5] { set MODELSIM_LIB C:/modeltech64_10.5/altera }
if [file isdirectory C:/modeltech_pe_10.5a] { set MODELSIM_LIB C:/modeltech_pe_10.5a/altera }

#vlog altera_mf.v
vlog tb.sv -y ./ -y ../rtl +libext+.v +libext+.sv 
vsim work.tb -voptargs=+acc -vopt
