/*
 *  RCSILogger.h
 *  RCSIpony
 *
 *
 *  Created by revenge on 2/2/11.
 *  Copyright (C) HT srl 2011. All rights reserved
 *
 */

#import <Foundation/Foundation.h>
#import "RCSIDebug.h"


#ifdef ENABLE_LOGGING

enum
{
  kInfoLevel,
  kWarnLevel,
  kErrLevel,
  kVerboseLevel,
};

#define infoLog(format,...) [[RCSILogger sharedInstance] log: __func__ \
                             line: __LINE__ level: kInfoLevel string: (format), ##__VA_ARGS__]

#define warnLog(format,...) [[RCSILogger sharedInstance] log: __func__ \
                             line: __LINE__ level: kWarnLevel string: (format), ##__VA_ARGS__]

#define errorLog(format,...) [[RCSILogger sharedInstance] log: __func__ \
                              line: __LINE__ level: kErrLevel string: (format), ##__VA_ARGS__]

#define verboseLog(format,...) [[RCSILogger sharedInstance] log: __func__ \
                                line: __LINE__ level: kVerboseLevel string: (format), ##__VA_ARGS__]

@interface RCSILogger : NSObject
{
@private
  NSFileHandle *mLogHandle;
  NSString *mLogName;
  int mLevel;
}

@property (setter = setLevel:, readwrite) int mLevel;

+ (RCSILogger *)sharedInstance;
+ (id)allocWithZone: (NSZone *)aZone;

+ (void)setComponent: (NSString *)aComponent;
+ (void)enableProcessNameVisualization: (BOOL)aFlag;

- (id)copyWithZone:  (NSZone *)aZone;
- (id)init;
- (id)retain;
- (unsigned)retainCount;
- (void)release;
- (id)autorelease;

- (void)log: (const char *)aCaller
       line: (int)aLineNumber
      level: (int)aLogLevel
     string: (NSString *)aFormat, ...;

@end

#endif
