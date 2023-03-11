/* Paaliaq - RAM bus interface
 * Copyright (C) 2023  qookie
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License, as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your opinion) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

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
