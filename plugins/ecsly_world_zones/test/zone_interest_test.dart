import 'package:ecsly_world_zones/ecsly_world_zones.dart';
import 'package:test/test.dart';
import 'package:universal_storage_world/universal_storage_world.dart';

void main() {
  group('ZoneCatalogInterest', () {
    test('resolves to the catalog member set, re-read every resolve', () {
      var catalog = const ZoneCatalog(
        zoneId: 'dungeon',
        entries: [ZoneMemberEntry(docId: 'docs/a'), ZoneMemberEntry(docId: 'docs/b')],
      );
      final policy = ZoneCatalogInterest(() => catalog);

      final first = policy.resolve();
      expect(first.matchesDocId('docs/a'), isTrue);
      expect(first.matchesDocId('docs/c'), isFalse);

      // The zone grew; the next resolve re-subscribes without any
      // protocol change.
      catalog = const ZoneCatalog(
        zoneId: 'dungeon',
        entries: [
          ZoneMemberEntry(docId: 'docs/a'),
          ZoneMemberEntry(docId: 'docs/b'),
          ZoneMemberEntry(docId: 'docs/c'),
        ],
      );
      expect(policy.resolve().matchesDocId('docs/c'), isTrue);
    });

    test('a missing census resolves to none (never the wildcard by '
        'accident)', () {
      final policy = ZoneCatalogInterest(() => null);
      expect(policy.resolve().matchesDocId('anything'), isFalse);
    });
  });

  group('SpatialInterestPolicy', () {
    test('membership is whatever the game query says right now', () {
      var nearby = {'entities/1', 'entities/2'};
      final policy = SpatialInterestPolicy(membersInInterest: () => nearby);

      expect(policy.resolve().matchesDocId('entities/1'), isTrue);
      nearby = {'entities/9'};
      expect(policy.resolve().matchesDocId('entities/1'), isFalse);
      expect(policy.resolve().matchesDocId('entities/9'), isTrue);
    });
  });

  group('RoamingInterest', () {
    test('unions open members, the zone, and the spatial query', () {
      final policy = RoamingInterest(
        openMembers: {'docs/open'},
        zone: MemberPrefixInterest({'sectors/dungeon/'}),
        spatial: SpatialInterestPolicy(membersInInterest: () => {'entities/3'}),
      );
      final selection = policy.resolve();
      expect(selection.matchesDocId('docs/open'), isTrue);
      expect(selection.matchesDocId('sectors/dungeon/room-1'), isTrue);
      expect(selection.matchesDocId('entities/3'), isTrue);
      expect(selection.matchesDocId('sectors/forest/x'), isFalse);
    });

    test('absent zone and spatial legs degrade to the open set', () {
      const policy = RoamingInterest(openMembers: {'docs/open'});
      final selection = policy.resolve();
      expect(selection.matchesDocId('docs/open'), isTrue);
      expect(selection.matchesDocId('anything/else'), isFalse);
    });
  });
}
