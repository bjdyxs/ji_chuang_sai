module Data_Processor (
    input  wire        clk,       // 系统时钟
    input  wire        rst_n,     // 低电平复位
    input  wire [11:0] temp_raw,  // I2C 模块传来的补码
    input  wire        data_vld,  // 数据有效脉冲
    input  wire        mode ,		 // 0摄氏度 1华氏度

    output reg         sign_bit,  // 符号位 (1表示负数，0表示正数)
    output reg  [3:0]  bcd_high,  // 百位 BCD 码 (0~9)
    output reg  [3:0]  bcd_mid,   // 十位 BCD 码 (0~9)
    output reg  [3:0]  bcd_low,   // 个位 BCD 码 (0~9)
    output reg  [3:0]  bcd_dec    // 小数位 BCD 码 (0~9)
);

   
    wire signed [15:0] signed_c = { {4{temp_raw[11]}}, temp_raw };  //把12位有符号数扩充到16位，防止华氏度转换时数据溢出
    wire signed [15:0] signed_f = (signed_c * 14'sd9) / 14'sd5 + 14'sd512; //华氏度转换公式，适应硬件配置
    
    wire signed [15:0] active_temp = mode ? signed_f : signed_c; //选择当前显示模式
    // 补码转原码 (求绝对值)
    // 逻辑：判断最高位 active_temp[15] 是否为 1 (1 代表负数)。
    // 如果是负数，则按位取反加一得到绝对值；
    // 如果是正数，则保持原样直接输出。
    wire [15:0] abs_val = active_temp[15] ? (~active_temp + 1'b1) : active_temp;

    // 物理意义拆分
    // 根据 LM75A 手册：高 8 位是整数，低 4 位是小数
    wire [11:0]  int_part  = abs_val[15:4]; // 提取 12-bit 整数部分
    wire [3:0]  frac_part = abs_val[3:0];  // 提取 4-bit 小数部分

    
    //时序逻辑转换 BCD 
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位时全部清零
            sign_bit <= 1'b0;
            bcd_high <= 4'd0;
            bcd_mid  <= 4'd0;
            bcd_low  <= 4'd0;
            bcd_dec  <= 4'd0;
        end else if (data_vld) begin
            //只有当 I2C 模块将有效脉冲发出时（即已完成通信），才抓取并计算
            
            //提取符号位备用 (留给数码管显示负号用)
            sign_bit <= active_temp[15]; 

            //整数转 BCD (除法和取余)
            bcd_high <=  int_part / 100;         // 百位：直接除以100
            bcd_mid  <= (int_part % 100) / 10;   // 十位：除以100取余数后，再除以10
            bcd_low  <=  int_part % 10;          // 个位：直接除以10取余数

            // 小数转 BCD 
            // 传感器低4位的真实权重是 0.0625℃ (即 1/16)。         
            // 先乘 10，再右移 4 位 (右移 4 位等价于除以 16)
            bcd_dec  <= (frac_part * 10) >> 4; 
        end
    end

endmodule