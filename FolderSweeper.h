
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

// This class implements a fast and easy way of sweeping over a folder, optionally
//	looking at all subfolders and/or file contents.

@interface FolderSweeper: NSObject {
    FSRef object;
    NSString* path;
    id delegate;
    UInt8* posix;
    BOOL followsLinks;
	BOOL stop;
}

// Call this to get a new, autoreleased sweeper object.
+ (FolderSweeper*)folderSweeper;

// This convenience class method returns the FSRef for a given path.
// No need to have a sweeper running for calling it.
// It will return NO if the path is invalid. You can pass NULL for either
//	parameter if you don't need that result.
+ (BOOL)refForPath:(NSString*)thePath outRef:(FSRef*)outRef isFolder:(BOOL*)isFolder;

// This convenience class method returns the full path for a given FSRef.
// No need to have a sweeper running for calling it.
// It will return nil if the FSRef is invalid, or if the path is too long.
+ (NSString*)pathForRef:(FSRef*)theRef;

// This convenience class method returns the LS info flags for a given FSRef,
//	and (optionally) the file extension. Pass in nil if you don't want that.
// No need to have a sweeper running for calling it.
// It will return all zeroes if the FSRef is invalid.
+ (LSItemInfoFlags)itemFlagsForRef:(FSRef*)theRef andExtension:(NSString **)outExtension;

// This convenience class method converts a UTCDateTime struct (such as is
//	found inside FSCatalogInfo) to a NSTimeInterval.
// The return value can be used to obtain a NSDate by passing it directly
//	to [NSDate dateWithTimeIntervalSinceReferenceDate:], if necessary.
+ (NSTimeInterval)intervalFromUTCDateTime:(UTCDateTime)timeStamp;

// This convenience class method converts a NSTimeInterval to UTCDateTime.
// You can pass in the result of [someNSDate timeIntervalSinceReferenceDate].
+ (UTCDateTime)UTCDateTimeFromInterval:(NSTimeInterval)interval;

// You must set the delegate before sweeping a folder.
- (void)setDelegate:(id)theDelegate;
- (id)delegate;

// Set and get the followsLinks flag. The default is YES.
// Call setFollowsLinks:NO to not follow aliases and symlinks while sweeping.
- (void)setFollowsLinks:(BOOL)flag;
- (BOOL)followsLinks;

// Call this from a delegate method or another thread to stop sweeping.
- (void)stop;

// This convenience method returns the full path for a given FSRef.
// If you call it from within one of the delegate methods you can pass in NULL
//	to mean the current FSRef - it may be faster as the path may already be available.
- (NSString*)pathForRef:(FSRef*)theRef;

// This convenience method returns the LS info flags for a given FSRef,
//	and (optionally) the file extension. Pass in nil if you don't want that.
// If you call it from within one of the delegate methods you can pass in NULL
//	to mean the current FSRef.
// It will return all zeroes if the FSRef is invalid.
- (LSItemInfoFlags)itemFlagsForRef:(FSRef*)theRef andExtension:(NSString **)outExtension;

// Call this to sweep a folder (and optionally subfolders).
// Pass 0 in whichInfo if you don't need to check file/folder metadata in the callbacks,
//	otherwise pass the appropriate masks. Getting all info (kFSCatInfoGettableInfo) may
//	slow things down somewhat.
// Returns YES if successful.
// Until this method returns, you shouldn't change that folder or any subfolders, or some
//	files may be skipped or handled twice.
- (BOOL)sweepFolder:(NSString*)thePath gettingInfo:(FSCatalogInfoBitmap)whichInfo error:(NSError **)error;

@end


// Category on NSObject specifying methods for FolderSweeper's delegate.
@interface NSObject(FolderSweeperDelegateMethods)

// The delegate must implement this.
// This is called for every file or subfolder seen.
// For a folder (isFolder == YES), return YES if you want that folder's contents to also
//	be swept.
// For a file (isFolder == NO), return YES if you want that file's contents to be passed
//	to the other delegate method, below.
// You shouldn't delete or rename files in this method.
- (BOOL)sweeper:(FolderSweeper*)sweeper shouldProcessObject:(FSRef*)aFileRef named:(NSString*)aFileName 
                    hasInfo:(FSCatalogInfo*)aFileInfo isFolder:(BOOL)isFolder;

// The delegate may implement this.
// This is called for every file that the other delegate method, above, returned YES for.
// The "contents" object is memory-mapped, so you should avoid looking at parts of the file
// you don't need. If you retain this object and use it outside the method, the file will
// be kept open until you release it.
// If memory-mapping fails (usually because no memory is available for mapping), "contents"
// will be nil, but you still may use the other parameters.
// You shouldn't delete or rename files in this method.
- (void)sweeper:(FolderSweeper*)sweeper processFile:(FSRef*)aFileRef named:(NSString*)aFileName 
            hasInfo:(FSCatalogInfo*)aFileInfo contents:(NSData*)contents;

@end
