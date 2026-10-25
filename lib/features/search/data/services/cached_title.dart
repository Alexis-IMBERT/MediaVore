import 'package:mediavore/core/domain/entities/media_item.dart';

/// Title of a saved entry in the current language: the cached TMDB title
/// when available, else the one stored when it was saved.
T preferCachedTitle<T extends String?>(MediaItem? cached, T storedTitle) {
  final title = cached?.title;
  return (title == null || title.isEmpty) ? storedTitle : title as T;
}
