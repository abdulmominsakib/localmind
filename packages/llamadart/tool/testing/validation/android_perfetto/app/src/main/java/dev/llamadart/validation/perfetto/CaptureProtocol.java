package dev.llamadart.validation.perfetto;

import java.nio.charset.StandardCharsets;

/** Fixed v49-compatible session acknowledgment and finite scratch-file transport. */
public final class CaptureProtocol {
    private CaptureProtocol() {}

    public static String path(String nonce) {
        if (!nonce.matches("[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")) {
            throw new IllegalArgumentException("Fresh UUID required");
        }
        return "/data/misc/perfetto-traces/llamadart-perfetto-" + nonce;
    }

    public static String startScript(String nonce, String config) {
        String path = path(nonce);
        // Android mksh materializes heredocs in shell_data_file storage, which
        // the Perfetto SELinux domain cannot read. A real pipe keeps the config
        // on its explicitly allowed shell FIFO boundary. Capture the PID through
        // a pipe too: shell-created PID/stderr regular files are not writable
        // across the domain transition. Perfetto creates only its own trace.
        String quotedConfig = "'" + config.replace("'", "'\\''") + "'";
        return "test ! -e " + path + ".trace || exit 1; pid=$(printf '%s' " + quotedConfig
            + " | perfetto --background-wait --txt -c - -o " + path
            + ".trace); code=$?; if [ $code -eq 0 ] && test -d /proc/\"$pid\"; then printf '%s\\nREADY:0\\n' \"$pid\"; "
            + "else printf 'READY:ERROR\\n'; fi";
    }

    public static int startedPid(byte[] acknowledgment) {
        String value = new String(acknowledgment, StandardCharsets.UTF_8);
        if (!value.matches("[1-9][0-9]{0,8}\\nREADY:0\\n")) {
            throw new IllegalStateException("Perfetto session did not acknowledge all sources started");
        }
        return Integer.parseInt(value.substring(0, value.indexOf('\n')));
    }

    public static String completedTraceScript(String nonce, int pid) {
        if (pid <= 0) throw new IllegalArgumentException("Positive acknowledged PID required");
        String path = path(nonce);
        // Shell cannot signal the Perfetto SELinux domain, even with kill -0.
        // Its visible /proc directory must disappear after the finite exit;
        // startScript established that this exact acknowledged PID was visible.
        return "for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do "
            + "if test ! -d /proc/" + pid + "; then cat " + path
            + ".trace; exit; fi; sleep 1; done; exit 1";
    }

    public static String cleanupCommand(String nonce) {
        String path = path(nonce);
        return "rm -f " + path + ".trace";
    }
}
