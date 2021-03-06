/*
 *  $Id: SCEventTests.h 181 2011-02-05 23:19:08Z stuart $
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

#import <SenTestingKit/SenTestingKit.h>

@class SCEvent;

/**
 * @class SCEventsTest SCEventsTest.h
 *
 * @author Stuart Connolly http://stuconnolly.com/
 *
 * SCEvent tests class.
 */
@interface SCEventTests : SenTestCase
{
	SCEvent *_event;
	
	NSUInteger _eventId;
    NSDate *_eventDate;
    NSString *_eventPath;
    FSEventStreamEventFlags _eventFlags;
}

/**
 * @property _eventId The ID of the event.
 */
@property (readwrite, assign, getter=eventId, setter=setEventId:) NSUInteger _eventId;

/**
 * @property _eventDate The date of the event.
 */
@property (readwrite, retain, getter=eventDate, setter=setEventDate:) NSDate *_eventDate;

/**
 * @property _eventPath The file system path of the event.
 */
@property (readwrite, retain, getter=eventPath, setter=setEventPath:) NSString *_eventPath;

/**
 * @property _eventFlag The flags that are associated with the event.
 */
@property (readwrite, assign, getter=eventFlag, setter=setEventFlag:) FSEventStreamEventFlags _eventFlags;

@end
