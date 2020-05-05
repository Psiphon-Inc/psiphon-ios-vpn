/*
 * Copyright (c) 2017, Psiphon Inc.
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import "EmbeddedServerEntriesHelpers.h"
#import <errno.h>
#import <stdlib.h>
#import <string.h>

// Forward declarations of helpers
void drop_last_char_if_char(char *s, int c);
char * strchrn(char const *s, int c, int n);

// See comment in header
char * hex_decode(const char *s) {
    if (s == NULL) {
        return NULL;
    }

    // Must have an even length.
    if (strlen(s) % 2 != 0) {
        return NULL;
    }

    unsigned long decoded_len = (strlen(s)/2) + 1;
    char *decoded = (char*)malloc(sizeof(char) * decoded_len);
    char *p = decoded;

    for (int i = 0; i < strlen(s); (i+=2)) {
        // Each hex character represents 4 bits of data.
        // Thus, each two characters represents 1 byte of data
        // which corresponds to one character.
        char hex[3];
        memcpy(hex, s + i, sizeof(char) * 2);
        hex[2] = '\0';

        errno = 0;
        long val = strtol(hex, NULL, 16);
        if (val == 0 || errno != 0) {
            // Failed to decode string. Defer error
            // handling to the caller.
            free(decoded);
            return NULL;
        }
        *p = (char)val;
        p++;
    }

    decoded[decoded_len-1] = '\0';

    return decoded;
}

// See comment in header
void drop_newline_and_carriage_return(char *s) {
    const char newline = '\n';
    const char carriage_return = '\r';
    drop_last_char_if_char(s, newline);
    drop_last_char_if_char(s, carriage_return);
}

// See comment in header
char * server_entry_json(const char *s) {
    // Skip past legacy format (4 space delimited fields)
    // to the JSON config and return a pointer to it.
    const char delim = ' ';
    char *json = strchrn(s, delim, 4);
    if (json != NULL) {
        json += sizeof(char); // move past delim
    }
    return json;
}

/*** HELPERS ***/

/*!
 * @brief Drops last char of string if is the same as character c.
 *
 * String is shortened by replacing the last character with a null terminating character.
 *
 * @param s Pointer to string.
 * @param c Character being searched for.
 */
void drop_last_char_if_char(char *s, int c) {
    const char ch = c;
    if (s == NULL) {
        return;
    }

    long len = strlen(s);
    if (len > 0 && (char)s[len-1] == ch) {
        s[len-1] = '\0';
    }
}

/*!
 * @brief Returns pointer to the nth occurrence of character c in the string s.
 * @param s Pointer to string.
 * @param c Character being searched for.
 * @param n Nth occurrence.
 * @return  Pointer to nth occurrence of c. NULL if nth occurrence does not exist.
 */
char * strchrn(char const *s, int c, int n) {
    const char ch = c;

    for (int i = 0; i < n; i++) {
        s = strchr(s, ch);
        if (s == NULL) {
            return NULL;
        }
        s++;
    }

    return (char *)s - 1;
}
