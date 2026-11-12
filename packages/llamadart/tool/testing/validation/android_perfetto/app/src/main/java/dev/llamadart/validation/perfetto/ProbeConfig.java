package dev.llamadart.validation.perfetto;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Model-free trace configuration. Producer discovery is not inference proof. */
public final class ProbeConfig {
    public static final int DURATION_MS = 15000;
    public static final int MAX_TRACE_BYTES = 16 * 1024 * 1024;
    public static final String PACKAGE_NAME = "dev.llamadart.validation.perfetto";
    private static final Pattern RENDER_STAGE = Pattern.compile(
        "(?<![A-Za-z0-9_.-])(gpu\\.renderstages(?:\\.[A-Za-z0-9_-]+)?)(?![A-Za-z0-9_.-])");

    private ProbeConfig() {}

    public static List<String> renderStageSources(String serviceState) {
        Set<String> sources = new TreeSet<>();
        Matcher matcher = RENDER_STAGE.matcher(serviceState);
        while (matcher.find()) sources.add(matcher.group(1));
        if (sources.size() > 16) throw new IllegalArgumentException("Too many GPU producers");
        return new ArrayList<>(sources);
    }

    public static String traceConfig(List<String> sources) {
        StringBuilder config = new StringBuilder(
            "duration_ms: " + DURATION_MS + "\n"
            + "buffers { size_kb: 4096 fill_policy: DISCARD }\n"
            + "data_sources { config { name: \"linux.ftrace\" ftrace_config {\n"
            + "ftrace_events: \"ftrace/print\"\n"
            + "atrace_apps: \"" + PACKAGE_NAME + "\"\n"
            + "} } }\n"
            + "data_sources { config { name: \"linux.process_stats\" "
            + "process_stats_config { scan_all_processes_on_start: true } } }\n");
        for (String source : sources) {
            if (!RENDER_STAGE.matcher(source).matches()) {
                throw new IllegalArgumentException("Invalid render-stage source");
            }
            config.append("data_sources { config { name: \"").append(source).append("\" } }\n");
        }
        return config.toString();
    }
}
