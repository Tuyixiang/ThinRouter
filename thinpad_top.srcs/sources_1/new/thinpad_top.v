`default_nettype none

module thinpad_top(
    input wire clk_50M,           // 50MHz 时钟输入
    input wire clk_11M0592,       // 11.0592MHz 时钟输入

    input wire clock_btn,         // BTN5手动时钟按钮开关，带消抖电路，按下时为1
    input wire reset_btn,         // BTN6手动复位按钮开关，带消抖电路，按下时为1

    input  wire[3:0]  touch_btn,  // BTN1~BTN4，按钮开关，按下时为1
    input  wire[31:0] dip_sw,     // 32位拨码开关，拨到“ON”时为1
    output wire[15:0] leds,       // 16位LED，输出时1点亮
    output wire[7:0]  dpy0,       // 数码管低位信号，包括小数点，输出1点亮
    output wire[7:0]  dpy1,       // 数码管高位信号，包括小数点，输出1点亮

    // CPLD串口控制器信号
    output wire uart_rdn,         // 读串口信号，低有效
    output wire uart_wrn,         // 写串口信号，低有效
    input wire uart_dataready,    // 串口数据准备好
    input wire uart_tbre,         // 发送数据标志
    input wire uart_tsre,         // 数据发送完毕标志

    // BaseRAM信号
    inout wire[31:0] base_ram_data, // BaseRAM数据，低8位与CPLD串口控制器共享
    output wire[19:0] base_ram_addr,// BaseRAM地址
    output wire[3:0] base_ram_be_n, // BaseRAM字节使能，低有效。如果不使用字节使能，请保持为0
    output wire base_ram_ce_n,      // BaseRAM片选，低有效
    output wire base_ram_oe_n,      // BaseRAM读使能，低有效
    output wire base_ram_we_n,      // BaseRAM写使能，低有效

    // ExtRAM信号
    inout wire[31:0] ext_ram_data,  // ExtRAM数据
    output wire[19:0] ext_ram_addr, // ExtRAM地址
    output wire[3:0] ext_ram_be_n,  // ExtRAM字节使能，低有效。如果不使用字节使能，请保持为0
    output wire ext_ram_ce_n,       // ExtRAM片选，低有效
    output wire ext_ram_oe_n,       // ExtRAM读使能，低有效
    output wire ext_ram_we_n,       // ExtRAM写使能，低有效

    //直连串口信号
    output wire txd,                // 直连串口发送端
    input  wire rxd,                // 直连串口接收端

    // Flash存储器信号，参考 JS28F640 芯片手册
    output wire [22:0]flash_a,      // Flash地址，a0仅在8bit模式有效，16bit模式无意义
    inout  wire [15:0]flash_d,      // Flash数据
    output wire flash_rp_n,         // Flash复位信号，低有效
    output wire flash_vpen,         // Flash写保护信号，低电平时不能擦除、烧写
    output wire flash_ce_n,         // Flash片选信号，低有效
    output wire flash_oe_n,         // Flash读使能信号，低有效
    output wire flash_we_n,         // Flash写使能信号，低有效
    output wire flash_byte_n,       // Flash 8bit模式选择，低有效。在使用flash的16位模式时请设为1

    // USB+SD 控制器信号，参考 CH376T 芯片手册
    output wire ch376t_sdi,
    output wire ch376t_sck,
    output wire ch376t_cs_n,
    output wire ch376t_rst,
    input  wire ch376t_int_n,
    input  wire ch376t_sdo,

    // 网络交换机信号，参考 KSZ8795 芯片手册及 RGMII 规范
    input  wire [3:0] eth_rgmii_rd,
    input  wire eth_rgmii_rx_ctl,
    input  wire eth_rgmii_rxc,
    output wire [3:0] eth_rgmii_td,
    output wire eth_rgmii_tx_ctl,
    output wire eth_rgmii_txc,
    output wire eth_rst_n,
    input  wire eth_int_n,

    input  wire eth_spi_miso,
    output wire eth_spi_mosi,
    output wire eth_spi_sck,
    output wire eth_spi_ss_n,

    //图像输出信号
    output wire[2:0] video_red,     // 红色像素，3位
    output wire[2:0] video_green,   // 绿色像素，3位
    output wire[1:0] video_blue,    // 蓝色像素，2位
    output wire video_hsync,        // 行同步（水平同步）信号
    output wire video_vsync,        // 场同步（垂直同步）信号
    output wire video_clk,          // 像素时钟输出
    output wire video_de            // 行数据有效信号，用于区分消隐区
);

// PLL分频示例
wire locked, clk_10M, clk_20M, clk_125M, clk_200M;
pll_example clock_gen 
 (
  // Clock out ports
  .clk_out1(clk_10M),       // 时钟输出1
  .clk_out2(clk_20M),       // 时钟输出2
  .clk_out3(clk_125M),      // 时钟输出3
  .clk_out4(clk_200M),      // 时钟输出4
  .reset(reset_btn),        // PLL 复位输入
  .locked(locked),          // 锁定输出，"1"表示时钟稳定，可作为后级电路复位
  .clk_in1(clk_50M)         // 外部时钟输入
 );

// 以太网交换机

assign eth_rst_n = ~reset_btn;

eth_conf conf(
    .clk(clk_50M),
    .rst_in_n(locked),

    .eth_spi_miso(eth_spi_miso),
    .eth_spi_mosi(eth_spi_mosi),
    .eth_spi_sck(eth_spi_sck),
    .eth_spi_ss_n(eth_spi_ss_n),

    .done()
);

/**********************
 *      路由模块      *
 *********************/

rgmii_manager rgmii_manager_inst (
    .clk_rgmii(clk_125M),
    .clk_internal(clk_125M),
    .clk_ref(clk_200M),
    .rst(reset_btn),
    .eth_rgmii_rd(eth_rgmii_rd),
    .eth_rgmii_rx_ctl(eth_rgmii_rx_ctl),
    .eth_rgmii_rxc(eth_rgmii_rxc),
    .eth_rgmii_td(eth_rgmii_td),
    .eth_rgmii_tx_ctl(eth_rgmii_tx_ctl),
    .eth_rgmii_txc(eth_rgmii_txc),
    .eth_rst_n(eth_rst_n)
);

endmodule
