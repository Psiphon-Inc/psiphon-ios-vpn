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

#import "JetsamMetrics+Feedback.h"
#import "RunningBuckets.h"
#import "NSError+Convenience.h"

NSErrorDomain _Nonnull const JetsamMetrics_FeedbackErrorDomain = @"JetsamMetrics_FeedbackErrorDomain";

@implementation JetsamMetrics (Feedback)

#pragma mark - Public

- (nullable NSString *)logForFeedback:(NSError * _Nullable *)outError {

    *outError = nil;

    NSError *err;
    NSDictionary *nestedJsonDict = [self jsonSerializableDictionaryRepresentation:&err];
    if (err != nil) {
        *outError = [NSError errorWithDomain:JetsamMetrics_FeedbackErrorDomain
                                        code:JetsamMetrics_FeedbackErrorNestedDictNil];

        return nil;
    }

    // Note: change the key if the structure changes in the future (e.g. "JetsamMetricsV2", ...)
    NSDictionary *jsonDict = @{@"JetsamMetrics": nestedJsonDict};

    if (![NSJSONSerialization isValidJSONObject:jsonDict]) {
        *outError = [NSError errorWithDomain:JetsamMetrics_FeedbackErrorDomain
                                        code:JetsamMetrics_FeedbackErrorInvalidDictForJSON];

        return nil;
    }

    NSData *serializedDictionary = [NSJSONSerialization dataWithJSONObject:jsonDict
                                                                   options:kNilOptions
                                                                     error:&err];
    if (err != nil) {
        *outError = [NSError errorWithDomain:JetsamMetrics_FeedbackErrorDomain
                                        code:JetsamMetrics_FeedbackErrorFailedToSerializeJSON
                         withUnderlyingError:err];
        return nil;
    }

    NSString *encodedJson = [[NSString alloc] initWithData:serializedDictionary encoding:NSUTF8StringEncoding];

    // TODO: this pattern occurs multiple times and should be abstracted out.
    return [NSString stringWithFormat:@"%@: %@", @"ContainerInfo", encodedJson];
}

#pragma mark - Private

- (NSDictionary<NSString *, id> *)jsonSerializableDictionaryRepresentation:(NSError * _Nullable *)outError {

    *outError = nil;

    NSMutableDictionary *jsonDict = [[NSMutableDictionary alloc] init];

    for (NSString *key in [self.perVersionMetrics allKeys]) {
        RunningStat *stat = [self.perVersionMetrics objectForKey:key];
        if (stat != nil) {
            NSMutableDictionary *perVersionStat =
              [NSMutableDictionary
               dictionaryWithDictionary:@{@"count": @(stat.count),
                                          @"min": @([stat min]),
                                          @"max": @([stat max]),
                                          @"mean": @([stat stdev]),
                                          @"stdev": @([stat stdev]),
                                          @"var": @([stat variance])}];

            NSArray<Bucket*> *talliedBuckets = [stat talliedBuckets];
            if (talliedBuckets != nil) {
                NSMutableArray<NSDictionary*> *bucketMetrics = [[NSMutableArray alloc]
                                                                initWithCapacity:[talliedBuckets count]];
                // Add each bucket
                for (Bucket *bucket in talliedBuckets) {
                    NSDictionary *bucketMetric = @{@"lower_bound": @(bucket.range.lowerBound),
                                                   @"upper_bound": @(bucket.range.upperBound),
                                                   @"count": @(bucket.count)};
                    [bucketMetrics addObject:bucketMetric];
                }
                [perVersionStat setObject:bucketMetrics forKey:@"buckets"];
            }

            [jsonDict setObject:perVersionStat forKey:key];
        }
    }

    if (![NSJSONSerialization isValidJSONObject:jsonDict]) {
        *outError = [NSError errorWithDomain:JetsamMetrics_FeedbackErrorDomain
                                        code:JetsamMetrics_FeedbackErrorInvalidDictForJSON];
        return nil;
    }

    return jsonDict;
}

@end
