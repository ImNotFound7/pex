# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge


async def start(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())  # 50 MHz
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0


@cocotb.test()
async def test_counts(dut):
    await start(dut)
    await ClockCycles(dut.clk, 2)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 3)
    await ReadOnly()
    assert dut.uo_out.value == 3


@cocotb.test()
async def test_reset_releases_uio(dut):
    await start(dut)
    for rst_n in [0] * 5 + [1] * 5:
        await FallingEdge(dut.clk)
        dut.rst_n.value = rst_n
        await RisingEdge(dut.clk)
        await ReadOnly()
        assert dut.uio_oe.value == 0
