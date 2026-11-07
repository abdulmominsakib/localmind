package pro.momin.localmind

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ActivityResultErrorsTest {
    private fun error(message: String, owner: String, method: String) =
        IllegalStateException(message).apply {
            stackTrace = arrayOf(StackTraceElement(owner, method, "Plugin.java", 1))
        }

    @Test fun containsOnlyTheReportedProcessTextFailure() {
        assertTrue(ActivityResultErrors.isDuplicateProcessTextReply(error(
            "Reply already submitted", "io.flutter.plugin.text.ProcessTextPlugin", "onActivityResult"
        )))
        assertFalse(ActivityResultErrors.isDuplicateProcessTextReply(error(
            "Reply already submitted", "other.Plugin", "onActivityResult"
        )))
        assertFalse(ActivityResultErrors.isDuplicateProcessTextReply(error(
            "Different failure", "io.flutter.plugin.text.ProcessTextPlugin", "onActivityResult"
        )))
        assertFalse(ActivityResultErrors.isDuplicateProcessTextReply(error(
            "Reply already submitted", "io.flutter.plugin.text.ProcessTextPlugin", "otherMethod"
        )))
    }
}
