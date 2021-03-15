/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 * @flow
 * @format
 */
'use strict';
import {Platform} from 'react-native';
import RNCCameraRoll from './nativeInterface';

const invariant = require('fbjs/lib/invariant');

const GROUP_TYPES_OPTIONS = {
  Album: 'Album',
  All: 'All', // default
  Event: 'Event',
  Faces: 'Faces',
  Library: 'Library',
  PhotoStream: 'PhotoStream',
  SavedPhotos: 'SavedPhotos',
};

const ASSET_TYPE_OPTIONS = {
  All: 'All',
  Videos: 'Videos',
  Photos: 'Photos',
};

export type GroupTypes = $Keys<typeof GROUP_TYPES_OPTIONS>;

/**
 * Shape of the param arg for the `getPhotos` function.
 */
export type GetPhotosParams = {
  /**
   * The number of photos wanted in reverse order of the photo application
   * (i.e. most recent first).
   */
  first: number,

  /**
   * A cursor that matches `page_info { end_cursor }` returned from a previous
   * call to `getPhotos`
   */
  after?: string,

  /**
   * Specifies which group types to filter the results to.
   */
  groupTypes?: GroupTypes,

  /**
   * Specifies filter on group names, like 'Recent Photos' or custom album
   * titles.
   */
  groupId?: string,

  /**
   * Specifies filter on asset type
   */
  assetType?: $Keys<typeof ASSET_TYPE_OPTIONS>,

  /**
   * Filter by mimetype (e.g. image/jpeg).
   */
  mimeTypes?: Array<string>,
};

export type PhotoIdentifier = {
  node: {
    type: string,
    group_name: string,
    image: {
      filename: string,
      file_size: number,
      uri: string,
      height: number,
      width: number,
      isStored?: boolean,
      isFavorite?: boolean,
      playableDuration: number,
    },
    timestamp: number,
    creation_date: number,
    location?: {
      latitude?: number,
      longitude?: number,
      altitude?: number,
      heading?: number,
      speed?: number,
    },
  },
};

export type PhotoIdentifiersPage = {
  edges: Array<PhotoIdentifier>,
  page_info: {
    has_next_page: boolean,
    start_cursor?: string,
    end_cursor?: string,
  },
};
export type SaveToCameraRollOptions = {
  type?: 'photo' | 'video' | 'auto',
  album?: Array<string>,
  albumOnly?: boolean,
  photoPath: string,
  creationTime: number
};

export type GetAlbumsParams = {
  assetType?: $Keys<typeof ASSET_TYPE_OPTIONS>,
}

export type Album = {
  title: string,
  id: String,
  count: number,
}

export type ThumbnailOutputType = "base64" | "filepath";

export type GetThumbnailParams = {
  format?: "jpeg" | "png",
  timestamp?: number, /** for video only */
  width: number,
  height: number,
  assetType: "Photos" | "Videos",
  outputType: ThumbnailOutputType
}

export type Thumbnail = {
  data : string,
  width: number,
  height: number
}
/**
 * `CameraRoll` provides access to the local camera roll or photo library.
 *
 * See https://facebook.github.io/react-native/docs/cameraroll.html
 */
class CameraRoll {
  static GroupTypesOptions = GROUP_TYPES_OPTIONS;
  static AssetTypeOptions = ASSET_TYPE_OPTIONS;

  /**
   * `CameraRoll.saveImageWithTag()` is deprecated. Use `CameraRoll.saveToCameraRoll()` instead.
   */
  static saveImageWithTag(tag: string): Promise<string> {
    console.warn(
      '`CameraRoll.saveImageWithTag()` is deprecated. Use `CameraRoll.saveToCameraRoll()` instead.',
    );
    return this.saveToCameraRoll(tag, 'photo');
  }

  /**
   * On iOS: requests deletion of a set of photos from the camera roll.
   * On Android: Deletes a set of photos from the camera roll.
   *
   */
  static deletePhotos(photoUris: Array<string>) {
    return RNCCameraRoll.deletePhotos(photoUris);
  }

  static checkAlbumExists(albumId: string) {
    return RNCCameraRoll.checkAlbumExists(albumId);
  }

  static saveAlbum(albumName: string) {
    return RNCCameraRoll.saveAlbum(albumName);
  }
  /**
   * Saves the photo or video to the camera roll or photo library.
   *
   */
  static save(
    tag: string,
    options: SaveToCameraRollOptions = {},
  ): Promise<string> {
    let {type = 'auto', album = [], albumOnly = false, photoPath='', creationTime = -1} = options;
    invariant(
      typeof tag === 'string',
      'CameraRoll.saveToCameraRoll must be a valid string.',
    );
    invariant(
      options.type === 'photo' ||
        options.type === 'video' ||
        options.type === 'auto' ||
        options.type === undefined,
      `The second argument to saveToCameraRoll must be 'photo' or 'video' or 'auto'. You passed ${type ||
        'unknown'}`,
    );
    invariant(
      typeof albumOnly === 'boolean',
      'The third argument to saveToCameraRoll must be boolean.',
    );
    invariant(
      typeof photoPath === 'string',
      'The forth argument to saveToCameraRoll must be string.',
    );
    invariant(
      typeof creationTime === 'number',
      'The fifth argument to saveToCameraRoll must be number.',
    );
    if (type === 'auto') {
      if (['mov', 'mp4'].indexOf(tag.split('.').slice(-1)[0]) >= 0) {
        type = 'video';
      } else {
        type = 'photo';
      }
    }
    if (albumOnly && photoPath.length > 1) {
      photoPath = photoPath.substring(1);
    }
    return RNCCameraRoll.saveToCameraRoll(tag, {type, album, albumOnly, photoPath, creationTime});
  }
  static saveToCameraRoll(
    tag: string,
    type?: 'photo' | 'video' | 'auto',
  ): Promise<string> {
    return CameraRoll.save(tag, {type});
  }
  static getAlbums(params?: GetAlbumsParams = { assetType: ASSET_TYPE_OPTIONS.All }): Promise<Album[]> {
    return RNCCameraRoll.getAlbums(params);
  }
  /**
   * Returns a Promise with photo identifier objects from the local camera
   * roll of the device matching shape defined by `getPhotosReturnChecker`.
   *
   * See https://facebook.github.io/react-native/docs/cameraroll.html#getphotos
   */
  static getPhotos(params: GetPhotosParams): Promise<PhotoIdentifiersPage> {
    if (!params.assetType) {
      params.assetType = ASSET_TYPE_OPTIONS.All;
    }
    if (!params.groupTypes && Platform.OS !== 'android') {
      params.groupTypes = GROUP_TYPES_OPTIONS.All;
    }
    if (arguments.length > 1) {
      console.warn(
        'CameraRoll.getPhotos(tag, success, error) is deprecated.  Use the returned Promise instead',
      );
      let successCallback = arguments[1];
      const errorCallback = arguments[2] || (() => {});
      RNCCameraRoll.getPhotos(params).then(successCallback, errorCallback);
    }
    return RNCCameraRoll.getPhotos(params);
  }

  /**
   * Returns a Promise with total no.of photos
   *
   * See https://facebook.github.io/react-native/docs/cameraroll.html#getphotos
   */
  static getTotalCount(params: GetPhotosParams): Promise<PhotoIdentifiersPage> {
    if (Platform.OS == "android") {
      if (params.assetType == ASSET_TYPE_OPTIONS.All) {
        return RNCCameraRoll.getMediaCount("PHOTO") + RNCCameraRoll.getMediaCount("VIDEO")
      }
      else if (params.assetType == ASSET_TYPE_OPTIONS.Photos) {
        return RNCCameraRoll.getMediaCount("PHOTO") 
      }
      else if (params.assetType == ASSET_TYPE_OPTIONS.Videos) {
        return RNCCameraRoll.getMediaCount("VIDEO") 
      }
      return 0;
    }
    if (!params.assetType) {
      params.assetType = ASSET_TYPE_OPTIONS.All;
    }
    if (!params.groupTypes && Platform.OS !== 'android') {
      params.groupTypes = GROUP_TYPES_OPTIONS.All;
    }
    if (arguments.length > 1) {
      console.warn(
        'CameraRoll.getTotalCount(tag, success, error) is deprecated.  Use the returned Promise instead',
      );
      let successCallback = arguments[1];
      const errorCallback = arguments[2] || (() => {});
      RNCCameraRoll.getTotalCount(params).then(successCallback, errorCallback);
    }
    return RNCCameraRoll.getTotalCount(params);
  }

  static getThumbnail(uri : string, params: GetThumbnailParams): Promise<Thumbnail> {
    return RNCCameraRoll.getThumbnail(uri, params);
  }
}

module.exports = CameraRoll;
