# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

# G1 memory probe (hw/probe/mem_probe.mli): shift a 32-bit {we, addr, data}
# word MSB first on ui_in[2] while ui_in[1] is high; uo_out shows rdata[7:0],
# or rdata[15:8] when ui_in[3] is high.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

WRITES = [(0x1234, 0), (0xBEEF, 1), (0x0001, 127), (0xFFFF, 64)]


async def start(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())  # 50 MHz
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2)
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1


async def send(dut, we, addr, data):
    word = (we << 31) | (addr << 16) | data
    for b in range(31, -1, -1):
        dut.ui_in.value = 0b010 | (((word >> b) & 1) << 2)
        await FallingEdge(dut.clk)
    dut.ui_in.value = 0
    await FallingEdge(dut.clk)


async def read(dut, addr):
    await send(dut, 0, addr, 0)
    lo = int(dut.uo_out.value)
    dut.ui_in.value = 0b1000
    await FallingEdge(dut.clk)
    hi = int(dut.uo_out.value)
    dut.ui_in.value = 0
    return (hi << 8) | lo


@cocotb.test()
async def test_writes_then_reads_4_addresses(dut):
    await start(dut)
    for data, addr in WRITES:
        await send(dut, 1, addr, data)
    for data, addr in WRITES:
        got = await read(dut, addr)
        assert got == data, f"addr {addr}: got {got:#06x}, want {data:#06x}"


@cocotb.test()
async def test_reset_releases_uio(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())  # 50 MHz
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    for rst_n in [0] * 5 + [1] * 5:
        await FallingEdge(dut.clk)
        dut.rst_n.value = rst_n
        await RisingEdge(dut.clk)
        await ReadOnly()
        assert dut.uio_oe.value == 0
