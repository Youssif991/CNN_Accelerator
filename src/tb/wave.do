onerror {resume}
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
add wave -noupdate -radix hexadecimal -childformat {{{/conv_top/intf/result_o[15]} -radix hexadecimal} {{/conv_top/intf/result_o[14]} -radix hexadecimal} {{/conv_top/intf/result_o[13]} -radix hexadecimal} {{/conv_top/intf/result_o[12]} -radix hexadecimal} {{/conv_top/intf/result_o[11]} -radix hexadecimal} {{/conv_top/intf/result_o[10]} -radix hexadecimal} {{/conv_top/intf/result_o[9]} -radix hexadecimal} {{/conv_top/intf/result_o[8]} -radix hexadecimal} {{/conv_top/intf/result_o[7]} -radix hexadecimal} {{/conv_top/intf/result_o[6]} -radix hexadecimal} {{/conv_top/intf/result_o[5]} -radix hexadecimal} {{/conv_top/intf/result_o[4]} -radix hexadecimal} {{/conv_top/intf/result_o[3]} -radix hexadecimal} {{/conv_top/intf/result_o[2]} -radix hexadecimal} {{/conv_top/intf/result_o[1]} -radix hexadecimal} {{/conv_top/intf/result_o[0]} -radix hexadecimal}} -subitemconfig {{/conv_top/intf/result_o[15]} {-radix hexadecimal} {/conv_top/intf/result_o[14]} {-radix hexadecimal} {/conv_top/intf/result_o[13]} {-radix hexadecimal} {/conv_top/intf/result_o[12]} {-radix hexadecimal} {/conv_top/intf/result_o[11]} {-radix hexadecimal} {/conv_top/intf/result_o[10]} {-radix hexadecimal} {/conv_top/intf/result_o[9]} {-radix hexadecimal} {/conv_top/intf/result_o[8]} {-radix hexadecimal} {/conv_top/intf/result_o[7]} {-radix hexadecimal} {/conv_top/intf/result_o[6]} {-radix hexadecimal} {/conv_top/intf/result_o[5]} {-radix hexadecimal} {/conv_top/intf/result_o[4]} {-radix hexadecimal} {/conv_top/intf/result_o[3]} {-radix hexadecimal} {/conv_top/intf/result_o[2]} {-radix hexadecimal} {/conv_top/intf/result_o[1]} {-radix hexadecimal} {/conv_top/intf/result_o[0]} {-radix hexadecimal}} /conv_top/intf/result_o
add wave -noupdate -radix hexadecimal /conv_top/intf/result_tlast_o
add wave -noupdate -expand -group FSM /conv_top/u_accelerator_top/u_fsm/load_cnt_q
add wave -noupdate -expand -group FSM /conv_top/u_accelerator_top/u_fsm/load_cnt_d
add wave -noupdate -expand -group FSM /conv_top/u_accelerator_top/u_fsm/exit_cnt_q
add wave -noupdate -expand -group FSM /conv_top/u_accelerator_top/u_fsm/exit_cnt_d
add wave -noupdate /conv_top/u_accelerator_top/u_fsm/stream_start_o
add wave -noupdate /conv_top/u_accelerator_top/u_frame_buffer/rd_rst_addr_i
add wave -noupdate /conv_top/u_accelerator_top/u_frame_buffer/rd_addr_q
add wave -noupdate /conv_top/u_accelerator_top/u_frame_buffer/rd_addr_d
add wave -noupdate /conv_top/u_accelerator_top/u_frame_buffer/rd_data_q
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {4513837 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
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
WaveRestoreZoom {3902500 ps} {5054456 ps}
