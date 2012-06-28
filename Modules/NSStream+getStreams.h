/*
 * NSStream Category
 *  Provides our good 'ol getStreamsToHost:port:inputStream:outputStream method
 *
 * 
 * Created on 09/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <Foundation/Foundation.h>


@interface NSStream (getStreamsAddition)

+ (void)getStreamsToHostNamed: (NSString *)hostName 
                         port: (NSInteger)port 
                  inputStream: (NSInputStream **)inputStreamPtr 
                 outputStream: (NSOutputStream **)outputStreamPtr;

@end