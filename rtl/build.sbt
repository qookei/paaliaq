ThisBuild / version := "1.0"
ThisBuild / scalaVersion := "2.12.16"

val spinalVersion = "1.8.0"
val spinalCore = "com.github.spinalhdl" %% "spinalhdl-core" % spinalVersion
val spinalLib = "com.github.spinalhdl" %% "spinalhdl-lib" % spinalVersion
val spinalIdslPlugin = compilerPlugin("com.github.spinalhdl" %% "spinalhdl-idsl-plugin" % spinalVersion)

lazy val paaliaq = (project in file("."))
	.settings(
		Compile / scalaSource := baseDirectory.value / "hw" / "spinal",
		libraryDependencies ++= Seq(spinalCore, spinalLib, spinalIdslPlugin)
	)

fork := true
