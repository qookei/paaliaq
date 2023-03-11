/* Paaliaq - Memory management unit
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

case class MMUIface() extends Bundle with IMasterSlave {
	val enable = Bool()
	val rd     = Bool()
	val wr     = Bool()
	val exec   = Bool()
	val vaddr  = UInt(24 bits)
	val paddr  = UInt(24 bits)
	val abort  = Bool()

	override def asMaster() : Unit = {
		out(enable, vaddr, rd, wr, exec)
		in(paddr, abort)
	}
}

case class TlbEntry(tagBits: BitCount, pageBits: BitCount) extends Bundle {
	val tag = UInt(tagBits)
	val paddr = UInt(pageBits)
	val user, exec, write, valid = Bool()
}

case class MMU(numWays: Int, numSets: Int, pageSize: Int, initialMappings: Seq[(Int, Int)]) extends Component {
	assert(isPow2(pageSize), "MMU: Page size is not a power of two")

	val pageBits = log2Up(pageSize)
	val offsetBits = 24 - pageBits

	val setBits = log2Up(numSets)
	val wayBits = log2Up(numWays)
	val tagBits = pageBits - setBits
	val tagOffset = offsetBits + setBits

	val tlbEntrySize = TlbEntry(tagBits bits, pageBits bits).getBitsWidth bits

	val io = slave(MMUIface())

	val ways = (0 until numWays).map(_ => Mem(Bits(tlbEntrySize), numSets))

	val curPageOffset = io.vaddr.resize(offsetBits bits)
	val curTag = (io.vaddr >> tagOffset).resize(tagBits bits)
	val curSet = Reg(UInt(setBits bits))

	val curWays = Vec(TlbEntry(tagBits bits, pageBits bits), numWays)
	curWays.zipWithIndex.foreach({ case (w, i) => {
		w.assignFromBits(ways(i)(curSet))
	}})

	val curWayIdx = (curWays.zipWithIndex.map({ case (w, i) => {
		(w.tag === curTag) ? U(i).resize(wayBits bits) | 0
	}}).reduce(_ | _))

	val curEntry = curWays(curWayIdx)

	/*


	val curWays = Vec(TlbEntry(tagBits bits, pageBits bits), numWays)
	curWays.zipWithIndex.foreach({ case (w, i) => {
		w.assignFromBits(ways(i)(curSet))
	}})

	val curWayIdx = curWays.zipWithIndex.map({ case (w, i) => {
		(w.tag === curTag) ? U(i).resize(wayBits bits) | 0
	}}).reduce(_ | _)
*/
	//val curEntry = Reg(TlbEntry(tagBits bits, pageBits bits))

	//val curLine = curWays(curWayIdx)

	val curHit = curEntry.valid & (curEntry.tag === curTag)

/*	val cacheLines = Vec(Reg(TlbEntry()) allowUnsetRegToAvoidLatch, numCacheLines)
	cacheLines.zipWithIndex.foreach({ case (l, i) => {
		// Prefill first N cache lines with predefined mappings to map in boot ROM
		if (i < initialMappings.size) {
			val (vaddr, paddr) = initialMappings(i)
			l.tag init vaddr >> 12
			l.paddr init paddr >> 12
			l.user init False
			l.exec init True
			l.write init True
			l.valid init True
		} else {
			l.tag init 0
			l.paddr init 0
			l.user init False
			l.exec init False
			l.write init False
			l.valid init False
		}
	}})

	val curTag = (io.vaddr >> 12).resize(12 bits)
	val curPageOffset = io.vaddr.resize(12 bits)

	val curLineIdx = cacheLines.zipWithIndex.map({ case (l, i) => {
		(l.tag === curTag) ? U(i).resize(log2Up(numCacheLines) bits) | 0
	}}).reduce(_ | _)
	val curLine = cacheLines(curLineIdx)
*/

	io.paddr := (curEntry.paddr << offsetBits) | curPageOffset.resized

	val abortWrite = io.wr & !curEntry.write
	val abortExec  = io.exec & !curEntry.exec
	val abortMiss  = (io.rd | io.wr | io.exec) & !curHit
	val abortPerms = abortExec | abortWrite

	io.abort := abortMiss | abortPerms

	val faultAddr = Reg(UInt(24 bits)) init 0
	val faultReason = Reg(Bits(8 bits)) init 0

	when(io.enable) {
		curSet := (io.vaddr >> offsetBits).resize(setBits bits)
	}

	val busIf = new Area {
		val io = slave(BusIface())

		val stage = Reg(Bool()) init False
		val rdData = Reg(UInt(8 bits)) init 0

		io.rd_data := rdData

		io.done := io.enable & stage

		when (io.enable.rise) {
			stage := False
		}

		val setIdx = Reg(UInt(setBits bits)) init 0
		val wayIdx = Reg(UInt(wayBits bits)) init 0

		val tlbPart0 = Reg(UInt(8 bits)) init 0
		val tlbPart1 = Reg(UInt(8 bits)) init 0

		when (io.enable & !stage) {
			switch (io.rdwr) {
				is(False) {
					switch(io.paddr) {
						is(0x000) { setIdx := io.wr_data.resized }
						is(0x001) { wayIdx := io.wr_data.resized }
						is(0x002) { tlbPart0 := io.wr_data }
						is(0x003) { tlbPart1 := io.wr_data }
						is(0x004) {
							val entry = (io.wr_data
									## tlbPart1
									## tlbPart0).resize(tlbEntrySize)

							switch(wayIdx) {
								ways.zipWithIndex.map({ case (w, i) => {
									is(i) { w(setIdx) := entry.resize(tlbEntrySize) }
								}})
							}
						}
					}
				}
				is(True) {
					switch(io.paddr) {
						is(0x000, 0x001, 0x002) {
							rdData := faultAddr.subdivideIn(8 bits)(io.paddr.resized)
						}
						is(0x003) { rdData := faultReason.asUInt }
						default { rdData := 0 }
					}
				}
			}
		}

		when (io.enable) { stage := !stage }
	}

	when (io.abort) {
		faultAddr := io.vaddr
		faultReason := abortMiss ## abortPerms ## abortWrite ## abortExec ## B"0000"
		busIf.setIdx := curSet
	}
}
