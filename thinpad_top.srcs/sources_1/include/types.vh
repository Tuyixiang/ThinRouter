`ifndef TYPES_MACRO
`define TYPES_MACRO

typedef logic [31:0] ip_t;
typedef logic [47:0] mac_t;
typedef logic [15:0] time_t;

typedef struct packed {
    ip_t addr;
    ip_t len;
    ip_t nexthop;
    ip_t metric;
} rip_entry_t;

// 由 packet_processor 存入 fifo 提供给路由表模块
typedef struct packed {
    ip_t  prefix;
    ip_t  nexthop;
    logic [5:0] mask;
    logic [4:0] metric;
    // 这个 RIP response 来自哪个接口（而不是 nexthop 的接口）
    logic [2:0] from_vlan;
} routing_entry_t;

`endif