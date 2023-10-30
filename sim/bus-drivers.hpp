#pragma once

#include "bus.hpp"

#include <optional>
#include <cassert>
#include <cstdint>
#include <vector>

struct fpga_bus_driver : bus_driver {
	template <std::invocable<> Fn>
	void bus_tick(Fn &&tick_cb, const uint8_t &i_cpu_clk,
			uint16_t &o_addr, const uint8_t &i_data, uint8_t &o_data,
			uint8_t &o_cpu_data_rw, uint8_t &o_cpu_vpa, uint8_t &o_cpu_vda,
			uint8_t &o_cpu_vp, const uint8_t &i_cpu_abort,
			const uint8_t &i_cpu_ie) {

		// Address hold time
		constexpr int t_ah = 2;
		// Address setup time (tADS & tBAS)
		constexpr int t_ads = 3;
		// Write data delay time
		constexpr int t_mds = 3;

		if (!i_cpu_clk && prev_cpu_clk_) { // Falling edge of the clock
			if (current_r_) {
				(vda_ || vpa_) && fprintf(stderr, "%06x.R = %02x\n", current_addr_, i_data);
				in_data_ = i_data;
			}

			bus_op_pending_ = false;
			tick_cb();
			assert(bus_op_pending_);

			t_ah_ctr_ = t_ah;
			t_ads_ctr_ = t_ads;
		} else if (i_cpu_clk && !prev_cpu_clk_) { // Rising edge of the clock
			// TODO: Probe ABORT here
			t_mds_ctr_ = t_mds;
		} else if (!t_ah_ctr_) {
			o_addr = 0;
			o_data = 0;
		} else if (!t_ads_ctr_) {
			o_addr = current_addr_ & 0xFFFF;
			o_data = (current_addr_ >> 16) & 0xFF;
			o_cpu_data_rw = current_r_ && !current_w_;
			o_cpu_vda = vda_;
			o_cpu_vpa = vpa_;
			o_cpu_vp = !vec_pull_;
		} else if (!t_mds_ctr_) {
			if (current_w_) {
				o_data = out_data_;
				(vda_ || vpa_) && fprintf(stderr, "%06x.W = %02x\n", current_addr_, o_data);
			}
		}

		if (t_ah_ctr_ >= 0) t_ah_ctr_--;
		if (t_ads_ctr_ >= 0) t_ads_ctr_--;
		if (t_mds_ctr_ >= 0) t_mds_ctr_--;
		prev_cpu_clk_ = i_cpu_clk;

		/*switch (bus_step_) {
			case 0: {
				if (current_r_ && i_cpu_ie) {
					in_data_ = i_data;
				}

				bus_op_pending_ = false;
				tick_cb();
				assert(bus_op_pending_);
				break;
			}

			case 3: {
				o_addr = 0;
				o_data = 0;
				break;
			}

			case 4: {
				o_addr = current_addr_ & 0xFFFF;
				o_data = (current_addr_ >> 16) & 0xFF;
				o_cpu_data_rw = current_r_ && !current_w_;
				o_cpu_vda = vda_;
				o_cpu_vpa = vpa_;
				o_cpu_vp = !vec_pull_;
				break;
			}

			case 9: {
				o_data = 0;
				break;
			}

			case 11: {
				if (current_w_)
					o_data = out_data_;
			}
		}

		bus_step_ = (bus_step_ + 1) % 16;*/
	}

private:
	int t_ah_ctr_ = -1;
	int t_ads_ctr_ = -1;
	int t_mds_ctr_ = -1;
	//int bus_step_ = 0;
	bool prev_cpu_clk_ = false;
};

struct test_bus_driver : bus_driver {
	static constexpr size_t ram_size = 16 * 1024 * 1024;

	struct cycle_record {
		uint32_t address;
		std::optional<uint8_t> data;
		bool vda, vpa, vp, rwb;

		bool operator==(const cycle_record &) const = default;
	};

	template <std::invocable<> Fn>
	void bus_tick(Fn &&tick_cb) {
		bus_op_pending_ = false;
		tick_cb();
		assert(bus_op_pending_);

		std::optional<uint8_t> data = std::nullopt;

		if (current_r_ && (vda_ || vpa_ || vec_pull_))
			data = in_data_ = ram_[current_addr_];
		else if (current_w_) {
			data = out_data_;
			if (vda_)
				ram_[current_addr_] = out_data_;
		}

		records_.push_back({current_addr_, data, vda_, vpa_, vec_pull_, current_r_});
	}

	uint8_t *&ram() { return ram_; }
	std::vector<cycle_record> &records() { return records_; }

private:
	uint8_t *ram_{};
	std::vector<cycle_record> records_;
};
