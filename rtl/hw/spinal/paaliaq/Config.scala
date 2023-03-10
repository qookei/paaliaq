package paaliaq

import spinal.core._

object Config {
	def spinal = SpinalConfig(
		targetDirectory = "hw/gen",
		defaultConfigForClockDomains = ClockDomainConfig(
			resetActiveLevel = HIGH
		),
		onlyStdLogicVectorAtTopLevelIo = true,
		device = Device.LATTICE
	)
}
