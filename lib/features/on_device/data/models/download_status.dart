enum DownloadStatus {
  pending,
  running,
  paused,
  canceled,
  failed,
  complete,
  undefined,
}

enum DownloadPauseReason {
  user,
  backgroundPolicy,
  networkPolicy,
  interrupted,
}

enum DownloadErrorCategory {
  network,
  httpAuth,
  httpNotFound,
  storage,
  registration,
  unknown,
}
