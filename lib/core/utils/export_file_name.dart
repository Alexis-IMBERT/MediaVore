/// Default file name of a data export: `mediavore_export_yyyy-MM-dd_HH-mm-ss.mdv`.
///
/// Uses local time (the name is meant for the user). Fields are zero-padded and
/// ordered most-significant first, so names sort chronologically; the time part
/// uses `-` because `:` is invalid in Windows and some Android file names.
/// The import does not depend on this name.
String exportFileName(DateTime dateTime) {
  final t = dateTime.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final date =
      '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}';
  final time = '${two(t.hour)}-${two(t.minute)}-${two(t.second)}';
  return 'mediavore_export_${date}_$time.mdv';
}
