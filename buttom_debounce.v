module Button_Debounce (
    input  wire clk,         // 系统时钟 (50MHz)
    input  wire rst_n,       // 低电平复位
    input  wire btn_in,      // 外部物理按键输入 (按下为0，松开为1)
    
    output reg  btn_tick     // 输出消抖后的单脉冲 (高电平1拍)
);

    // 20ms 考察期 (50MHz * 0.02s = 1,000,000)
    parameter CNT_20MS = 20'd1_000_000;
    
    reg [19:0] cnt;
    reg [1:0]  btn_sync;

    
    // 跨时钟域同步 (当前周期按下的键可能产生抖动，但经过一个周期的消耗之后，变成
    // 下一个周期的btn_sync[1]，这时再读取就能读到稳定信号了，详细可以查询按键消抖原理)
    
    always @(posedge clk) begin
        btn_sync <= {btn_sync[0], btn_in};
    end

   
    // 计时与单脉冲截取
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt      <= 20'd0;
            btn_tick <= 1'b0;
        end else begin
            if (btn_sync[1] == 1'b0) begin 
                // 检测到按下 (低电平)
                if (cnt < CNT_20MS) begin
                    cnt      <= cnt + 1'b1;  // 没走完消耗时间，继续数
                    btn_tick <= 1'b0;
                end else if (cnt == CNT_20MS) begin
                    cnt      <= cnt + 1'b1;  // 锁死计数器，防止溢出死循环
                    btn_tick <= 1'b1;        // 刚刚好满 20ms 的那一瞬间，发出脉冲
                end else begin
                    // 只要手还不松开，计数器就停在 1000001，脉冲归零
                    btn_tick <= 1'b0;        
                end
            end else begin 
                // 一松开手，或者发生哪怕一微秒的弹片抖动跳回1
                cnt      <= 20'd0;           // 直接清零，重新开始
                btn_tick <= 1'b0;
            end
        end
    end

endmodule
