module cocotb_iverilog_dump();
initial begin
    $dumpfile("sim_build/reciprocal_maker.fst");
    $dumpvars(0, reciprocal_maker);
end
endmodule
