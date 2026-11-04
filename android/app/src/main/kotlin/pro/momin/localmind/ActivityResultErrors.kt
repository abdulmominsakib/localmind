package pro.momin.localmind

internal object ActivityResultErrors {
    fun isDuplicateProcessTextReply(error: IllegalStateException): Boolean =
        error.message == "Reply already submitted" && error.stackTrace.any {
            it.className == "io.flutter.plugin.text.ProcessTextPlugin" &&
                it.methodName == "onActivityResult"
        }
}
