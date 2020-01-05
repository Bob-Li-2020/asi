file delete -force work
if ![file isdirectory ./work] { vlib ./work }
vmap work ./work

if [file isdirectory D:/modeltech64_10.5] { set MODELSIM_LIB D:/modeltech64_10.5/altera }
if [file isdirectory D:/modeltech_pe_10.5a] { set MODELSIM_LIB D:/modeltech_pe_10.5a/altera } else {
	set MODELSIM_LIB C:/altera/15.1/altera_precompiled/verilog_libs
}

#vlog altera_mf.v
vlog tb.sv -y ./ -y ../rtl +libext+.v +libext+.sv 
vsim work.tb -voptargs=+acc -vopt
run 300ns
