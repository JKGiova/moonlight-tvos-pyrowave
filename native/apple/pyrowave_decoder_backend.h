// SPDX-License-Identifier: MIT
// Local, experimental decoder extension. The pinned encoder API is unchanged.
#ifndef PW_DECODER_BACKEND_H
#define PW_DECODER_BACKEND_H
#include "pyrowave_metal.h"
#ifdef __cplusplus
extern "C" {
#endif
// Candidate check only: pipeline creation and resource allocation can still fail.
// Apple5 and later; Intel/AMD Macs remain excluded from the live codec.
PYROWAVE_PUBLIC_API bool pw_decoder_backend_is_candidate(pyrowave_mtl_device device);
// Decoder-only device. Prefer native Apple7 unless force_portable is requested;
// Apple5/6 use the threadgroup dequantizer. Does not qualify a profile for Auto.
PYROWAVE_PUBLIC_API pyrowave_result pw_decoder_device_create(const pyrowave_device_create_info *info,
                                        bool force_portable, pyrowave_device *device);
// Static string, valid even after destroying the device. Never NULL.
PYROWAVE_PUBLIC_API const char *pw_decoder_backend_name(pyrowave_device device);
#ifdef __cplusplus
}
#endif
#endif
