import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediavore/core/domain/entities/media_item.dart';
import 'package:mediavore/features/search/data/repositories/media_repository_impl.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockMediaRemoteDataSource remote;
  late MockMediaListLocalDataSource local;
  late MockMediaCache cache;

  setUpAll(() {
    registerFallbackValue(MediaType.movie);
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    remote = MockMediaRemoteDataSource();
    local = MockMediaListLocalDataSource();
    cache = MockMediaCache();
    when(() => local.getAllListNames()).thenAnswer((_) async => []);
    when(() => local.isLiked(any(), any())).thenAnswer((_) async => true);
    when(() => local.getQuickAddItems()).thenAnswer((_) async => []);
    when(() => cache.getItems(any())).thenAnswer((_) async => []);
  });

  group('MediaRepositoryImpl initialization', () {
    test('should hold delegated calls until the cache is open', () async {
      final opened = Completer<void>();
      when(() => cache.init()).thenAnswer((_) => opened.future);
      // Keep the automatic warm-up from running in this test.
      when(() => local.getAllSeenItems()).thenAnswer((_) async => []);
      when(() => local.getLikedItems()).thenAnswer((_) async => []);
      when(() => local.getNotifiedItems()).thenAnswer((_) async => []);
      when(
        () => cache.cleanup(
          keepKeys: any(named: 'keepKeys'),
          olderThan: any(named: 'olderThan'),
        ),
      ).thenAnswer((_) async {});

      final repository = MediaRepositoryImpl(
        remoteDataSource: remote,
        localDataSource: local,
        cache: cache,
      );

      var liked = false;
      var quickAdd = false;
      unawaited(
        repository.isLiked(1, MediaType.movie).then((_) => liked = true),
      );
      unawaited(repository.getQuickAddItems().then((_) => quickAdd = true));
      await pumpEventQueue();
      expect(liked, isFalse);
      expect(quickAdd, isFalse);
      verifyNever(() => local.getQuickAddItems());

      opened.complete();
      await pumpEventQueue();
      expect(liked, isTrue);
      expect(quickAdd, isTrue);
    });

    test('should not open the cache when autoInit is off', () async {
      final repository = MediaRepositoryImpl(
        remoteDataSource: remote,
        localDataSource: local,
        cache: cache,
        autoInit: false,
      );

      expect(await repository.isLiked(1, MediaType.movie), isTrue);
      verifyNever(() => cache.init());
    });
  });
}
