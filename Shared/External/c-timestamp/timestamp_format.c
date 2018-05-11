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
#include <stddef.h>
#include "timestamp.h"

static const uint16_t DayOffset[13] = {
    0, 306, 337, 0, 31, 61, 92, 122, 153, 184, 214, 245, 275
};

/* Rata Die algorithm by Peter Baum */

static void
rdn_to_ymd(uint32_t rdn, uint16_t *yp, uint16_t *mp, uint16_t *dp) {
    uint32_t Z, H, A, B;
    uint16_t y, m, d;

    Z = rdn + 306;
    H = 100 * Z - 25;
    A = H / 3652425;
    B = A - (A >> 2);
    y = (100 * B + H) / 36525;
    d = B + Z - (1461 * y >> 2);
    m = (535 * d + 48950) >> 14;
    if (m > 12) {
        y++;
        m -= 12;
    }

    *yp = y;
    *mp = m;
    *dp = d - DayOffset[m];
}

#define EPOCH INT64_C(62135683200)  /* 1970-01-01T00:00:00 */

static const uint32_t Pow10[10] = {
    1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000
};

static size_t
timestamp_format_internal(char *dst, size_t len, const timestamp_t *tsp, const int precision) {
    unsigned char *p;
    uint64_t sec;
    uint32_t rdn, v;
    uint16_t y, m, d;
    size_t dlen;

    dlen = sizeof("YYYY-MM-DDThh:mm:ssZ") - 1;
    if (tsp->offset)
        dlen += 5; /* hh:mm */

    if (precision)
        dlen += 1 + precision;

    if (dlen >= len)
        return 0;

    sec = (uint64_t) (tsp->sec + tsp->offset * 60 + EPOCH);
    rdn = (uint32_t) (sec / 86400);

    rdn_to_ymd(rdn, &y, &m, &d);

   /*
    *           1
    * 0123456789012345678
    * YYYY-MM-DDThh:mm:ss
    */
    p = (unsigned char *)dst;
    v = sec % 86400;
    p[18] = '0' + (v % 10); v /= 10;
    p[17] = '0' + (v %  6); v /=  6;
    p[16] = ':';
    p[15] = '0' + (v % 10); v /= 10;
    p[14] = '0' + (v %  6); v /=  6;
    p[13] = ':';
    p[12] = '0' + (v % 10); v /= 10;
    p[11] = '0' + (v % 10);
    p[10] = 'T';
    p[ 9] = '0' + (d % 10); d /= 10;
    p[ 8] = '0' + (d % 10);
    p[ 7] = '-';
    p[ 6] = '0' + (m % 10); m /= 10;
    p[ 5] = '0' + (m % 10);
    p[ 4] = '-';
    p[ 3] = '0' + (y % 10); y /= 10;
    p[ 2] = '0' + (y % 10); y /= 10;
    p[ 1] = '0' + (y % 10); y /= 10;
    p[ 0] = '0' + (y % 10);
    p += 19;

    if (precision) {
        v = tsp->nsec / Pow10[9 - precision];
        switch (precision) {
            case 9: p[9] = '0' + (v % 10); v /= 10;
            case 8: p[8] = '0' + (v % 10); v /= 10;
            case 7: p[7] = '0' + (v % 10); v /= 10;
            case 6: p[6] = '0' + (v % 10); v /= 10;
            case 5: p[5] = '0' + (v % 10); v /= 10;
            case 4: p[4] = '0' + (v % 10); v /= 10;
            case 3: p[3] = '0' + (v % 10); v /= 10;
            case 2: p[2] = '0' + (v % 10); v /= 10;
            case 1: p[1] = '0' + (v % 10);
        }
        p[0] = '.';
        p += 1 + precision;
    }

    if (!tsp->offset)
        *p++ = 'Z';
    else {
        if (tsp->offset < 0) {
            p[0] = '-';
            v = -tsp->offset;
        } else {
            p[0] = '+';
            v = tsp->offset;
        }

        p[5] = '0' + (v % 10); v /= 10;
        p[4] = '0' + (v %  6); v /=  6;
        p[3] = ':';
        p[2] = '0' + (v % 10); v /= 10;
        p[1] = '0' + (v % 10);
        p += 6;
    }
    *p = 0;
    return dlen;
}

/*
 *          1         2         3
 * 12345678901234567890123456789012345 (+ null-terminator)
 * YYYY-MM-DDThh:mm:ssZ
 * YYYY-MM-DDThh:mm:ss±hh:mm
 * YYYY-MM-DDThh:mm:ss.123Z
 * YYYY-MM-DDThh:mm:ss.123±hh:mm
 * YYYY-MM-DDThh:mm:ss.123456Z
 * YYYY-MM-DDThh:mm:ss.123456±hh:mm
 * YYYY-MM-DDThh:mm:ss.123456789Z
 * YYYY-MM-DDThh:mm:ss.123456789±hh:mm
 */

size_t
timestamp_format(char *dst, size_t len, const timestamp_t *tsp) {
    uint32_t f;
    int precision;

    if (!timestamp_valid(tsp))
        return 0;

    f = tsp->nsec;
    if (!f)
        precision = 0;
    else {
        if      ((f % 1000000) == 0) precision = 3;
        else if ((f %    1000) == 0) precision = 6;
        else                         precision = 9;
    }
    return timestamp_format_internal(dst, len, tsp, precision);
}

size_t
timestamp_format_precision(char *dst, size_t len, const timestamp_t *tsp, int precision) {
    if (!timestamp_valid(tsp) || precision < 0 || precision > 9)
        return 0;
    return timestamp_format_internal(dst, len, tsp, precision);
}

