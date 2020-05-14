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
#import "JetsamEvent.h"
#import "JetsamMetrics.h"
#import "RunningBins.h"

/*
* Two classes which facilitate logging jetsam events from the extension and aggregating these events
* into jetsam statistics in the container.
*
* The container tracks which jetsam events it has read previously to ensure that only new jetsam
* events are used in each aggregation. This prevents double counting jetsams.
*/

NS_ASSUME_NONNULL_BEGIN

#if TARGET_IS_CONTAINER || TARGET_IS_TEST

FOUNDATION_EXPORT NSErrorDomain const ContainerJetsamTrackingErrorDomain;

typedef NS_ERROR_ENUM(ContainerJetsamTrackingErrorDomain, ContainerJetsamTrackingErrorCode) {
    ContainerJetsamTrackingErrorInitFileReaderFailed = 1,
    ContainerJetsamTrackingErrorReadingDataFailed = 2,
    ContainerJetsamTrackingErrorDecodingDataFailed = 3,
    ContainerJetsamTrackingErrorUnarchivingDataFailed = 4,
    ContainerJetsamTrackingErrorPersistingRegistryFailed = 5,
};


/// Container jetsam reading.
@interface ContainerJetsamTracking : NSObject

/// Aggregate new jetsam events into per-app-version statistics.
/// @param filepath Location of the file which contains jetsam logs.
/// @param rotatedFilepath Location where the file which contains jetsam logs is rotated.
/// @param registryFilepath Filepath at which to store the registry file (which is used to track file reads).
/// @param readChunkSize Number of bytes to read at a time.
/// @param binRanges A collection of bin ranges in which to bin jetsam times.
/// @param outError  If non-nill on return, then initializing the reader failed with the provided error.
/// @return Returns nil when `outError` is non-nil.
+ (JetsamMetrics *_Nullable)getMetricsFromFilePath:(NSString*)filepath
                               withRotatedFilepath:(NSString*)rotatedFilepath
                                  registryFilepath:(NSString*)registryFilepath
                                     readChunkSize:(NSUInteger)readChunkSize
                                         binRanges:(NSArray<BinRange*>*_Nullable)binRanges
                                             error:(NSError * _Nullable *)outError;

@end

#endif

#if TARGET_IS_EXTENSION || TARGET_IS_TEST

FOUNDATION_EXPORT NSErrorDomain const ExtensionJetsamTrackingErrorDomain;

typedef NS_ERROR_ENUM(ExtensionJetsamTrackingErrorDomain, ExtensionJetsamTrackingErrorCode) {
    ExtensionJetsamTrackingErrorInitWriterFailed = 1,
    ExtensionJetsamTrackingErrorArchiveDataFailed = 2,
    ExtensionJetsamTrackingErrorWriteDataFailed = 3,
};

/// Extension jetsam logging.
@interface ExtensionJetsamTracking : NSObject

/// Log a jetsam event.
/// @param jetsamEvent Event to log.
/// @param filepath File where the event should be logged.
/// @param rotatedFilepath Filepath where the logfile should be rotated to when it exceeds the configured max filesize.
/// @param maxFilesizeBytes Configured max filesize.
/// @param outError If non-nill on return, then logging the jetsam event failed with the provided error.
+ (void)logJetsamEvent:(JetsamEvent*)jetsamEvent
            toFilepath:(NSString*)filepath
   withRotatedFilepath:(NSString*)rotatedFilepath
      maxFilesizeBytes:(NSUInteger)maxFilesizeBytes
                 error:(NSError * _Nullable *)outError;

@end

#endif

NS_ASSUME_NONNULL_END
