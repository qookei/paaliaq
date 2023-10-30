#pragma once

#include <cstdint>
#include <cstddef>
#include <cstdlib>
#include <cassert>
#include <queue>
#include <variant>

#include "bus.hpp"

struct w65c816 {
	w65c816(bus_driver &driver)
	: driver_{driver} { }

	void tick();
	int executed_ops() const { return executed_ops_; }

	struct flags {
		static constexpr uint8_t N = (1 << 7);
		static constexpr uint8_t V = (1 << 6);
		static constexpr uint8_t M = (1 << 5);
		static constexpr uint8_t X = (1 << 4);
		static constexpr uint8_t D = (1 << 3);
		static constexpr uint8_t I = (1 << 2);
		static constexpr uint8_t Z = (1 << 1);
		static constexpr uint8_t C = (1 << 0);
	};

	struct regs {
		uint16_t a = 0;
		uint16_t x = 0, y = 0;
		uint8_t pbr = 0, dbr = 0;
		uint16_t pc = 0;
		uint16_t s = 0x0100, d = 0;
		uint8_t flags = 0;
		bool e = true;

		bool operator==(const regs &) const = default;

		uint32_t far_pc() const {
			return pc | uint32_t{pbr} << 16;
		}

		bool is_a_wide() const {
			return !e && !(flags & flags::M);
		}

		int a_size() const {
			return is_a_wide() ? 2 : 1;
		}

		void set_a(uint16_t v) {
			if (is_a_wide()) a = v;
			else a = (a & 0xFF00) | (v & 0x00FF);
		}

		uint16_t get_a() {
			if (is_a_wide()) return a;
			else return a & 0x00FF;
		}

		bool is_xy_wide() const {
			return !e && !(flags & flags::X);
		}

		int xy_size() const {
			return is_xy_wide() ? 2 : 1;
		}

		void set_x(uint16_t v) {
			if (is_xy_wide()) x = v;
			else x = v & 0x00FF;
		}

		void set_y(uint16_t v) {
			if (is_xy_wide()) y = v;
			else y = v & 0x00FF;
		}

		void set_s(uint16_t v) {
			if (e) s = 0x0100 | (v & 0xFF);
			else s = v;
		}

		void adjust_regs_flags() {
			if (e) {
				s = 0x0100 | (s & 0x00FF);
				flags |= flags::M | flags::X;
			}

			if (flags & flags::X) {
				x &= 0x00FF;
				y &= 0x00FF;
			}
		}
	};

	void inject_test() {
		executed_ops_ = 0;
		pending_test_ = true;
		pending_reset_ = false;
	}

	regs &reg() {
		return r_;
	}

private:
	bus_driver &driver_;

	int executed_ops_ = 0;

	uint32_t tmp_data_ = 0;

	regs r_{};

	uint8_t opcode_;

	uint32_t stack_data_;

	int determine_operand_length();

	uint8_t operand_buf_[3];
	size_t operand_idx_ = 0;

	std::queue<void *> pending_states_;
	bool pending_reset_ = true;
	bool pending_test_ = false;

	std::variant<uint8_t *, uint16_t *> pull_to_;
	size_t stack_data_off_;

	uint8_t target_bank_;
	uint8_t target_bank_preindex_;
	uint16_t target_addr_;
	uint16_t target_addr_preindex_;
	bool target_wrap_in_bank_;

	enum class target_kind {
		none,
		immediate,
		address,
		dp_address,
		stack_address,
		far_address,
		accumulator
	} target_kind_, inner_target_kind_;

	size_t target_indirect_len_;
	bool target_indexed_;

	void compute_operand_target_();
	void determine_indirect_target_();

	uint8_t io_bank_;
	uint16_t io_addr_;
	uint32_t io_data_;
	uint32_t io_pos_;
	bool io_backwards_;
	bool io_wrap_in_bank_;
	bool io_vec_pull_;

	uint32_t determine_io_addr_();

	void update_flags_nz_(uint16_t value, int top) {
		r_.flags &= ~(flags::N | flags::Z);
		if (!(value & ((1 << (top + 1)) - 1)))
			r_.flags |= flags::Z;
		if (value & (1 << top))
			r_.flags |= flags::N;
	}

	size_t op_final_operand_size_();
	bool op_requires_load_(); // i.e. not ST{A,X,Y}
	uint16_t op_source_value_noload_();

	enum class op_target {
		discard, // CMP, CPX, CPY
		mem, // R-M-W, ST{A,X,Y}
		a_reg,
		x_reg, // LDX
		y_reg, // LDY
	};

	op_target store_op_result_to_();
	void eval_alu_op_();
};
