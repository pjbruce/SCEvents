/*
 *  $Id: SCEvents.m 218 2012-04-12 19:16:38Z stuart $
 *
 *  SCEvents
 *  http://stuconnolly.com/projects/code/
 *
 *  Copyright (c) 2011 Stuart Connolly. All rights reserved.
 *
 *  Permission is hereby granted, free of charge, to any person
 *  obtaining a copy of this software and associated documentation
 *  files (the "Software"), to deal in the Software without
 *  restriction, including without limitation the rights to use,
 *  copy, modify, merge, publish, distribute, sublicense, and/or sell
 *  copies of the Software, and to permit persons to whom the
 *  Software is furnished to do so, subject to the following
 *  conditions:
 *
 *  The above copyright notice and this permission notice shall be
 *  included in all copies or substantial portions of the Software.
 * 
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *  OTHER DEALINGS IN THE SOFTWARE.
 */

#import "SCEvents.h"
#import "SCEvent.h"
#import "pthread.h"

// Constants
static const CGFloat SCEventsDefaultNotificationLatency = 3.0;
static const NSUInteger SCEventsDefaultIgnoreEventsFromSubDirs = 1;

/**
 * Private API
 */
@interface SCEvents ()

static FSEventStreamRef _create_events_stream(SCEvents *watcher,
											  CFArrayRef paths, 
											  CFTimeInterval latency,
											  FSEventStreamEventId sinceWhen);

static void _events_callback(ConstFSEventStreamRef streamRef, 
							 void *clientCallBackInfo, 
							 size_t numEvents, 
							 void *eventPaths, 
							 const FSEventStreamEventFlags eventFlags[], 
							 const FSEventStreamEventId eventIds[]);

static CFStringRef _strip_trailing_slash_from_path(CFStringRef path);

@end

@implementation SCEvents

@synthesize _delegate;
@synthesize _isWatchingPaths;
@synthesize _ignoreEventsFromSubDirs;
@synthesize _lastEvent;
@synthesize _notificationLatency;
@synthesize _watchedPaths;
@synthesize _excludedPaths;
@synthesize _resumeFromEventId;

#pragma mark -
#pragma mark Initialisation

/**
 * Initializes an instance of SCEvents setting its default values.
 *
 * @return The initialized SCEvents instance
 */
- (id)init
{
    if ((self = [super init])) {
        _isWatchingPaths = NO;
		
		pthread_mutex_init(&_eventsLock, NULL);
        
		[self setResumeFromEventId:kFSEventStreamEventIdSinceNow];
        [self setNotificationLatency:SCEventsDefaultNotificationLatency];
        [self setIgnoreEventsFromSubDirs:SCEventsDefaultIgnoreEventsFromSubDirs];
    }
    
    return self;
}

#pragma mark -
#pragma mark Public API

/**
 * Flushes the event stream synchronously by sending events that have already 
 * occurred but not yet delivered.
 *
 * @return A BOOL indicating the sucess or failure
 */
- (BOOL)flushEventStreamSync
{
	pthread_mutex_lock(&_eventsLock);
	
    if (!_isWatchingPaths) {
		pthread_mutex_unlock(&_eventsLock);
		
		return NO;
	}
    
    FSEventStreamFlushSync(_eventStream);
    
	pthread_mutex_unlock(&_eventsLock);
	
    return YES;
}

/**
 * Flushes the event stream asynchronously by sending events that have already 
 * occurred but not yet delivered.
 *
 * @return A BOOL indicating the sucess or failure
 */
- (BOOL)flushEventStreamAsync
{
    pthread_mutex_lock(&_eventsLock);
	
    if (!_isWatchingPaths) {
		pthread_mutex_unlock(&_eventsLock);
		
		return NO;
	}
    
    FSEventStreamFlushAsync(_eventStream);
    
	pthread_mutex_unlock(&_eventsLock);
	
    return YES;
}

/**
 * Starts watching the supplied array of paths for events on the current run loop.
 *
 * @param paths An array of paths to watch
 *
 * @return A BOOL indicating the success or failure
 */
- (BOOL)startWatchingPaths:(NSArray *)paths
{
    return [self startWatchingPaths:paths onRunLoop:[NSRunLoop currentRunLoop]];
}

/**
 * Starts watching the supplied array of paths for events on the supplied run loop.
 * A boolean value is returned to indicate the success of starting the stream. If 
 * there are no paths to watch or the stream is already running then false is
 * returned.
 *
 * @param paths   An array of paths to watch
 * @param runLoop The runloop the events stream is to be scheduled on
 *
 * @return A BOOL indicating the success or failure
 */
- (BOOL)startWatchingPaths:(NSArray *)paths onRunLoop:(NSRunLoop *)runLoop
{
	pthread_mutex_lock(&_eventsLock);
	
	_runLoop = [runLoop getCFRunLoop];
	
    if ([paths count] == 0 || _isWatchingPaths) {
		pthread_mutex_unlock(&_eventsLock);
		
		return NO;
	}
    
    [self setWatchedPaths:paths];
    
	_eventStream = _create_events_stream(self, ((CFArrayRef)_watchedPaths), _notificationLatency, _resumeFromEventId);
    
    // Schedule the event stream on the supplied run loop
    FSEventStreamScheduleWithRunLoop(_eventStream, _runLoop, kCFRunLoopDefaultMode);
    
    // Start the event stream
    FSEventStreamStart(_eventStream);
    
    _isWatchingPaths = YES;
    
	pthread_mutex_unlock(&_eventsLock);
	
    return YES;
}

/**
 * Stops the event stream from watching the set paths. A boolean value is returned
 * to indicate the success of stopping the stream. False is return if this method 
 * is called when the stream is not already running.
 *
 * @return A BOOL indicating the success or failure
 */
- (BOOL)stopWatchingPaths
{
	pthread_mutex_lock(&_eventsLock);
	
    if (!_isWatchingPaths) {
		pthread_mutex_unlock(&_eventsLock);
		
		return NO;
	}
	    
    FSEventStreamStop(_eventStream);
	
	if (_runLoop) FSEventStreamUnscheduleFromRunLoop(_eventStream, _runLoop, kCFRunLoopDefaultMode);
	
    FSEventStreamInvalidate(_eventStream);
	
	if (_eventStream) FSEventStreamRelease(_eventStream), _eventStream = NULL;
    
    _isWatchingPaths = NO;
    
	pthread_mutex_unlock(&_eventsLock);
	
    return YES;
}

/**
 * Provides a description of the event stream. Useful for debugging purposes.
 *
 * @return The descroption string
 */
- (NSString *)streamDescription
{
	pthread_mutex_lock(&_eventsLock);
	
	NSString *description = (_isWatchingPaths) ? (NSString *)FSEventStreamCopyDescription(_eventStream) : nil;
	
	pthread_mutex_unlock(&_eventsLock);
	
	return [description autorelease];
}

#pragma mark -
#pragma mark Other

/**
 * Provides the string used when printing this object in NSLog, etc. Useful for
 * debugging purposes.
 *
 * @return The description string
 */
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ { watchedPaths = %@, excludedPaths = %@ } >", [self className], _watchedPaths, _excludedPaths];
}

#pragma mark -

- (void)dealloc
{
	_delegate = nil;
	
	// Stop the event stream if it's still running
	if (_isWatchingPaths) [self stopWatchingPaths];
        
	pthread_mutex_destroy(&_eventsLock);
	
	[_lastEvent release], _lastEvent = nil;
    [_watchedPaths release], _watchedPaths = nil;
    [_excludedPaths release], _excludedPaths = nil;
    
    [super dealloc];
}


- (BOOL)isHideFile:(NSString*)strPath
{
    NSRange findDotRange;
    findDotRange = [strPath rangeOfString:@"/." options:NSCaseInsensitiveSearch];
    if(findDotRange.location !=NSNotFound || [[strPath lastPathComponent] characterAtIndex: 0] == '.' )
    {
        return YES;
    }
    
    return NO;
}

- (BOOL)isExistPath:(NSString*)strPath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:strPath])
    {
        return YES;
    }
    
    return NO;
}

- (BOOL)isAddPath:(SCEvent*)firstEvent secondEvent:(SCEvent*)secondEvent
{
    if (firstEvent.eventId+1 != secondEvent.eventId) {
        if (firstEvent.eventFlags & kFSEventStreamEventFlagItemCreated) {
            NSLog(@"Add");
            return YES;
        }
    }
    return NO;
}

- (BOOL)isRenamePath:(SCEvent*)firstEvent secondEvent:(SCEvent*)secondEvent
{
    if (firstEvent.eventId+1 == secondEvent.eventId) {
        NSString *firstPath = [firstEvent.eventPath stringByDeletingLastPathComponent];
        NSString *secondPath = [secondEvent.eventPath stringByDeletingLastPathComponent];
        if ([firstPath compare:secondPath options:NSCaseInsensitiveSearch] == NSOrderedSame && ![self isExistPath:firstEvent.eventPath] && [self isExistPath:secondEvent.eventPath]) {
            NSLog(@"Rename");
            return YES;
        }
    }
    return NO;
}

- (BOOL)isMovePath:(SCEvent*)firstEvent secondEvent:(SCEvent*)secondEvent
{
    if (firstEvent.eventId+1 == secondEvent.eventId) {
        NSString *firstPath = [firstEvent.eventPath stringByDeletingLastPathComponent];
        NSString *secondPath = [secondEvent.eventPath stringByDeletingLastPathComponent];
        if ([firstPath compare:secondPath options:NSCaseInsensitiveSearch] != NSOrderedSame && ![self isExistPath:firstEvent.eventPath] && [self isExistPath:secondEvent.eventPath]) {
             NSLog(@"Move");
            return YES;
        }
    }
    return NO;
}

- (BOOL)isModifyOrAddPath:(SCEvent*)event
{
    if ([self isExistPath:event.eventPath] && (event.eventFlags & kFSEventStreamEventFlagItemCreated)) {
        NSLog(@"Add");
        return YES;
    }
    else if ([self isExistPath:event.eventPath])
    {
        NSLog(@"Modify");
        return YES;
    }
    
    return NO;
}
- (BOOL)isModifyPath:(SCEvent*)firstEvent secondEvent:(SCEvent*)secondEvent
{
    if (firstEvent.eventId+1 != secondEvent.eventId) {
        NSString *firstPath = [firstEvent.eventPath stringByDeletingLastPathComponent];
        NSString *secondPath = [secondEvent.eventPath stringByDeletingLastPathComponent];
        if ([firstPath compare:secondPath options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            if (![self isExistPath:firstEvent.eventPath] && [self isExistPath:secondEvent.eventPath]) {
                NSLog(@"Modify");
                return YES;
            }
        }
        
        
    }
    return NO;
}
- (BOOL)isDeletePath:(SCEvent*)firstEvent secondEvent:(SCEvent*)secondEvent
{
    if (firstEvent.eventId+1 != secondEvent.eventId) {
        
        if (![self isExistPath:firstEvent.eventPath] && ![self isExistPath:secondEvent.eventPath]) {
            NSLog(@"Delete");
            return YES;
        }
    }
    return NO;
}
#pragma mark -
#pragma mark Private API

/**
 * Creates and returns the initialised events stream.
 *
 * @param watcher The watcher instance that is to be supplied to the callback function  
 * @param paths   The paths that are to be 'watched'
 * @param latency The notification latency
 */
static FSEventStreamRef _create_events_stream(SCEvents *watcher, CFArrayRef paths, CFTimeInterval latency, FSEventStreamEventId sinceWhen)
{
	FSEventStreamContext callbackInfo;
	
	callbackInfo.version = 0;
	callbackInfo.info    = (void *)watcher;
	callbackInfo.retain  = NULL;
	callbackInfo.release = NULL;
	callbackInfo.copyDescription = NULL;
    
    return FSEventStreamCreate(kCFAllocatorDefault, 
							   &_events_callback,
							   &callbackInfo, 
							   paths, 
							   sinceWhen, 
							   1.0,
							   kFSEventStreamCreateFlagUseCFTypes  | kFSEventStreamCreateFlagFileEvents);
}

/**
 * FSEvents callback function. For each event that occurs an instance of SCEvent
 * is created and passed to the delegate. The frequency at which this callback is
 * called depends upon the notification latency value. This callback is usually
 * called with more than one event and so multiple instances of SCEvent are created
 * and the delegate notified.
 *
 * @param streamRef          The calling stream reference
 * @param clientCallBackInfo Any client callback info that was supplied when the stream was created
 * @param numEvents          The number of events being supplied
 * @param eventPaths         An array of the event's paths
 * @param eventFlags         An array of flags associated with the events
 * @param eventIds           An array of IDs associated with the events
 */
static void _events_callback(ConstFSEventStreamRef streamRef, 
							  void *clientCallBackInfo, 
							  size_t numEvents, 
							  void *eventPaths, 
							  const FSEventStreamEventFlags eventFlags[], 
							  const FSEventStreamEventId eventIds[])
{
    NSUInteger i;
    BOOL shouldIgnore = NO;
    
	CFArrayRef paths = (CFArrayRef)eventPaths;
    SCEvents *pathWatcher = (SCEvents *)clientCallBackInfo;
    uint32 modifiedFiles = kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed |kFSEventStreamEventFlagItemModified;
    
    NSLog(@"_events_callback\n\n");
    NSMutableArray *eventArray = [[NSMutableArray alloc] init];
    for (i = 0; i < numEvents; i++)
	{
        /* Please note that we are estimating the date for when the event occurred 
         * because the FSEvents API does not provide us with it. This date however
         * should not be taken as the date the event actually occurred and more 
         * appropriatly the date for when it was delivered to this callback function.
         * Depending on what the notification latency is set to, this means that some
         * events may have very close event dates because this callback is only called 
         * once with events that occurred within the latency time.
         *
         * To get a more accurate date for when events occur, you could decrease the 
         * notification latency from its default value. This means that this callback 
         * will be called more frequently for events that just occur and reduces the
         * number of events that are subsequntly delivered during one of these calls.
         * The drawback to this approach however, is the increased resources required
         * calling this callback more frequently.
         */
        
		NSArray *excludedPaths = [pathWatcher excludedPaths];
        CFStringRef eventPath = CFArrayGetValueAtIndex(paths, (CFIndex)i);

        
        
        // Check to see if the event should be ignored if it's path is in the exclude list
        if ([excludedPaths containsObject:(NSString *)eventPath]) {
            shouldIgnore = YES;
        }
        else {
            // If we did not find an exact match in the exclude list and we are to ignore events from
            // sub-directories then see if the exclude paths match as a prefix of the event path.
            if ([pathWatcher ignoreEventsFromSubDirs]) {
                for (NSString *path in [pathWatcher excludedPaths]) 
				{
					if (CFStringHasPrefix(eventPath, (CFStringRef)path)) {
						shouldIgnore = YES;
                        break;
					}
                }
            }
        }
    
        if (eventFlags[i] == kFSEventStreamEventFlagMustScanSubDirs) {
            NSLog(@"11");
        }
        if (!shouldIgnore) {
						
			// If present remove the path's trailing slash
			eventPath = _strip_trailing_slash_from_path(eventPath);
					
            if ([pathWatcher isHideFile:(NSString *)eventPath])
            {
                continue;
            }
            
            if(eventFlags[i] & modifiedFiles)
            {
                if ((unsigned int)eventFlags[i] & kFSEventStreamEventFlagItemModified) {
                    NSLog(@"kFSEventStreamEventFlagItemModified");
                }
                if ((unsigned int)eventFlags[i] & kFSEventStreamEventFlagItemCreated) {
                    NSLog(@"kFSEventStreamEventFlagItemCreated");
                }
                if ((unsigned int)eventFlags[i] & kFSEventStreamEventFlagItemRenamed) {
                    NSLog(@"kFSEventStreamEventFlagItemRenamed");
                }
                
                if ((unsigned int)eventFlags[i] & kFSEventStreamEventFlagItemRemoved) {
                    NSLog(@"kFSEventStreamEventFlagItemRemoved");
                }
                NSLog(@"Change %llu in %@, flags %x\n", eventIds[i], (NSString *)eventPath, (unsigned int)eventFlags[i]);
            }
            else
            {
                NSLog(@"Ignoring %llu in %@, flags %x\n", eventIds[i], (NSString *)eventPath, (unsigned int)eventFlags[i]);
            }

            
            SCEvent *event = [SCEvent eventWithEventId:(NSUInteger)eventIds[i]
											 eventDate:[NSDate date] 
											 eventPath:(NSString *)eventPath 
											eventFlags:(SCEventFlags)eventFlags[i]];
            [eventArray addObject:event];
            if ([[pathWatcher delegate] conformsToProtocol:@protocol(SCEventListenerProtocol)]) {
                [[pathWatcher delegate] pathWatcher:pathWatcher eventOccurred:event];
            }
            
            if (i == (numEvents - 1)) {
                [pathWatcher setLastEvent:event];
            }
        }
    }
    
    NSInteger iCount = [eventArray count];
    if (iCount == 1) {
        SCEvent *event = [eventArray objectAtIndex:0];
        if ([pathWatcher isExistPath:event.eventPath]) {
            NSLog(@"Modify");
        }
        else
        {
            NSLog(@"Delete");
        }
    }
    else if (iCount >=2)
    {
        for (NSInteger index =0; index< iCount; index++) {
            
            NSLog(@"index:%ld", (long)index);
            SCEvent *firstEvent = [eventArray objectAtIndex:index];
            if (index+1 < iCount) {
                SCEvent *secondEvent = [eventArray objectAtIndex:index+1];
                if ([pathWatcher isModifyOrAddPath:firstEvent]) {
                    NSLog(@"Modify");
                }
                else if ([pathWatcher isRenamePath:firstEvent secondEvent:secondEvent]) {
                    NSLog(@"Rename");
                    index++;
                }
                else if ([pathWatcher isModifyPath:firstEvent secondEvent:secondEvent])
                {
                    NSLog(@"Modify");
                    index++;
                }
                else if ([pathWatcher isDeletePath:firstEvent secondEvent:secondEvent])
                {
                    NSLog(@"Delete");
                }
                else if ([pathWatcher isAddPath:firstEvent secondEvent:secondEvent])
                {
                    NSLog(@"Addd");
                }
                else if ([pathWatcher isMovePath:firstEvent secondEvent:secondEvent])
                {
                    NSLog(@"Move");
                    index++;
                }
            }
            else
            {
                if ([pathWatcher isExistPath:firstEvent.eventPath]) {
                    if (firstEvent.eventFlags & kFSEventStreamEventFlagItemCreated) {
                        NSLog(@"Add");
                    }
                    else
                    {
                        NSLog(@"Modify");
                    }
                    
                }
                else
                {
                    NSLog(@"Delete");
                }
            }
            
            
        }
    }
    
    [eventArray release];
}


+ (BOOL)isFolderPath:(NSString*)path
{
    BOOL bFolder = NO;
    NSFileManager *manager = [NSFileManager defaultManager];
    NSDictionary *attributes =	[manager attributesOfItemAtPath: path error: nil];
    if ([[attributes fileType] isEqualToString:NSFileTypeDirectory])
    {
        bFolder = YES;
    }
    
    return bFolder;
}


/**
 * If present, strips the trailing slash from the supplied string.
 *
 * @param string The string that is to be stripped
 *
 @ @return The resulting string
 */
static CFStringRef _strip_trailing_slash_from_path(CFStringRef path)
{
	NSString *string = (NSString *)path;

	NSUInteger length = [string length];
	
	return (length > 1 && [string hasSuffix:@"/"]) ? (CFStringRef)[string substringToIndex:length - 1] : path;
}

@end
