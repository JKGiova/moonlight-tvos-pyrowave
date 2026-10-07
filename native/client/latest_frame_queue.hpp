// SPDX-License-Identifier: MIT
#pragma once
#include <array>
#include <optional>
#include <utility>
#include <cstdint>
#include <cstddef>

namespace PWClient {
// External synchronization is required. Never create one dispatch block per
// arriving frame: this mailbox owns two GPU slots and only the newest pending
// frame. Stopping discards pending work but retains occupied slots until their
// command buffers finish.
template<class Frame> class LatestFrameQueue {
public:
    struct Work { size_t slot; Frame frame; };
    bool submit(Frame frame) {
        if (stopped_) return false;
        if (pending_) ++pendingReplacements;
        pending_ = std::move(frame);
        return true;
    }
    std::optional<Work> take() {
        if (stopped_ || !pending_) return {};
        for (size_t i=0; i<busy_.size(); ++i) if (!busy_[i]) {
            busy_[i] = true;
            Work work{i, std::move(*pending_)};
            pending_.reset();
            return work;
        }
        return {};
    }
    bool complete(size_t slot) {
        if (slot >= busy_.size() || !busy_[slot]) return false;
        busy_[slot] = false;
        return true;
    }
    void stop() { stopped_ = true; pending_.reset(); }
    bool stopped() const { return stopped_; }
    size_t inFlight() const { return size_t(busy_[0])+size_t(busy_[1]); }
    bool pending() const { return pending_.has_value(); }
    uint64_t pendingReplacements = 0;
private:
    std::array<bool,2> busy_{};
    std::optional<Frame> pending_;
    bool stopped_ = false;
};
}
