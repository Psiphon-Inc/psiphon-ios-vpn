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

#import <Foundation/Foundation.h>
#import "JetsamMetrics.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const JetsamMetrics_FeedbackErrorDomain;

typedef NS_ERROR_ENUM(JetsamMetrics_FeedbackErrorDomain, JetsamMetrics_FeedbackErrorCode) {
    JetsamMetrics_FeedbackErrorInvalidDictForJSON = 1,
    JetsamMetrics_FeedbackErrorNestedDictNil = 2,
    JetsamMetrics_FeedbackErrorFailedToSerializeJSON = 3,
};

/// Adds methods which structure the underlying data for submission with feedback.
@interface JetsamMetrics (Feedback)

- (nullable NSString *)logForFeedback:(NSError * _Nullable *)outError;

@end

NS_ASSUME_NONNULL_END
