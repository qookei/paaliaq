#include "cpu.hpp"
#include <iostream>
#include <bit>
#include <array>
#include <algorithm>

int w65c816::determine_operand_length() {
	auto aaa = opcode_ >> 5 & 0b111;
	auto bbb = opcode_ >> 2 & 0b111;
	auto cc  = opcode_      & 0b011;

	if ((opcode_ & 0b11111) == 0b10000) // Bcc
		return 1;

	switch (opcode_) {
		case 0x08: // PHP
		case 0x0B: // PHD
		case 0x18: // CLC
		case 0x1A: // INA
		case 0x1B: // TCS
		case 0x28: // PLP
		case 0x2B: // PLD
		case 0x38: // SEC
		case 0x3A: // DEA
		case 0x3B: // TSC
		case 0x40: // RTI
		case 0x42: // WDM NOTE: Although it has an operand byte, it is not fetched (PC updated in exec_op)
		case 0x48: // PHA
		case 0x4B: // PHK
		case 0x58: // CLI
		case 0x5A: // PHY
		case 0x5B: // TCD
		case 0x60: // RTS
		case 0x68: // PLA
		case 0x6B: // RTL
		case 0x78: // SEI
		case 0x7A: // PLY
		case 0x7B: // TDC
		case 0x88: // DEY
		case 0x8A: // TXA
		case 0x8B: // PHB
		case 0x98: // TYA
		case 0x9A: // TXS
		case 0x9B: // TXY
		case 0xA8: // TAY
		case 0xAA: // TAX
		case 0xAB: // PLB
		case 0xB8: // CLV
		case 0xBA: // TSX
		case 0xBB: // TYX
		case 0xC8: // INY
		case 0xCA: // DEX
		case 0xCB: // WAI
		case 0xD8: // CLD
		case 0xDA: // PHX
		case 0xDB: // STP
		case 0xE8: // INX
		case 0xEA: // NOP
		case 0xEB: // XBA
		case 0xF8: // SED
		case 0xFA: // PLX
		case 0xFB: // XCE
			return 0;

		case 0x00: // BRK sig
		case 0x02: // COP sig
		case 0x80: // BRA r
		case 0xC2: // REP imm
		case 0xD4: // PEI dp, d
		case 0xE2: // SEP imm
			return 1;

		case 0x20: // JSR abs
		case 0x44: // MVP sb, db
		case 0x54: // MVN sb, db
		case 0x62: // PER rl
		case 0x82: // BRL rl
		case 0xDC: // JML (abs)
		case 0xF4: // PEA abs
		case 0xFC: // JSR (abs, X)
			return 2;

		case 0x22: // JSL absl
		case 0x5C: // JMP absl
			return 3;
	}

	if (cc == 0b00) {
		switch (bbb) {
			case 0: // imm (X/Y index)
				return r_.is_xy_wide() ? 2 : 1;
			case 3: // abs
			case 7: // abs, X
				return 2;
			case 1: // dp, d
			case 5: // dp, d, X
				return 1;
			case 2:
			case 4:
			case 6: abort();
		}
	} else if (cc == 0b01) {
		switch (bbb) {
			case 0: // (dp, d, X)
			case 1: // dp, d
			case 4: // (dp, d), Y
			case 5: // dp, d, X
				return 1;
			case 3: // abs
			case 6: // abs, Y
			case 7: // abs, X
				return 2;
			case 2: // imm (accumulator)
				return r_.is_a_wide() ? 2 : 1;
		}
	} else if (cc == 0b10) {
		switch (bbb) {
			case 0: // imm (X index)
				return r_.is_xy_wide() ? 2 : 1;
			case 1: // dp, d
			case 4: // (dp, d) { instructions for cc == 0b01 }
			case 5: // dp, d, X/Y
				return 1;
			case 2: // A
				return 0;
			case 3: // abs
			case 7: // abs, X/Y
				return 2;
			case 6: abort();
		}
	} else if (cc == 0b11) {
		switch (bbb) {
			case 0: // d, S
			case 1: // [dp, d]
			case 4: // (d, S), Y
			case 5: // [dp, d], Y
				return 1;
			case 3: // absl
			case 7: // absl, X
				return 3;
			case 2:
			case 6: abort();
		}
	}

	abort();
}

void w65c816::compute_operand_target_() {
	target_bank_ = 0;
	target_addr_ = 0;
	target_kind_ = target_kind::none;
	inner_target_kind_ = target_kind::none;
	target_indirect_len_ = 0;
	target_indexed_ = false;
	target_wrap_in_bank_ = false;

	auto val16 = [this] () -> uint16_t {
		return uint16_t{operand_buf_[1]} << 8 | operand_buf_[0];
	};

	auto sext8_16 = [this] () -> uint16_t {
		return uint16_t(operand_buf_[0] & 0x80 ? 0xFF00 : 0x0000)
			| operand_buf_[0];
	};

	auto rel8 = [&] {
		target_bank_ = r_.pbr;
		target_addr_ = r_.pc + sext8_16();
		target_kind_ = target_kind::address;
	};

	auto rel16 = [&] {
		target_bank_ = r_.pbr;
		target_addr_ = r_.pc + val16();
		target_kind_ = target_kind::address;
	};

	auto imm8 = [&] {
		target_addr_ = operand_buf_[0];
		target_kind_ = target_kind::immediate;
	};

	auto imm16 = [&] {
		target_addr_ = val16();
		target_kind_ = target_kind::immediate;
	};

	auto imm_reg = [&] (bool wide) {
		if (wide)
			imm16();
		else
			imm8();
	};

	auto abs = [&] (uint16_t offset = 0) {
		uint32_t v1 = uint32_t{val16()};
		uint32_t v2 = uint32_t{val16()} + offset;

		target_bank_ = r_.dbr + (v2 >> 16);
		target_bank_preindex_ = r_.dbr;
		target_addr_ = v2 & 0xFFFF;
		target_addr_preindex_ = v1 & 0xFFFF;
		target_kind_ = target_kind::address;
	};

	auto absl = [&] (uint16_t offset = 0) {
		uint32_t v1 = uint32_t{val16()};
		uint32_t v2 = uint32_t{val16()} + offset;

		target_bank_ = operand_buf_[2] + (v2 >> 16);
		target_bank_preindex_ = operand_buf_[2];
		target_addr_ = v2 & 0xFFFF;
		target_addr_preindex_ = v1 & 0xFFFF;
		target_kind_ = target_kind::far_address;
	};

	auto dp = [&] (uint16_t offset = 0) {
		uint16_t v1 = r_.e
			? r_.d + (uint16_t{operand_buf_[0]} & 0x00FF)
			: r_.d  + uint16_t{operand_buf_[0]};

		uint16_t v2 = r_.e
			? r_.d + ((uint16_t{operand_buf_[0]} + offset) & 0x00FF)
			: r_.d  + uint16_t{operand_buf_[0]} + offset;

		target_bank_ = 0;
		target_bank_preindex_ = 0;
		target_addr_ = v2;
		target_addr_preindex_ = v1;
		target_kind_ = target_kind::dp_address;
		target_wrap_in_bank_ = true;
	};

	auto sp = [&] {
		uint16_t v = r_.s + uint16_t{operand_buf_[0]};

		target_bank_ = 0;
		target_bank_preindex_ = 0;
		target_addr_ = v;
		target_addr_preindex_ = v;
		target_kind_ = target_kind::stack_address;
		target_wrap_in_bank_ = true;
	};

	auto aaa = opcode_ >> 5 & 0b111;
	auto bbb = opcode_ >> 2 & 0b111;
	auto cc  = opcode_      & 0b011;

	if (opcode_ == 0x80 || (opcode_ & 0b11111) == 0b10000) { // Bcc
		rel8();
		return;
	}

	switch (opcode_) {
		case 0x00: // BRK sig
		case 0x02: // COP sig
		case 0xC2: // REP imm
		case 0xE2: // SEP imm
			imm8();
			return;
		case 0x89: // BIT imm
			imm_reg(r_.is_a_wide());
			return;
		case 0x04: // TSB dp, d
		case 0x14: // TRB db, d
		case 0x64: // STZ db, d
			dp();
			return;
		case 0x74: // STZ db, d, X
			dp(r_.x);
			target_indexed_ = true;
			return;
		case 0x0C: // TRB abs
		case 0x1C: // TRB abs
		case 0x9C: // STZ abs
			abs();
			return;
		case 0x9E: // STZ abs, X
			abs(r_.x);
			target_indexed_ = true;
			return;
		case 0xD4: // PEI dp, d
			dp();
			target_indirect_len_ = 2;
			return;
		case 0x20: // JSR abs
		case 0xF4: // PEA abs
			abs();
			return;
		case 0x44: // MVP sb, db
		case 0x54: // MVN sb, db
			imm16();
			return;
		case 0x62: // PER rl
		case 0x82: // BRL rl
			rel16();
			return;
		case 0x6C: // JMP (abs) NOTE: This can be decoded with the second switch,
			   // but we ought to do it now to actually handle the indirection
			abs();
			target_bank_ = 0;
			target_indirect_len_ = 2;
			return;
		case 0xDC: // JML (abs)
			abs();
			target_bank_ = 0;
			target_wrap_in_bank_ = true;
			target_indirect_len_ = 3;
			return;
		case 0x7C: // JMP (abs, X) NOTE: Same reason as for 0x6C "JMP (abs)"
		case 0xFC: // JSR (abs, X)
			abs(r_.x);
			target_bank_ = r_.pbr;
			target_indirect_len_ = 2;
			target_indexed_ = true;
			return;
		case 0x22: // JSL absl
		case 0x5C: // JMP absl
			absl();
			return;
	}

	uint8_t addr_mode = (cc << 3) | bbb;
	// LDX and STX use Y instead of X for indexing
	bool use_y_not_x = opcode_ == 0x96 /* STX dp, d, Y */
			|| opcode_ == 0xB6 /* LDX dp, d, Y */
			|| opcode_ == 0xBE;/* LDX dp, d, Y */

	switch (addr_mode) {
		case 0b00000:
		case 0b10000: // Immediate (X/Y reg)
			imm_reg(r_.is_xy_wide());
			return;
		case 0b01010: // Immediate (A reg)
			imm_reg(r_.is_a_wide());
			return;
		case 0b01100: // (dp, d), Y
		case 0b10100: // (dp, d)
		case 0b11001: // [dp, d]
		case 0b11101: // [dp, d], Y
			target_indirect_len_ = cc == 0b11 ? 3 : 2;
			[[fallthrough]];
		case 0b00001: // dp, d
		case 0b01001: // dp, d
		case 0b10001: // dp, d
			dp();
			return;
		case 0b01000: // (dp, d, X)
			target_indirect_len_ = 2;
			[[fallthrough]];
		case 0b01101: // dp, d, X
		case 0b00101: // dp, d, X
		case 0b10101: // dp, d, X/Y
			dp(use_y_not_x ? r_.y : r_.x);
			target_indexed_ = true;
			return;
		case 0b11100: // (d, S), Y
			target_indirect_len_ = 2;
			[[fallthrough]];
		case 0b11000:
			sp(); // d, S
			return;
		case 0b00011: // abs
		case 0b01011: // abs
		case 0b10011: // abs
			abs();
			return;
		case 0b00111: // abs, X
		case 0b01111: // abs, X
		case 0b10111: // abs, X/Y
			abs(use_y_not_x ? r_.y : r_.x);
			target_indexed_ = true;
			return;
		case 0b01110: // abs, Y
			abs(r_.y);
			target_indexed_ = true;
			return;
		case 0b11011: // absl
			absl();
			return;
		case 0b11111: // absl, X
			absl(r_.x);
			target_indexed_ = true;
			return;
		case 0b10010: // A
			target_addr_ = r_.get_a();
			target_kind_ = target_kind::accumulator;
			return;
	}
}

void w65c816::determine_indirect_target_() {
	target_wrap_in_bank_ = target_wrap_in_bank_ && target_kind_ != target_kind::stack_address;
	inner_target_kind_ = target_kind_;
	target_bank_ = 0;
	target_bank_preindex_ = 0;
	target_addr_ = 0;
	target_addr_preindex_ = 0;
	target_kind_ = target_kind::none;
	target_indirect_len_ = 0;
	target_indexed_ = false;

	auto val16 = [this] () -> uint16_t {
		return io_data_ & 0xFFFF;
	};

	auto abs = [&] (uint16_t offset = 0) {
		uint32_t v1 = uint32_t{val16()};
		uint32_t v2 = uint32_t{val16()} + offset;

		target_bank_ = r_.dbr + (v2 >> 16);
		target_bank_preindex_ = r_.dbr;
		target_addr_ = v2 & 0xFFFF;
		target_addr_preindex_ = v1 & 0xFFFF;
		target_kind_ = target_kind::address;
	};

	auto absl = [&] (uint16_t offset = 0) {
		uint32_t v1 = uint32_t{val16()};
		uint32_t v2 = uint32_t{val16()} + offset;

		target_bank_ = ((io_data_ >> 16) & 0xFF) + (v2 >> 16);
		target_bank_preindex_ = ((io_data_ >> 16) & 0xFF);
		target_addr_ = v2 & 0xFFFF;
		target_addr_preindex_ = v1 & 0xFFFF;
		target_kind_ = target_kind::far_address;
	};

	auto aaa = opcode_ >> 5 & 0b111;
	auto bbb = opcode_ >> 2 & 0b111;
	auto cc  = opcode_      & 0b011;

	switch (opcode_) {
		case 0xD4: // PEI dp, d
			abs();
			return;
		case 0xDC: // JML (abs)
			absl();
			return;
		case 0x6C: // JMP (abs)
		case 0x7C: // JSR (abs, X)
		case 0xFC: // JSR (abs, X)
			abs();
			target_bank_ = r_.pbr;
			return;
	}

	uint8_t addr_mode = (cc << 3) | bbb;

	switch (addr_mode) {
		case 0b11001: // [dp, d]
			absl();
			return;
		case 0b11101: // [dp, d], Y
			absl(r_.y);
			target_indexed_ = true;
			return;
		case 0b10100: // (dp, d)
		case 0b01000: // (dp, d, X)
			abs();
			return;
		case 0b01100: // (dp, d), Y
		case 0b11100: // (d, S), Y
			abs(r_.y);
			target_indexed_ = true;
			return;
	}

	abort();
}

size_t w65c816::op_final_operand_size_() {
	auto aaa = opcode_ >> 5 & 0b111;
	auto bbb = opcode_ >> 2 & 0b111;
	auto cc  = opcode_      & 0b011;

	switch (opcode_) {
		case 0x89: /* BIT imm */
		case 0x04: /* TSB dp, d */
		case 0x0C: /* TSB abs */
		case 0x14: /* TRB dp, d */
		case 0x1C: /* TRB abs */
		case 0x64: /* STZ dp, d */
		case 0x9C: /* STZ abs */
		case 0x74: /* STZ dp, d, X */
		case 0x9E: /* STZ abs, X */ return r_.a_size();
	}

	if (cc == 0b00 && (aaa & 0b100))
		return r_.xy_size();

	if (cc == 0b10 && (aaa == 0b100 || aaa == 0b101) && (bbb != 0b100))
		return r_.xy_size();

	// cc == 0b01 and cc == 0b11 are all accumulator-sized,
	// additionally cc == 0b10, bbb == 0b100 encodes cc == 0b01
	// ops with the (dp, d) addressing mode.

	return r_.a_size();
}

bool w65c816::op_requires_load_() {
	auto aaa = opcode_ >> 5 & 0b111;
	auto bbb = opcode_ >> 2 & 0b111;
	auto cc  = opcode_      & 0b011;

	switch (opcode_) {
		case 0x64: /* STZ dp, d */
		case 0x9C: /* STZ abs */
		case 0x74: /* STZ dp, d, X */
		case 0x9E: /* STZ abs, X */ return false;
	}

	return target_kind_ != target_kind::accumulator
		&& target_kind_ != target_kind::immediate
		&& aaa != 0b100; // ST{A,X,Y}
}

auto w65c816::store_op_result_to_() -> op_target {
	auto aaa = opcode_ >> 5 & 0b111;
	auto bbb = opcode_ >> 2 & 0b111;
	auto cc  = opcode_      & 0b011;

	switch (opcode_) {
		case 0x89: /* BIT imm */ return op_target::discard;
		case 0x04: /* TSB dp, d */
		case 0x0C: /* TSB abs */
		case 0x14: /* TRB dp, d */
		case 0x1C: /* TRB abs */ return op_target::mem;
		case 0x64: /* STZ dp, d */
		case 0x9C: /* STZ abs */
		case 0x74: /* STZ dp, d, X */
		case 0x9E: /* STZ abs, X */ return op_target::mem;
	}

	if (cc == 0b01 || cc == 0b11 || (cc == 0b10 && bbb == 0b100))
		return aaa == 0b100 /* STA */
			? op_target::mem
			: aaa == 0b110 /* CMP */
				? op_target::discard
				: op_target::a_reg;

	if (cc == 0b10)
		return bbb != 0b010 /* A accumulator */
			? aaa == 0b101 /* LDX */
				? op_target::x_reg
				: op_target::mem
			: op_target::a_reg;

	if (cc == 0b00)
		return aaa == 0b101 /* LDY */
			? op_target::y_reg
			: aaa == 0b100 /* STY */
				? op_target::mem
				: op_target::discard;

	abort();
}

void w65c816::eval_alu_op_() {
	auto aaa = opcode_ >> 5 & 0b111;
	auto bbb = opcode_ >> 2 & 0b111;
	auto cc  = opcode_      & 0b011;
	auto result_size = op_final_operand_size_();

	//printf("eval_alu_op_ op %02x aaa %d bbb %d cc %d output width %zu\n", opcode_, aaa, bbb, cc, result_size);

	auto update_overflow = [&] (uint32_t o, uint32_t l, uint32_t r) {
		uint32_t sign_bit = 1 << (result_size * 8 - 1);

		if ((o & sign_bit) != (l & sign_bit)
				&& (o & sign_bit) != (r & sign_bit))
			r_.flags |= flags::V;
	};

	auto update_carry = [&] (uint32_t o) {
		uint32_t carry_mask = 0xFFFFFF00 << ((result_size - 1) * 8);

		if (o & carry_mask)
			r_.flags |= flags::C;
	};

	auto one_bcd_digit = [&] (int nth, int32_t tmp, auto do_adjust, bool old_carry) {
			uint32_t digit_mask = 0xF << (nth * 4);
			int32_t prev_digits_mask = nth ? (0xFFF >> ((3 - nth) * 4)) : 0;

			tmp = do_adjust(nth, tmp);
			return (r_.get_a() & digit_mask) + (io_data_ & digit_mask)
				+ (prev_digits_mask && tmp > prev_digits_mask ? prev_digits_mask + 1 : 0)
				+ (tmp & prev_digits_mask)
				+ (!nth ? old_carry : 0);
		};

	auto adc_decimal = [&] (bool old_carry) {
		int32_t tmp = 0;

		auto adc_adjust = [] (int nth, int32_t tmp) {
			int32_t adjust_thresh = 0x9FFF >> ((4 - nth) * 4);
			uint32_t adjust_value = nth ? (0x6 << ((nth - 1) * 4)) : 0;

			if (tmp > adjust_thresh) tmp += adjust_value;
			return tmp;
		};

		tmp = one_bcd_digit(0, tmp, adc_adjust, old_carry);
		tmp = one_bcd_digit(1, tmp, adc_adjust, old_carry);

		if (result_size == 2) {
			tmp = one_bcd_digit(2, tmp, adc_adjust, old_carry);
			tmp = one_bcd_digit(3, tmp, adc_adjust, old_carry);
		}

		update_overflow(tmp, r_.get_a(), io_data_);
		tmp = adc_adjust(result_size * 2, tmp);
		update_carry(tmp);

		io_data_ = tmp;
	};

	auto adc = [&] {
		bool old_carry = r_.flags & flags::C;
		r_.flags &= ~(flags::C | flags::V);
		if (r_.flags & flags::D)
			return adc_decimal(old_carry);

		uint32_t tmp = io_data_;
		tmp += r_.get_a() + old_carry;

		update_carry(tmp);
		update_overflow(tmp, r_.get_a(), io_data_);

		io_data_ = tmp;
	};

	auto sbc_decimal = [&] (bool old_carry) {
		int32_t tmp = 0;

		io_data_ = ~io_data_;

		auto sbc_adjust = [] (int nth, int32_t tmp) {
			int32_t adjust_thresh = 0x1 << (nth * 4);
			int32_t adjust_value = nth ? (0x6 << ((nth - 1) * 4)) : 0;

			if (tmp < adjust_thresh) tmp -= adjust_value;
			return tmp;
		};

		tmp = one_bcd_digit(0, tmp, sbc_adjust, old_carry);
		tmp = one_bcd_digit(1, tmp, sbc_adjust, old_carry);

		if (result_size == 2) {
			tmp = one_bcd_digit(2, tmp, sbc_adjust, old_carry);
			tmp = one_bcd_digit(3, tmp, sbc_adjust, old_carry);
		}

		update_overflow(tmp, r_.get_a(), io_data_);
		tmp = sbc_adjust(result_size * 2, tmp);

		if (tmp >= (result_size == 2 ? 0xFFFF : 0xFF))
			r_.flags |= flags::C;

		io_data_ = tmp;
	};

	auto sext = [&] (uint16_t v) -> int32_t {
		return result_size == 2
			? int32_t(int16_t(v))
			: int32_t(int8_t(v));
	};

	auto sbc = [&] {
		bool old_carry = r_.flags & flags::C;
		r_.flags &= ~(flags::C | flags::V);
		if (r_.flags & flags::D)
			return sbc_decimal(old_carry);

		int32_t w1 = int32_t(r_.get_a()), w2 = int32_t(io_data_);
		int32_t s1 = sext(w1), s2 = sext(w2);
		int32_t tmp = w1 - w2 - !old_carry;

		if (tmp >= 0)
			r_.flags |= flags::C;

		int32_t stmp = s1 - s2 - !old_carry;
		int32_t min = result_size == 2 ? -32768 : -128;
		int32_t max = result_size == 2 ? 32767 : 127;
		if (stmp < min || stmp > max)
			r_.flags |= flags::V;

		io_data_ = tmp;
	};

	auto cmp = [&] (uint16_t a) {
		r_.flags &= ~flags::C;

		auto sa = int32_t(a), sb = int32_t(io_data_);
		auto v = sa - sb;

		if (v >= 0)
			r_.flags |= flags::C;

		io_data_ = v;
	};

	auto rot = [&] (bool go_left, bool shift_in) {
		uint32_t top_bit = 1 << (result_size * 8 - 1);
		uint32_t over_bit = 1 << (result_size * 8);
		r_.flags &= ~flags::C;

		if (go_left) {
			io_data_ <<= 1;
			io_data_ |= shift_in;
			r_.flags |= (io_data_ & over_bit) ? flags::C : 0;
		} else {
			r_.flags |= (io_data_ & 1) ? flags::C : 0;
			io_data_ >>= 1;
			io_data_ |= shift_in ? top_bit : 0;
		}
	};

	auto bit = [&] {
		bool nv = target_kind_ != target_kind::immediate;
		size_t mask1 = (1 << (result_size * 8 - 2)),
			mask2 = mask1 << 1;

		r_.flags &= ~flags::Z;
		if (nv)
			r_.flags &= ~(flags::N | flags::V);

		r_.flags |= !(io_data_ & r_.get_a()) ? flags::Z : 0;
		if (nv)
			r_.flags |= ((io_data_ & mask1) ? flags::V : 0)
				| ((io_data_ & mask2) ? flags::N : 0);
	};

	auto tsb = [&] {
		bool set = r_.get_a() & io_data_;
		io_data_ |= r_.get_a();

		r_.flags &= ~flags::Z;
		r_.flags |= !set ? flags::Z : 0;
	};

	auto trb = [&] {
		bool set = r_.get_a() & io_data_;
		io_data_ &= ~r_.get_a();

		r_.flags &= ~flags::Z;
		r_.flags |= !set ? flags::Z : 0;
	};

	bool decoded_ = true;
	switch (opcode_) {
		case 0x89: /* BIT imm */ bit(); return;
		case 0x14: /* TRB dp, d */
		case 0x1C: /* TRB abs */ trb(); return;
		case 0x64: /* STZ dp, d */
		case 0x9C: /* STZ abs */
		case 0x74: /* STZ dp, d, X */
		case 0x9E: /* STZ abs, X */ io_data_ = 0; return;
		default: decoded_ = false;
	}

	if (decoded_)
		goto finish_alu_op;

	if (cc == 0b01 || cc == 0b11 || (cc == 0b10 && bbb == 0b100)) {
		switch (aaa) {
			case 0b000: /* ORA */ io_data_ |= r_.get_a(); break;
			case 0b001: /* AND */ io_data_ &= r_.get_a(); break;
			case 0b010: /* EOR */ io_data_ ^= r_.get_a(); break;
			case 0b011: /* ADC */ adc(); break;
			case 0b100: /* STA */ io_data_ = r_.get_a(); return;
			case 0b101: /* LDA */ break;
			case 0b110: /* CMP */ cmp(r_.get_a()); break;
			case 0b111: /* SBC */ sbc(); break;
		}
	} else if (cc == 0b00) {
		switch (aaa) {
			case 0b000: /* TSB */ tsb(); return;
			case 0b001: /* BIT */ bit(); return;
			case 0b100: /* STY */ io_data_ = r_.y; return;
			case 0b101: /* LDY */ break;
			case 0b110: /* CPY */ cmp(r_.y); break;
			case 0b111: /* CPX */ cmp(r_.x); break;
		}
	} else if (cc == 0b10) {
		switch (aaa) {
			case 0b000: /* ASL */ rot(true, false); break;
			case 0b001: /* ROL */ rot(true, r_.flags & flags::C); break;
			case 0b010: /* LSR */ rot(false, false); break;
			case 0b011: /* ROR */ rot(false, r_.flags & flags::C); break;
			case 0b100: /* STX */ io_data_ = r_.x; return;
			case 0b101: /* LDX */ break;
			case 0b110: /* DEC */ io_data_--; break;
			case 0b111: /* INC */ io_data_++; break;
		}
	}

finish_alu_op:
	update_flags_nz_(io_data_, result_size * 8 - 1);
}

uint32_t make_far_(uint8_t bank, uint16_t addr) {
	return (uint32_t{bank} << 16) | addr;
}

uint32_t w65c816::determine_io_addr_() {
	return io_wrap_in_bank_
		? make_far_(io_bank_, io_addr_ + io_pos_)
		: make_far_(io_bank_, io_addr_) + io_pos_;
}

template<std::integral T>
constexpr T byteswap(T value) noexcept {
	static_assert(std::has_unique_object_representations_v<T>, 
			"T may not have padding bits");
	auto value_representation = std::bit_cast<std::array<std::byte, sizeof(T)>>(value);
	std::ranges::reverse(value_representation);
	return std::bit_cast<T>(value_representation);
}

void w65c816::tick() {
	auto enqueue = [&] (auto &&...args) {
		((args ? pending_states_.push(args) : (void)0), ...);
	};

#define GOTO_NEXT() \
	do { \
		assert(pending_states_.size()); \
		void *state = pending_states_.front(); \
		pending_states_.pop(); \
		goto *state; \
	} while (false);

#define PUSH_INTERNAL(v, len, do_stall, then) \
	do { \
		auto d = (do_stall); \
		stack_data_ = (v); \
		stack_data_off_ = ((len - 1) * 8); \
		enqueue(d ? &&push : nullptr, \
			(len) > 1 ? &&push : nullptr, \
			(len) > 2 ? &&push : nullptr, \
			(len) > 3 ? &&push : nullptr, \
			(then)); \
		goto *(d ? &&stall_last : &&push); \
	} while (false);

#define PUSH(v, len) PUSH_INTERNAL((v), (len), true, &&complete_op)
#define PUSH_NOSTALL(v, len) PUSH_INTERNAL((v), (len), false, &&complete_op)
#define PUSH_NOSTALL_THEN(v, len, then) PUSH_INTERNAL((v), (len), false, (then))

#define PULL_THEN(len, next_state) \
	do { \
		stack_data_ = 0; \
		stack_data_off_ = 0; \
		enqueue(&&stall_last, \
			&&initiate_pull, \
			(len) > 1 ? &&pull : nullptr, \
			(len) > 2 ? &&pull : nullptr, \
			(len) > 3 ? &&pull : nullptr, \
			&&complete_pull, \
			(next_state)); \
		goto stall_last; \
	} while (false);

#define READ_THEN(from_bank, from_addr, len, backwards, stalls, wrap_in_bank, pull_vec, next_state) \
	do { \
		auto s1 = (stalls) > 0; \
		auto s2 = (stalls) > 1; \
		io_data_ = 0; \
		io_bank_ = (from_bank); \
		io_addr_ = (from_addr); \
		io_backwards_ = (backwards); \
		io_pos_ = io_backwards_ ? (len) - 1: 0; \
		io_vec_pull_ = (pull_vec); \
		io_wrap_in_bank_ = (wrap_in_bank); \
		enqueue(s2 ? &&stall_last : nullptr, \
			s1 ? &&initiate_read : nullptr, \
			(len) > 1 ? &&read : nullptr, \
			(len) > 2 ? &&read : nullptr, \
			(len) > 3 ? &&read : nullptr, \
			&&complete_read, \
			(next_state)); \
		goto *(s1 ? &&stall_last : &&initiate_read); \
	} while (false);

#define WRITE_THEN(to_bank, to_addr, data, len, backwards, wrap_in_bank, next_state) \
	do { \
		io_data_ = (data); \
		io_bank_ = (to_bank); \
		io_addr_ = (to_addr); \
		io_backwards_ = (backwards); \
		io_pos_ = io_backwards_ ? (len) - 1: 0; \
		io_wrap_in_bank_ = (wrap_in_bank); \
		enqueue(&&write, \
			(len) > 1 ? &&write : nullptr, \
			(len) > 2 ? &&write : nullptr, \
			(len) > 3 ? &&write : nullptr, \
			(next_state)); \
		GOTO_NEXT(); \
	} while (false);

#define ENTER_VECTOR(addr, do_stall) \
	do { \
		if ((do_stall)) \
			enqueue(&&stall, &&stall); \
		io_addr_ = (addr); \
		PUSH_NOSTALL_THEN( \
				uint32_t{r_.pbr} << 24 \
				| uint32_t{r_.pc} << 8 \
				| uint32_t{r_.flags}, 3 + !r_.e, &&enter_vector_1) \
	} while (false);

	if (pending_reset_) {
		pending_reset_ = false;
		enqueue(&&stall, &&stall, &&stall, &&stall,
			&&reset0, &&reset1, &&reset2);
	} else if (pending_test_) {
		pending_states_ = {};
		pending_test_ = false;
		goto initiate_op_fetch;
		return;
	}

	GOTO_NEXT();

// Misc
stall:
	driver_.initiate_stall_at(r_.far_pc(), true);
	return;
stall_last:
	driver_.initiate_stall_idle();
	return;
stall_last_r:
	driver_.initiate_stall_idle_rwb(true);
	return;
stall_last_w:
	driver_.initiate_stall_idle_rwb(false);
	return;
maybe_stall_indexed:
	if (target_indexed_ && inner_target_kind_ == target_kind::stack_address) {
		goto stall_last;
	} else if (target_indexed_ && target_kind_ != target_kind::far_address
			&& ((target_addr_preindex_ & 0xFF00) != (target_addr_ & 0xFF00)
				|| !(r_.flags & flags::X)
				|| store_op_result_to_() == op_target::mem)) {
		driver_.transitive_addr(make_far_(target_bank_preindex_,
					(target_addr_preindex_ & 0xFF00)
					| (target_addr_ & 0x00FF)));
		goto stall_last;
	}
	GOTO_NEXT();
// Reset
reset0:
	driver_.initiate_read(0x00FFFC, true, false, true);
	return;
reset1:
	r_.pc |= driver_.read_data();
	driver_.initiate_read(0x00FFFD, true, false, true);
	return;
reset2:
	r_.pbr = 0;
	r_.pc |= uint16_t{driver_.read_data()} << 8;
	goto initiate_op_fetch;
// Vector entry
enter_vector_1:
	READ_THEN(0, io_addr_, 2, 0, 0, false, true, &&enter_vector_4);
enter_vector_4:
	r_.flags |= flags::I;
	r_.flags &= ~flags::D;
	r_.pbr = 0;
	if (r_.e) r_.dbr = 0;
	r_.pc = io_data_;
	executed_ops_++;
// Opcode fetch & initial decode
initiate_op_fetch:
	if (driver_.irq() && !(r_.flags & flags::I)) {
		ENTER_VECTOR(r_.e ? 0xFFFE : 0xFFEE, true);
	}

	if (driver_.nmi()) {
		ENTER_VECTOR(r_.e ? 0xFFFA : 0xFFEA, true);
	}

	driver_.initiate_read(r_.far_pc(), true, true, false);
	enqueue(&&prepare_exec_op);
	return;
prepare_exec_op:
	r_.pc++;
	driver_.transitive_addr(r_.far_pc());
	opcode_ = driver_.read_data();
	if (auto op_len = determine_operand_length()) {
		operand_idx_ = 0;
		enqueue(op_len > 1 ? &&fetch_oper : nullptr,
			op_len > 2 ? &&fetch_oper : nullptr,
			&&complete_fetch_oper);
		goto initiate_fetch_oper;
	} else {
		goto determine_operand_target;
	}
// Operand fetch
complete_fetch_oper:
	operand_buf_[operand_idx_++] = driver_.read_data();
	goto determine_operand_target;
fetch_oper:
	operand_buf_[operand_idx_++] = driver_.read_data();
initiate_fetch_oper:
	driver_.initiate_read(r_.far_pc(), false, true, false);
	r_.pc++;
	return;
// Pull
complete_pull:
	stack_data_ |= uint32_t{driver_.read_data()} << stack_data_off_;
	GOTO_NEXT();
pull:
	stack_data_ |= uint32_t{driver_.read_data()} << stack_data_off_;
	stack_data_off_ += 8;
initiate_pull:
	r_.set_s(r_.s + 1);
	driver_.initiate_read(r_.s, true, false, false);
	return;
// Push
push:
	driver_.initiate_write(r_.s, (stack_data_ >> stack_data_off_) & 0xFF);
	r_.set_s(r_.s - 1);
	stack_data_off_ -= 8;
	return;
// Read
complete_read:
	io_data_ |= uint32_t{driver_.read_data()} << (io_pos_ * 8);
	GOTO_NEXT();
read:
	io_data_ |= uint32_t{driver_.read_data()} << (io_pos_ * 8);
	io_pos_ += io_backwards_ ? -1 : 1;
initiate_read:
	driver_.initiate_read(determine_io_addr_(), true, false, io_vec_pull_);
	return;
// Write
write:
	driver_.initiate_write(determine_io_addr_(), (io_data_ >> (io_pos_ * 8)) & 0xFF);
	io_pos_ += io_backwards_ ? -1 : 1;
	return;
// Opcode execution
determine_operand_target:
	compute_operand_target_();

	if (target_indirect_len_) {
		auto stalls =
			(target_kind_ == target_kind::dp_address && (r_.d & 0xFF))
			+ target_indexed_
			+ (target_kind_ == target_kind::stack_address);
		READ_THEN(target_bank_, target_addr_,
				target_indirect_len_, false,
				stalls, target_wrap_in_bank_, false, &&determine_indirect_target);
	} else {
		if (target_kind_ == target_kind::dp_address && (r_.d & 0xFF))
			enqueue(&&stall_last);

		if (target_kind_ == target_kind::stack_address)
			enqueue(&&stall_last);

		if (target_indexed_ && target_kind_ != target_kind::dp_address)
			enqueue(&&maybe_stall_indexed);
		else if (target_indexed_)
			enqueue(&&stall_last);

		enqueue(&&exec_op);
		GOTO_NEXT();
	}
determine_indirect_target:
	determine_indirect_target_();

	enqueue(&&maybe_stall_indexed, &&exec_op);
	GOTO_NEXT();
exec_op:
	switch (opcode_) {
		case 0x00: /* BRK */ ENTER_VECTOR(r_.e ? 0xFFFE : 0xFFE6, false);
		case 0x02: /* COP */ ENTER_VECTOR(r_.e ? 0xFFF4 : 0xFFE4, false);
		case 0x08: /* PHP */ PUSH(r_.flags, 1);
		case 0x0B: /* PHD */ PUSH(r_.d, 2);
		case 0x18: /* CLC */ r_.flags &= ~flags::C; break;
		case 0x1A: /* INA */ r_.set_a(r_.get_a() + 1); update_flags_nz_(r_.a, r_.a_size() * 8 - 1); break;
		case 0x1B: /* TCS */ r_.set_s(r_.a); break;
		case 0x20: /* JSR */
		case 0xFC: /* JSR */ goto exec_call;
		case 0x22: /* JSL */ goto exec_call_far;
		case 0x28: /* PLP */ PULL_THEN(1, &&exec_pull_flags);
		case 0x2B: /* PLD */ pull_to_ = &r_.d; PULL_THEN(2, &&exec_pull_reg);
		case 0x38: /* SEC */ r_.flags |= flags::C; break;
		case 0x3A: /* DEA */ r_.set_a(r_.get_a() - 1); update_flags_nz_(r_.a, r_.a_size() * 8 - 1); break;
		case 0x3B: /* TSC */ r_.a = r_.s; update_flags_nz_(r_.a, 15); break;
		case 0x40: /* RTI */ PULL_THEN(3 + !r_.e, &&exec_return);
		case 0x42: /* WDM */ r_.pc++; break; /* NOTE: WDM does have an operand byte, but it's not fetched */
		case 0x44: /* MVP */ goto exec_block_move1;
		case 0x48: /* PHA */ PUSH(r_.a, r_.a_size());
		case 0x4B: /* PHK */ PUSH(r_.pbr, 1);
		case 0x54: /* MVN */ goto exec_block_move1;
		case 0x5A: /* PHY */ PUSH(r_.y, r_.xy_size());
		case 0x5B: /* TCD */ r_.d = r_.a; update_flags_nz_(r_.d, 15); break;
		case 0x5C: /* JMP */
		case 0xDC: /* JML */ r_.pbr = target_bank_; [[fallthrough]];
		case 0x6C: /* JMP */
		case 0x7C: /* JMP */
		case 0x4C: /* JMP */ r_.pc = target_addr_; goto complete_op;
		case 0x58: /* CLI */ r_.flags &= ~flags::I; break;
		case 0x60: /* RTS */ PULL_THEN(2, &&exec_return);
		case 0x68: /* PLA */ PULL_THEN(r_.a_size(), &&exec_pull_a);
		case 0x6B: /* RTL */ PULL_THEN(3, &&exec_return);
		case 0x78: /* SEI */ r_.flags |= flags::I; break;
		case 0x7A: /* PLY */ pull_to_ = &r_.y; PULL_THEN(r_.xy_size(), &&exec_pull_reg);
		case 0x7B: /* TDC */ r_.a = r_.d; update_flags_nz_(r_.a, 15); break;
		case 0x82: /* BRL */ r_.pc = target_addr_; break;
		case 0x88: /* DEY */ r_.set_y(r_.y - 1); update_flags_nz_(r_.y, r_.xy_size() * 8 - 1); break;
		case 0x8A: /* TXA */ r_.set_a(r_.x); update_flags_nz_(r_.a, r_.a_size() * 8 - 1); break;
		case 0x8B: /* PHB */ PUSH(r_.dbr, 1);
		case 0x98: /* TYA */ r_.set_a(r_.y); update_flags_nz_(r_.a, r_.a_size() * 8 - 1); break;
		case 0x9A: /* TXS */ r_.set_s(r_.x); break;
		case 0x9B: /* TXY */ r_.y = r_.x; update_flags_nz_(r_.y, r_.xy_size() * 8 - 1); break;
		case 0xA8: /* TAY */ r_.set_y(r_.a); update_flags_nz_(r_.y, r_.xy_size() * 8 - 1); break;
		case 0xAA: /* TAX */ r_.set_x(r_.a); update_flags_nz_(r_.x, r_.xy_size() * 8 - 1); break;
		case 0xAB: /* PLB */ pull_to_ = &r_.dbr; PULL_THEN(1, &&exec_pull_reg);
		case 0xB8: /* CLV */ r_.flags &= ~flags::V; break;
		case 0xBA: /* TSX */ r_.set_x(r_.s); update_flags_nz_(r_.x, r_.xy_size() * 8 - 1); break;
		case 0xBB: /* TYX */ r_.set_x(r_.y); update_flags_nz_(r_.x, r_.xy_size() * 8 - 1); break;
		case 0xC2: /* REP */ r_.flags &= ~target_addr_; r_.adjust_regs_flags(); break;
		case 0xC8: /* INY */ r_.set_y(r_.y + 1); update_flags_nz_(r_.y, r_.xy_size() * 8 - 1); break;
		case 0xCA: /* DEX */ r_.set_x(r_.x - 1); update_flags_nz_(r_.x, r_.xy_size() * 8 - 1); break;
		case 0xCB: /* WAI */ break; // TODO
		case 0xD8: /* CLD */ r_.flags &= ~flags::D; break;
		case 0xDB: /* STP */ break; // TODO NOTE: Probably the same as WAI except only reacts to RST#?
		case 0xE2: /* SEP */ r_.flags |= target_addr_; r_.adjust_regs_flags(); break;
		case 0xE8: /* INX */ r_.set_x(r_.x + 1); update_flags_nz_(r_.x, r_.xy_size() * 8 - 1); break;
		case 0xEA: /* NOP */ break;
		case 0xEB: /* XBA */ r_.a = byteswap(r_.a); update_flags_nz_(r_.a, 7); enqueue(&&stall_last); break;
		case 0xDA: /* PHX */ PUSH(r_.x, r_.xy_size());
		case 0x62: /* PER */ PUSH(target_addr_, 2);
		case 0xD4: /* PEI */
		case 0xF4: /* PEA */ PUSH_NOSTALL(target_addr_, 2);
		case 0xF8: /* SED */ r_.flags |= flags::D; break;
		case 0xFA: /* PLX */ pull_to_ = &r_.x; PULL_THEN(r_.xy_size(), &&exec_pull_reg);
		case 0xFB: /* XCE */ {
			bool c = r_.flags & flags::C;
			std::swap(c, r_.e);
			r_.flags &= ~flags::C;
			r_.flags |= c ? flags::C : 0;
			r_.adjust_regs_flags();
			break;
		}
		default: goto exec_op2;
	}

	enqueue(&&complete_op);
	goto stall_last;
exec_return:
	switch (opcode_) {
		case 0x40: /* RTI */
			if (!r_.e) r_.pbr = (stack_data_ >> 24) & 0xFF;
			r_.pc = (stack_data_ >> 8) & 0xFFFF;
			r_.flags = stack_data_ & 0xFF;
			r_.adjust_regs_flags();
			goto complete_op;
		case 0x60: /* RTS */
			r_.pc = (stack_data_ & 0xFFFF) + 1;
			enqueue(&&complete_op);
			goto stall_last;
		case 0x6B: /* RTL */
			r_.pc = (stack_data_ & 0xFFFF) + 1;
			r_.pbr = (stack_data_ >> 16) & 0xFF;
			goto complete_op;
	}
exec_pull_reg:
	if (uint8_t **v = std::get_if<uint8_t *>(&pull_to_))
		**v = stack_data_;
	else if (uint16_t **v = std::get_if<uint16_t *>(&pull_to_))
		**v = stack_data_;
	update_flags_nz_(stack_data_, stack_data_off_ + 7);
	goto complete_op;
exec_pull_flags:
	r_.flags = stack_data_;
	r_.adjust_regs_flags();
	goto complete_op;
exec_pull_a:
	r_.set_a(stack_data_);
	update_flags_nz_(stack_data_, stack_data_off_ + 7);
	goto complete_op;
exec_call:
	{
		auto old_pc = r_.pc;
		assert(target_kind_ == target_kind::address);
		r_.pc = target_addr_;
		PUSH(old_pc - 1, 2);
	}
exec_call_far:
	{
		auto old_pc = r_.pc; auto old_pbr = r_.pbr;
		assert(target_kind_ == target_kind::far_address);
		r_.pc = target_addr_;
		r_.pbr = target_bank_;
		PUSH(uint32_t{old_pc - 1U} | uint32_t{old_pbr} << 16, 3);
	}
exec_op2:
	if (opcode_ == 0x80 /* BRA */ || (opcode_ & 0b11111) == 0b10000 /* Bcc */) {
		uint8_t flag_bits[] = { flags::N, flags::V, flags::C, flags::Z };
		uint8_t flag = flag_bits[(opcode_ >> 6) & 0b11];
		bool taken = opcode_ == 0x80 || (!!(r_.flags & flag) == !!(opcode_ & (1 << 5)));

		if (taken) {
			if (r_.e && (r_.pc & 0xFF00) != (target_addr_ & 0xFF00))
				enqueue(&&stall_last);

			r_.pc = target_addr_;

			enqueue(&&complete_op);
			goto stall_last;
		} else {
			goto complete_op;
		}
	}
	/* Only remaining possibility here is an aaabbbcc encoded op */
	/* So we know we should fetch the data if it's not an immediate */
	if (op_requires_load_()) {
		READ_THEN(target_bank_, target_addr_, op_final_operand_size_(),
				false, 0, target_wrap_in_bank_, false, &&exec_op3);
	} else {
		io_data_ = target_addr_;
	}
exec_op3:
	eval_alu_op_();

	switch (store_op_result_to_()) {
		using enum op_target;

		case discard: break;
#define REG_STALL_RMW() do { enqueue(target_kind_ == target_kind::accumulator && !op_requires_load_() ? &&stall_last : nullptr); } while(0)
		case a_reg: r_.set_a(io_data_); REG_STALL_RMW(); break;
		case x_reg: r_.set_x(io_data_); REG_STALL_RMW(); break;
		case y_reg: r_.set_y(io_data_); REG_STALL_RMW(); break;
#undef REG_STALL_RMW
		case mem: {
			bool is_rmw = op_requires_load_();
			enqueue(is_rmw
				? r_.e
					? &&stall_last_w
					: &&stall_last_r
				: nullptr);
			WRITE_THEN(target_bank_, target_addr_, io_data_,
					op_final_operand_size_(), is_rmw, target_wrap_in_bank_, &&complete_op);
		}
	}
	enqueue(&&complete_op);
	GOTO_NEXT();
exec_block_move1:
	READ_THEN(operand_buf_[1], r_.x, 1, false, 0, false, false, &&exec_block_move2);
exec_block_move2:
	WRITE_THEN(operand_buf_[0], r_.y, io_data_ & 0xFF, 1, false, false, &&exec_block_move3);
exec_block_move3:
	enqueue(&&stall_last);
	if (r_.a) {
		r_.a = r_.a - 1;
		r_.pc -= 3;
		int d = opcode_ == 0x44 ? -1 : 1;
		r_.set_x(r_.x + d);
		r_.set_y(r_.y + d);
		r_.dbr = operand_buf_[0];
		enqueue(&&initiate_op_fetch);
	} else {
		enqueue(&&complete_op);
	}
	goto stall_last_r;
complete_op:
	executed_ops_++;
	goto initiate_op_fetch;
}
