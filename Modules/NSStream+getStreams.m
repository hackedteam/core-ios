/*
 * NSStream Category
 *  Provides our good 'ol getStreamsToHost:port:inputStream:outputStream method
 *
 * 
 * Created by Alfredo 'revenge' Pesoli on 09/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <CFNetwork/CFSocketStream.h>
#import "NSStream+getStreams.h"

//#define DEBUG


@implementation NSStream (getStreamsAddition)

+ (void)getStreamsToHostNamed: (NSString *)hostName 
                         port: (NSInteger)port 
                  inputStream: (NSInputStream **)inputStreamPtr 
                 outputStream: (NSOutputStream **)outputStreamPtr
{
  CFReadStreamRef     readStream;
  CFWriteStreamRef    writeStream;
  
  readStream  = NULL;
  writeStream = NULL;
  
  CFStreamCreatePairWithSocketToHost(NULL, 
                                     (CFStringRef)hostName, 
                                     port,
                                     (CFReadStreamRef *)inputStreamPtr,
                                     (CFWriteStreamRef *)outputStreamPtr
                                     );
  
  /*
  CFStreamCreatePairWithSocketToHost(
                                     NULL, 
                                     (CFStringRef)hostName, 
                                     port,
                                     ((inputStreamPtr  != nil) ? &readStream  : NULL),
                                     ((outputStreamPtr != nil) ? &writeStream : NULL)
                                     );
  
  if (inputStreamPtr != NULL && readStream)
    {
      //CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
      //*inputStreamPtr  = [NSMakeCollectable(readStream) autorelease];
      *inputStreamPtr = (NSInputStream *)readStream;
    }
  
  if (outputStreamPtr != NULL && writeStream)
    {
      //CFWriteStreamSetProperty(writeStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
      //*outputStreamPtr = [NSMakeCollectable(writeStream) autorelease];
      *outputStreamPtr = (NSOutputStream *)writeStream;
    }
  */
}

@end