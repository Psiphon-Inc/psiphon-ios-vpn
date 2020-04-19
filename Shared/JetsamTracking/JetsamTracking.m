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

#import "JetsamTracking.h"
#import "Archiver.h"
#import "ExtensionContainerFile.h"
#import "NSError+Convenience.h"

#if TARGET_IS_CONTAINER || TARGET_IS_TEST

NSErrorDomain _Nonnull const ContainerJetsamTrackingErrorDomain = @"ContainerJetsamTrackingErrorDomain";

@implementation ContainerJetsamTracking

+ (JetsamMetrics*)getMetricsFromFilePath:(NSString*)filepath
                     withRotatedFilepath:(NSString*)rotatedFilepath
                        registryFilepath:(NSString*)registryFilepath
                           readChunkSize:(NSUInteger)readChunkSize
                                   error:(NSError * _Nullable *)outError {

    *outError = nil;

    NSError *err;
    ContainerReaderRotatedFile *cont =
      [[ContainerReaderRotatedFile alloc] initWithFilepath:filepath
                                             olderFilepath:rotatedFilepath
                                          registryFilepath:registryFilepath
                                             readChunkSize:readChunkSize
                                                     error:&err];
    if (err != nil) {
        *outError = [NSError errorWithDomain:ContainerJetsamTrackingErrorDomain
                                        code:ContainerJetsamTrackingErrorInitFileReaderFailed
                         withUnderlyingError:err];
        return nil;
    }

    JetsamMetrics *metrics = [[JetsamMetrics alloc] init];

    while (true) {
        NSString *line = [cont readLineWithError:&err];
        if (err != nil) {
            *outError = [NSError errorWithDomain:ContainerJetsamTrackingErrorDomain
                                            code:ContainerJetsamTrackingErrorReadingDataFailed
                             withUnderlyingError:err];
            return nil;
        }
        if (line == nil) {
            // Done reading
            return metrics;
        }

        NSData *data = [[NSData alloc] initWithBase64EncodedData:[line dataUsingEncoding:NSUTF8StringEncoding]
                                                         options:kNilOptions];
        if (data == nil) {
             *outError = [NSError errorWithDomain:ContainerJetsamTrackingErrorDomain
                                             code:ContainerJetsamTrackingErrorDecodingDataFailed
                          andLocalizedDescription:@"data is nil"];
            return nil;
        }

        JetsamEvent *event = [Archiver unarchiveObjectWithData:data error:&err];
        if (err != nil) {
            *outError = [NSError errorWithDomain:ContainerJetsamTrackingErrorDomain
                                            code:ContainerJetsamTrackingErrorUnarchivingDataFailed
                             withUnderlyingError:err];
            return nil;
        }

        [metrics addJetsamForAppVersion:event.appVersion runningTime:event.runningTime];
    }

}


@end

#endif

#if TARGET_IS_EXTENSION || TARGET_IS_TEST

NSErrorDomain _Nonnull const ExtensionJetsamTrackingErrorDomain = @"ExtensionJetsamTrackingErrorDomain";

@implementation ExtensionJetsamTracking

+ (void)logJetsamEvent:(JetsamEvent*)jetsamEvent
            toFilepath:(NSString*)filepath
   withRotatedFilepath:(NSString*)rotatedFilepath
      maxFilesizeBytes:(NSUInteger)maxFilesizeBytes
                 error:(NSError * _Nullable *)outError {

    *outError = nil;

    NSError *err;
    ExtensionWriterRotatedFile *ext =
      [[ExtensionWriterRotatedFile alloc] initWithFilepath:filepath
                                             olderFilepath:rotatedFilepath
                                          maxFilesizeBytes:maxFilesizeBytes
                                                     error:&err];
    if (err != nil) {
        *outError = [NSError errorWithDomain:ExtensionJetsamTrackingErrorDomain
                                        code:ExtensionJetsamTrackingErrorInitWriterFailed
                         withUnderlyingError:err];
        return;
    }

    NSData *encodedData = [Archiver archiveObject:jetsamEvent error:&err];
    if (err != nil) {
        *outError = [NSError errorWithDomain:ExtensionJetsamTrackingErrorDomain
                                        code:ExtensionJetsamTrackingErrorArchiveDataFailed
                         withUnderlyingError:err];
        return;
    }
    NSString *b64EncodedString = [encodedData base64EncodedStringWithOptions:kNilOptions];
    NSMutableData *data = [NSMutableData dataWithData:[b64EncodedString dataUsingEncoding:NSASCIIStringEncoding]];
    [data appendData:[@"\n" dataUsingEncoding:NSASCIIStringEncoding]];

    [ext writeData:data error:&err];
    if (err != nil) {
        *outError = [NSError errorWithDomain:ExtensionJetsamTrackingErrorDomain
                                        code:ExtensionJetsamTrackingErrorWriteDataFailed
                     andLocalizedDescription:@"data is nil"];
        return;
    }

    return;
}

@end

#endif
