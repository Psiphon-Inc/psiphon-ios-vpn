/*
 * Copyright (c) 2021, Psiphon Inc.
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

// Following code is adapted from following WireGuard (WireGuardKit) code.
// WireGuard commit: https://git.zx2c4.com/wireguard-apple/commit/?id=23bf3cfccb5a6fa9faf85c35ca24ec4c3e29c3fe
// Mirror: https://github.com/WireGuard/wireguard-apple/commit/23bf3cfccb5a6fa9faf85c35ca24ec4c3e29c3fe

// MIT License:
// Copyright © 2018-2021 WireGuard LLC. All Rights Reserved.
// Permission is hereby granted, free of charge, to any person obtaining a copy of
// this software and associated documentation files (the "Software"), to deal in
// the Software without restriction, including without limitation the rights to
// use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is furnished to do
// so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#import "TunnelFileDescriptor.h"

#include <sys/socket.h>
#include <sys/ioctl.h>
#include <net/if.h>


/* From <sys/kern_control.h> */

#define CTLIOCGINFO 0xc0644e03UL

struct ctl_info {
    u_int32_t   ctl_id;
    char        ctl_name[96];
};

struct sockaddr_ctl {
    u_char      sc_len;
    u_char      sc_family;
    u_int16_t   ss_sysaddr;
    u_int32_t   sc_id;
    u_int32_t   sc_unit;
    u_int32_t   sc_reserved[5];
};


@implementation TunnelFileDescriptor

+ (NSNumber *_Nullable)getTunnelFileDescriptor {
    
    struct ctl_info ctlInfo;
    strcpy(ctlInfo.ctl_name, "com.apple.net.utun_control");
    
    for (int32_t fd = 0; fd <= 1024; fd++) {
        
        struct sockaddr_ctl addr;
        int ret = -1;
        socklen_t len = sizeof(addr);
        
        ret = getpeername(fd, (struct sockaddr *)&addr, &len);
        
        if (ret != 0 || addr.sc_family != AF_SYSTEM) {
            continue;
        }
        
        if (ctlInfo.ctl_id == 0) {
            ret = ioctl(fd, CTLIOCGINFO, &ctlInfo);
            if (ret != 0) {
                continue;
            }
        }
        
        if (addr.sc_id == ctlInfo.ctl_id) {
            return [NSNumber numberWithInt:fd];
        }
        
    }
    
    return nil;
    
}

+ (NSString *_Nullable)getInterfaceName:(NSNumber *)tunnelFileDescriptor {
    
    if (tunnelFileDescriptor == nil) {
        return nil;
    }
    
    char buf[IFNAMSIZ];
    
    socklen_t ifnameSize = IFNAMSIZ;
    
    int result = getsockopt((int)[tunnelFileDescriptor integerValue],
                            2 /* SYSPROTO_CONTROL */,
                            2 /* UTUN_OPT_IFNAME */,
                            &buf,
                            &ifnameSize);
    
    if (result == 0) {
        return [NSString stringWithCString:buf encoding:NSUTF8StringEncoding];
    } else {
        return nil;
    }
    
}

@end
