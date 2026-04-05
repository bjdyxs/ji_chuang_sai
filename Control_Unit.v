module Control_Unit (
    input  wire        clk,       // 系统时钟 (假设 50MHz)
    input  wire        rst_n,     // 低电平异步复位
    inout  wire        sda,       // I2C 数据总线
    output wire        scl,       // I2C 时钟总线
    output reg  [11:0] temp_raw,  // 原始补码温度数据 (12-bit)
    output reg         data_vld   // 数据有效脉冲
);

    
    // 参数定义    
    // 系统时钟到 I2C SCL 的分频参数 ( 系统时钟clk=50MHz, 目标可使用时钟 SCL=100kHz)
    // 50MHz / 100kHz = 500。将周期分成 4 个节拍，每拍 125 个 clk
    parameter SYS_CLK_FREQ = 50_000_000;
    parameter I2C_SCL_FREQ = 100_000;
    parameter DIV_CYC      = 125; 

    // LM75A 默认设备地址 (1001000) + 读指令 (1) = 8'h91
    parameter LM75A_RD_CMD = 8'h91; 

    // 状态机定义
    localparam IDLE      = 4'd0;  //空闲状态
    localparam START     = 4'd1;  //主机发送开始指令
    localparam SEND_ADDR = 4'd2;  //主机向从机发送设备地址
    localparam ACK_1     = 4'd3;  //从机收到地址后回复
    localparam READ_MSB  = 4'd4;  //从机向主机发送高8位数据
    localparam ACK_2     = 4'd5;  //主机收到数据后回复（继续发送）
    localparam READ_LSB  = 4'd6;  //从机向主机发送低8位数据
    localparam NACK      = 4'd7;  //主机收到数据后回复（停止发送）
    localparam STOP      = 4'd8;  //主机向从机发送通信终止信号
    localparam DONE      = 4'd9;  //发送完成，整理有效数据


    // 内部信号声明
    reg  [3:0]  state, next_state; //当前状态和下一状态
    reg  [7:0]  cnt_clk;      // 分频计数器
    reg         i2c_tick;     // I2C 节拍使能 (1/4 SCL周期为一拍，节拍使能为1时下一拍)
    reg  [1:0]  step;         // 0~3 描述 SCL 的低-升-高-降 四个相位
    
    reg  [3:0]  bit_cnt;      // 数据位计数器 (0~7)
    reg  [15:0] rx_data;      // 接收到的 16 位数据
    
    reg         scl_out;      // SCL 输出寄存器
    reg         sda_out;      // SDA 输出数据
    reg         sda_dir;      // SDA 方向控制：1为输出，0为输入(高阻)

    // 轮询等待计数器 (连续读取之间的间隔)
    reg  [15:0] wait_cnt;   //发送过程间隙等待中计时  
    wire        start_req;

    
    // SDA 三态门控制    
    assign sda = sda_dir ? sda_out : 1'bz;  //SDA 方向控制：1为主机输出给从机，0为从机输入给主机(高阻态)
    assign scl = scl_out; //将输出寄存器的值转换成实际scl
    
    wire sda_in = sda; // 内部读取 SDA 的值


    // 时钟分频与节拍生成
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin  //复位
            cnt_clk  <= 8'd0;
            i2c_tick <= 1'b0;
        end else if (cnt_clk == DIV_CYC - 1) begin  //每计数到124/125时就进入下一拍
            cnt_clk  <= 8'd0;
            i2c_tick <= 1'b1;
        end else begin
            cnt_clk  <= cnt_clk + 1'b1;
            i2c_tick <= 1'b0;
        end
    end


    // 自动轮询请求
    // 这里设置每隔一段时间自动拉高请求，持续读取 LM75A
    always @(posedge clk or negedge rst_n)  //空闲状态自动计数，计数到65535就是1.3毫秒，每隔 1.3 毫秒，就会自动向 LM75A 索取温度数据。
    begin
        if (!rst_n) begin
            wait_cnt <= 16'd0;
        end else if (state == IDLE) begin
            if (wait_cnt < 16'hFFFF) begin 
                wait_cnt <= wait_cnt + 1'b1; //如果没数到目标值，就加 1；数到了就停在原地等
            end
        end else begin
            wait_cnt <= 16'd0;
        end
    end
    assign start_req = (wait_cnt == 16'hFFFF);


    // I2C 状态机与控制逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            step     <= 2'd0;
            bit_cnt  <= 4'd0;
            rx_data  <= 16'd0;
            scl_out  <= 1'b1;
            sda_out  <= 1'b1; 
            sda_dir  <= 1'b1; // 默认输出，总线scl和sda双线空闲时全高
            data_vld <= 1'b0; 
            temp_raw <= 12'd0;
        end else begin
            // 默认 data_vld 只有一拍的高电平
            data_vld <= 1'b0; 

            if (i2c_tick) begin //进入下一拍时，step也进入下一阶段
                step <= step + 1'b1;
                
                case (state)
                    IDLE:   //空闲状态保持双高，收到开始请求时进入开始阶段
                    begin
                        scl_out <= 1'b1;
                        sda_out <= 1'b1;
                        sda_dir <= 1'b1;
                        step    <= 2'd0;
                        if (start_req) 
                            state <= START;
                    end

                    START: begin
                        // 产生 START 条件: SCL高时，SDA拉低
                        if (step == 0) begin scl_out <= 1'b1; sda_out <= 1'b1; end //双高准备阶段
                        if (step == 1) begin scl_out <= 1'b1; sda_out <= 1'b0; end //scl=1时sda由1变为0,产生start信号
                        if (step == 2) begin scl_out <= 1'b0; sda_out <= 1'b0; end //提前准备下一阶段所需要的信号
                        if (step == 3) begin                                       //准备进入下一阶段
                            state   <= SEND_ADDR; 
                            bit_cnt <= 4'd0; 
                        end
                    end

                    SEND_ADDR: begin
                        sda_dir <= 1'b1; // 主机输出
                        // 发送 8'h91 (地址 + 读位)
                        if (step == 0) begin sda_out <= LM75A_RD_CMD[7 - bit_cnt]; scl_out <= 1'b0; end //在scl为低时，允许主机发送地址
                        if (step == 1) begin scl_out <= 1'b1; end //把scl拉高
                        if (step == 2) begin scl_out <= 1'b1; end //当scl为高时，数据无法改变，此时从机读取地址
                        if (step == 3) begin //把scl拉低，再判断地址位是否全部发完，原因在于如果scl=1而sda传输过程中地址码中有1到0的跳变/0到1的跳变，就会误判为start状态/stop状												  态，就会出错。
                            scl_out <= 1'b0;
                            if (bit_cnt == 4'd7) begin
                                state   <= ACK_1;
                                bit_cnt <= 4'd0;
                            end else begin
                                bit_cnt <= bit_cnt + 1'b1;
                            end
                        end
                    end

                    ACK_1: begin 
                        sda_dir <= 1'b0; // 主机释放 SDA，此时转换为从机发给主机
                        if (step == 0) scl_out <= 1'b0;
                        if (step == 1) scl_out <= 1'b1;//把scl拉高
                        if (step == 2) begin 
                            scl_out <= 1'b1; 
                            //在线检测机制，保持scl高，判断传感器有没有把SDA拉低
                            if (sda_in == 1'b1) begin 
                                // 传感器没把SDA拉低，说明不在线
                                state <= STOP; // 强行跳到STOP挂断通信
                            end
                        end
                        if (step == 3) begin
                            scl_out <= 1'b0; //拉低scl，原因同上
                            // 只有当 step 2 没有触发报错跳到 STOP 时，才继续往下读数据
                            if (state == ACK_1) 
                                state <= READ_MSB;
                        end
                    end

                    READ_MSB: begin
                        sda_dir <= 1'b0; 
                        if (step == 0) scl_out <= 1'b0;//scl为低时，从机将高8位数据传输给主机
                        if (step == 1) scl_out <= 1'b1;//拉高scl
                        if (step == 2) begin 
                            scl_out <= 1'b1; //scl为高时数据无法变化，此时主机读取数据
                            rx_data[15 - bit_cnt] <= sda_in; // 采样 高8位 数据
                        end
                        if (step == 3) begin
                            scl_out <= 1'b0; //拉低scl，原因同上
                            if (bit_cnt == 4'd7) begin
                                state   <= ACK_2; //准备进入第二个应答环节
                                bit_cnt <= 4'd0;
                            end else begin
                                bit_cnt <= bit_cnt + 1'b1;
                            end
                        end
                    end

                    ACK_2: begin
                        sda_dir <= 1'b1; // 主机收回SDA，准备向从机发送应答信号
                        if (step == 0) begin sda_out <= 1'b0; scl_out <= 1'b0; end //发送双低ACK信号，表示收到高8位数据
                        if (step == 1) begin scl_out <= 1'b1; end //拉高scl
                        if (step == 2) begin scl_out <= 1'b1; end //从机读取scl=1且sda=0（持续为0而不发生跳变，不算start信号），表示继续发送低8位
                        if (step == 3) begin
                            scl_out <= 1'b0; //拉低scl，给反应时间，准备进入下一模块
                            state   <= READ_LSB;
                        end
                    end

                    READ_LSB: begin
                        sda_dir <= 1'b0; // 主机再次释放SDA，从机向主机发送数据
                        if (step == 0) scl_out <= 1'b0; //scl为低时，从机把低8位数据发送给主机
                        if (step == 1) scl_out <= 1'b1; //拉高scl
                        if (step == 2) begin 
                            scl_out <= 1'b1; //scl为高时数据无法变化，此时主机读取数据
                            rx_data[7 - bit_cnt] <= sda_in; //采样 低8位 数据
                        end
                        if (step == 3) begin
                            scl_out <= 1'b0;
                            if (bit_cnt == 4'd7) begin
                                state   <= NACK;//准备进入第三个应答环节
                                bit_cnt <= 4'd0;
                            end else begin
                                bit_cnt <= bit_cnt + 1'b1;
                            end
                        end
                    end

                    NACK: begin
                        sda_dir <= 1'b1; // 主机再次收回SDA，准备向从机发送应答信号
                        if (step == 0) begin sda_out <= 1'b1; scl_out <= 1'b0; end //发送NACK信号，表示收到低8位数据
                        if (step == 1) begin scl_out <= 1'b1; end //拉高scl
                        if (step == 2) begin scl_out <= 1'b1; end //从机读取scl=1且sda=1，表示不需要继续发送
                        if (step == 3) begin
                            scl_out <= 1'b0; //拉低scl，给反应时间，准备进入下一模块
                            state   <= STOP;
                        end
                    end

                    STOP: begin
                        sda_dir <= 1'b1; 
                        // 产生 STOP 条件: SCL高时，SDA拉高
                        if (step == 0) begin sda_out <= 1'b0; scl_out <= 1'b0; end //把SDA先拉低
                        if (step == 1) begin sda_out <= 1'b0; scl_out <= 1'b1; end //再把SCL先拉高
                        if (step == 2) begin sda_out <= 1'b1; scl_out <= 1'b1; end // 在SCL为高时把SDA也拉高，产生STOP信号
                        if (step == 3) begin //准备通信结束
                            state <= DONE;
                        end
                    end

                    DONE: begin
                        // 组装并输出数据
                        // LM75A 16 位读取后，高 11 位为有效温度值,加最高位代表正负
                        temp_raw <= rx_data[15:4]; // 截取高 12-bit 作为输出结果
                        data_vld <= 1'b1;          // 拉高一拍有效信号
                        state    <= IDLE;          //回到空闲状态，等待轮询后再进入下一轮通信
                    end
                    
                    default: state <= IDLE;  //数据异常时，回到异常状态
                endcase
            end
        end
    end

endmodule