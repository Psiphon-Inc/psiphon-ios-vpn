/*
* Copyright (c) 2020, Psiphon Inc.
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

import Foundation

extension Date {
    
    enum SecondsFractionPrecision: Int32 {
        case zero = 0
        case three = 3
        case six = 6
        case nine = 9
    }
    
    static func parse(rfc3339Date: String) -> Date? {
        var ts = timestamp_t()
        let result = timestamp_parse(rfc3339Date,
                                     rfc3339Date.lengthOfBytes(using: .utf8),
                                     &ts)
        
        // 0 success case
        guard result == 0 else {
            return nil
        }
        
        let secondFraction: Double = Double(ts.nsec) / pow(10, 9)
        let timeIntervalSince1970: TimeInterval = Double(ts.sec) + secondFraction
        return Date(timeIntervalSince1970: timeIntervalSince1970)
    }
    
    func formatRFC3339(
        secondsFractionPrecision: SecondsFractionPrecision = .three,
        timezoneOffsetUTCMinutes: Int16 = Int16(0)
    ) -> String? {
        // TimeInterval cannot represent unix time
        // with an accuracy of higher than 7 decimal places.
        let unixTime = self.timeIntervalSince1970

        let (sec_integral, sec_fraction) = modf(unixTime)
        
        // Converts sec_fraction to an integral nanoseconds value without loss in precision.
        let precision = secondsFractionPrecision.rawValue
        let sec_fraction_integer = (sec_fraction * 1_000_000).rounded()
        let nsec = sec_fraction_integer * 1_000
        
        var ts = timestamp_t(sec: Int64(sec_integral),
                             nsec: Int32(nsec),
                             offset: timezoneOffsetUTCMinutes)
        
        var buf = Array<Int8>(repeating: 0, count: 40)
        let length = timestamp_format_precision(&buf, buf.count, &ts, precision)
                
        guard length > 0 else {
            return nil
        }
        
        return String(cString: buf)
    }
    
}

extension JSONDecoder {
    
    static func makeRfc3339Decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom{
            let container = try $0.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            guard let date = Date.parse(rfc3339Date: dateString) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: $0.codingPath,
                        debugDescription: "Failed to parse RFC3339 string '\(dateString)'"
                    )
                )
            }
            return date
        }
        return decoder
    }
    
}

extension JSONEncoder {
    
    static func makeRfc3339Encoder(
        precision: Date.SecondsFractionPrecision = .three,
        timezoneOffset: Int16 = 0
    ) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, dateEncoder in
            let maybeFormattedData = date.formatRFC3339(secondsFractionPrecision: precision,
                                                        timezoneOffsetUTCMinutes: timezoneOffset)
            guard let formattedDate = maybeFormattedData else {
                throw EncodingError.invalidValue(
                    date,
                    EncodingError.Context(
                        codingPath: dateEncoder.codingPath,
                        debugDescription: "Failed to format date '\(date)' to RFC3339 string"
                    )
                )
            }
            
            var container = dateEncoder.singleValueContainer()
            try container.encode(formattedDate)
        }
        return encoder
    }
    
}
