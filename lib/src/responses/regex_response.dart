class RegexResponse {
  static const String regexHTTP = r'^(http|https):\/\/([\w.]+\/?)\S*';
  static const String regexURL = r'(.*)\r?\/';
  static const String regexM3U8Resolution =
      r'#EXT-X-STREAM-INF:(?:.*,RESOLUTION=(\d+x\d+))?,?(.*)\r?\n(.*)';
}
