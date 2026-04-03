module Alarm_System (
    input  wire        clk,        // 50MHz
    input  wire        rst_n,
    input  wire [11:0] temp_raw,   // 来自 I2C 的 12位补码数据
    input  wire        data_vld,   // 数据有效脉冲

    output reg         led_alarm,  // LED 报警输出
    output reg         buzzer_pwm  // 蜂鸣器 PWM 输出
);

    
    // 报警阈值定义 (LM75A 原始数据 = 温度✖16)

    // 50度 = 50 * 16 = 800 
    // 0度  = 0  * 16 = 0   
    wire signed [11:0] s_temp = temp_raw; // 转为有符号数进行比较
    wire is_abnormal = (s_temp > 12'sd800) || (s_temp < 12'sd0); //警报判断条件


    // 连续采样滤波 (10次确认)
    reg [3:0] confirm_cnt;  // 采样计数
    reg       alarm_active; // 报警激活信号

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            confirm_cnt  <= 4'd0;
            alarm_active <= 1'b0;
        end else if (data_vld) begin
            if (is_abnormal) begin   //判断当前温度是否属于异常范围
                if (confirm_cnt < 4'd10)
                    confirm_cnt <= confirm_cnt + 1'b1;  //温度异常，计数器加1
                else
                    alarm_active <= 1'b1; // 连续 10 次异常，拉高报警
            end else begin
                confirm_cnt  <= 4'd0;    // 只要有一次正常，计数归零
                alarm_active <= 1'b0;    // 报警立刻停止
            end
        end
    end


    // LED 闪烁控制 (频率约 2Hz)
    reg [23:0] led_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led_cnt   <= 24'd0;
            led_alarm <= 1'b0;
        end else if (alarm_active) begin
            if (led_cnt >= 24'd12_500_000) begin // 0.25秒翻转一次
                led_cnt   <= 24'd0;
                led_alarm <= ~led_alarm;
            end else begin
                led_cnt <= led_cnt + 1'b1;
            end
        end else begin
            led_cnt   <= 24'd0;
            led_alarm <= 1'b0; // 正常时熄灭
        end
    end

    // ==========================================
    // 4. 蜂鸣器 PWM 驱动 (频率 2kHz, 占空比 50%)
    // ==========================================
    reg [14:0] pwm_cnt;
    // 50MHz / 2kHz = 25,000 个周期
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_cnt    <= 15'd0;
            buzzer_pwm <= 1'b0;
        end else if (alarm_active) begin
            if (pwm_cnt >= 15'd24_999) begin
                pwm_cnt <= 15'd0;
            end else begin
                pwm_cnt <= pwm_cnt + 1'b1;
            end
            // 产生 50% 占空比的正弦方波
            buzzer_pwm <= (pwm_cnt < 15'd12500);
        end else begin
            pwm_cnt    <= 15'd0;
            buzzer_pwm <= 1'b0; // 正常时静音
        end
    end

endmodule