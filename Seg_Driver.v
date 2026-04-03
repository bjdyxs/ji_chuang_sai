module Seg_Driver (
    input  wire        clk,       // 系统时钟 50MHz
    input  wire        rst_n,     // 低电平复位
    input  wire        mode,      // 显示模式
    input  wire        standby_en, // 待机使能
    
    // 从 Data_Processor 传来的温度原码
    input  wire        sign_bit,  // 符号位 (1为负数)
    input  wire [3:0]  bcd_high,  // 百位
    input  wire [3:0]  bcd_mid,   // 十位
    input  wire [3:0]  bcd_low,   // 个位
    input  wire [3:0]  bcd_dec,   // 小数位

    
    output reg  [5:0]  seg_sel,   // 6位 位选信号 (低电平有效：0选中，1不亮)
    output reg  [7:0]  seg_led    // 8位 段选信号 (高电平有效：共阴极，1亮，顺序 dp g f e d c b a，在显示数字时使用)
);

    
    // 扫描时钟分频 (50MHz -> 每位扫描时间 1ms)
    parameter SCAN_MAX = 50_000; // 50,000 * 20ns = 1ms
    
    reg [15:0] scan_cnt;
    reg [2:0]  scan_idx; // 0~5，轮流点亮 6 个数码管

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_cnt <= 16'd0;
            scan_idx <= 3'd0;
        end else if (scan_cnt == SCAN_MAX - 1) begin
            scan_cnt <= 16'd0;
            if (scan_idx == 3'd5)
                scan_idx <= 3'd0; // 扫到最后一个，回头重扫
            else
                scan_idx <= scan_idx + 1'b1;
        end else begin
            scan_cnt <= scan_cnt + 1'b1;
        end
    end

   
    // 首零消隐逻辑判断 
    // 百位：如果为 0，直接消隐
    wire blank_high = (bcd_high == 4'd0);
    
    // 十位：只有当百位已经是0且十位本身也是0时，才消隐
    wire blank_mid  = (blank_high) && (bcd_mid == 4'd0);

    
    // 动态扫描输出 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seg_sel <= 6'b111111; // 默认全部不选中
            seg_led <= 8'h00;     // 默认全部熄灭
        end else begin
            // 在每个 1ms 切换周期的最初 10 个时钟周期内，强行全灭。
            // 消除物理引脚切换延迟带来的重影现象。
            if (scan_cnt < 10) begin 
                seg_sel <= 6'b111111; 
                seg_led <= 8'h00;
            end else begin
            if (standby_en) begin  //按键为待机状态
                    seg_sel <= ~(6'b000001 << scan_idx); // 轮流选中6个管子
                    seg_led <= 8'h3F;                    // 强制输出 0
                end else begin
                case (scan_idx)
                    3'd0: begin //显示字母 'C'
                        seg_sel <= 6'b111110; 
                        if (mode)
                            seg_led <= 8'h71; // 华氏度显示大写 'F'
                        else
                            seg_led <= 8'h58; // 摄氏度显示小写 'c'
                    end
                    3'd1: begin //小数位
                        seg_sel <= 6'b111101; 
                        seg_led <= decode_bcd(bcd_dec);
                    end
                    3'd2: begin //个位 + 常亮小数点
                        seg_sel <= 6'b111011; 
                        // 最高位强行点亮 dp 段
                        seg_led <= decode_bcd(bcd_low) | 8'h80; 
                    end
                    3'd3: begin //十位 (消隐逻辑)
                        seg_sel <= 6'b110111; 
                        if (blank_mid)
                            seg_led <= 8'h00; // 如果满足消隐条件，直接断电全灭
                        else
                            seg_led <= decode_bcd(bcd_mid);
                    end
                    3'd4: begin //百位 (消隐逻辑)
                        seg_sel <= 6'b101111; 
                        if (blank_high)
                            seg_led <= 8'h00; // 如果满足消隐条件，直接断电全灭
                        else
                            seg_led <= decode_bcd(bcd_high);
                    end
                    3'd5: begin //符号位
                        seg_sel <= 6'b011111; 
                        if (sign_bit)
                            seg_led <= 8'h40; // 负数显示 '-' (只有中间的 g 段亮)
                        else
                            seg_led <= 8'h00; // 正数不亮
                    end
                    default: begin
                        seg_sel <= 6'b111111;
                        seg_led <= 8'h00;
                    end
                endcase
            end
        end
    end
end

    // BCD 转共阴极 7 段码查表函数
    function [7:0] decode_bcd;
        input [3:0] bcd_in;
        begin
            case (bcd_in)
                4'd0: decode_bcd = 8'h3F; // 0011_1111
                4'd1: decode_bcd = 8'h06; // 0000_0110
                4'd2: decode_bcd = 8'h5B; // 0101_1011
                4'd3: decode_bcd = 8'h4F; // 0100_1111
                4'd4: decode_bcd = 8'h66; // 0110_0110
                4'd5: decode_bcd = 8'h6D; // 0110_1101
                4'd6: decode_bcd = 8'h7D; // 0111_1101
                4'd7: decode_bcd = 8'h07; // 0000_0111
                4'd8: decode_bcd = 8'h7F; // 0111_1111
                4'd9: decode_bcd = 8'h6F; // 0110_1111
                default: decode_bcd = 8'h00; // 越界全灭
            endcase
        end
    endfunction

endmodule