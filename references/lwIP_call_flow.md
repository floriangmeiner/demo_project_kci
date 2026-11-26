STM32F746G-DISCO · lwIP + FreeRTOS (CMSIS-RTOS v2) · CubeMX 6.18.1

# lwIP Call Flow

How one UDP datagram travels between the Ethernet hardware and `linkTask`, in each direction. Function names come from this project's generated code and the lwIP and HAL sources it ships with.

## Who runs what

Each column in the diagrams is a separate execution context. Work passes between them only through a semaphore or a message queue.

| Context | Priority | Stack | Waits on | Job |
| --- | --- | --- | --- | --- |
| Hardware | n/a | n/a | n/a | LAN8742 PHY, MAC and DMA move frames between the wire and RAM |
| `ETH_IRQHandler` | NVIC 6 | Main stack | n/a | Only releases a semaphore |
| `EthIf` | Realtime (48) | 350 B, raising to 1024 | `RxPktSemaphore` | Turns DMA buffers into pbufs, posts them to `tcpip_thread` |
| `tcpip_thread` | Normal (24) | 4096 B | `tcpip_mbox` (6 slots) | All of lwIP: ARP, IP, UDP, TCP, timers, TFTP |
| `linkTask` | Yours | Yours | `conn->recvmbox` | Your telemetry link, through the netconn API |

Function call in the same context Hand-off to another context (semaphore or queue)

## Receiving: wire to `linkTask`

```mermaid
sequenceDiagram
  autonumber
  participant HW as HardwarePHY + MAC + DMA
  participant ISR as ETH interruptNVIC priority 6
  participant EI as EthIf threadRealtime
  participant TT as tcpip_threadNormal
  participant LT as linkTaskyour thread
  Note over EI: blocked in osSemaphoreAcquire(RxPktSemaphore)
  Note over LT: blocked in netconn_recv()sys_arch_mbox_fetch(conn->recvmbox)
  HW->>HW: DMA writes the frame into an RX_POOL buffer
  HW->>ISR: ETH_IRQHandler()
  ISR->>ISR: HAL_ETH_IRQHandler()→ HAL_ETH_RxCpltCallback()
  ISR-)EI: osSemaphoreRelease(RxPktSemaphore)
  loop until HAL_ETH_ReadData returns no frame
    EI->>EI: low_level_input() → HAL_ETH_ReadData()RxLinkCallback wraps the buffer in a pbufRxAllocateCallback refills the descriptor
    EI-)TT: netif->input = tcpip_input(p)→ tcpip_inpkt() → sys_mbox_trypost(tcpip_mbox)
  end
  TT->>TT: tcpip_thread_handle_msg() → ethernet_input()→ ip4_input() → udp_input()
  TT-)LT: pcb->recv = recv_udp()→ sys_mbox_trypost(conn->recvmbox, netbuf)
  LT->>LT: netconn_recv() returns the netbufnetbuf_data() gives your bytes
  LT->>LT: netbuf_delete() → pbuf_free()→ pbuf_free_custom(): buffer back to RX_POOL
```

- **The interrupt does one thing.** `HAL_ETH_RxCpltCallback` in `ethernetif.c` only releases `RxPktSemaphore`. Because the interrupt calls an RTOS function, its NVIC priority must be 5 or higher (`configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY`). It's 6.
- **Zero copy.** The DMA writes straight into an `RX_POOL` buffer, and the pbuf wraps that same memory. Nothing is copied until you copy it out of the netbuf.
- **Free your netbuf promptly.** The pool has 12 buffers. Every netbuf you hold keeps one. When all 12 are held, reception stops. `pbuf_free_custom` then releases `RxPktSemaphore` so `EthIf` can refill the ring.
- **Drops happen quietly.** If `tcpip_mbox` (6 slots) or your `recvmbox` is full, `sys_mbox_trypost` fails and the packet is freed. UDP doesn't retry, so your protocol's sequence numbers will show the gap.

## Sending: `linkTask` to wire

```mermaid
sequenceDiagram
  autonumber
  participant LT as linkTaskyour thread
  participant TT as tcpip_threadNormal
  participant HW as HardwareMAC + DMA
  participant ISR as ETH interruptNVIC priority 6
  LT->>LT: netbuf_new() + netbuf_alloc()copy your frame in
  LT-)TT: netconn_send() → netconn_apimsg()→ tcpip_send_msg_wait_sem(): post to tcpip_mbox
  Note over LT: blocked on the message's semaphore
  TT->>TT: lwip_netconn_do_send() → udp_send()→ udp_sendto_if_src() → ip4_output_if_src()
  TT->>TT: netif->output = etharp_output()looks up the Pi's MAC address
  alt MAC address not in the ARP table yet
    TT->>HW: etharp_query(): hold the packet, send an ARP request
    Note over TT: the held packet goes out when the ARP replyarrives on the receive path
  end
  TT->>TT: ethernet_output() adds the Ethernet header
  TT->>HW: netif->linkoutput = low_level_output()pbuf_ref(p), HAL_ETH_Transmit_IT()
  TT-)LT: sys_sem_signal(): the API call is done
  LT->>LT: netconn_send() returns ERR_OK
  HW->>HW: DMA reads the frame from RAMMAC inserts the checksums
  HW->>ISR: frame sent: ETH_IRQHandler()
  ISR-)TT: HAL_ETH_TxCpltCallback()→ osSemaphoreRelease(TxPktSemaphore)
```

- **No transmit thread.** Everything from `lwip_netconn_do_send` to `HAL_ETH_Transmit_IT` runs inside `tcpip_thread`.
- **`netconn_send` returns before the frame is on the wire.** `HAL_ETH_Transmit_IT` only queues a DMA descriptor. That's why the example copies the frame with `netbuf_alloc`: with `netbuf_ref` the DMA would read your own buffer later, so you couldn't reuse it straight away.
- **`TxPktSemaphore` is usually not waited on.** `low_level_output` waits on it only when `HAL_ETH_Transmit_IT` reports the descriptor ring is busy. It then calls `HAL_ETH_ReleaseTxPacket`, which frees the sent pbufs through `HAL_ETH_TxFreeCallback`, and retries. So sent pbufs stay allocated until the ring fills up.
- **The first packet to the Pi costs an ARP round trip.** lwIP's default `ARP_QUEUEING` is 0, so only the latest packet is held while it waits. Send a few packets in a row at start-up and the earlier ones are dropped.

## Rules for your code

### Only `tcpip_thread` touches lwIP's core

From `linkTask`, use the netconn or socket API. They post a message and block, as in step 2 of the send path. Don't call `udp_send`, `udp_new` or `tcp_write` from your own thread.

### TFTP runs inside `tcpip_thread`

lwIP's TFTP server uses the raw API, so its callbacks are called straight from `udp_input`, with no `recvmbox` step. Keep them short: hand slow work such as flash erases to another thread.

Sources: `LWIP/Target/ethernetif.c`, `LWIP/App/lwip.c`, `Middlewares/Third_Party/LwIP/src/api/` (tcpip.c, api_lib.c, api_msg.c), `src/core/` (udp.c, ipv4/ip4.c, ipv4/etharp.c), `src/netif/ethernet.c`, `system/OS/sys_arch.c` and `stm32f7xx_hal_eth.c`.