/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 * @format
 */

declare namespace CameraRoll {
  type GroupType =
    | 'Album'
    | 'All'
    | 'Event'
    | 'Faces'
    | 'Library'
    | 'PhotoStream'
    | 'SavedPhotos';

  type AssetType = 'All' | 'Videos' | 'Photos';

  interface GetPhotosParams {
    first?: number;
    after?: string; 
    groupTypes?: GroupType;
    groupId?: string;
    assetType?: AssetType;
    mimeTypes?: Array<string>;
    fromTime?: number;
    toTime?: number;
  }

  interface PhotoIdentifier {
    node: {
      type: string,
      group_name: string,
      image: {
        filename: string,
        uri: string,
        height: number,
        width: number,
        isStored?: boolean,
        isFavorite?: boolean,
        playableDuration: number,
      },
      timestamp: number,
      creation_date: number,
      file_size: number,
      location?: {
        latitude?: number,
        longitude?: number,
        altitude?: number,
        heading?: number,
        speed?: number,
      },
    };
  }

  interface PhotoIdentifiersPage {
    edges: Array<PhotoIdentifier>;
    page_info: {
      has_next_page: boolean,
      start_cursor?: string,
      end_cursor?: string,
    };
  }

  interface GetAlbumsParams {
    assetType?: AssetType;
  }

  interface Album {
    title: string;
    id: string;
    count: number;
  }

  type SaveToCameraRollOptions = {
    type?: 'photo' | 'video' | 'auto',
    album?: Array<string>,
    albumOnly?: boolean,
    photoPath: string,
    creationTime: double
  };

  type ThumbnailOutputType = "base64" | "filepath";

  type GetThumbnailParams = {
    format?: "jpeg" | "png", /** default is jpeg */
    timestamp?: number, /** for video only */
    width: number,
    height: number,
    assetType: "Photos" | "Videos",
    outputType?: ThumbnailOutputType /** default is filepath */
  }
  
  type Thumbnail = {
    data : string,
    width: number,
    height: number
  }

    /**
     * `CameraRoll.saveImageWithTag()` is deprecated. Use `CameraRoll.saveToCameraRoll()` instead.
     */
    function saveImageWithTag(tag: string): Promise<string>;

    /**
     * Delete a photo from the camera roll or media library. photoUris is an array of photo uri's.
     */
    function deletePhotos(photoUris: Array<string>): Promise<boolean>;
    
    /**
     * Saves the photo or video to the camera roll or photo library.
     */
    function saveToCameraRoll(tag: string, type?: 'photo' | 'video'): Promise<string>;

    /**
     * Saves the photo or video to the camera roll or photo library.
     */
    function save(tag: string, options?: SaveToCameraRollOptions): Promise<string> 

    /**
     * Returns a Promise with photo identifier objects from the local camera
     * roll of the device matching shape defined by `getPhotosReturnChecker`.
     */
    function getPhotos(params: GetPhotosParams): Promise<PhotoIdentifiersPage>;

    function getAlbums(params: GetAlbumsParams): Promise<Album[]>;

    function getTotalCount(params: GetPhotosParams): Promise<number>;

    function checkAlbumExists(albumId: string): Promise<boolean>;
    
    function saveAlbum(albumName: string): Promise<string>;

    function getThumbnail(uri : string, params: GetThumbnailParams): Promise<Thumbnail>;
}

export = CameraRoll;
