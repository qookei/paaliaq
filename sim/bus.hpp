#pragma once

#include <cstdint>
#include <cassert>
#include <utility>

struct bus_driver {
	void initiate_read(uint32_t addr, bool vda, bool vpa, bool vec_pull) {
		assert(!bus_op_pending_);
		current_addr_ = addr;
		current_r_ = true;
		current_w_ = false;
		vda_ = vda;
		vpa_ = vpa;
		vec_pull_ = vec_pull;
		bus_op_pending_ = true;
	}

	void initiate_write(uint32_t addr, uint8_t data) {
		assert(!bus_op_pending_);
		current_addr_ = addr;
		current_r_ = false;
		current_w_ = true;
		out_data_ = data;
		vda_ = true;
		vpa_ = false;
		vec_pull_ = false;
		bus_op_pending_ = true;
	}

	void initiate_stall_at(uint32_t addr, bool rwb) {
		assert(!bus_op_pending_);
		current_addr_ = addr;
		current_r_ = rwb;
		current_w_ = !rwb;
		vda_ = false;
		vpa_ = false;
		vec_pull_ = false;
		bus_op_pending_ = true;
	}

	void initiate_stall_idle() {
		assert(!bus_op_pending_);
		vda_ = false;
		vpa_ = false;
		vec_pull_ = false;
		bus_op_pending_ = true;
	}

	void initiate_stall_idle_rwb(bool rwb) {
		assert(!bus_op_pending_);

		if (!rwb && current_r_)
			out_data_ = in_data_;

		current_r_ = rwb;
		current_w_ = !rwb;

		vda_ = false;
		vpa_ = false;
		vec_pull_ = false;
		bus_op_pending_ = true;
	}

	void transitive_addr(uint32_t addr) {
		current_addr_ = addr;
	}

	uint8_t read_data() const {
		return in_data_;
	}

	bool irq() const {
		return irq_;
	}

	bool nmi() {
		return std::exchange(nmi_, false);
	}

protected:
	bool bus_op_pending_ = false;

	uint32_t current_addr_ = 0x000000;

	uint8_t in_data_, out_data_;

	bool current_r_ = false;
	bool current_w_ = false;

	bool vda_ = false, vpa_ = false;
	bool vec_pull_ = false;

	bool irq_ = false, nmi_ = false;
};
