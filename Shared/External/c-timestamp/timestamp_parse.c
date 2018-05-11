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

static int
leap_year(uint16_t y) {
    return ((y & 3) == 0 && (y % 100 != 0 || y % 400 == 0));
}

static unsigned char
month_days(uint16_t y, uint16_t m) {
    static const unsigned char days[2][13] = {
        {0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31},
        {0, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
    };
    return days[m == 2 && leap_year(y)][m];
}

static int 
parse_2d(const unsigned char * const p, size_t i, uint16_t *vp) {
    unsigned char d0, d1;
    if (((d0 = p[i + 0] - '0') > 9) ||
        ((d1 = p[i + 1] - '0') > 9))
        return 1;
    *vp = d0 * 10 + d1;
    return 0;
}

static int 
parse_4d(const unsigned char * const p, size_t i, uint16_t *vp) {
    unsigned char d0, d1, d2, d3;
    if (((d0 = p[i + 0] - '0') > 9) ||
        ((d1 = p[i + 1] - '0') > 9) ||
        ((d2 = p[i + 2] - '0') > 9) ||
        ((d3 = p[i + 3] - '0') > 9))
        return 1;
    *vp = d0 * 1000 + d1 * 100 + d2 * 10 + d3;
    return 0;
}

static const uint32_t Pow10[10] = {
    1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000
};

static const uint16_t DayOffset[13] = {
    0, 306, 337, 0, 31, 61, 92, 122, 153, 184, 214, 245, 275
};

int
timestamp_parse(const char *str, size_t len, timestamp_t *tsp) {
    const unsigned char *cur, *end;
    unsigned char ch;
    uint16_t year, month, day, hour, min, sec;
    uint32_t rdn, sod, nsec;
    int16_t offset;

    /*
     *           1
     * 01234567890123456789
     * 2013-12-31T23:59:59Z
     */
    cur = (const unsigned char *)str;
    if (len < 20 ||
        cur[4]  != '-' || cur[7]  != '-' ||
        cur[13] != ':' || cur[16] != ':')
        return 1;

    ch = cur[10];
    if (!(ch == 'T' || ch == ' ' || ch == 't'))
        return 1;

    if (parse_4d(cur,  0, &year)  || year  <  1 ||
        parse_2d(cur,  5, &month) || month <  1 || month > 12 ||
        parse_2d(cur,  8, &day)   || day   <  1 || day   > 31 ||
        parse_2d(cur, 11, &hour)  || hour  > 23 ||
        parse_2d(cur, 14, &min)   || min   > 59 ||
        parse_2d(cur, 17, &sec)   || sec   > 59)
        return 1;

    if (day > 28 && day > month_days(year, month))
        return 1;

    if (month < 3)
        year--;

    rdn = (1461 * year)/4 - year/100 + year/400 + DayOffset[month] + day - 306;
    sod = hour * 3600 + min * 60 + sec;
    end = cur + len;
    cur = cur + 19;
    offset = nsec = 0;

    ch = *cur++;
    if (ch == '.') {
        const unsigned char *start;
        size_t ndigits;

        start = cur;
        for (; cur < end; cur++) {
            const unsigned char digit = *cur - '0';
            if (digit > 9)
                break;
            nsec = nsec * 10 + digit;
        }

        ndigits = cur - start;
        if (ndigits < 1 || ndigits > 9)
            return 1;

        nsec *= Pow10[9 - ndigits];

        if (cur == end)
            return 1;

        ch = *cur++;
    }

    if (!(ch == 'Z' || ch == 'z')) {
        /*
         *  01234
         * ±00:00
         */
        if (cur + 5 < end || !(ch == '+' || ch == '-') || cur[2] != ':')
            return 1;

        if (parse_2d(cur, 0, &hour) || hour > 23 ||
            parse_2d(cur, 3, &min)  || min  > 59)
            return 1;

        offset = hour * 60 + min;
        if (ch == '-')
            offset *= -1;

        cur += 5;
    }

    if (cur != end)
        return 1;

    tsp->sec    = ((int64_t)rdn - 719163) * 86400 + sod - offset * 60;
    tsp->nsec   = nsec;
    tsp->offset = offset;
    return 0;
}

