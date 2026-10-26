import 'package:meta/meta.dart';
import 'package:universal_storage_world/universal_storage_world.dart';

/// Interest policies for zone travel (ADR 0003 §2; the contract is
/// ADR 0048). Positions and zone membership are GAME knowledge — they
/// live here, never in the storage family. The sync layer only ever sees
/// the resolved [InterestSelection].

/// Subscribe to every member of a zone census (the catalog doc's own
/// member list — ADR 0047 §2). Re-resolved every pulse, so a zone that
/// grows re-subscribes without protocol change.
///
/// The typical journey: subscribe to the catalog FIRST (a
/// [StaticInterestPolicy] or prefix), read it, then hand it here to
/// subscribe to its members and warm them.
final class ZoneCatalogInterest implements InterestPolicy {
  ZoneCatalogInterest(this._readCatalog);

  /// Reads the current census — usually `ZoneCatalogCodec.decode(doc)`
  /// over the zone's catalog member.
  final ZoneCatalog? Function() _readCatalog;

  @override
  InterestSelection resolve() {
    final catalog = _readCatalog();
    if (catalog == null) return const InterestSelection.none();
    return InterestSelection(docIds: catalog.memberDocIds());
  }
}

/// Spatial interest: membership is whatever the game's query says right
/// now (entities within a radius, a room's contents, a fleet's assets).
/// The storage family never learns coordinates; this is the ONLY seam a
/// game needs to make the mesh a relevancy filter.
final class SpatialInterestPolicy implements InterestPolicy {
  SpatialInterestPolicy({required Set<String> Function() membersInInterest})
    : _membersInInterest = membersInInterest;

  final Set<String> Function() _membersInInterest;

  @override
  InterestSelection resolve() =>
      InterestSelection(docIds: _membersInInterest());
}

/// The composite game policy: open surfaces PLUS the current zone PLUS
/// whatever the spatial query holds — the union is the roaming working
/// set (ADR 0047 §5's interest half).
@immutable
final class RoamingInterest implements InterestPolicy {
  const RoamingInterest({
    required this.openMembers,
    this.zone,
    this.spatial,
  });

  /// Explicitly open members (docs on screen, loaded boards).
  final Set<String> openMembers;

  /// The current zone's interest policy, when travelling inside one.
  final InterestPolicy? zone;

  /// The game's spatial policy, when the world has positions.
  final InterestPolicy? spatial;

  @override
  InterestSelection resolve() {
    var selection = InterestSelection(docIds: openMembers);
    final zonePolicy = zone;
    if (zonePolicy != null) {
      selection = selection.union(zonePolicy.resolve());
    }
    final spatialPolicy = spatial;
    if (spatialPolicy != null) {
      selection = selection.union(spatialPolicy.resolve());
    }
    return selection;
  }
}
