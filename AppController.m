
#import "AppController.h"
#import "FolderSweeper.h"

// This class illustrates how to sweep a folder and it's subfolders, using the
//	FolderSweeper class, looking for text files and trying to identify their
//	encodings.

// Variables to store number of files, number of text files, and number of text files of each encoding.
// They could also be instance variables of the AppController object; for singleton objects
//	it doesn't really matter.

static NSUInteger fileCounter = 0;
static NSUInteger textCounter = 0;
static NSCountedSet* types = nil;

@implementation AppController

// This method is called on the application delegate after the Dock icon stops bouncing.
// You may think this could also be done by implementing -awakeFromNib, but that should
//	properly be reserved for setup pertaining to nib objects... note that it's not
//	impossible for awakeFromNib being called multiple times, for instance.
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
	// Note current date/time so we can work out how long the folder-sweep took.
	NSDate* start = [NSDate date];
	
	// Get a FolderSweeper instance, and set ourselves as its delegate.
	FolderSweeper* sweeper = [FolderSweeper folderSweeper];
	[sweeper setDelegate:self];
	
	// Comment this out if you want to try following links...
	[sweeper setFollowsLinks:NO];
	
	// Sweep the user's Logs folder - usually plenty of files in there.
	// Note that you never should hardcode paths like this; call NSSearchPathForDirectoriesInDomains()
	//	or some other system function. This is just convenient for testing.
	NSString* folder = [@"~/Library/Logs" stringByExpandingTildeInPath];
	
	// We set up a pointer to an NSError, so we can get information on any errors which may occur.
	// You can also just pass NULL for the error: argument if you're not interested in errors.
	NSError *error = nil; 
	BOOL result = [sweeper sweepFolder:folder gettingInfo:0 error:&error]; // pass in 0 for gettingInfo as we don't need file metadata
	if (error) {
		NSLog(@"An error occurred: %@", error);
	}
	if (result) {
		// Work out how long we took, and output the results of the sweep.
		NSTimeInterval delta = -[start timeIntervalSinceNow];
		NSLog(@"Swept folder \"%@\" in %g seconds, %d files, %d text files.", 
			  folder, delta, fileCounter, textCounter);
		
		for (NSNumber* enc in types) {
			NSLog(@"%d files encoded as %@", [types countForObject:enc], 
				  CFStringGetNameOfEncoding([enc unsignedIntValue]));
		}
	}
	
	// Quit the app.
	[NSApp terminate:self];
}


- (BOOL)sweeper:(FolderSweeper*)sweeper shouldProcessObject:(FSRef*)aFileRef named:(NSString*)aFileName 
					hasInfo:(FSCatalogInfo*)aFileInfo isFolder:(BOOL)isFolder {
	// This method, which must be implemented, is called to determine whether to further process a file or folder.
	// Processing a folder means recursively sweeping its contents, and processing a file means that our 
	//	processFile:named:hasInfo:contents: method will be called for that file.
	
	// This implementation processes only folders (so we fully traverse the folder hierarchy),
	//	and also files which conform to the "public.text" Uniform Type Identifier (i.e. text files).
	BOOL result = isFolder;
	
	if (!isFolder) {
		
		// This illustrates one way of testing for UTI conformance.
		CFStringRef uti;
		if (LSCopyItemAttribute(aFileRef, kLSRolesViewer, kLSItemContentType, (CFTypeRef*)&uti)==noErr) {
			if (UTTypeConformsTo(uti, kUTTypeText)) {
				result = YES;
			}
			CFRelease(uti);
		}
		// Note that we've encountered another file. 
		++fileCounter;
	}
	
	// The following code shows how not to sweep into packages and bundles.
	if (isFolder) {
		if ([sweeper itemFlagsForRef:NULL andExtension:nil] & kLSItemInfoIsPackage) {
			result = NO;
		}
	}
	
	return result;
}


- (void)sweeper:(FolderSweeper*)sweeper processFile:(FSRef*)aFileRef named:(NSString*)aFileName 
			hasInfo:(FSCatalogInfo*)aFileInfo contents:(NSData*)contents {
	// This is an optional delegate method for the FolderSweeper's delegate.
	// If implemented, it will be called with the memory-mapped contents of 
	//	each file to which our shouldProcessObject:named:hasInfo:isFolder: 
	//	method returned YES.
	
	// If the file contents are longer than zero bytes, we try to determine what 
	//	text-encoding the file uses, by looking at the BOM bytes for common encodings.
	// This heuristic should work for most text files on a developer's system,
	//	but is by no means complete.
	
	NSUInteger length = [contents length];
	if (length>0) {
		// We get a pointer to the actual bytes here, in order to look at the first ones.
		// Remember the file will be memory-mapped, so this will page in only the first 4K.
		UInt8* bytes = (UInt8*)[contents bytes];
		CFStringEncoding encoding = CFStringGetSystemEncoding();
		Boolean bom = TRUE;
		switch (bytes[0]) {
			case 0x00:
				if (length>3 && bytes[1]==0x00 && bytes[2]==0xFE && bytes[3]==0xFF) {
					encoding = kCFStringEncodingUTF32BE;
				}
				break;
				case 0xEF:
				if (length>2 && bytes[1]==0xBB && bytes[2]==0xBF) {
					encoding = kCFStringEncodingUTF8;
				}
				break;
				case 0xFE:
				if (length>1 && bytes[1]==0xFF) {
					encoding = kCFStringEncodingUTF16BE;
				}
				break;
				case 0xFF:
				if (length>1 && bytes[1]==0xFE) {
					if (length>3 && bytes[2]==0x00 && bytes[3]==0x00) {
						encoding = kCFStringEncodingUTF32LE;
					} else {
						encoding = kCFStringEncodingUTF16LE;
					}
				}
				break;
				default:
				bom = FALSE;
				encoding = kCFStringEncodingUTF8; // fall back on UTF8
				break;
		}
		
		// Try to create an NSString with the encoding we determined.
		// The "bytes" pointer refers to the actual memory-mapped file and we're just
		//	creating another object referring to that, without copying anything;
		//	copying would mean paging the entire file into memory, which might be slow.
		NSString* string = (NSString*)CFStringCreateWithBytesNoCopy(kCFAllocatorDefault, bytes, length, 
																	encoding, bom, kCFAllocatorNull);
		
		if (!string && !bom && (encoding == kCFStringEncodingUTF8)) {
			// If we failed, try creating an NSString with the system encoding instead;
			//	this will normally be MacRoman.
			encoding = CFStringGetSystemEncoding();
			string = (NSString*)CFStringCreateWithBytesNoCopy(kCFAllocatorDefault, bytes, length, 
															  encoding, FALSE, kCFAllocatorNull);
		}
		
		if (string) {
			// Create the "types" NSCountedSet if necessary.
			if (!types) {
				types = [[NSCountedSet alloc] init];
			}
			// Note we've found another file of this encoding.
			NSNumber* enc = [[NSNumber alloc] initWithUnsignedInt:encoding];
			[types addObject:enc];
			[enc release];
			
			// Note we found another text file.
			++textCounter;
			
			// Do something interesting with the string here...
			
			// Release the string.
			[string release];
		}
	}
}


@end
