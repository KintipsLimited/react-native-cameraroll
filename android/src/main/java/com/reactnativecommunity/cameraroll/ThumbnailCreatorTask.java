package com.reactnativecommunity.cameraroll;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import android.util.Log;
import android.webkit.URLUtil;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.GuardedAsyncTask;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContext;
import com.facebook.react.bridge.WritableMap;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.util.UUID;

public class ThumbnailCreatorTask extends GuardedAsyncTask<Void, Void> {
    private final ReactApplicationContext reactContext;

    private static final String MEDIA_PHOTO = "PHOTO";
    private static final String MEDIA_VIDEO = "VIDEO";

    private static final String JPEG_EXT = "jpeg";
    private static final String PNG_EXT = "png";
    private static final String PNG_MIME_TYPE = "image/png";
    private static final String THUMBNAILS_FOLDER = "/thumbnails";

    private static final String ERROR_UNABLE_TO_GENERATE_THUMBNAIL = "E_UNABLE_TO_GENERATE_THUMBNAIL";
    private static final String ERROR_UNABLE_TO_DECODE_FILE = "E_UNABLE_TO_DECODE_FILE";

    private final String uri;
    private final int width;
    private final int height;
    private final String format;
    private final int timestamp;
    private final String assetType;
    private final Promise promise;

    public ThumbnailCreatorTask(ReactApplicationContext reactContext, String uri, int width, int height, String format, int timestamp, String assetType, Promise promise) {
        super(reactContext);
        this.reactContext = reactContext;
        this.uri = uri;
        this.width = width;
        this.height = height;
        this.format = format;
        this.timestamp = timestamp;
        this.assetType = assetType;
        this.promise = promise;
    }

    @Override
    protected void doInBackgroundGuarded(Void... voids) {
        this.createThumbnail();
    }

    private void createThumbnail() {
        String thumbnailFolder = reactContext.getApplicationContext().getCacheDir().getAbsolutePath() + THUMBNAILS_FOLDER;
        Log.d("RNCameraRoll", "Thumbnail folder: " + thumbnailFolder);
        try {
            File thumbnailDir = createDirIfNotExists(thumbnailFolder);
            if (assetType.equals(MEDIA_PHOTO)) {
                createPhotoThumbnail(thumbnailDir, thumbnailFolder);
            } else if (assetType.equals(MEDIA_VIDEO)) {
                createVideoThumbnail(thumbnailDir, thumbnailFolder);
            }
            promise.resolve(null);
        }
        catch (Exception e) {

        }
    }

    private void createVideoThumbnail(File thumbnailDir, String thumbnailFolder) {
        OutputStream fOut = null;

        try {
            Bitmap image = getBitmapAtTime(uri, timestamp);
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inSampleSize = calculateInSampleSize(options.outWidth, options.outHeight, width, height);
            options.inJustDecodeBounds = false;
            Bitmap sampledImage = scaleAndCropBitmap(image, width, height);
            String forVideoFormat = format != null ? format : "jpeg";
            String filename = generateThumbnailFilename(forVideoFormat, options);

            File imageFile = new File(thumbnailDir, filename);
            imageFile.createNewFile();
            fOut = new FileOutputStream(imageFile);

            if (PNG_EXT.equals(format)) {
                sampledImage.compress(Bitmap.CompressFormat.PNG, 100, fOut);
            } else {
                sampledImage.compress(Bitmap.CompressFormat.JPEG, 100, fOut);
            }

            fOut.flush();
            fOut.close();

            WritableMap map = Arguments.createMap();
            map.putString("url", "file://" + thumbnailFolder + "/" + filename);
            map.putDouble("width", sampledImage.getWidth());
            map.putDouble("height", sampledImage.getHeight());

            promise.resolve(map);
        } catch (Exception e) {
            promise.reject(ERROR_UNABLE_TO_GENERATE_THUMBNAIL, e);
        }
    }

    private Bitmap getBitmapAtTime(String uri, int timestamp) {
        MediaMetadataRetriever retriever = new MediaMetadataRetriever();
        if (URLUtil.isFileUrl(uri)) {
            retriever.setDataSource(Uri.decode(uri).replace("file://", ""));
        } else {
            throw new IllegalStateException("Remote videos are not supported for thumbnail creation.");
        }

        Bitmap image = retriever.getFrameAtTime(timestamp * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC);
        retriever.release();
        if (image == null) {
            throw new IllegalStateException("File doesn't exist or not supported");
        }
        return image;
    }

    private void createPhotoThumbnail(File thumbnailDir, String thumbnailFolder) {
        OutputStream fOut = null;

        try {
            SampledBitmap decodedSample = decodeSampledBitmapFromFile(uri, width, height);
            Log.d("RNCameraRoll", "Bitmap created with width: " + decodedSample.bitmap.getWidth() + " height: " + decodedSample.bitmap.getHeight());
            Bitmap bitmap = scaleAndCropBitmap(decodedSample.bitmap, width, height);
            BitmapFactory.Options options = decodedSample.options;
            String filename = generateThumbnailFilename(format, options);
            File imageFile = new File(thumbnailDir, filename);
            imageFile.createNewFile();
            fOut = new FileOutputStream(imageFile);

            // 100 means no compression, the lower you go the stronger the compression
            Log.d("RNCameraRoll", "Compressing image");
            compressImage(bitmap, options, fOut, format);
            Log.d("RNCameraRoll", "Image compressed");

            fOut.flush();
            fOut.close();

            WritableMap map = Arguments.createMap();
            map.putString("url", "file://" + thumbnailFolder + "/" + filename);
            map.putDouble("width", bitmap.getWidth());
            map.putDouble("height", bitmap.getHeight());
            Log.d("RNCameraRoll", "Thumbnail creation finished on " + map.getString("url"));

            promise.resolve(map);

        }
        catch (Exception e) {
            Log.d("RNCameraRoll", e.toString());
            promise.reject(ERROR_UNABLE_TO_GENERATE_THUMBNAIL, e);
        }
    }

    private SampledBitmap decodeSampledBitmapFromFile(String uri, int width, int height) {
        String fileUri = uri;
        if (URLUtil.isFileUrl(uri)) {
            fileUri = Uri.decode(uri).replace("file://", "");
        }

        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inJustDecodeBounds = true;
        BitmapFactory.decodeFile(fileUri, options);

        options.inSampleSize = calculateInSampleSize(options.outWidth, options.outHeight, width, height);
        //Log.d("RNCameraRoll", " image: " + photoForThumbnail.toString());
        options.inJustDecodeBounds = false;
//        return new SampledBitmap(scaleAndCropBitmap(photoForThumbnail, width, height), options);
        return new SampledBitmap(BitmapFactory.decodeFile(fileUri, options), options);
    }

    private int calculateInSampleSize(final int bitmapWidth, final int bitmapHeight, int requestedWidth, int requestedHeight) {
        int inSampleSize = 1;

        if (bitmapHeight > requestedHeight || bitmapWidth > requestedWidth) {
            final int halfHeight = bitmapHeight / 2;
            final int halfWidth = bitmapWidth / 2;

            while ((halfHeight / inSampleSize) >= requestedHeight && (halfWidth / inSampleSize) >= requestedWidth) {
                inSampleSize *= 2;
            }
        }
        return inSampleSize;
    }

    private String generateThumbnailFilename(String format, BitmapFactory.Options options) {
        String fileName = "thumb-" + UUID.randomUUID().toString() + ".";

        if (format != null) {
            fileName += PNG_EXT.equals(format) ? PNG_EXT : JPEG_EXT;
        }
        // This will use the mime type of the file if there is no format specified.
        else {
            fileName += PNG_MIME_TYPE.equals(options.outMimeType) ? PNG_EXT : JPEG_EXT;
        }
        return fileName;
    }

    private void compressImage(Bitmap image, BitmapFactory.Options options, OutputStream out, String format) {
        if (format != null && PNG_EXT.equals(format)) {
            image.compress(Bitmap.CompressFormat.PNG, 100, out);
        }
        else if (format != null) {
            image.compress(Bitmap.CompressFormat.JPEG, 90, out);
        }
        else {
            if (PNG_MIME_TYPE.equals(options.outMimeType)) {
                image.compress(Bitmap.CompressFormat.PNG, 100, out);
            }
            else {
                image.compress(Bitmap.CompressFormat.JPEG, 90, out);
            }
        }
    }

    private Bitmap scaleAndCropBitmap(Bitmap image, int requestedWidth, int requestedHeight) {
        int bitmapWidth = image.getWidth();
        int bitmapHeight = image.getHeight();
        // if width < height, use requestedWidth as reference for scale
        Log.d("RNCameraRoll", "scaleAndCropBitmap new sampled width: " + bitmapWidth + " height: " + bitmapHeight);
        Log.d("RNCameraRoll", "scaleAndCropBitmap createScaledBitmap passed parameters - width: " + requestedWidth + " height: " + requestedHeight);
        int resultWidth = requestedWidth;
        int resultHeight = requestedHeight;
        float scaleRatio = 1;
        if (bitmapWidth < bitmapHeight) {
            scaleRatio = ((float) requestedWidth) / bitmapWidth;
            Log.d("RNCameraRoll", "createScaledBitmap scaleRatio: " + requestedWidth + "/" + bitmapWidth + "=" + scaleRatio);
            resultHeight = (int) (bitmapHeight * scaleRatio);
            Log.d("RNCameraRoll", "scaleAndCropBitmap createScaledBitmap passed parameters - new height: " + (bitmapHeight * scaleRatio));
        }
        // if height < width, use requestedHeight as reference for scale
        else if (bitmapHeight < bitmapWidth) {
            scaleRatio = ((float) requestedHeight) / bitmapHeight;
            Log.d("RNCameraRoll", "createScaledBitmap scaleRatio: " + requestedHeight + "/" + bitmapHeight + "=" + scaleRatio);
            Log.d("RNCameraRoll", "createScaledBitmap scaleRatio: " + scaleRatio);
            resultWidth = (int) (bitmapWidth * scaleRatio);
            Log.d("RNCameraRoll", "scaleAndCropBitmap createScaledBitmap passed parameters - new width: " + (bitmapWidth * scaleRatio));
        }
        // // if height and width are equal, simply scale to requestedWidth
        // else {
        //     scaleRatio = requestedWidth / bitmapWidth;
        // }
        Log.d("RNCameraRoll", "scaleAndCropBitmap createScaledBitmap - result width: " + resultWidth + " result height: " + resultHeight);
        Bitmap scaledDown = Bitmap.createScaledBitmap(image, resultWidth, resultHeight, false);

        //perform cropping to "center" of the image
        return cropBitmap(scaledDown, requestedWidth, requestedHeight);
    }

    private Bitmap cropBitmap(Bitmap image, int requestedWidth, int requestedHeight) {
        int bitmapWidth = image.getWidth();
        int bitmapHeight = image.getHeight();
        Log.d("RNCameraRoll", "cropBitmap to be cropped - width: " + bitmapWidth + " height: " + bitmapHeight);
        Log.d("RNCameraRoll", "cropBitmap requested dims - width: " + requestedWidth + " height: " + requestedHeight);
        if (bitmapWidth == requestedWidth && bitmapHeight == requestedHeight) {
            return image;
        }

        int offsetX = 0;
        int offsetY = 0;

        if (bitmapWidth < bitmapHeight) {
            offsetY = (int) ((bitmapHeight - bitmapWidth) / 2);
        }
        else if (bitmapHeight < bitmapWidth) {
            offsetX = (int) ((bitmapWidth - bitmapHeight) / 2);
        }

        Bitmap cropped = Bitmap.createBitmap(image, offsetX, offsetY, requestedWidth, requestedHeight);
        Log.d("RNCameraRoll", "cropBitmap created - width: " + cropped.getWidth() + " height: " + cropped.getHeight());
        return cropped;
    }

    private File createDirIfNotExists(String path) {
        File dir = new File(path);
        if (dir.exists()) {
            return dir;
        }

        try {
            dir.mkdirs();
            // Add .nomedia to hide the thumbnail directory from gallery
            File noMedia = new File(path, ".nomedia");
            noMedia.createNewFile();
        } catch (IOException e) {
            e.printStackTrace();
        }
        return dir;
    }

    private class SampledBitmap {
        Bitmap bitmap;
        BitmapFactory.Options options;

        SampledBitmap(Bitmap bitmap, BitmapFactory.Options options) {
            this.bitmap = bitmap;
            this.options = options;
            Log.d("RNCameraRoll", "Bitmap created with the following: " + bitmap.toString() + " options: " + options.toString());
        }
    }
}
