/*
 * Copyright (c) 2014 Christian Hansen <chansen@cpan.org>
 * <https://github.com/chansen/c-timestamp>
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met: 
 * 
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer. 
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution. 
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
#ifndef __TIMESTAMP_H__
#define __TIMESTAMP_H__
#include <stddef.h>
#include <time.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// TODO: "c-timestamp" module is embedded in "Utilities" Swift package.
// PsiFeedbackLogger APIs should be updated to not include this module directly.

typedef struct {
    int64_t sec;    /* Number of seconds since the epoch of 1970-01-01T00:00:00Z */
    int32_t nsec;   /* Nanoseconds [0, 999999999] */
    int16_t offset; /* Offset from UTC in minutes [-1439, 1439] */
} dup_timestamp_t;

int         dup_timestamp_parse            (const char *str, size_t len, dup_timestamp_t *tsp);
size_t      dup_timestamp_format           (char *dst, size_t len, const dup_timestamp_t *tsp);
size_t      dup_timestamp_format_precision (char *dst, size_t len, const dup_timestamp_t *tsp, int precision);
int         dup_timestamp_compare          (const dup_timestamp_t *tsp1, const dup_timestamp_t *tsp2);
bool        dup_timestamp_valid            (const dup_timestamp_t *tsp);
struct tm * dup_timestamp_to_tm_utc        (const dup_timestamp_t *tsp, struct tm *tmp);
struct tm * dup_timestamp_to_tm_local      (const dup_timestamp_t *tsp, struct tm *tmp);

#ifdef __cplusplus
}
#endif
#endif
