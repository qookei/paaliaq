package paaliaq

import spinal.core._
import spinal.lib._
import spinal.lib.io._

case class CpuIo() extends Bundle {
	val clk = out Bool()
	val rst = out Bool()

	val addr = in UInt(16 bits)
	val data = master(TriState(UInt(8 bits)))

	val rwb = in Bool()
	val vda = in Bool()
	val vpa = in Bool()
	val vpb = in Bool()

	val abort = out Bool()
}

case class CpuDriver() extends Component {
	val io = CpuIo()

	val busIo = master(BusIface())
	val mmuIo = master(MMUIface())

	io.clk.setAsReg()
	io.rst.setAsReg()
	io.data.writeEnable.setAsReg()
	io.abort.setAsReg()

	io.rst := False

	val state = Reg(UInt(3 bits)) init 0

	val vaddr = Reg(UInt(24 bits)) init 0
	val rwb   = Reg(Bool()) init False
	val vda   = Reg(Bool()) init False
	val vpa   = Reg(Bool()) init False
	val vpb   = Reg(Bool()) init False

	// Set to true when an abort is initiated, cleared when VDA=VPA=1 (vector entry sequence)
	// We should ignore all I/O the CPU does if this is set
	val isAborting = Reg(Bool()) init False
	val valid = (vda | vpa) & !isAborting

	io.data.write := busIo.rd_data
	busIo.rdwr := valid & rwb
	busIo.wr_data.setAsReg()
	busIo.enable.setAsReg()
	busIo.paddr := mmuIo.paddr

	mmuIo.vaddr := vaddr
	mmuIo.enable.setAsReg()
	mmuIo.rd.setAsReg()
	mmuIo.wr.setAsReg()
	mmuIo.exec.setAsReg()

	switch(state) {
		is(0) {
			io.clk := False
			io.abort := False

			busIo.wr_data := io.data.read
		}
		is(1) {
			busIo.enable := valid & !rwb

			io.data.writeEnable := False
		}
		is(2) {
			vaddr := (io.data.read ## io.addr).asUInt
			rwb := io.rwb
			vda := io.vda
			vpa := io.vpa
			vpb := io.vpb

			isAborting := isAborting & !(io.vda & io.vpa)
			mmuIo.rd := valid & io.rwb
			mmuIo.wr := valid & !io.rwb
			mmuIo.exec := valid & io.rwb & io.vda & io.vpa
			mmuIo.enable := True
		}
		is(3) {
			io.abort := mmuIo.abort
			isAborting := mmuIo.abort
			busIo.enable := False
		}
		is(4) {
			io.clk := True
			mmuIo.enable := False
		}
		is(5, 6) {}
		is(7) {
			io.data.writeEnable := valid & rwb
			busIo.enable := valid & rwb
		}
	}

	state := state + 1
}
