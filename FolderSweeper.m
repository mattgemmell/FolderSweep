// FolderSweep 1.0
//
// Copyright (c)2008 by Rainer Brockerhoff.


#import "FolderSweeper.h"

// This class implements a fast and easy way of sweeping over a folder, optionally
//	looking at all subfolders and/or file contents.

@implementation FolderSweeper

// This is a convenience class method to get a new FolderSweeper instance.
+ (FolderSweeper*)folderSweeper {
	return [[[FolderSweeper alloc] init] autorelease];
}

// Convenience class method to get the FSRef from a path.
+ (BOOL)refForPath:(NSString*)thePath outRef:(FSRef*)outRef isFolder:(BOOL*)isFolder {
	if (thePath) {
		FSRef ref = {0};
		if (FSPathMakeRef((UInt8*)[thePath fileSystemRepresentation], &ref, (Boolean*)isFolder) == noErr) {
			if (outRef) {
				bcopy(&ref, outRef, sizeof(FSRef));
			}
			return YES;
		}
	}
	return NO;
}

// Convenience class method to get the full path from a FSRef.
+ (NSString*)pathForRef:(FSRef*)theRef {
	NSString* result = nil;
	if (theRef) {
		UInt8* buffer = malloc(4*PATH_MAX);
		if (FSRefMakePath(theRef, buffer, 4 * PATH_MAX - 1) == noErr) {
			result = [NSString stringWithUTF8String:(char*)buffer]; 
		}
		free(buffer);
	}
	return result;
}

// Convenience class method to get item flags and, optionally, extension from a FSRef.
+ (LSItemInfoFlags)itemFlagsForRef:(FSRef*)theRef andExtension:(NSString **)outExtension {
	LSItemInfoRecord info = {0};
	if (theRef) {
		LSRequestedInfo which = kLSRequestAllFlags;
		if (outExtension) {
			*outExtension = nil;
			which |= kLSRequestExtension;
		}
		if (LSCopyItemInfoForRef(theRef, which, &info)==noErr) {
			if (outExtension) {
				*outExtension = [(NSString*)info.extension autorelease];
			}
		}
	}
	return info.flags;
}

// Convenience class method to convert UTCDateTime to NSTimeInterval.
+ (NSTimeInterval)intervalFromUTCDateTime:(UTCDateTime)timeStamp {
	NSTimeInterval time = timeStamp.lowSeconds - 3061152000.0;
	time += ((UInt64)timeStamp.highSeconds)<<32;
	time += timeStamp.fraction/65536.0;
	return time;
}

// Convenience class method to convert NSTimeInterval to UTCDateTime.
+ (UTCDateTime)UTCDateTimeFromInterval:(NSTimeInterval)interval {
	UInt64 value = (interval += 3061152000.0);
	UTCDateTime result = {value>>32,value,(interval-value)*65536.0};
	return result;
}

// Default init
- (id)init {
	if ((self = [super init])) {
		followsLinks = YES;	// other instance variables stay zero
	}
	return self;
}

// This just copies the delegate pointer into the instance variable.
// Note that delegates are never retained.
- (void)setDelegate:(id)theDelegate {
	delegate = theDelegate;
}

- (id)delegate {
	return delegate;
}

// Set and get the followsLinks flag.
- (void)setFollowsLinks:(BOOL)flag {
	followsLinks = flag;
}

- (BOOL)followsLinks {
	return followsLinks;
}

// Call this from a delegate method or another thread to stop sweeping.
- (void)stop {
	stop = YES;
}

// Instance method to get the full path from a FSRef.
- (NSString*)pathForRef:(FSRef*)theRef {
	if (!theRef) {	// parameter is NULL
		if (path) {	// if we already have the path, return it
			return path;
		}
		theRef = &object;
	}
	return [FolderSweeper pathForRef:theRef];
}

// Instance method to get item flags and, optionally, extension from a FSRef.
- (LSItemInfoFlags)itemFlagsForRef:(FSRef*)theRef andExtension:(NSString **)outExtension {
	return [FolderSweeper itemFlagsForRef:theRef?:&object andExtension:outExtension];
}

// This is a private method called only from within this implementation itself - note one
//	possible naming convention for such methods. Since it doesn't appear in the .h file, it
//	must be implemented before any reference by other methods.
-(UInt8*)FS__posix {
	// We have a per-instance buffer used to hold the POSIX file path.
	if (!posix) {
		// FSRefMakePath is capable of returning paths longer than PATH_MAX, oddly enough.
		posix = malloc(4*PATH_MAX);
	}
	return posix;
}

// Convenience method for error reporting.
- (void)setError:(NSError **)error withStatus:(OSStatus)err {
	// Set it if the user wants the error, but it's still nil. This will keep the first error.
	if (error && !*error) {
		*error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
	}
}

// This method does the actual work and calls itself recursively.
- (BOOL)FS__sweepFolderRef:(FSRef*)theRef level:(NSUInteger)level gettingInfo:(FSCatalogInfoBitmap)whichInfo 
			 checkContents:(BOOL)checkContents error:(NSError **)error {
	FSIterator iterator;	// This holds the iteration position for FSGetCatalogInfoBulk().
	
	// We initialize the iterator (which should always work, but checking is always good).
	OSStatus err = FSOpenIterator(theRef, kFSIterateFlat, &iterator);
	if (err == noErr) {
		
		HFSUniStr255 name;
		FSCatalogInfo info = {0};
		ItemCount count = 0;
		
		// This loops over all contents of the folder in directory order (which for HFS+
		//	is strictly alphabetical).
		// We OR in kFSCatInfoNodeFlags since we need the kFSNodeIsDirectoryMask bit in
		// any case. We also get the file/folder's name while we're at it.
		while ((FSGetCatalogInfoBulk(iterator, 1, &count, NULL, whichInfo | kFSCatInfoNodeFlags, 
									 &info, &object, NULL, &name) == noErr) && (count > 0)) {

			// Check if we should stop.
			if (stop) {
				// We clear the flag if we're at the outermost level, so the sweeper can run again.
				if (level == 0) {
					stop = NO;
				}
				break;
			}

			// Follow aliases and symbolic links unless followsLinks is NO.
			Boolean isalias = FALSE;
			if (followsLinks) {
				// We cut off alias chains at 32 items, which seems reasonable.
				for (int i=0;i<32;i++) {
					Boolean isfolder = FALSE;
					err = FSResolveAliasFileWithMountFlags(&object,NO,&isfolder,&isalias,kResolveAliasFileNoUI);
					if (err == noErr) {
						// Break out of the loop once we hit a non-alias/link item, or a broken one.
						if (!isalias) {
							isalias = TRUE;
							break;
						}
					} else {
						// Don't report broken aliases/links.
						if ((err != fnfErr) && (err != nsvErr)) {
							[self setError:error withStatus:err];
						}
						break;
					}
				}
			}
			if (isalias) {	// alias was followed, we need to get the pointed-at item's name and info
				err = FSGetCatalogInfo(&object, whichInfo | kFSCatInfoNodeFlags, &info, &name, NULL, NULL);
				if (err != noErr) {
					[self setError:error withStatus:err];
					continue;	// but if that fails we skip processing entirely
				}
			}
			
			// We make a NSString from the unicode name. This particular call doesn't copy the
			//	characters but keeps the original HFSUniStr255 for storage. Note we also avoid
			//	generating autoreleased objects anywhere.
			NSString* nameString = [[NSString alloc] initWithCharactersNoCopy:name.unicode 
																	   length:name.length freeWhenDone:NO];
			
			// This may look weird to you, but nodeFlags is a 32-bit variable, and we're
			//	masking one bit from that, so the 32-bit result can't be truncated to a 8-bit BOOL.
			// Even if the mask were in the rightmost 8 bits (which it is, in this case), we're
			//	passing this BOOL to other methods that may depend on the value being strictly
			//	YES or NO - they really shouldn't, but it happens.
			BOOL isFolder = info.nodeFlags & kFSNodeIsDirectoryMask? YES : NO;
			
			// We create and destroy an autorelease pool around the delegate call just in case
			// that it creates temporary objects. If it doesn't, little time will be wasted.
			NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
			BOOL should = [delegate sweeper:self shouldProcessObject:&object 
									  named:nameString hasInfo:&info isFolder:isFolder];
			[pool release];
			
			if (should) {	// Further process file or folder
				
				if (isFolder) {	// Further process subfolder
					
					// We don't need the name from here on, so we release it before recursing.
					[nameString release];
					nameString = nil;	// this avoids releasing it again further ahead
					
					// We call the same method recursively on the subfolder. We don't need to
					//	to check the result here, as any error will be reported in "error".
					[self FS__sweepFolderRef:&object level:level+1 gettingInfo:whichInfo 
							   checkContents:checkContents error:error];
					
				} else if (checkContents) {	// Further process files, if the delegate method is implemented
					
					UInt8* buffer = [self FS__posix];
					// We need the full path to memory-map the file.
					err = FSRefMakePath(&object, buffer, 4 * PATH_MAX - 1);
					if (err == noErr) {
						// Convert the POSIX path to a NSString. This is also stored in case
						// the delegate will ask for it. The string will be a copy.
						path = [[NSString alloc] initWithUTF8String:(char*)buffer];
						NSData* data = [[NSData alloc] initWithContentsOfMappedFile:path];
						
						// Here too, we create and destroy an autorelease pool around the delegate call.
						pool = [[NSAutoreleasePool alloc] init];
						[delegate sweeper:self processFile:&object named:nameString hasInfo:&info contents:data];
						[pool release];
						[path release];
						path = nil;
						[data release];
					} else {
						[self setError:error withStatus:err];
					}
				}
			}
			// We release the name here; if it was a folder, nameString will already be nil, so nothing
			//	will happen.
			[nameString release];
		}
		
		// We need to close/destroy the iterator before exiting.
		FSCloseIterator(iterator);
		return YES;
	}

	// If we get here, we didn't succeed in starting the sweep.
	[self setError:error withStatus:err];
	return NO;
}

// This public method actually just does some checking before calling the previous method.
- (BOOL)sweepFolder:(NSString*)thePath gettingInfo:(FSCatalogInfoBitmap)whichInfo error:(NSError **)error {
	// If the user wants the error, we first set it to nil.
	if (error) {
		*error = nil;
	}
	OSStatus err = paramErr;	// keep this error if the delegate is not set, or doesn't
								// implement the first delegate method
	if ([delegate respondsToSelector:@selector(sweeper:shouldProcessObject:named:hasInfo:isFolder:)]) {
		FSRef parent = {0};
		BOOL isDir = FALSE;

		if ([FolderSweeper refForPath:thePath outRef:&parent isFolder:&isDir]) {
			if (isDir) {
				// Note how we check if the delegate responds the optional method.
				return [self FS__sweepFolderRef:&parent level:0 gettingInfo:whichInfo
								  checkContents:[delegate respondsToSelector:@selector(sweeper:processFile:named:hasInfo:contents:)] 
										  error:error];
			}
			err = errFSNotAFolder;	// thePath has to be a folder
		}
	}
		
	// If we get here, we had an error outright.
	[self setError:error withStatus:err];
	return NO;
}


@end
