package dev.llamadart.validation.perfetto;

import android.app.Instrumentation;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.os.Build;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import android.os.Process;
import android.os.SystemClock;
import android.os.Trace;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.runner.AndroidJUnit4;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;

/** Collection capability only. It cannot qualify model inference placement. */
@RunWith(AndroidJUnit4.class)
public class PerfettoCapabilityTest {
    private static volatile long cpuResult;

    @Test(timeout = 90000)
    public void collectModelFreeTrace() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        Bundle arguments = InstrumentationRegistry.getArguments();
        assertEquals("Probe requires an explicit opt-in", "true", arguments.getString("perfettoProbe"));
        String source = arguments.getString("validationCommit");
        assertNotNull("validationCommit is required", source);
        assertTrue("validationCommit must be a full source SHA", source.matches("[0-9a-f]{40}"));
        assertTrue("executeShellCommandRwe needs Android API 34+", Build.VERSION.SDK_INT >= 34);

        Context context = instrumentation.getTargetContext();
        String nonce = UUID.randomUUID().toString();
        File directory = new File(context.getExternalFilesDir(null), "perfetto_capability/" + nonce);
        assertTrue("Fresh output directory required", directory.mkdirs());
        // The instrumentation shell descriptor streams the bytes to app-owned
        // storage. Test Lab need not pull a shell-owned /data/misc output file.
        instrumentation.getUiAutomation();
        ShellResult version = command(instrumentation, "perfetto --version", null, 5000, 1024 * 1024);
        ShellResult state = command(instrumentation, "perfetto --query --long", null, 5000, 2 * 1024 * 1024);
        ShellResult rawState = command(instrumentation, "perfetto --query-raw", null, 5000, 2 * 1024 * 1024);
        save(directory, "version.txt", version.stdout);
        save(directory, "version.stderr.txt", version.stderr);
        save(directory, "service-state.txt", state.stdout);
        save(directory, "service-state.stderr.txt", state.stderr);
        save(directory, "service-state.pb", rawState.stdout);
        save(directory, "service-state-raw.stderr.txt", rawState.stderr);
        assertTrue("Tracing service returned no descriptor bytes", rawState.stdout.length > 0);
        List<String> sources = ProbeConfig.renderStageSources(new String(state.stdout, StandardCharsets.UTF_8));
        String config = ProbeConfig.traceConfig(sources);
        save(directory, "config.pbtxt", config.getBytes(StandardCharsets.UTF_8));

        ShellResult trace;
        byte[] startupErrors = new byte[0];
        int capturePid = 0;
        long captureAcknowledged = 0;
        boolean markersEnabled = false;
        String cpuMarker = "llamadart_probe_cpu_" + nonce;
        String idleMarker = "llamadart_probe_idle_" + nonce;
        long cpuStarted = 0;
        long cpuEnded = 0;
        long idleStarted = 0;
        long idleEnded = 0;
        try {
            ShellResult acknowledgment = startCapture(instrumentation, directory, nonce, config);
            startupErrors = acknowledgment.stderr;
            capturePid = CaptureProtocol.startedPid(acknowledgment.stdout);
            captureAcknowledged = SystemClock.elapsedRealtimeNanos();
            markersEnabled = Trace.isEnabled();
            cpuStarted = SystemClock.elapsedRealtimeNanos();
            Trace.beginAsyncSection(cpuMarker, 1);
            try {
                long value = 17;
                long deadline = SystemClock.elapsedRealtime() + 1000;
                while (SystemClock.elapsedRealtime() < deadline) {
                    for (int i = 0; i < 10000; i++) value = value * 1664525 + 1013904223;
                }
                cpuResult = value;
            } finally {
                Trace.endAsyncSection(cpuMarker, 1);
                cpuEnded = SystemClock.elapsedRealtimeNanos();
            }
            idleStarted = SystemClock.elapsedRealtimeNanos();
            Trace.beginAsyncSection(idleMarker, 2);
            try {
                Thread.sleep(1000);
            } finally {
                Trace.endAsyncSection(idleMarker, 2);
                idleEnded = SystemClock.elapsedRealtimeNanos();
            }
            ShellResult payload = command(instrumentation,
                "sh", CaptureProtocol.completedTraceScript(nonce, capturePid).getBytes(StandardCharsets.UTF_8), 25000, ProbeConfig.MAX_TRACE_BYTES);
            trace = new ShellResult(payload.stdout, joined(startupErrors, payload.stderr));
        } finally {
            command(instrumentation, CaptureProtocol.cleanupCommand(nonce), null, 5000, 1024);
        }
        save(directory, "capture.perfetto-trace", trace.stdout);
        save(directory, "capture.stderr.txt", trace.stderr);
        assertTrue("Trace output is empty", trace.stdout.length > 0);

        JSONObject receipt = new JSONObject();
        receipt.put("schema_version", 1);
        receipt.put("scope", "model_free_trace_collection_capability");
        receipt.put("gpu_inference_qualified", false);
        receipt.put("trace_semantics_validated", false);
        receipt.put("source_commit_declaration", source);
        receipt.put("nonce", nonce);
        receipt.put("pid", Process.myPid());
        receipt.put("uid", Process.myUid());
        receipt.put("package", context.getPackageName());
        receipt.put("api", Build.VERSION.SDK_INT);
        receipt.put("model", Build.MODEL);
        receipt.put("fingerprint", Build.FINGERPRINT);
        receipt.put("no_activity_or_flutter_engine", true);
        receipt.put("app_hardware_accelerated", false);
        receipt.put("app_debuggable", (context.getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0);
        receipt.put("app_apk_sha256", sha256(new File(context.getPackageCodePath())));
        receipt.put("test_apk_sha256", sha256(new File(instrumentation.getContext().getPackageCodePath())));
        receipt.put("discovered_render_stage_source_names", new JSONArray(sources));
        receipt.put("atrace_enabled_when_markers_submitted", markersEnabled);
        receipt.put("capture_session_start_acknowledged", true);
        receipt.put("capture_session_pid", capturePid);
        receipt.put("capture_ack_boottime_ns", captureAcknowledged);
        receipt.put("cpu_control", new JSONObject().put("marker", cpuMarker)
            .put("start_boottime_ns", cpuStarted).put("end_boottime_ns", cpuEnded).put("result", cpuResult));
        receipt.put("idle_control", new JSONObject().put("marker", idleMarker)
            .put("start_boottime_ns", idleStarted).put("end_boottime_ns", idleEnded));
        JSONObject files = new JSONObject();
        for (String name : new String[] {"version.txt", "version.stderr.txt", "service-state.txt",
                "service-state.stderr.txt", "service-state.pb", "service-state-raw.stderr.txt", "config.pbtxt",
                "capture.perfetto-trace", "capture.stderr.txt", "capture-start-ack.txt"}) {
            File file = new File(directory, name);
            files.put(name, new JSONObject().put("sha256", sha256(file)).put("bytes", file.length()));
        }
        receipt.put("files", files);
        save(directory, "receipt.json", (receipt.toString(2) + "\n").getBytes(StandardCharsets.UTF_8));
        // No GPU producer is a supported probe outcome, not GPU qualification.
        // The offline checker must find both real markers and parse the trace.
    }

    @Test(timeout = 45000)
    public void malformedConfigPreservesDiagnosticsAfterCleanup() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        assertEquals("Probe requires an explicit opt-in", "true",
            InstrumentationRegistry.getArguments().getString("perfettoProbe"));
        assertTrue("executeShellCommandRwe needs Android API 34+", Build.VERSION.SDK_INT >= 34);
        String nonce = UUID.randomUUID().toString();
        File directory = new File(instrumentation.getTargetContext().getExternalFilesDir(null),
            "perfetto_failure_control/" + nonce);
        assertTrue("Fresh failure-control directory required", directory.mkdirs());
        String config = "duration_ms: invalid_number\n";
        ShellResult acknowledgment;
        try {
            acknowledgment = startCapture(instrumentation, directory, nonce, config);
            try {
                CaptureProtocol.startedPid(acknowledgment.stdout);
                fail("Malformed config was acknowledged");
            } catch (IllegalStateException expected) {
                assertArrayEquals("READY:ERROR\n".getBytes(StandardCharsets.UTF_8), acknowledgment.stdout);
                assertTrue("Perfetto must explain config rejection", acknowledgment.stderr.length > 0);
            }
        } finally {
            command(instrumentation, CaptureProtocol.cleanupCommand(nonce), null, 5000, 1024);
        }
        assertEquals(config, new String(readSaved(directory, "config.pbtxt", 1024), StandardCharsets.UTF_8));
        assertArrayEquals(acknowledgment.stdout, readSaved(directory, "capture-start-ack.txt", 1024));
        assertArrayEquals(acknowledgment.stderr, readSaved(directory, "capture.stderr.txt", 1024 * 1024));
    }

    private static ShellResult startCapture(Instrumentation instrumentation, File directory,
            String nonce, String config) throws Exception {
        save(directory, "config.pbtxt", config.getBytes(StandardCharsets.UTF_8));
        ShellResult acknowledgment = command(instrumentation, "sh",
            CaptureProtocol.startScript(nonce, config).getBytes(StandardCharsets.UTF_8), 35000, 1024);
        // Persist before the caller validates and before shell scratch cleanup.
        save(directory, "capture-start-ack.txt", acknowledgment.stdout);
        save(directory, "capture.stderr.txt", acknowledgment.stderr);
        return acknowledgment;
    }

    private static ShellResult command(Instrumentation instrumentation, String command, byte[] stdin,
            int timeoutMs, int stdoutLimit) throws Exception {
        ParcelFileDescriptor[] descriptors = instrumentation.getUiAutomation().executeShellCommandRwe(command);
        ExecutorService readers = Executors.newFixedThreadPool(2);
        try (InputStream stdout = new ParcelFileDescriptor.AutoCloseInputStream(descriptors[0]);
             FileOutputStream input = new ParcelFileDescriptor.AutoCloseOutputStream(descriptors[1]);
             InputStream stderr = new ParcelFileDescriptor.AutoCloseInputStream(descriptors[2])) {
            Future<byte[]> output = readers.submit(() -> read(stdout, stdoutLimit));
            Future<byte[]> errors = readers.submit(() -> read(stderr, 1024 * 1024));
            if (stdin != null) input.write(stdin);
            input.close();
            long deadline = SystemClock.elapsedRealtime() + timeoutMs;
            byte[] bytes = output.get(timeoutMs, TimeUnit.MILLISECONDS);
            long remaining = Math.max(1, deadline - SystemClock.elapsedRealtime());
            return new ShellResult(bytes, errors.get(remaining, TimeUnit.MILLISECONDS));
        } finally {
            readers.shutdownNow();
        }
    }

    private static byte[] readSaved(File directory, String name, int limit) throws Exception {
        try (InputStream input = new FileInputStream(new File(directory, name))) {
            return read(input, limit);
        }
    }

    private static byte[] joined(byte[]... inputs) throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        for (byte[] input : inputs) output.write(input);
        return output.toByteArray();
    }

    private static byte[] read(InputStream input, int limit) throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[64 * 1024];
        int count;
        while ((count = input.read(buffer)) != -1) {
            if (count > limit - output.size()) throw new IllegalStateException("Shell output exceeded probe limit");
            output.write(buffer, 0, count);
        }
        return output.toByteArray();
    }

    private static void save(File directory, String name, byte[] bytes) throws Exception {
        try (FileOutputStream output = new FileOutputStream(new File(directory, name))) {
            output.write(bytes);
            output.getFD().sync();
        }
    }

    private static String sha256(File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream input = new FileInputStream(file)) {
            byte[] buffer = new byte[64 * 1024];
            int count;
            while ((count = input.read(buffer)) != -1) digest.update(buffer, 0, count);
        }
        StringBuilder hex = new StringBuilder();
        for (byte value : digest.digest()) hex.append(String.format("%02x", value & 255));
        return hex.toString();
    }

    private static class ShellResult {
        final byte[] stdout;
        final byte[] stderr;
        ShellResult(byte[] stdout, byte[] stderr) { this.stdout = stdout; this.stderr = stderr; }
    }
}
