/* Paaliaq - Bus interconnect
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
import spinal.lib.bus.misc._

case class BusIface() extends Bundle with IMasterSlave {
	val enable  = Bool()
	val paddr   = UInt(24 bits)
	val rd_data = UInt(8 bits)
	val wr_data = UInt(8 bits)
	val rdwr    = Bool()
	val done    = Bool()

	override def asMaster() : Unit = {
		out(enable, paddr, wr_data, rdwr)
		in(rd_data, done)
	}
}

case class Bus(numMasters: Int, decodings: Seq[SizeMapping]) extends Component {
	assert(!SizeMapping.verifyOverlapping(decodings), "Bus: overlapping decodings")

	val fromMasters = Vec(slave(BusIface()), numMasters)
	val toSlaves = Vec(master(BusIface()), decodings.length)

	val stage = Reg(Bool()) init True
	val masterSel = Reg(UInt(log2Up(numMasters) bits)) init 0
	val curMaster = masterSel.muxList(fromMasters.zipWithIndex.map(p => p.swap))

	//val done = Reg(Bool()) init False
	//val data = Reg(UInt(8 bits))

	for ((toSlave, decoding) <- toSlaves.zip(decodings)) {
		val sel = curMaster.enable ? decoding.hit(curMaster.paddr) | False

		toSlave.enable := sel
		toSlave.paddr := decoding.removeOffset(curMaster.paddr).resize(24 bits)
		toSlave.wr_data := curMaster.wr_data
		toSlave.rdwr := curMaster.rdwr

		//when (sel & stage) {
		//	data := toSlave.rd_data
		//	done := toSlave.done
		//}
	}

	for (fromMaster <- fromMasters) {
		fromMaster.rd_data := toSlaves.map(s => {
			s.enable ? s.rd_data | 0
		}).reduce(_ | _)

		fromMaster.done := toSlaves.map(s => {
			s.enable ? s.done | False
		}).reduce(_ | _)
	}

	//for (fromMaster <- fromMasters) {
	//	fromMaster.rd_data := data
	//	fromMaster.done := done & fromMaster.enable
	//}

	when(!stage) {
		//done := False

		masterSel := PriorityMux(
			fromMasters.map(m => m.enable) ++ List(True),
			(Seq.range(0, numMasters) ++ List(0)).map(i => U(i)))
	}

	stage := !stage
}

object Bus {
	def apply(masters: Seq[BusIface], slaves: Seq[(BusIface, SizeMapping)]) : Bus = {
		val bus = Bus(masters.size, slaves.map(s => s._2))

		for ((master, i) <- masters.zipWithIndex) {
			bus.fromMasters(i) <> master
		}

		for (((slave, decoding), i) <- slaves.zipWithIndex) {
			bus.toSlaves(i) <> slave
		}

		bus
	}
}
