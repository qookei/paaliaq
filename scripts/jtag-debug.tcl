proc tx {v} {
    irscan ecp5.tap 0x38
    drscan ecp5.tap 8 $v
    return {}
}

proc rx {} {
    irscan ecp5.tap 0x32
    return 0x[drscan ecp5.tap 8 0]
}

proc poke {addr val} {
    tx 0x77
    tx [expr {($addr >> 0)  & 0xFF}]
    tx [expr {($addr >> 8)  & 0xFF}]
    tx [expr {($addr >> 16) & 0xFF}]
    tx $val
    rx
    return {}
}

proc peek {addr} {
    tx 0x72
    tx [expr {($addr >> 0)  & 0xFF}]
    tx [expr {($addr >> 8)  & 0xFF}]
    tx [expr {($addr >> 16) & 0xFF}]
    tx 0
    return [rx]
}


proc trace_en {} {
    poke 0x10408 0x04
}

proc trace_dis {} {
    poke 0x10408 0x00
}

proc trace_do_step {} {
    poke 0x10408 0x0c
}

proc trace_step {} {
    # Grab the address and bus state, then tick forward, then grab r/w data
    set va [peek 0x1040c]
    set va [expr {$va | ([peek 0x1040d] << 8)}]
    set va [expr {$va | ([peek 0x1040e] << 16)}]

    set pa [peek 0x10414]
    set pa [expr {$pa | ([peek 0x10415] << 8)}]
    set pa [expr {$pa | ([peek 0x10416] << 16)}]

    set bus [peek 0x10409]

    set vpa [expr {$bus & (1 << 0)}]
    set vda [expr {$bus & (1 << 1)}]
    set vpb [expr {$bus & (1 << 2)}]
    set rwb [expr {$bus & (1 << 3)}]

    trace_do_step

    set rdata [peek 0x10411]
    set wdata [peek 0x10410]

    format "%06x %s %s%s%s%s %s" \
	$va \
	[expr {($vda | $vpa) ? [format "%06x" $pa] : "??????"}] \
	[expr {$vpa ? "P" : "-"}] \
	[expr {$vda ? "D" : "-"}] \
	[expr {$vpb ? "-" : "V"}] \
	[expr {($vda | $vpa) ? ($rwb ? "R" : "W") : "-"}] \
	[expr {($vda | $vpa) ? [format "%02x" [expr {$rwb ? $rdata : $wdata}]] : "??"}]
}
