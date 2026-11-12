package dev.llamadart.validation.perfetto;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.Test;
import static org.junit.Assert.*;

public class CaptureProtocolTest {
    private static final String NONCE = "11111111-2222-4333-8444-555555555555";

    @Test public void sessionAckRequiresPidAndSuccess() {
        assertEquals(12345, CaptureProtocol.startedPid("12345\nREADY:0\n".getBytes(StandardCharsets.UTF_8)));
        for (String invalid : new String[] {"", "12345\n", "READY:0\n", "0\nREADY:0\n", "123\nREADY:ERROR\n", "123\nREADY:0\nextra", "-1\nREADY:0\n"}) {
            try { CaptureProtocol.startedPid(invalid.getBytes(StandardCharsets.UTF_8)); fail(invalid); }
            catch (IllegalStateException expected) {}
        }
    }

    @Test public void fixedTransportWaitsForSourcesAndFiniteExitWithoutSignals() {
        String start = CaptureProtocol.startScript(NONCE, "duration_ms: 15000");
        assertTrue(start.contains("| perfetto --background-wait --txt -c -"));
        assertFalse(start.contains("<<"));
        assertTrue(start.contains("/data/misc/perfetto-traces/"));
        assertTrue(start.contains("code=$?; if [ $code -eq 0 ]"));
        assertFalse(start.contains("--notify-fd"));
        String completion = CaptureProtocol.completedTraceScript(NONCE, 12345);
        assertTrue(completion.contains("test ! -d /proc/12345"));
        assertTrue(start.contains("test -d /proc/\"$pid\""));
        assertFalse(completion.contains("kill"));
        assertFalse(completion.contains("kill -TERM"));
        assertFalse(completion.contains("kill -INT"));
        assertTrue(completion.contains("19 20; do"));
        assertTrue(CaptureProtocol.cleanupCommand(NONCE).endsWith(NONCE + ".trace"));
        assertFalse(start.contains(".pid"));
        assertFalse(start.contains(".stderr"));
    }

    @Test public void shellReceivesScriptOnStdinAndAcknowledgesOnlySuccessfulStart() throws Exception {
        Path directory = Files.createTempDirectory("perfetto-protocol-");
        Path executable = directory.resolve("perfetto");
        try {
            String fake = "#!/bin/sh\nwhile [ $# -gt 0 ]; do if [ \"$1\" = -o ]; then shift; out=$1; fi; shift; done\n"
                + "config=$(cat); [ \"$config\" = \"duration_ms: 15000 # 'quoted'\" ] || exit 2\n"
                + "printf TRACE > \"$out\"\nprintf '12345\\n'\nexit ${MOCK_EXIT:-0}\n";
            Files.write(executable, fake.getBytes(StandardCharsets.UTF_8));
            assertTrue(executable.toFile().setExecutable(true));
            for (String code : new String[] {"0", "1"}) {
                String nonce = code.equals("0") ? NONCE : "22222222-2222-4333-8444-555555555555";
                ProcessBuilder builder = new ProcessBuilder("sh");
                builder.environment().put("PATH", directory + ":" + System.getenv("PATH"));
                builder.environment().put("MOCK_EXIT", code);
                java.lang.Process process = builder.start();
                process.getOutputStream().write(CaptureProtocol.startScript(nonce, "duration_ms: 15000 # 'quoted'")
                    .replace("/data/misc/perfetto-traces/", directory + "/")
                    .replace("test -d /proc/\"$pid\"", "test -d " + directory).getBytes(StandardCharsets.UTF_8));
                process.getOutputStream().close();
                byte[] acknowledgment = process.getInputStream().readAllBytes();
                assertEquals(0, process.waitFor());
                if (code.equals("0")) assertEquals(12345, CaptureProtocol.startedPid(acknowledgment));
                else {
                    try { CaptureProtocol.startedPid(acknowledgment); fail("Failed producer start accepted"); }
                    catch (IllegalStateException expected) {}
                }
            }
        } finally {
            try (java.util.stream.Stream<Path> paths = Files.walk(directory)) {
                for (Path path : paths.sorted(java.util.Comparator.reverseOrder()).toArray(Path[]::new)) Files.delete(path);
            }
        }
    }

    @Test(expected = IllegalArgumentException.class) public void untrustedPathCannotReachShell() {
        CaptureProtocol.startScript("'; touch /tmp/untrusted; '", "duration_ms: 15000");
    }

    @Test(expected = IllegalArgumentException.class) public void missingPidCannotReachShell() {
        CaptureProtocol.completedTraceScript(NONCE, 0);
    }
}
