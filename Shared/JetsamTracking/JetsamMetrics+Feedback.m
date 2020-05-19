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
#import "RunningBins.h"
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

    NSMutableDictionary *jsonDict = [[NSMutableDictionary alloc] initWithDictionary:@{@"v":@1}];

    for (NSString *key in [self.perVersionMetrics allKeys]) {
        JetsamPerAppVersionStat *stat = [self.perVersionMetrics objectForKey:key];

        NSMutableDictionary *perVersionStats = [[NSMutableDictionary alloc] init];

        RunningStat *runningTimeStat = stat.runningTime;
        if (runningTimeStat != NULL) {
            [perVersionStats setObject:[JetsamMetrics statToFeedbackDict:runningTimeStat]
                                forKey:@"running_times"];
        }
        RunningStat *timeBetweenJetsamsStat = stat.timeBetweenJetsams;
        if (timeBetweenJetsamsStat != NULL) {
            [perVersionStats setObject:[JetsamMetrics statToFeedbackDict:timeBetweenJetsamsStat]
                                forKey:@"time_between"];
        }

        [jsonDict setObject:perVersionStats forKey:key];
    }

    if (![NSJSONSerialization isValidJSONObject:jsonDict]) {
        *outError = [NSError errorWithDomain:JetsamMetrics_FeedbackErrorDomain
                                        code:JetsamMetrics_FeedbackErrorInvalidDictForJSON];
        return nil;
    }

    return jsonDict;
}

/// Transform stat into a dictionary valid for JSON serialization.
+ (NSDictionary *_Nonnull)statToFeedbackDict:(RunningStat*_Nonnull)stat {

    // Round to zero decimal places.
    NSMutableDictionary *statDict =
      [NSMutableDictionary
       dictionaryWithDictionary:@{@"count": @(stat.count),
                                  @"min": @((int)round([stat min])),
                                  @"max": @((int)round([stat max])),
                                  @"mean": @((int)round([stat mean]))}];

    if (stat.count > 1) {
        [statDict setObject:@((int)round([stat stdev])) forKey:@"stdev"];
        [statDict setObject:@((int)round([stat variance])) forKey:@"var"];
    }

    NSArray<Bin*> *talliedBins = [stat talliedBins];
    if (talliedBins != nil) {
        NSMutableArray<NSDictionary*> *binMetrics = [[NSMutableArray alloc]
                                                     initWithCapacity:[talliedBins count]];
        // Add each bin
        for (Bin *bin in talliedBins) {
            NSMutableDictionary *binMetric = [NSMutableDictionary dictionaryWithDictionary:@{@"count": @(bin.count)}];

            // Omit bound if it is the absolute max or min.
            if (bin.range.lowerBound != -DBL_MAX) {
                [binMetric setObject:@(bin.range.lowerBound) forKey:@"lower_bound"];
            }
            if (bin.range.upperBound != DBL_MAX) {
                [binMetric setObject:@(bin.range.upperBound) forKey:@"upper_bound"];
            }

            [binMetrics addObject:binMetric];
        }
        [statDict setObject:binMetrics forKey:@"bins"];
    }

    return statDict;
}

@end
