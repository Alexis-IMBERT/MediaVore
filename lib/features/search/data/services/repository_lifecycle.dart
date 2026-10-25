import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mediavore/core/cache/cache_warmup_policy.dart';
import 'package:mediavore/core/cache/media_cache.dart';
import 'package:mediavore/core/l10n/locale_service.dart';
import 'package:mediavore/features/search/data/services/cache_warmup_service.dart';

/// Initialization of `MediaRepositoryImpl`: opens the cache, drops it when it
/// was filled in another language, then starts the automatic warm-up.
///
/// Every public repository call awaits [ensureInitialized] first.
class RepositoryLifecycle {
  final MediaCache cache;
  final CacheWarmupService warmup;

  /// Gates the automatic warm-up started by [init]. `null` = always run.
  final CacheWarmupPolicy? warmupPolicy;

  /// App language; the TMDB cache is dropped when it changes so titles are
  /// never shown in a previous language. `null` disables the check.
  final LocaleService? localeService;

  final Completer<void> _initCompleter = Completer<void>();

  Future<bool>? _languageChange;

  RepositoryLifecycle({
    required this.cache,
    required this.warmup,
    this.warmupPolicy,
    this.localeService,
  });

  Future<void> ensureInitialized() async {
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }
  }

  /// Marks the repository ready without opening the cache (tests, or callers
  /// that open it themselves).
  void skipInit() {
    if (!_initCompleter.isCompleted) {
      _initCompleter.complete();
    }
  }

  Future<void> init() async {
    try {
      debugPrint('[Repo] Starting Cache Init...');
      await cache.init();
      await _dropStaleLanguageCache();
      debugPrint('[Repo] Cache Init Done.');
    } catch (e) {
      debugPrint('[Repo] Cache Init Error: $e');
    } finally {
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
    }

    // Background cache filling/refreshing, throttled and skipped in the
    // WorkManager isolate.
    final policy = warmupPolicy;
    if (policy == null || policy.shouldRunAutomatically()) {
      unawaited(
        warmup.run().then((completed) async {
          if (completed) await policy?.markCompleted();
        }),
      );
    } else {
      debugPrint('[Repo] Skipping automatic cache warm-up (throttled).');
    }
  }

  /// Drops the cache when the app language changed since it was filled, then
  /// re-runs the warm-up. Concurrent calls share one run.
  Future<bool> applyLanguageChange() {
    return _languageChange ??= _applyLanguageChange().whenComplete(
      () => _languageChange = null,
    );
  }

  Future<bool> _applyLanguageChange() async {
    await ensureInitialized();
    if (!await _dropStaleLanguageCache()) return false;
    // Re-fetch saved items so their titles come back in the new language.
    unawaited(warmup.run());
    return true;
  }

  /// Clears the TMDB cache if it was filled in another language than the
  /// current one. Returns whether it was cleared.
  Future<bool> _dropStaleLanguageCache() async {
    final locale = localeService;
    if (locale == null || !locale.isCacheLanguageStale) return false;
    debugPrint(
      '[Repo] Cache language differs from ${locale.tmdbLanguage}; clearing.',
    );
    warmup.cancel();
    await cache.clearAll();
    await locale.markCacheLanguage();
    return true;
  }
}
