/* Paaliaq - SoC top level
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
import spinal.lib.bus.misc._

case class TopLevel() extends Component {
	val cpuIo = CpuIo()
	val cpuDriver = CpuDriver()
	cpuDriver.io <> cpuIo

	val mmu = MMU(numWays = 2, numSets = 256, pageSize = 0x1000, initialMappings = List(
		0x0000 -> 0x000000,
		0x1000 -> 0x001000,
	))
	cpuDriver.mmuIo <> mmu.io

	val ramIo = RamIo(21 bits)
	val ramDriver = RamDriver(21 bits)
	ramDriver.io <> ramIo

	// (0x000000, 8 MiB), // RAM
	// (0x800000, 4 KiB), // MMU
	// (0x801000, 4 KiB), // INTC
	// (0x802000, 4 KiB), // TIMER
	// (0x803000, 4 KiB), // UART
	// (0x804000, 4 KiB), // SPI
	// (0x805000, 4 KiB), // GPIO
	// (0xFFF000, 4 KiB), // Boot ROM

	val bus = Bus(masters = List(cpuDriver.busIo), slaves = List(
		ramDriver.busIo -> SizeMapping(0x000000, 8 MiB),
		mmu.busIf.io -> SizeMapping(0x800000, 4 KiB),
	))
}

object TopLevelVerilog extends App {
	Config.spinal.generateVerilog(InOutWrapper(TopLevel())).printPruned()
}
