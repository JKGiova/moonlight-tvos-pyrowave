// SPDX-License-Identifier: MIT
#pragma once

namespace PWClient {
// External synchronization is required. Presentation may finish (or be
// abandoned) before the decode completion callback has been delivered.
class FrameCompletion {
public:
    bool completeDecode() {
        decodeDone_ = true;
        return releaseIfFinished();
    }
    bool completePresentation() {
        presentationDone_ = true;
        return releaseIfFinished();
    }
private:
    bool releaseIfFinished() {
        if (!decodeDone_ || !presentationDone_ || released_) return false;
        released_ = true;
        return true;
    }
    bool decodeDone_ = false;
    bool presentationDone_ = false;
    bool released_ = false;
};
}
