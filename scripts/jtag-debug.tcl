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
