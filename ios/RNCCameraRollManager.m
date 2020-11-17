/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "RNCCameraRollManager.h"

#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <MobileCoreServices/UTType.h>

#import <React/RCTBridge.h>
#import <React/RCTConvert.h>
#import <React/RCTImageLoaderProtocol.h>
#import <React/RCTLog.h>
#import <React/RCTUtils.h>

#import "RNCAssetsLibraryRequestHandler.h"

#import <AVFoundation/AVFoundation.h>

@implementation RCTConvert (PHAssetCollectionSubtype)

RCT_ENUM_CONVERTER(PHAssetCollectionSubtype, (@{
   @"album": @(PHAssetCollectionSubtypeAny),
   @"all": @(PHAssetCollectionSubtypeSmartAlbumUserLibrary),
   @"event": @(PHAssetCollectionSubtypeAlbumSyncedEvent),
   @"faces": @(PHAssetCollectionSubtypeAlbumSyncedFaces),
   @"library": @(PHAssetCollectionSubtypeSmartAlbumUserLibrary),
   @"photo-stream": @(PHAssetCollectionSubtypeAlbumMyPhotoStream), // incorrect, but legacy
   @"photostream": @(PHAssetCollectionSubtypeAlbumMyPhotoStream),
   @"saved-photos": @(PHAssetCollectionSubtypeAny), // incorrect, but legacy correspondence in PHAssetCollectionSubtype
   @"savedphotos": @(PHAssetCollectionSubtypeAny), // This was ALAssetsGroupSavedPhotos, seems to have no direct correspondence in PHAssetCollectionSubtype
}), PHAssetCollectionSubtypeAny, integerValue)


@end

@implementation RCTConvert (PHFetchOptions)

+ (PHFetchOptions *)PHFetchOptionsFromMediaType:(NSString *)mediaType
                                       fromTime:(NSUInteger)fromTime
                                         toTime:(NSUInteger)toTime
{
  // This is not exhaustive in terms of supported media type predicates; more can be added in the future
  NSString *const lowercase = [mediaType lowercaseString];
  NSMutableArray *format = [NSMutableArray new];
  NSMutableArray *arguments = [NSMutableArray new];
  
  if ([lowercase isEqualToString:@"photos"]) {
    [format addObject:@"mediaType = %d"];
    [arguments addObject:@(PHAssetMediaTypeImage)];
  } else if ([lowercase isEqualToString:@"videos"]) {
    [format addObject:@"mediaType = %d"];
    [arguments addObject:@(PHAssetMediaTypeVideo)];
  } else {
    if (![lowercase isEqualToString:@"all"]) {
      RCTLogError(@"Invalid filter option: '%@'. Expected one of 'photos',"
                  "'videos' or 'all'.", mediaType);
    }
  }
  
  if (fromTime > 0) {
    NSDate* fromDate = [NSDate dateWithTimeIntervalSince1970:fromTime/1000];
    [format addObject:@"creationDate > %@"];
    [arguments addObject:fromDate];
  }
  if (toTime > 0) {
    NSDate* toDate = [NSDate dateWithTimeIntervalSince1970:toTime/1000];
    [format addObject:@"creationDate < %@"];
    [arguments addObject:toDate];
  }
  
  // This case includes the "all" mediatype
  PHFetchOptions *const options = [PHFetchOptions new];
  if ([format count] > 0) {
    options.predicate = [NSPredicate predicateWithFormat:[format componentsJoinedByString:@" AND "] argumentArray:arguments];
  }
  return options;
}

@end

@implementation RNCCameraRollManager

RCT_EXPORT_MODULE(RNCCameraRoll)

@synthesize bridge = _bridge;

static NSString *const kErrorUnableToSave = @"E_UNABLE_TO_SAVE";
static NSString *const kErrorUnableToLoad = @"E_UNABLE_TO_LOAD";

static NSString *const kErrorAuthRestricted = @"E_PHOTO_LIBRARY_AUTH_RESTRICTED";
static NSString *const kErrorAuthDenied = @"E_PHOTO_LIBRARY_AUTH_DENIED";
static NSString *const kErrorUnsupportedUrl = @"E_UNSUPPORTED_URL";

static NSString *const kErrorFileDoesntExist = @"E_FILE_DOESNT_EXIST";

static NSString *const kMedia_Photos = @"photos";
static NSString *const kMedia_Videos = @"videos";
static NSString *const kJpegExt = @"jpeg";
static NSString *const kPngExt = @"png";
static NSString *const kPngMimeType = @"image/png";

static NSString *const kThumbnailFolder = @"/thumbnails/";

typedef void (^PhotosAuthorizedBlock)(void);

static void requestPhotoLibraryAccess(RCTPromiseRejectBlock reject, PhotosAuthorizedBlock authorizedBlock) {
  PHAuthorizationStatus authStatus = [PHPhotoLibrary authorizationStatus];
  if (authStatus == PHAuthorizationStatusRestricted) {
    reject(kErrorAuthRestricted, @"Access to photo library is restricted", nil);
  } else if (authStatus == PHAuthorizationStatusAuthorized) {
    authorizedBlock();
  } else if (authStatus == PHAuthorizationStatusNotDetermined) {
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
      requestPhotoLibraryAccess(reject, authorizedBlock);
    }];
  } else {
    reject(kErrorAuthDenied, @"Access to photo library was denied", nil);
  }
}

RCT_EXPORT_METHOD(checkAlbumExists:(NSString *) albumId
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
    fetchOptions.predicate = [NSPredicate predicateWithFormat:@"localIdentifier = %@", albumId ];
    PHAssetCollection * collection = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum
                                                          subtype:PHAssetCollectionSubtypeAny
                                                          options:fetchOptions].firstObject;
    if (collection) {
        resolve([NSNumber numberWithBool:YES]);
    } else {
        resolve([NSNumber numberWithBool:NO]);
    }
}

RCT_EXPORT_METHOD(saveAlbum:(NSString *) albumName
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
     __block PHObjectPlaceholder *placeholder;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
      PHAssetCollectionChangeRequest *createAlbum = [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:albumName];
      placeholder = [createAlbum placeholderForCreatedAssetCollection];
    } completionHandler:^(BOOL success, NSError *error) {
      if (success) {
        resolve(placeholder.localIdentifier);
      } else {
        reject(kErrorUnableToSave, nil, error);
      }
    }];
}
                    

RCT_EXPORT_METHOD(saveToCameraRoll:(NSURLRequest *)request
                  options:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
  // We load images and videos differently.
  // Images have many custom loaders which can load images from ALAssetsLibrary URLs, PHPhotoLibrary
  // URLs, `data:` URIs, etc. Video URLs are passed directly through for now; it may be nice to support
  // more ways of loading videos in the future.
  __block NSURL *inputURI = nil;
  __block UIImage *inputImage = nil;
  __block PHFetchResult *photosAsset;
  __block PHAssetCollection *collection;
  __block PHObjectPlaceholder *placeholder;
  __block NSInteger saveBlockCall;
  __block NSInteger albumCount;
  __block NSInteger curAlbumCount;

  void (^saveBlock)(void) = ^void() {
    // performChanges and the completionHandler are called on
    // arbitrary threads, not the main thread - this is safe
    // for now since all JS is queued and executed on a single thread.
    // We should reevaluate this if that assumption changes.
    if (++saveBlockCall == 1) {
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetChangeRequest *assetRequest ;
        PHFetchResult* fetchResult;

        if ([options[@"albumOnly"] boolValue]) {
          if (![options[@"photoPath"] isEqualToString:@""]) {
            @try {
              fetchResult = [PHAsset fetchAssetsWithLocalIdentifiers:@[options[@"photoPath"]] options:nil];
            }
            @catch ( NSException *e ) {
              RCTLogInfo( @"NSException caught" );
              RCTLogInfo( @"Name: %@", e.name);
              RCTLogInfo( @"Reason: %@", e.reason );
            }
          }
        } else {
          if ([options[@"type"] isEqualToString:@"video"]) {
            assetRequest = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:inputURI];
          } else {
            assetRequest = [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:inputURI];
          }
          placeholder = [assetRequest placeholderForCreatedAsset];
        }

        if ([options[@"album"] count]) {
          for (NSString *album in options[@"album"]) {
            if (![album isEqualToString:@""]) {
              PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
              fetchOptions.predicate = [NSPredicate predicateWithFormat:@"localIdentifier = %@", album ];
              PHAssetCollection *album_collection = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum
                                                                    subtype:PHAssetCollectionSubtypeAny
                                                                    options:fetchOptions].firstObject;

              if (album_collection) {
                photosAsset = [PHAsset fetchAssetsInAssetCollection:album_collection options:nil];
                PHAssetCollectionChangeRequest *albumChangeRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:album_collection assets:photosAsset];
                
                if ([options[@"albumOnly"] boolValue]) {
                  if (![options[@"photoPath"] isEqualToString:@""]) {
                    if([fetchResult count] > 0) {
                        [albumChangeRequest addAssets:fetchResult];
                    }
                  }
                } else {
                  [albumChangeRequest addAssets:@[placeholder]];
                }
                
              }
              
            }
          }
        }
      } completionHandler:^(BOOL success, NSError *error) {
        if (success) {
          @try {
              NSString *result;
              
              if ([options[@"albumOnly"] boolValue]) {
                  PHFetchResult* fetchRes = [PHAsset fetchAssetsWithLocalIdentifiers:@[options[@"photoPath"]] options:nil];
                  NSString * filename = @"";
                  NSTimeInterval modifiedDate;
                  NSString * uri = @"";
                  // get the filename
                  if ([fetchRes count] > 0) {
                      PHAsset * asset = [fetchRes firstObject];
                      filename = [asset valueForKey:@"filename"];
                      uri = [NSString stringWithFormat:@"ph://%@", [asset localIdentifier]];
                      modifiedDate = [[asset modificationDate] timeIntervalSince1970];
                      result = [NSString stringWithFormat:@"{\"uri\": \"%@\", \"filename\": \"%@\", \"lastModifiedDate\": %f}", uri, filename, modifiedDate];
                  } else {
                      NSError *error = [NSError errorWithDomain:@"com.kintips.authenticator" code:10000 userInfo:@{@"Error reason": [NSString stringWithFormat:@"Cannot add photo \"%@\" to album", options[@"photoPath"]]}];
                      reject(kErrorUnableToSave, nil, error);
                      return;
                  }
                  
              } else {
                  PHFetchResult* fetchRes = [PHAsset fetchAssetsWithLocalIdentifiers:@[[placeholder localIdentifier]] options:nil];
                  NSString * uri = [NSString stringWithFormat:@"ph://%@", [placeholder localIdentifier]];
                  NSString * filename = @"";
                  NSTimeInterval modifiedDate;
                  // get the filename
                  if ([fetchRes count] > 0) {
                      PHAsset * asset = [fetchRes firstObject];
                      filename = [asset valueForKey:@"filename"];
                      modifiedDate = [[asset modificationDate] timeIntervalSince1970];
                  } else {
                      NSError *error = [NSError errorWithDomain:@"com.kintips.authenticator" code:10000 userInfo:@{@"Error reason": [NSString stringWithFormat:@"Cannot add photo \"%@\" to album", options[@"photoPath"]]}];
                      reject(kErrorUnableToSave, nil, error);
                      return;
                  }
                  
                  result = [NSString stringWithFormat:@"{\"uri\": \"%@\", \"filename\": \"%@\", \"lastModifiedDate\": %f}", uri, filename, modifiedDate];
              }
              resolve(result);
          }
          @catch ( NSException *e ) {
              RCTLogInfo( @"NSException caught" );
              RCTLogInfo( @"Name: %@", e.name);
              RCTLogInfo( @"Reason: %@", e.reason );
              reject(kErrorUnableToSave, nil, error);
          }
        } else {
          reject(kErrorUnableToSave, nil, error);
        }
      }];
    }
  };
  void (^saveWithOptions)(void) = ^void() {
    saveBlockCall = 0;
    saveBlock();
    // leave the create album job to the method createAlbum
    /*
    if ([options[@"album"] count]) {
      albumCount = 0;
      curAlbumCount = 0;
      for (NSString *album in options[@"album"]) {
        if (![album isEqualToString:@""]) {
          albumCount++;
        }
      }

      for (NSString *album in options[@"album"]) {
        if (![album isEqualToString:@""]) {
          PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
          fetchOptions.predicate = [NSPredicate predicateWithFormat:@"localIdentifier = %@", album ];
          collection = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum
                                                                subtype:PHAssetCollectionSubtypeAny
                                                                options:fetchOptions].firstObject;
          // Create the album
          if (!collection) {
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
              PHAssetCollectionChangeRequest *createAlbum = [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:album];
              placeholder = [createAlbum placeholderForCreatedAssetCollection];
            } completionHandler:^(BOOL success, NSError *error) {
              if (success) {
                PHFetchResult *collectionFetchResult = [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[placeholder.localIdentifier]
                                                                                                            options:nil];
                collection = collectionFetchResult.firstObject;

                curAlbumCount++;
                if (curAlbumCount == albumCount) {
                  saveBlock();
                }
              } else {
                reject(kErrorUnableToSave, nil, error);
              }
            }];
          } else {
            curAlbumCount++;
          }
        }
      }
      if (curAlbumCount == albumCount) {
        saveBlock();
      }
    } else {
      saveBlock();
    }
    */
  };

  void (^loadBlock)(void) = ^void() {
    inputURI = request.URL;
    saveWithOptions();
  };

  requestPhotoLibraryAccess(reject, loadBlock);
}

RCT_EXPORT_METHOD(getAlbums:(NSDictionary *)params
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
  NSString *const mediaType = [params objectForKey:@"assetType"] ? [RCTConvert NSString:params[@"assetType"]] : @"All";
  PHFetchOptions* options = [[PHFetchOptions alloc] init];
  PHFetchResult<PHAssetCollection *> *const assetCollectionFetchResult = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAlbumRegular options:options];
  NSMutableArray * result = [NSMutableArray new];
  [assetCollectionFetchResult enumerateObjectsUsingBlock:^(PHAssetCollection * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
    PHFetchOptions *const assetFetchOptions = [RCTConvert PHFetchOptionsFromMediaType:mediaType fromTime:0 toTime:0];
    // Enumerate assets within the collection
    PHFetchResult<PHAsset *> *const assetsFetchResult = [PHAsset fetchAssetsInAssetCollection:obj options:assetFetchOptions];
    if (assetsFetchResult.count > 0) {
      [result addObject:@{
        @"title": [obj localizedTitle],
        @"id": [obj localIdentifier],
        @"count": @(assetsFetchResult.count)
      }];
    }
  }];
  resolve(result);
}

static void RCTResolvePromise(RCTPromiseResolveBlock resolve,
                              NSArray<NSDictionary<NSString *, id> *> *assets,
                              BOOL hasNextPage)
{
  if (!assets.count) {
    resolve(@{
      @"edges": assets,
      @"page_info": @{
        @"has_next_page": @NO,
      }
    });
    return;
  }
  resolve(@{
    @"edges": assets,
    @"page_info": @{
      @"start_cursor": assets[0][@"node"][@"image"][@"uri"],
      @"end_cursor": assets[assets.count - 1][@"node"][@"image"][@"uri"],
      @"has_next_page": @(hasNextPage),
    }
  });
}

RCT_EXPORT_METHOD(getTotalCount:(NSDictionary *)params
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
  checkPhotoLibraryConfig();

  NSString *const groupName = [RCTConvert NSString:params[@"groupName"]];
  NSString *const groupTypes = [[RCTConvert NSString:params[@"groupTypes"]] lowercaseString];
  NSString *const mediaType = [RCTConvert NSString:params[@"assetType"]];
  NSUInteger const fromTime = [RCTConvert NSInteger:params[@"fromTime"]];
  NSUInteger const toTime = [RCTConvert NSInteger:params[@"toTime"]];
  
  // If groupTypes is "all", we want to fetch the SmartAlbum "all photos". Otherwise, all
  // other groupTypes values require the "album" collection type.
  PHAssetCollectionType const collectionType = ([groupTypes isEqualToString:@"all"]
                                                ? PHAssetCollectionTypeSmartAlbum
                                                : PHAssetCollectionTypeAlbum);
  PHAssetCollectionSubtype const collectionSubtype = [RCTConvert PHAssetCollectionSubtype:groupTypes];
  
  // Predicate for fetching assets within a collection
  PHFetchOptions *const assetFetchOptions = [RCTConvert PHFetchOptionsFromMediaType:mediaType fromTime:fromTime toTime:toTime];
  
  PHFetchOptions *const collectionFetchOptions = [PHFetchOptions new];
    collectionFetchOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"endDate" ascending:NO]];
    if (groupName != nil) {
      collectionFetchOptions.predicate = [NSPredicate predicateWithFormat:[NSString stringWithFormat:@"localizedTitle == '%@'", groupName]];
    }
  
  requestPhotoLibraryAccess(reject, ^{
    
    if ([groupTypes isEqualToString:@"all"]) {
      PHFetchResult <PHAsset *> *const assetFetchResult = [PHAsset fetchAssetsWithOptions: assetFetchOptions];
        NSUInteger totalFiles = [assetFetchResult count];
        resolve([NSNumber numberWithUnsignedInteger:totalFiles]);
    } else {
      PHFetchResult<PHAssetCollection *> *const assetCollectionFetchResult = [PHAssetCollection fetchAssetCollectionsWithType:collectionType subtype:collectionSubtype options:collectionFetchOptions];
      [assetCollectionFetchResult enumerateObjectsUsingBlock:^(PHAssetCollection * _Nonnull assetCollection, NSUInteger collectionIdx, BOOL * _Nonnull stopCollections) {
        PHFetchResult<PHAsset *> *const assetsFetchResult = [PHAsset fetchAssetsInAssetCollection:assetCollection options:assetFetchOptions];
        *stopCollections = YES;
        NSUInteger totalFiles = [assetsFetchResult count];
        resolve([NSNumber numberWithUnsignedInteger:totalFiles]);
      }];
    }

  });
}

RCT_EXPORT_METHOD(getPhotos:(NSDictionary *)params
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
  checkPhotoLibraryConfig();

  NSUInteger const first = [RCTConvert NSInteger:params[@"first"]];
  NSString *const afterCursor = [RCTConvert NSString:params[@"after"]];
  NSString *const groupId = [RCTConvert NSString:params[@"groupId"]];
  NSString *const groupTypes = [[RCTConvert NSString:params[@"groupTypes"]] lowercaseString];
  NSString *const mediaType = [RCTConvert NSString:params[@"assetType"]];
  NSUInteger const fromTime = [RCTConvert NSInteger:params[@"fromTime"]];
  NSUInteger const toTime = [RCTConvert NSInteger:params[@"toTime"]];
  NSArray<NSString *> *const mimeTypes = [RCTConvert NSStringArray:params[@"mimeTypes"]];
  
  // If groupTypes is "all", we want to fetch the SmartAlbum "all photos". Otherwise, all
  // other groupTypes values require the "album" collection type.
  PHAssetCollectionType const collectionType = ([groupTypes isEqualToString:@"all"]
                                                ? PHAssetCollectionTypeSmartAlbum
                                                : PHAssetCollectionTypeAlbum);
  PHAssetCollectionSubtype const collectionSubtype = [RCTConvert PHAssetCollectionSubtype:groupTypes];
  
  // Predicate for fetching assets within a collection
  PHFetchOptions *const assetFetchOptions = [RCTConvert PHFetchOptionsFromMediaType:mediaType fromTime:fromTime toTime:toTime];
  assetFetchOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
  
  BOOL __block foundAfter = NO;
  BOOL __block hasNextPage = NO;
  BOOL __block resolvedPromise = NO;
  NSMutableArray<NSDictionary<NSString *, id> *> *assets = [NSMutableArray new];
  
  // Filter collection name ("group")
  PHFetchOptions *const collectionFetchOptions = [PHFetchOptions new];
  collectionFetchOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"endDate" ascending:NO]];
  if (groupId != nil) {
    collectionFetchOptions.predicate = [NSPredicate predicateWithFormat:[NSString stringWithFormat:@"localIdentifier == '%@'", groupId]];
  }
  
  BOOL __block stopCollections_;
  NSString __block *currentCollectionName;

  requestPhotoLibraryAccess(reject, ^{
    void (^collectAsset)(PHAsset*, NSUInteger, BOOL*) = ^(PHAsset * _Nonnull asset, NSUInteger assetIdx, BOOL * _Nonnull stopAssets) {
      NSString *const uri = [NSString stringWithFormat:@"ph://%@", [asset localIdentifier]];
      if (afterCursor && !foundAfter) {
        if ([afterCursor isEqualToString:uri]) {
          foundAfter = YES;
        }
        return; // skip until we get to the first one
      }

      // Get underlying resources of an asset - this includes files as well as details about edited PHAssets
      // NSArray<PHAssetResource *> *const assetResources = [PHAssetResource assetResourcesForAsset:asset];
      // if (![assetResources firstObject]) {
      //   return;
      // }
      // PHAssetResource *const _Nonnull resource = [assetResources firstObject];

      // if ([mimeTypes count] > 0) {
      //   CFStringRef const uti = (__bridge CFStringRef _Nonnull)(resource.uniformTypeIdentifier);
      //   NSString *const mimeType = (NSString *)CFBridgingRelease(UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType));

      //   BOOL __block mimeTypeFound = NO;
      //   [mimeTypes enumerateObjectsUsingBlock:^(NSString * _Nonnull mimeTypeFilter, NSUInteger idx, BOOL * _Nonnull stop) {
      //     if ([mimeType isEqualToString:mimeTypeFilter]) {
      //       mimeTypeFound = YES;
      //       *stop = YES;
      //     }
      //   }];

      //   if (!mimeTypeFound) {
      //     return;
      //   }
      // }

      // If we've accumulated enough results to resolve a single promise
      if (first == assets.count) {
        *stopAssets = YES;
        stopCollections_ = YES;
        hasNextPage = YES;
        RCTAssert(resolvedPromise == NO, @"Resolved the promise before we finished processing the results.");
        RCTResolvePromise(resolve, assets, hasNextPage);
        resolvedPromise = YES;
        return;
      }

      NSString *const assetMediaTypeLabel = (asset.mediaType == PHAssetMediaTypeVideo
                                            ? @"video"
                                            : (asset.mediaType == PHAssetMediaTypeImage
                                                ? @"image"
                                                : (asset.mediaType == PHAssetMediaTypeAudio
                                                  ? @"audio"
                                                  : @"unknown")));
      CLLocation *const loc = asset.location;
      // NSString * origFilenameTemp = resource.originalFilename;
      // if (assetResources.count > 1) {
      //   for (PHAssetResource * resourceTemp in assetResources)
      //   {
      //     if (resourceTemp.type != PHAssetResourceTypePhoto) {
      //       continue;
      //     }
      //     origFilenameTemp = resourceTemp.originalFilename;
      //   }
      // }
      // NSString *const origFilename = origFilenameTemp;
      NSString * origFilename = [asset valueForKey:@"filename"];

      // A note on isStored: in the previous code that used ALAssets, isStored
      // was always set to YES, probably because iCloud-synced images were never returned (?).
      // To get the "isStored" information and filename, we would need to actually request the
      // image data from the image manager. Those operations could get really expensive and
      // would definitely utilize the disk too much.
      // Thus, this field is actually not reliable.
      // Note that Android also does not return the `isStored` field at all.
      [assets addObject:@{
        @"node": @{
          @"type": assetMediaTypeLabel, // TODO: switch to mimeType?
          @"group_name": currentCollectionName,
          @"image": @{
              @"uri": uri,
              @"filename": origFilename,
              @"height": @([asset pixelHeight]),
              @"width": @([asset pixelWidth]),
              @"isStored": @YES, // this field doesn't seem to exist on android
              @"playableDuration": @([asset duration]) // fractional seconds
          },
          @"timestamp": @(asset.modificationDate.timeIntervalSince1970),
          @"location": (loc ? @{
              @"latitude": @(loc.coordinate.latitude),
              @"longitude": @(loc.coordinate.longitude),
              @"altitude": @(loc.altitude),
              @"heading": @(loc.course),
              @"speed": @(loc.speed), // speed in m/s
            } : @{})
          }
      }];
    };

    if ([groupTypes isEqualToString:@"all"]) {
      PHFetchResult <PHAsset *> *const assetFetchResult = [PHAsset fetchAssetsWithOptions: assetFetchOptions];
      currentCollectionName = @"All Photos";
      [assetFetchResult enumerateObjectsUsingBlock:collectAsset];
    } else {
      PHFetchResult<PHAssetCollection *> *const assetCollectionFetchResult = [PHAssetCollection fetchAssetCollectionsWithType:collectionType subtype:collectionSubtype options:collectionFetchOptions];
      [assetCollectionFetchResult enumerateObjectsUsingBlock:^(PHAssetCollection * _Nonnull assetCollection, NSUInteger collectionIdx, BOOL * _Nonnull stopCollections) {
        // Enumerate assets within the collection
        PHFetchResult<PHAsset *> *const assetsFetchResult = [PHAsset fetchAssetsInAssetCollection:assetCollection options:assetFetchOptions];
        currentCollectionName = [assetCollection localizedTitle];
        [assetsFetchResult enumerateObjectsUsingBlock:collectAsset];
        *stopCollections = stopCollections_;
      }];
    }

    // If we get this far and haven't resolved the promise yet, we reached the end of the list of photos
    if (!resolvedPromise) {
      hasNextPage = NO;
      RCTResolvePromise(resolve, assets, hasNextPage);
      resolvedPromise = YES;
    }
  });
}

RCT_EXPORT_METHOD(deletePhotos:(NSArray<NSString *>*)assets
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
  NSMutableArray *convertedAssets = [NSMutableArray array];
  
  for (NSString *asset in assets) {
    [convertedAssets addObject: [asset stringByReplacingOccurrencesOfString:@"ph://" withString:@""]];
  }

  [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
      PHFetchResult<PHAsset *> *fetched =
        [PHAsset fetchAssetsWithLocalIdentifiers:convertedAssets options:nil];
      [PHAssetChangeRequest deleteAssets:fetched];
    }
  completionHandler:^(BOOL success, NSError *error) {
    if (success == YES) {
      resolve(@(success));
    }
    else {
      reject(@"Couldn't delete", @"Couldn't delete assets", error);
    }
  }
  ];
}

RCT_EXPORT_METHOD(getThumbnail:(NSString *)url params:(NSDictionary *)params resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject) {
  NSUInteger const width = [params objectForKey:@"width"] ? [RCTConvert NSInteger:params[@"width"]] : 0;
  NSUInteger const height = [params objectForKey:@"height"] ? [RCTConvert NSInteger:params[@"height"]] : 0;
  NSString *const format = [params objectForKey:@"format"] ? [RCTConvert NSString:params[@"format"]] : @"jpeg";
  NSUInteger const timestamp = [params objectForKey:@"timestamp"] ? [RCTConvert NSInteger:params[@"timestamp"]] : 0;
  NSString *const assetType = [params objectForKey:@"assetType"] ? [RCTConvert NSString:params[@"assetType"]] : nil;
    
  NSLog(@"getThumbnail - params %@", params);
  NSLog(@"getThumbnail - url %@", url);
  NSLog(@"getThumbnail - req width %lu", width);
  NSLog(@"getThumbnail - req height %lu", height);
  NSLog(@"getThumbnail - format %@", format);
  NSLog(@"getThumbnail - timestamp %lu", timestamp);
  NSLog(@"getThumbnail - assetType %@", assetType);
  
  NSString* tempThumbDirectory = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
  tempThumbDirectory = [tempThumbDirectory stringByAppendingString:@"/thumbnails/"];
    
  [[NSFileManager defaultManager] createDirectoryAtPath:tempThumbDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    
  NSString *const lowercaseAssetType = [assetType lowercaseString];
  if ([lowercaseAssetType isEqualToString:kMedia_Photos]) {
    createPhotoThumbnail(url, width, height, format, tempThumbDirectory, resolve, reject);
  }
  else if ([lowercaseAssetType isEqualToString:kMedia_Videos]) {
    createVideoThumbnail(url, width, height, format, tempThumbDirectory, timestamp, resolve, reject);
  }
  else {
    resolve(nil);
  }
}

static void createPhotoThumbnail(NSString* uri, NSUInteger requestWidth, NSUInteger requestedHeight, NSString* format, NSString* thumbnailDir, RCTPromiseResolveBlock resolve, RCTPromiseRejectBlock reject) {
  PHFetchResult* fetchResult = nil;
  
  NSString* photoThumbnailDir = [thumbnailDir stringByAppendingString:[@"/" stringByAppendingString: kMedia_Photos]];
  [[NSFileManager defaultManager] createDirectoryAtPath:photoThumbnailDir withIntermediateDirectories:YES attributes:nil error:nil];
    
  NSURL* url = [NSURL URLWithString:uri];
  if ([url.scheme isEqualToString:@"ph"]) {
      fetchResult = [PHAsset fetchAssetsWithLocalIdentifiers:@[[uri substringFromIndex: 5]] options:nil];
  } else {
      fetchResult = [PHAsset fetchAssetsWithALAssetURLs:@[url] options:nil];
  }
    
  PHAsset* asset = [fetchResult firstObject];
  if (asset) {
      NSLog(@"[createPhotoThumbnail] photo thumbnail asset url %@", url);
      NSLog(@"[createPhotoThumbnail] photo thumbnail asset %@", asset);
      NSLog(@"[createPhotoThumbnail] photo thumbnail %lu %lu", asset.pixelWidth, asset.pixelHeight);
      NSLog(@"[createPhotoThumbnail] photo thumbnail - fetch result count %lu", fetchResult.count);
      showSquareImageForAsset(asset, format, requestWidth, requestedHeight, photoThumbnailDir, resolve, reject);
  }
  else {
      reject(kErrorFileDoesntExist, @"Unable to find file.", nil);
  }
}

static void showSquareImageForAsset(PHAsset* asset, NSString* format, NSUInteger requestedWidth, NSUInteger requestedHeight, NSString* thumbnailDir, RCTPromiseResolveBlock resolve, RCTPromiseRejectBlock reject) {
    //Compute the size based on width and height comparisons.
    //New target size should be based on the smaller dimension.
    
    NSUInteger assetWidth = asset.pixelWidth;
    NSUInteger assetHeight = asset.pixelHeight;
    CGSize targetSize = CGSizeMake(requestedWidth, requestedHeight);
    
    if (assetWidth < assetHeight) {
        // If width is smaller than height, width is equal to the requestedWidth and height is
        // adjusted accordingly
        targetSize = CGSizeMake(requestedWidth, (assetHeight * requestedWidth) / assetWidth);
    }
    else if (assetHeight < assetWidth) {
        // If height is smaller than height, height is equal to the requestedHeight and width is
        // adjusted accordingly
        targetSize = CGSizeMake( (assetWidth * requestedHeight) / assetHeight, requestedHeight);
    }
    else {
        targetSize = CGSizeMake( (assetWidth * requestedHeight) / assetHeight, (assetHeight * requestedWidth) / assetWidth);
    }
    
    PHImageRequestOptions *cropOptions = [[PHImageRequestOptions alloc] init];
    cropOptions.resizeMode = PHImageRequestOptionsResizeModeExact;
    cropOptions.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    
    NSLog(@"[createPhotoThumbnail] targetSize: %f %f", targetSize.width, targetSize.height);
    NSLog(@"[createPhotoThumbnail] requested dimensions: %lu %lu", requestedWidth, requestedHeight);
    
    [[PHImageManager defaultManager]
     requestImageForAsset:asset
     targetSize:targetSize
     contentMode:PHImageContentModeAspectFit
     options:cropOptions
     resultHandler:^(UIImage *result, NSDictionary *info) {
        NSNumber *degradedKey = [info objectForKey:@"PHImageResultIsDegradedKey"];
        if ([degradedKey intValue] == 0) {
            NSLog(@"[createPhotoThumbnail] asset size info: %lu %lu", assetWidth, assetHeight);
            NSLog(@"[createPhotoThumbnail] image from asset size info: %@", info);
            NSLog(@"[createPhotoThumbnail] image from asset size width: %f", result.size.width);
            NSLog(@"[createPhotoThumbnail] image from asset size height  %f", result.size.height);
            generateThumbnail(result, format, thumbnailDir, resolve, reject);
        }
    }];
}

static void createVideoThumbnail(NSString* uri, NSUInteger width, NSUInteger height, NSString* format, NSString* thumbnailDir, NSUInteger timestamp, RCTPromiseResolveBlock resolve, RCTPromiseRejectBlock reject) {
  NSString* videoThumbnailDir = [thumbnailDir stringByAppendingString:[@"/" stringByAppendingString: kMedia_Videos]];
  [[NSFileManager defaultManager] createDirectoryAtPath:videoThumbnailDir withIntermediateDirectories:YES attributes:nil error:nil];
    
  NSURL* url = [NSURL URLWithString:uri];
  PHFetchResult* fetchResult = nil;
  if ([url.scheme isEqualToString:@"ph"]) {
      fetchResult = [PHAsset fetchAssetsWithLocalIdentifiers:@[[uri substringFromIndex: 5]] options:nil];
  } else {
      fetchResult = [PHAsset fetchAssetsWithALAssetURLs:@[url] options:nil];
  }
    
  PHAsset* asset = [fetchResult firstObject];
  if (asset) {
    PHVideoRequestOptions *videoOptions = [PHVideoRequestOptions new];
    videoOptions.networkAccessAllowed = YES;
    videoOptions.deliveryMode = PHVideoRequestOptionsDeliveryModeHighQualityFormat;
      
    [[PHImageManager defaultManager]
     requestAVAssetForVideo:asset options:videoOptions resultHandler:^(AVAsset* asset,
                                                                       AVAudioMix * audioMix, NSDictionary* info) {
        AVURLAsset* videoAsset = (AVURLAsset*)asset;
        @try {
          generateVideoThumbImage(videoAsset, timestamp, width, height, videoThumbnailDir, format, resolve, reject);
        } @catch (NSException *exception) {
            reject(exception.name, exception.reason, nil);
        }
    }];
  }
  else {
      resolve(nil);
  }
}

static void generateVideoThumbImage(AVURLAsset* asset, NSUInteger timeStamp, NSUInteger requestedWidth, NSUInteger requestedHeight, NSString* thumbnailDir, NSString* format, RCTPromiseResolveBlock resolve, RCTPromiseRejectBlock reject) {
    AVAssetImageGenerator *generator = [ [AVAssetImageGenerator alloc] initWithAsset:asset ];
    generator.appliesPreferredTrackTransform = YES;
    CMTime time = [asset duration];
    time.value = time.timescale * timeStamp / 1000;
    CMTime actTime = CMTimeMake(0, 0);
    NSError *err = NULL;
    CGImageRef imageRef = [generator copyCGImageAtTime:time actualTime:&actTime error:&err];
    if (err) {
        NSLog(@"[createVideoThumbnail] GENERATE THUMBNAIL ERROR %@", err);
        NSException *e = [NSException
            exceptionWithName:kErrorUnsupportedUrl
            reason:@"File doesn't exist or not supported"
            userInfo:nil];
        @throw e;
    }
    
    CGFloat scaleFloat = 1.0;
    NSUInteger imageWidth = CGImageGetWidth(imageRef);
    NSUInteger imageHeight = CGImageGetHeight(imageRef);
    
    if (imageWidth < imageHeight) {
        scaleFloat = ((float) imageWidth) / requestedWidth;
    }
    else if (imageHeight < imageWidth) {
        scaleFloat = ((float) imageHeight) / requestedHeight;
    }
    else {
        scaleFloat = ((float) imageWidth) / requestedWidth;
    }
    NSLog(@"[createVideoThumbnail] scaleFloat %f", scaleFloat);

    UIImage *thumbnail = [UIImage imageWithCGImage:imageRef scale:scaleFloat orientation:UIImageOrientationUp];
    NSLog(@"[createVideoThumbnail] generateVideoThumbImage width %f height %f", thumbnail.size.width, thumbnail.size.height);
    CGImageRelease(imageRef);
    
    generateThumbnail(thumbnail, format, thumbnailDir, resolve, reject);
}

static void generateThumbnail(UIImage *thumbnail, NSString* format, NSString* thumbnailDir, RCTPromiseResolveBlock resolve, RCTPromiseRejectBlock reject) {
    NSLog(@"[createPhotoThumbnail] generating thumbnail file %@", thumbnail);
    NSLog(@"[createPhotoThumbnail] generating thumbnail file with size %f %f", thumbnail.size.width, thumbnail.size.height);
    NSData *data = nil;
    NSString *fullPath = nil;
    
    NSLog(@"[createPhotoThumbnail] generating thumbnail file %@", thumbnail);
  
    if ([format isEqual: @"png"]) {
        data = UIImagePNGRepresentation(thumbnail);
        fullPath = [thumbnailDir stringByAppendingPathComponent: [NSString stringWithFormat:@"thumb-%@.png",[[NSProcessInfo processInfo] globallyUniqueString]]];
    } else {
        data = UIImageJPEGRepresentation(thumbnail, 1.0);
        NSLog(@"data %@", data);
        fullPath = [thumbnailDir stringByAppendingPathComponent: [NSString stringWithFormat:@"thumb-%@.jpeg",[[NSProcessInfo processInfo] globallyUniqueString]]];
    }
  
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createFileAtPath:fullPath contents:data attributes:nil];
    resolve(@{
        @"path"     : fullPath,
        @"width"    : [NSNumber numberWithFloat: thumbnail.size.width],
        @"height"   : [NSNumber numberWithFloat: thumbnail.size.height]
    });
}

static void checkPhotoLibraryConfig()
{
#if RCT_DEV
  if (![[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSPhotoLibraryUsageDescription"]) {
    RCTLogError(@"NSPhotoLibraryUsageDescription key must be present in Info.plist to use camera roll.");
  }
#endif
}

@end
