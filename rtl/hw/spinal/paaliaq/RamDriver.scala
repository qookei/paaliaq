package paaliaq

import spinal.core._
import spinal.lib._
import spinal.lib.io._

case class RamIo(addrBits: BitCount) extends Bundle {
	val addr = out UInt(addrBits)
	val data = master(TriState(UInt(8 bits)))

	val chipEn  = out Bool()
	val readEn  = out Bool()
	val writeEn = out Bool()
}

case class RamDriver(addrBits: BitCount) extends Component {
	val io = RamIo(addrBits)
	val busIo = slave(BusIface())

	io.data.writeEnable := !busIo.rdwr
	io.chipEn := busIo.enable
	io.readEn := busIo.rdwr
	io.writeEn := !busIo.rdwr

	io.addr := busIo.paddr.resized
	io.data.write := busIo.wr_data

	val stage = Reg(Bool()) init False
	val rdData = Reg(UInt(8 bits))

	busIo.rd_data := rdData

	busIo.done := busIo.enable & stage

	when (busIo.enable.rise) {
		stage := False
	}

	when (busIo.enable) {
		when (stage & busIo.rdwr) { rdData := io.data.read }
		stage := !stage
	}
}
