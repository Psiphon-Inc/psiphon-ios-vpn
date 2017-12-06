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

#ifndef EmbeddedServerEntriesHelpers_h
#define EmbeddedServerEntriesHelpers_h

/*!
 * @brief Decodes hex encoded string.
 *
 * Decodes a hex encoded string.
 *
 * On success a pointer to the decoded string is returned. This pointer points to
 * allocated memory on the heap and must be freed by the caller.
 *
 * On failure NULL will be returned.
 *
 * Caller should check errno when NULL is returned. Errno may be set by
 * library functions.
 *
 * @param s Pointer to hex encoded string. Must only contain hexadecimal characters and have an even length.
 * @return  Pointer to decoded string. NULL on error. Caller must free.
 */
char * hex_decode(const char *s);

/*!
 * @brief Drops newline and carriage return from end of string.
 *
 * Removes \r\n or \n from end of string by shortening the string with a null terminating character.
 * The string will not be altered if these deliminators are not found. No reallocation is performed.
 *
 * @param s Pointer to string.
 */
void drop_newline_and_carriage_return(char *s);

/*!
 * @brief Skip past legacy format (4 space delimited fields) to JSON config.
 *
 * See DecodeServerEntry (https://github.com/Psiphon-Labs/psiphon-tunnel-core/blob/master/psiphon/common/protocol/serverEntry.go)
 * for more details.
 *
 * @param s Pointer to decoded server entry line.
 * @return  Pointer to JSON config in server entry line.
 */
char * server_entry_json(const char *s);

#endif /* EmbeddedServerEntriesHelpers_h */
