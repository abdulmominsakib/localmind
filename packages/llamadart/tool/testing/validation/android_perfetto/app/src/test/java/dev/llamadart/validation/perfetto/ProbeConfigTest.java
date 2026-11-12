package dev.llamadart.validation.perfetto;

import java.util.Arrays;
import org.junit.Test;
import static org.junit.Assert.*;

public class ProbeConfigTest {
    @Test public void actualNamesAreExactSortedAndUnique() {
        assertEquals(Arrays.asList("gpu.renderstages", "gpu.renderstages.adreno"),
            ProbeConfig.renderStageSources(
                "name: gpu.renderstages.adreno\nname: gpu.renderstages\n"
                + "name: gpu.renderstages.adreno\nname: gpu.counters\n"));
    }

    @Test public void prefixesNestedSuffixesAndCountersAreNotProducers() {
        assertTrue(ProbeConfig.renderStageSources(
            "fakegpu.renderstages gpu.renderstages.adreno.fake gpu.counters.adreno "
            + "gpu.renderstages-extra").isEmpty());
    }

    @Test public void missingProducerDoesNotInventGpuSupport() {
        assertFalse(ProbeConfig.traceConfig(ProbeConfig.renderStageSources(
            "linux.ftrace linux.process_stats")).contains("gpu.renderstages"));
    }

    @Test(expected = IllegalArgumentException.class)
    public void sourceCannotInjectConfiguration() {
        ProbeConfig.traceConfig(Arrays.asList("gpu.renderstages\" } } }"));
    }

    @Test(expected = IllegalArgumentException.class)
    public void unexpectedlyLargeDiscoveryFailsClosed() {
        StringBuilder state = new StringBuilder();
        for (int i = 0; i < 17; i++) state.append("gpu.renderstages.vendor").append(i).append("\n");
        ProbeConfig.renderStageSources(state.toString());
    }
}
