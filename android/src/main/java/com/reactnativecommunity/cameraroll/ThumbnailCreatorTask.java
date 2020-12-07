package com.reactnativecommunity.cameraroll;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import android.util.Base64;
import android.util.Log;
import android.webkit.URLUtil;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.GuardedAsyncTask;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContext;
import com.facebook.react.bridge.WritableMap;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.util.UUID;

public class ThumbnailCreatorTask extends GuardedAsyncTask<Void, Void> {
    private final ReactApplicationContext reactContext;

    private static final String MEDIA_PHOTO = "photos";
    private static final String MEDIA_VIDEO = "videos";

    public static final String JPEG_EXT = "jpeg";
    public static final String PNG_EXT = "png";
    private static final String PNG_MIME_TYPE = "image/png";
    private static final String THUMBNAILS_FOLDER = "/thumbnails";

    private static final String FILEPATH_OUTPUT_TYPE = "filepath";
    private static final String BASE64_OUTPUT_TYPE = "base64";

    private static final String ERROR_UNABLE_TO_GENERATE_THUMBNAIL = "E_UNABLE_TO_GENERATE_THUMBNAIL";
    private static final String ERROR_FILE_DOES_NOT_EXIST = "E_FILE_DOES_NOT_EXIST";
    private static final String ERROR_UNSUPPORTED_URL = "E_UNSUPPORTED_URL";
    private static final String PNG_BASE64_PREFIX = "data:image/png;base64,";
    private static final String JPEG_BASE64_PREFIX = "data:image/jpeg;base64,";

    private final String uri;
    private final int width;
    private final int height;
    private final String format;
    private final int timestamp;
    private final String assetType;
    private final String outputType;
    private final Promise promise;

    public ThumbnailCreatorTask(ReactApplicationContext reactContext, String uri, int width, int height, String format, int timestamp, String assetType, String outputType, Promise promise) {
        super(reactContext);
        this.reactContext = reactContext;
        this.uri = uri;
        this.width = width;
        this.height = height;
        this.format = format;
        this.timestamp = timestamp;
        this.assetType = assetType;
        this.outputType = outputType;
        this.promise = promise;
    }

    @Override
    protected void doInBackgroundGuarded(Void... voids) {
        this.createThumbnail();
    }

    private void createThumbnail() {
        if (URLUtil.isNetworkUrl(uri)) {
            if (assetType.equalsIgnoreCase(MEDIA_PHOTO)) {
                promise.reject(ERROR_UNSUPPORTED_URL, "Cannot support remote photos");
            } else if (assetType.equalsIgnoreCase(MEDIA_VIDEO)) {
                promise.reject(ERROR_UNSUPPORTED_URL, "Cannot support remote videos");
            }
            return;
        }

        if (!checkIfFileExists(uri)) {
//            Log.d("RNCameraRoll", "File doesn't exist so null is returned.");
            promise.reject(ERROR_FILE_DOES_NOT_EXIST, "File doesn't exist");
            return;
        }

        String thumbnailFolder = reactContext.getApplicationContext().getCacheDir().getAbsolutePath() + THUMBNAILS_FOLDER;
        Log.d("RNCameraRoll", "Thumbnail folder: " + thumbnailFolder);
        try {
//            File thumbnailDir = createDirIfNotExists(thumbnailFolder);
            if (assetType.equalsIgnoreCase(MEDIA_PHOTO)) {
                String photoFolder = thumbnailFolder + "/" + MEDIA_PHOTO;
                File photoDir = createDirIfNotExists(photoFolder);
                createPhotoThumbnail(photoDir, photoFolder);
                return;
            } else if (assetType.equalsIgnoreCase(MEDIA_VIDEO)) {
                String videoFolder = thumbnailFolder + "/" + MEDIA_PHOTO;
                File videoDir = createDirIfNotExists(thumbnailFolder + "/" + MEDIA_VIDEO);
                createVideoThumbnail(videoDir, videoFolder);
                return;
            }
            promise.resolve(null);
        }
        catch (Exception e) {
            promise.reject(ERROR_UNABLE_TO_GENERATE_THUMBNAIL, e);
        }
    }

    private void createVideoThumbnail(File thumbnailDir, String thumbnailFolder) {
        try {
            Bitmap image = getBitmapAtTime(uri, timestamp);
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inSampleSize = calculateInSampleSize(options.outWidth, options.outHeight, width, height);
            options.inJustDecodeBounds = false;
            Bitmap sampledImage = scaleAndCropBitmap(image, width, height);
            String forVideoFormat = format != null ? format : "jpeg";
            String data = "";

            if (FILEPATH_OUTPUT_TYPE.equals(outputType)) {
                String filename = generateThumbnailFilename(format, options);
                File imageFile = new File(thumbnailDir, filename);
                imageFile.createNewFile();
                OutputStream fOut = new FileOutputStream(imageFile);
                compressImage(sampledImage, options, fOut, forVideoFormat);
                fOut.flush();
                fOut.close();
                data = "file://" + thumbnailFolder + "/" + filename;
            }
            else if (BASE64_OUTPUT_TYPE.equals(outputType)) {
                ByteArrayOutputStream bOut = new ByteArrayOutputStream();
                compressImage(sampledImage, options, bOut, forVideoFormat);
                bOut.flush();
                bOut.close();
                StringBuilder b64building = new StringBuilder();
                b64building.append(getBase64Prefix(options, format));
                b64building.append(Base64.encodeToString(bOut.toByteArray(), Base64.DEFAULT));
                data = b64building.toString();
            }

            WritableMap map = Arguments.createMap();
            map.putString("data", data);
            map.putDouble("width", sampledImage.getWidth());
            map.putDouble("height", sampledImage.getHeight());
            Log.d("RNCameraRoll", "Thumbnail creation finished on " + map.getString("data"));

            promise.resolve(map);

            sampledImage.recycle();
        }
        catch (IllegalStateException e) {
            promise.reject(ERROR_UNABLE_TO_GENERATE_THUMBNAIL, e.getMessage());
        }
        catch (FileNotFoundException e) {
            promise.reject(ERROR_FILE_DOES_NOT_EXIST, "File not found.");
        }
        catch (IOException e) {
            promise.reject(ERROR_UNABLE_TO_GENERATE_THUMBNAIL, "There was an issue in saving the file.");
        }
        catch (Exception e) {
            Log.d("RNCameraRoll", e.getMessage());
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
        try {
            SampledBitmap decodedSample = decodeSampledBitmapFromFile(uri, width, height);
            if (decodedSample.bitmap == null) {
                Log.d("RNCameraRoll", "Unable to generate thumbnail with the url specified");
                promise.reject(ERROR_UNABLE_TO_GENERATE_THUMBNAIL, "There was an issue in saving the file.");
                return;
            }

            Log.d("RNCameraRoll", "Bitmap created with width: " + decodedSample.bitmap.getWidth() + " height: " + decodedSample.bitmap.getHeight());
            Bitmap bitmap = scaleAndCropBitmap(decodedSample.bitmap, width, height);
            BitmapFactory.Options options = decodedSample.options;
            String data = "";
            if (FILEPATH_OUTPUT_TYPE.equals(outputType)) {
                String filename = generateThumbnailFilename(format, options);
                File imageFile = new File(thumbnailDir, filename);
                imageFile.createNewFile();
                OutputStream fOut = new FileOutputStream(imageFile);
                compressImage(bitmap, options, fOut, format);
                fOut.flush();
                fOut.close();
                data = "file://" + thumbnailFolder + "/" + filename;
            }
            else if (BASE64_OUTPUT_TYPE.equals(outputType)) {
                ByteArrayOutputStream bOut = new ByteArrayOutputStream();
                compressImage(bitmap, options, bOut, format);
                bOut.flush();
                bOut.close();
                StringBuilder b64building = new StringBuilder();
                b64building.append(getBase64Prefix(options, format));
                b64building.append(Base64.encodeToString(bOut.toByteArray(), Base64.DEFAULT));
                data = b64building.toString();
            }

            WritableMap map = Arguments.createMap();
            map.putString("data", data);
            map.putDouble("width", bitmap.getWidth());
            map.putDouble("height", bitmap.getHeight());
            Log.d("RNCameraRoll", "Thumbnail creation finished on " + map.getString("data"));

            promise.resolve(map);
            bitmap.recycle();
        }
        catch (FileNotFoundException e) {
            promise.reject(ERROR_FILE_DOES_NOT_EXIST, "File not found.");
        }
        catch (IOException e) {
            promise.reject(ERROR_UNABLE_TO_GENERATE_THUMBNAIL, "There was an issue in saving the file.");
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

    private String removeFileUrlPrefix(String uri) {
        String fileUri = uri;
        if (URLUtil.isFileUrl(uri)) {
            fileUri = Uri.decode(uri).replace("file://", "");
        }
        return fileUri;
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
            fileName += JPEG_EXT;
        }
        return fileName;
    }

    private void compressImage(Bitmap image, BitmapFactory.Options options, OutputStream out, String format) {
        if (format != null && PNG_EXT.equals(format)) {
            image.compress(Bitmap.CompressFormat.PNG, 100, out);
        }
        else {
            image.compress(Bitmap.CompressFormat.JPEG, 90, out);
        }
    }

    private String getBase64Prefix(BitmapFactory.Options options, String format) {
        if (format != null && PNG_EXT.equals(format)) {
            return PNG_BASE64_PREFIX;
        }
        else if (format != null) {
            return JPEG_BASE64_PREFIX;
        }
        return JPEG_BASE64_PREFIX;
    }

    /*
    * Bitmap is scaled not exactly to size but according to the smaller dimension. This is to maintain aspect ratio.
    * If the width of original bitmap is smaller, the bitmap is scaled down to requestedWidth and requestedHeight is ignored when scaling.
    * If the height of original bitmap is smaller, the bitmap is scaled down to requestedHeight and requestedWidth is ignored when scaling.
    * */
    private Bitmap scaleAndCropBitmap(Bitmap image, int requestedWidth, int requestedHeight) {
        int bitmapWidth = image.getWidth();
        int bitmapHeight = image.getHeight();
        int resultWidth = requestedWidth;
        int resultHeight = requestedHeight;
        float scaleRatio = 1;

        if (bitmapWidth < bitmapHeight) {
            scaleRatio = ((float) requestedWidth) / bitmapWidth;
            resultHeight = (int) (bitmapHeight * scaleRatio);
        }
        // if height < width, use requestedHeight as reference for scale
        else if (bitmapHeight < bitmapWidth) {
            scaleRatio = ((float) requestedHeight) / bitmapHeight;
            resultWidth = (int) (bitmapWidth * scaleRatio);
        }


        float middleX = resultWidth / 2.0f;
        float middleY = resultHeight / 2.0f;

        Bitmap scaledBitmap = Bitmap.createBitmap(resultWidth, resultHeight, Bitmap.Config.ARGB_8888);
        Matrix scaleMatrix = new Matrix();
        scaleMatrix.setScale(scaleRatio, scaleRatio, middleX, middleY);

        Canvas canvas = new Canvas(scaledBitmap);
        canvas.setMatrix(scaleMatrix);
        canvas.drawBitmap(image, middleX - image.getWidth() / 2, middleY - image.getHeight() / 2, new Paint(Paint.FILTER_BITMAP_FLAG));

//        Bitmap scaledDown = Bitmap.createScaledBitmap(image, resultWidth, resultHeight, false);

        return scaledBitmap;
    }

    private boolean checkIfFileExists(String path) {
        String newPath = removeFileUrlPrefix(path);
        File media = new File(newPath);
        if (media.exists()) {
            return true;
        }
        return false;
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
        }
    }
}
