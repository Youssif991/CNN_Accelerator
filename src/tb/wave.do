onerror {resume}
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/kernel_i[7:0]} k_0
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/kernel_i[15:8]} K_1
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/kernel_i[23:16]} k_2
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/kernel_i[31:24]} k_4
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/kernel_i[39:31]} k_4001
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/kernel_i[47:40]} k_5
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/kernel_i[55:48]} k_6
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/kernel_i[39:32]} k_4002
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/kernel_i[63:56]} k_7
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/kernel_i[71:64]} k_8
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/window_i[7:0]} w_0
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/window_i[15:8]} w_1
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/window_i[23:16]} w_2
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/window_i[31:24]} w_3
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/window_i[39:32]} w_4
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/window_i[47:40]} w_5
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/window_i[55:48]} w_6
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/window_i[63:56]} w_7
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/window_i[71:64]} w_8
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/products_o[15:0]} p_0
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/products_o[31:16]} k_1
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/products_o[47:32]} k_2001
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/products_o[63:48]} p_3
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/products_o[79:64]} p_4
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/products_o[95:80]} p_5
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/products_o[111:96]} p_6
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/products_o[127:112]} p_7
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/products_o[143:128]} p_8
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/products_o[159:144]} p_9
quietly virtual signal -install /conv_top/u_accelerator_top/u_mac_array { /conv_top/u_accelerator_top/u_mac_array/products_o[161:160]} overflow
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {System Signals}
add wave -noupdate -radix hexadecimal /conv_top/clk_i
add wave -noupdate -radix hexadecimal /conv_top/rst_n_i
add wave -noupdate -divider {Interface Signals}
add wave -noupdate -radix hexadecimal /conv_top/intf/start_i
add wave -noupdate -radix hexadecimal /conv_top/intf/ready_o
add wave -noupdate -radix hexadecimal /conv_top/intf/busy_o
add wave -noupdate -radix hexadecimal /conv_top/intf/done_o
add wave -noupdate -radix hexadecimal /conv_top/intf/state_o
add wave -noupdate -divider {Input Data (Pixel & Kernel)}
add wave -noupdate -radix hexadecimal /conv_top/intf/kernel_wr_valid_i
add wave -noupdate -radix hexadecimal /conv_top/intf/kernel_wr_data_i
add wave -noupdate -radix hexadecimal /conv_top/intf/pixel_valid_i
add wave -noupdate -radix hexadecimal /conv_top/intf/pixel_in_i
add wave -noupdate -divider {Output Stream}
add wave -noupdate -radix hexadecimal /conv_top/intf/result_ready_i
add wave -noupdate -radix hexadecimal /conv_top/intf/result_valid_o
add wave -noupdate -radix hexadecimal /conv_top/intf/result_o
add wave -noupdate -radix hexadecimal /conv_top/intf/result_tlast_o
add wave -noupdate -group FSM_SIGNALS /conv_top/u_accelerator_top/u_fsm/state_q
add wave -noupdate -group FSM_SIGNALS /conv_top/u_accelerator_top/u_fsm/state_d
add wave -noupdate -group FSM_SIGNALS /conv_top/u_accelerator_top/u_fsm/load_cnt_q
add wave -noupdate -group FSM_SIGNALS /conv_top/u_accelerator_top/u_fsm/load_cnt_d
add wave -noupdate -group FSM_SIGNALS /conv_top/u_accelerator_top/u_fsm/exit_cnt_q
add wave -noupdate -group FSM_SIGNALS /conv_top/u_accelerator_top/u_fsm/exit_cnt_d
add wave -noupdate -group FSM_SIGNALS /conv_top/u_accelerator_top/u_fsm/pix_row
add wave -noupdate -group FSM_SIGNALS /conv_top/u_accelerator_top/u_fsm/block_valid
add wave -noupdate -group COUNTERS /conv_top/u_accelerator_top/u_in/en_i
add wave -noupdate -group COUNTERS /conv_top/u_accelerator_top/u_in/rst_count_i
add wave -noupdate -group COUNTERS -radix unsigned /conv_top/u_accelerator_top/u_in/addr_o
add wave -noupdate -group COUNTERS /conv_top/u_accelerator_top/u_in/last_o
add wave -noupdate -group fifo_input /conv_top/u_accelerator_top/u_out_fifo/wr_data_i
add wave -noupdate -group fifo_input /conv_top/u_accelerator_top/u_out_fifo/wr_valid_i
add wave -noupdate -group fifo_input /conv_top/u_accelerator_top/u_out_fifo/wr_ptr_q
add wave -noupdate -group fifo_input /conv_top/u_accelerator_top/u_out_fifo/wr_ptr_d
add wave -noupdate -group fifo_input /conv_top/u_accelerator_top/u_out_fifo/rd_ptr_q
add wave -noupdate -group fifo_input /conv_top/u_accelerator_top/u_out_fifo/rd_ptr_d
add wave -noupdate -group fifo_input /conv_top/u_accelerator_top/u_out_fifo/rd_data_o
add wave -noupdate -group MAC_array /conv_top/u_accelerator_top/u_mac_array/en_i
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[0]/u_dsp_mult_r4/pixel_i}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[0]/u_dsp_mult_r4/coeff_i}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[0]/u_dsp_mult_r4/prod_o}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[1]/u_dsp_mult_r4/pixel_i}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[1]/u_dsp_mult_r4/coeff_i}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[1]/u_dsp_mult_r4/prod_o}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[2]/u_dsp_mult_r4/pixel_i}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[2]/u_dsp_mult_r4/coeff_i}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[2]/u_dsp_mult_r4/prod_o}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[3]/u_dsp_mult_r4/pixel_i}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[3]/u_dsp_mult_r4/coeff_i}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[3]/u_dsp_mult_r4/prod_o}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[4]/u_dsp_mult_r4/pixel_i}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[4]/u_dsp_mult_r4/coeff_i}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[4]/u_dsp_mult_r4/prod_o}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[5]/u_dsp_mult_r4/pixel_i}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[5]/u_dsp_mult_r4/coeff_i}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[5]/u_dsp_mult_r4/prod_o}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[6]/u_dsp_mult_r4/pixel_i}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[6]/u_dsp_mult_r4/coeff_i}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[6]/u_dsp_mult_r4/prod_o}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[7]/u_dsp_mult_r4/pixel_i}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[7]/u_dsp_mult_r4/coeff_i}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[7]/u_dsp_mult_r4/prod_o}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[8]/u_dsp_mult_r4/pixel_i}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[8]/u_dsp_mult_r4/coeff_i}
add wave -noupdate -group MAC_array {/conv_top/u_accelerator_top/u_mac_array/gen_mac_taps[8]/u_dsp_mult_r4/prod_o}
add wave -noupdate -group adders /conv_top/u_accelerator_top/u_adder_tree/products_i
add wave -noupdate -group adders /conv_top/u_accelerator_top/u_adder_tree/sum_o
add wave -noupdate -group adders /conv_top/u_accelerator_top/u_adder_tree/sum_acc
add wave -noupdate -radix decimal /conv_top/u_accelerator_top/u_sat_round_unit/sum_i
add wave -noupdate /conv_top/u_accelerator_top/u_sat_round_unit/result_o
add wave -noupdate /conv_top/u_accelerator_top/u_sat_round_unit/sum_relu
add wave -noupdate /conv_top/u_accelerator_top/u_sat_round_unit/rounded
add wave -noupdate /conv_top/u_accelerator_top/u_sat_round_unit/truncated
add wave -noupdate /conv_top/u_accelerator_top/u_sat_round_unit/result_d
add wave -noupdate /conv_top/u_accelerator_top/u_sat_round_unit/relu_en_i
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {532207 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 309
configure wave -valuecolwidth 98
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {214473 ps} {1210039 ps}
