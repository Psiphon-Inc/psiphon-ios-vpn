/*
* Copyright (c) 2019, Psiphon Inc.
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

#import "AnimatedControl.h"

@implementation AnimatedControl

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(nullable UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    [UIView animateWithDuration:0.1
                     animations:^{
                        self.transform = CGAffineTransformMakeScale(0.98f, 0.98f);
                        self.alpha = 0.8;
                     }];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    [UIView animateWithDuration:0.1
                     animations:^{
                         self.transform = CGAffineTransformMakeScale(1.f, 1.f);
                         self.alpha = 1.0;
                     }];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(nullable UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    [UIView animateWithDuration:0.1
                     animations:^{
                         self.transform = CGAffineTransformMakeScale(1.f, 1.f);
                         self.alpha = 1.0;
                     }];
}

@end
