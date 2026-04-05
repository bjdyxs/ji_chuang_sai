module RGB_Indicator (
    input  wire standby_en,  // 接收待机状态
    input  wire alarm_flag,  // 接收报警状态

    output reg  rgb_b,       // 蓝灯待机
    output reg  rgb_g,       // 绿灯正常测温
    output reg  rgb_r        // 红灯报警
);

    
    
    always @(*) begin
        if (standby_en) begin
            // 待机状态：无论外界温度如何，只亮蓝灯
            rgb_b = 1'b0;
            rgb_g = 1'b1;
            rgb_r = 1'b1;
        end else if (alarm_flag) begin
            // 工作状态且正在报警，只亮红灯
            rgb_b = 1'b1;
            rgb_g = 1'b1;
            rgb_r = 1'b0;
        end else begin
            // 工作状态且在安全温度，只亮绿灯
            rgb_b = 1'b1;
            rgb_g = 1'b0;
            rgb_r = 1'b1;
        end
    end

endmodule