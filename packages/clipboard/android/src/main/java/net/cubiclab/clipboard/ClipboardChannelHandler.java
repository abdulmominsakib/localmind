package net.cubiclab.clipboard;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.ContentValues;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.EventChannel;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class ClipboardChannelHandler implements MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private final Context context;
    private final ClipboardManager clipboardManager;
    private EventChannel.EventSink eventSink;
    private ClipboardManager.OnPrimaryClipChangedListener clipboardChangeListener;

    public ClipboardChannelHandler(Context context) {
        this.context = context;
        this.clipboardManager = (ClipboardManager) context.getSystemService(Context.CLIPBOARD_SERVICE);
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "copy":
                handleCopy(call, result);
                break;
            case "copyRichText":
                handleCopyRichText(call, result);
                break;
            case "copyMultiple":
                handleCopyMultiple(call, result);
                break;
            case "copyImage":
                handleCopyImage(call, result);
                break;
            case "paste":
                handlePaste(call, result);
                break;
            case "pasteRichText":
                handlePasteRichText(call, result);
                break;
            case "pasteImage":
                handlePasteImage(call, result);
                break;
            case "getContentType":
                handleGetContentType(call, result);
                break;
            case "hasData":
                handleHasData(call, result);
                break;
            case "clear":
                handleClear(call, result);
                break;
            case "getDataSize":
                handleGetDataSize(call, result);
                break;
            case "startMonitoring":
                startMonitoring();
                result.success(true);
                break;
            case "stopMonitoring":
                stopMonitoring();
                result.success(true);
                break;
            default:
                result.notImplemented();
        }
    }

    private void handleCopy(MethodCall call, MethodChannel.Result result) {
        String text = call.argument("text");
        if (text == null || text.isEmpty()) {
            result.error("EMPTY_TEXT", "Text cannot be empty", null);
            return;
        }
        try {
            ClipData clip = ClipData.newPlainText("text", text);
            clipboardManager.setPrimaryClip(clip);
            result.success(true);
        } catch (Exception e) {
            result.error("COPY_ERROR", e.getMessage(), null);
        }
    }

    private void handleCopyRichText(MethodCall call, MethodChannel.Result result) {
        String text = call.argument("text");
        String html = call.argument("html");
        if ((text == null || text.isEmpty()) && (html == null || html.isEmpty())) {
            result.error("EMPTY_CONTENT", "Either text or html must be provided", null);
            return;
        }
        try {
            if (html != null && !html.isEmpty() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
                ClipData clip = ClipData.newHtmlText("html", text != null ? text : "", html);
                clipboardManager.setPrimaryClip(clip);
            } else {
                ClipData clip = ClipData.newPlainText("text", text != null ? text : "");
                clipboardManager.setPrimaryClip(clip);
            }
            result.success(true);
        } catch (Exception e) {
            result.error("COPY_RICH_ERROR", e.getMessage(), null);
        }
    }

    @SuppressWarnings("unchecked")
    private void handleCopyMultiple(MethodCall call, MethodChannel.Result result) {
        Map<String, Object> formats = call.argument("formats");
        if (formats == null || formats.isEmpty()) {
            result.error("EMPTY_FORMATS", "At least one format must be provided", null);
            return;
        }
        try {
            String text = formats.get("text/plain") != null ? formats.get("text/plain").toString() : "";
            String html = formats.get("text/html") != null ? formats.get("text/html").toString() : null;
            List<Integer> imageBytes = null;
            if (formats.get("image/png") instanceof List) {
                imageBytes = (List<Integer>) formats.get("image/png");
            }

            // Handle image using MediaStore
            if (imageBytes != null && !imageBytes.isEmpty()) {
                byte[] byteArray = new byte[imageBytes.size()];
                for (int i = 0; i < imageBytes.size(); i++) {
                    byteArray[i] = imageBytes.get(i).byteValue();
                }
                Bitmap bitmap = BitmapFactory.decodeByteArray(byteArray, 0, byteArray.length);
                if (bitmap != null) {
                    Uri imageUri = insertImageToMediaStore(bitmap);
                    if (imageUri != null) {
                        ClipData clip = ClipData.newUri(context.getContentResolver(), "image", imageUri);
                        if (text != null && !text.isEmpty()) {
                            clip.addItem(new ClipData.Item(text));
                        }
                        clipboardManager.setPrimaryClip(clip);
                        result.success(true);
                        return;
                    }
                }
            }

            if (html != null && !html.isEmpty() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
                ClipData clip = ClipData.newHtmlText("html", text, html);
                clipboardManager.setPrimaryClip(clip);
            } else if (text != null && !text.isEmpty()) {
                ClipData clip = ClipData.newPlainText("text", text);
                clipboardManager.setPrimaryClip(clip);
            }
            result.success(true);
        } catch (Exception e) {
            result.error("COPY_MULTIPLE_ERROR", e.getMessage(), null);
        }
    }

    private void handleCopyImage(MethodCall call, MethodChannel.Result result) {
        List<Integer> imageBytes = call.argument("imageBytes");
        if (imageBytes == null || imageBytes.isEmpty()) {
            result.error("EMPTY_IMAGE", "Image bytes cannot be empty", null);
            return;
        }
        try {
            byte[] byteArray = new byte[imageBytes.size()];
            for (int i = 0; i < imageBytes.size(); i++) {
                byteArray[i] = imageBytes.get(i).byteValue();
            }
            Bitmap bitmap = BitmapFactory.decodeByteArray(byteArray, 0, byteArray.length);
            if (bitmap == null) {
                result.error("INVALID_IMAGE", "Failed to decode image", null);
                return;
            }
            
            // Use MediaStore to insert image and get content:// URI
            Uri imageUri = insertImageToMediaStore(bitmap);
            if (imageUri == null) {
                result.error("SAVE_ERROR", "Failed to save image to MediaStore", null);
                return;
            }
            
            ClipData clip = ClipData.newUri(context.getContentResolver(), "image", imageUri);
            clipboardManager.setPrimaryClip(clip);
            result.success(true);
        } catch (Exception e) {
            result.error("COPY_IMAGE_ERROR", "Failed to copy image: " + e.getMessage(), null);
        }
    }
    
    private Uri insertImageToMediaStore(Bitmap bitmap) {
        try {
            ContentValues values = new ContentValues();
            values.put(MediaStore.Images.Media.DISPLAY_NAME, "clipboard_image_" + System.currentTimeMillis() + ".png");
            values.put(MediaStore.Images.Media.MIME_TYPE, "image/png");
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES);
                values.put(MediaStore.Images.Media.IS_PENDING, 1);
            }
            
            Uri uri = context.getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values);
            if (uri == null) {
                return null;
            }
            
            try {
                java.io.OutputStream outputStream = context.getContentResolver().openOutputStream(uri);
                if (outputStream == null) {
                    return null;
                }
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream);
                outputStream.close();
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    values.clear();
                    values.put(MediaStore.Images.Media.IS_PENDING, 0);
                    context.getContentResolver().update(uri, values, null, null);
                }
                
                return uri;
            } catch (Exception e) {
                context.getContentResolver().delete(uri, null, null);
                return null;
            }
        } catch (Exception e) {
            return null;
        }
    }

    private void handlePaste(MethodCall call, MethodChannel.Result result) {
        try {
            ClipData clipData = clipboardManager.getPrimaryClip();
            String text = clipData != null && clipData.getItemCount() > 0
                ? clipData.getItemAt(0).getText().toString()
                : "";
            Map<String, String> resultMap = new HashMap<>();
            resultMap.put("text", text);
            result.success(resultMap);
        } catch (Exception e) {
            result.error("PASTE_ERROR", e.getMessage(), null);
        }
    }

    private void handlePasteRichText(MethodCall call, MethodChannel.Result result) {
        try {
            ClipData clipData = clipboardManager.getPrimaryClip();
            ClipData.Item item = clipData != null && clipData.getItemCount() > 0
                ? clipData.getItemAt(0)
                : null;
            String text = item != null && item.getText() != null ? item.getText().toString() : "";
            String html = null;
            if (item != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
                html = item.getHtmlText();
            }
            List<Integer> imageBytes = getImageFromClipboard(item);

            Map<String, Object> resultMap = new HashMap<>();
            resultMap.put("text", text);
            resultMap.put("html", html);
            resultMap.put("imageBytes", imageBytes);
            resultMap.put("timestamp", System.currentTimeMillis());
            result.success(resultMap);
        } catch (Exception e) {
            result.error("PASTE_RICH_ERROR", e.getMessage(), null);
        }
    }

    private void handlePasteImage(MethodCall call, MethodChannel.Result result) {
        try {
            ClipData clipData = clipboardManager.getPrimaryClip();
            ClipData.Item item = clipData != null && clipData.getItemCount() > 0
                ? clipData.getItemAt(0)
                : null;
            List<Integer> imageBytes = getImageFromClipboard(item);
            Map<String, Object> resultMap = new HashMap<>();
            resultMap.put("imageBytes", imageBytes);
            result.success(resultMap);
        } catch (Exception e) {
            result.error("PASTE_IMAGE_ERROR", e.getMessage(), null);
        }
    }

    private void handleGetContentType(MethodCall call, MethodChannel.Result result) {
        // Don't access clipboard automatically
        result.success("unknown");
    }

    private void handleHasData(MethodCall call, MethodChannel.Result result) {
        // Don't access clipboard automatically
        result.success(false);
    }

    private void handleClear(MethodCall call, MethodChannel.Result result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                clipboardManager.clearPrimaryClip();
            } else {
                ClipData clip = ClipData.newPlainText("", "");
                clipboardManager.setPrimaryClip(clip);
            }
            result.success(true);
        } catch (Exception e) {
            result.error("CLEAR_ERROR", e.getMessage(), null);
        }
    }

    private void handleGetDataSize(MethodCall call, MethodChannel.Result result) {
        // Don't access clipboard automatically
        result.success(0);
    }

    private List<Integer> getImageFromClipboard(ClipData.Item item) {
        if (item == null || item.getUri() == null) {
            return null;
        }
        try {
            android.content.ContentResolver resolver = context.getContentResolver();
            String mimeType = resolver.getType(item.getUri());
            if (mimeType == null || !mimeType.startsWith("image/")) {
                return null;
            }
            
            java.io.InputStream inputStream = resolver.openInputStream(item.getUri());
            if (inputStream == null) {
                return null;
            }
            
            Bitmap bitmap = BitmapFactory.decodeStream(inputStream);
            inputStream.close();
            if (bitmap == null) {
                return null;
            }
            
            ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream);
            byte[] byteArray = outputStream.toByteArray();
            outputStream.close();
            
            List<Integer> result = new ArrayList<>();
            for (byte b : byteArray) {
                result.add((int) b & 0xFF);
            }
            return result;
        } catch (Exception e) {
            return null;
        }
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        this.eventSink = events;
        startMonitoring();
    }

    @Override
    public void onCancel(Object arguments) {
        this.eventSink = null;
        stopMonitoring();
    }

    private void startMonitoring() {
        if (clipboardChangeListener != null) {
            return;
        }
        clipboardChangeListener = () -> {
            if (eventSink != null) {
                try {
                    ClipData clipData = clipboardManager.getPrimaryClip();
                    ClipData.Item item = clipData != null && clipData.getItemCount() > 0
                        ? clipData.getItemAt(0)
                        : null;
                    String text = item != null && item.getText() != null
                        ? item.getText().toString()
                        : "";
                    String html = null;
                    if (item != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
                        html = item.getHtmlText();
                    }
                    Map<String, Object> eventMap = new HashMap<>();
                    eventMap.put("text", text);
                    eventMap.put("html", html);
                    eventMap.put("timestamp", System.currentTimeMillis());
                    eventSink.success(eventMap);
                } catch (Exception e) {
                    // Ignore errors
                }
            }
        };
        clipboardManager.addPrimaryClipChangedListener(clipboardChangeListener);
    }

    private void stopMonitoring() {
        if (clipboardChangeListener != null) {
            clipboardManager.removePrimaryClipChangedListener(clipboardChangeListener);
            clipboardChangeListener = null;
        }
    }
}

