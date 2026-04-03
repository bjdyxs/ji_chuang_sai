module LM75A_Top (
    
    input  wire        clk,         // 晶振系统时钟 (50MHz)
    input  wire        rst_n,       // 外部复位按键 (低电平有效)
    input  wire        btn_mode,     // 按键：0显示摄氏度，1显示华氏度
    
    
    inout  wire        sda,         // I2C 数据总线
    output wire        scl,         // I2C 时钟总线
    
    
    output wire [5:0]  seg_sel,     // 6位 数码管位选
    output wire [7:0]  seg_led,     // 8位 数码管段选
    output wire        led_alarm,   // LED 报警指示灯
    output wire        buzzer_pwm   // 蜂鸣器报警 PWM 输出
);

    
    //底层采集到的数据 
    wire [11:0] temp_raw;  
    wire        data_vld;  
    
    
    wire        sign_bit;  
    wire [3:0]  bcd_high;  
    wire [3:0]  bcd_mid;   
    wire [3:0]  bcd_low;   
    wire [3:0]  bcd_dec;   

	wire  mode_tick;  //消抖模块的输出高电平
    reg mode_reg; //状态寄存器，0为C，1为F
    
    // 模块 1：I2C 驱动模块
    
    Control_Unit u_Control_Unit (
        .clk        (clk),
        .rst_n      (rst_n),
        .sda        (sda),
        .scl        (scl),
        .temp_raw   (temp_raw),  // 12位 原始数据
        .data_vld   (data_vld)   // 有效脉冲
    );

    
    // 模块 2：数据处理模块 
    
    Data_Processor u_Data_Processor (
        .clk        (clk),
        .rst_n      (rst_n),
        .temp_raw   (temp_raw),  // 原始数据
        .data_vld   (data_vld),  
        .mode       (mode_reg),   // 接收按键的指令
        
        .sign_bit   (sign_bit),  // 翻译好的各个位
        .bcd_high   (bcd_high),
        .bcd_mid    (bcd_mid),
        .bcd_low    (bcd_low),
        .bcd_dec    (bcd_dec)
    );

    
    // 模块 3：数码管显示模块 

    Seg_Driver u_Seg_Driver (
        .clk        (clk),
        .rst_n      (rst_n),
        .mode       (mode_reg),   // 接收按键指令 (决定最右边亮 c 还是 F)
        
        .sign_bit   (sign_bit),  
        .bcd_high   (bcd_high),
        .bcd_mid    (bcd_mid),
        .bcd_low    (bcd_low),
        .bcd_dec    (bcd_dec),
        
        .seg_sel    (seg_sel),   
        .seg_led    (seg_led)    
    );

    
    // 模块 4：报警与滤波系统 
  
    Alarm_system u_Alarm_system (
        .clk        (clk),
        .rst_n      (rst_n),
        .temp_raw   (temp_raw),  // 直接查看底层的数据
        .data_vld   (data_vld),  // 有效脉冲做连续10次滤波
        
        .led_alarm  (led_alarm), // 驱动板子上的 LED
        .buzzer_pwm (buzzer_pwm) // 驱动板子上的 蜂鸣器
    );
    
    
    // 模块 5：按键消抖       
    buttom_debounce u_Button_Debounce (
        .clk      (clk),
        .rst_n    (rst_n),
        .btn_in   (btn_mode),
        .btn_tick (mode_tick)
    );

    // 翻转逻辑：每检测到一个脉冲，状态取反
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mode_reg <= 1'b0;
        else if (mode_tick)
            mode_reg <= ~mode_reg;
    end


endmodule