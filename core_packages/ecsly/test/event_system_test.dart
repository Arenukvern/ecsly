// ignore_for_file: cascade_invocations

import 'dart:typed_data';

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

void main() {
  group('Event System', () {
    late World world;

    setUp(() {
      world = World();
    });

    test('can register and use event channels', () {
      // Register event channel with TypedData factory
      world.events.register<DamageEvent>(
        capacity: 10,
        fromDoubleFieldsFactory: (final fields) => DamageEvent(
          targetEntity: fields[0].toInt(),
          sourceEntity: fields[1].toInt(),
          amount: fields[2],
        ),
        sampleEvent: DamageEvent(targetEntity: 0, sourceEntity: 0, amount: 0),
      );

      // Get writer and send event
      final writer = world.events.writer<DamageEvent>();
      final success = writer.trySend(
        DamageEvent(targetEntity: 1, sourceEntity: 2, amount: 25),
      );

      expect(success, isTrue);

      // Get reader and check event
      final reader = world.events.reader<DamageEvent>();
      expect(reader.isNotEmpty, isTrue);
      expect(reader.length, equals(1));

      // Read the event
      final events = <DamageEvent>[];
      reader.forEach(events.add);
      expect(events.length, equals(1));
      expect(events[0].targetEntity, equals(1));
      expect(events[0].sourceEntity, equals(2));
      expect(events[0].amount, equals(25.0));
    });

    test('handles capacity overflow with drop policy', () {
      world.events.register<DamageEvent>(
        capacity: 2,
        fromDoubleFieldsFactory: (final fields) => DamageEvent(
          targetEntity: fields[0].toInt(),
          sourceEntity: fields[1].toInt(),
          amount: fields[2],
        ),
        sampleEvent: DamageEvent(targetEntity: 0, sourceEntity: 0, amount: 0),
      );

      final writer = world.events.writer<DamageEvent>();

      // Fill to capacity
      expect(
        writer.trySend(
          DamageEvent(targetEntity: 1, sourceEntity: 2, amount: 10),
        ),
        isTrue,
      );
      expect(
        writer.trySend(
          DamageEvent(targetEntity: 3, sourceEntity: 4, amount: 20),
        ),
        isTrue,
      );

      // Next event should be dropped
      expect(
        writer.trySend(
          DamageEvent(targetEntity: 5, sourceEntity: 6, amount: 30),
        ),
        isFalse,
      );

      // Should still have 2 events
      final reader = world.events.reader<DamageEvent>();
      expect(reader.length, equals(2));
    });

    test('clears events after frame', () {
      world.events.register<DamageEvent>(
        fromDoubleFieldsFactory: (final fields) => DamageEvent(
          targetEntity: fields[0].toInt(),
          sourceEntity: fields[1].toInt(),
          amount: fields[2],
        ),
        sampleEvent: DamageEvent(targetEntity: 0, sourceEntity: 0, amount: 0),
      );

      final writer = world.events.writer<DamageEvent>();
      writer.send(DamageEvent(targetEntity: 1, sourceEntity: 2, amount: 15));

      expect(world.events.reader<DamageEvent>().isNotEmpty, isTrue);

      // Clear events (simulating end of frame)
      world.events.clearAll();

      expect(world.events.reader<DamageEvent>().isEmpty, isTrue);
    });

    test('requires explicit registration', () {
      // Don't pre-register channel
      expect(world.resources.has<EventChannel<DamageEvent>>(), isFalse);

      // Accessing writer without registration should throw
      expect(
        () => world.events.writer<DamageEvent>(),
        throwsA(isA<EventNotRegisteredException<DamageEvent>>()),
      );

      // Accessing reader without registration should throw
      expect(
        () => world.events.reader<DamageEvent>(),
        throwsA(isA<EventNotRegisteredException<DamageEvent>>()),
      );

      // After explicit registration, it should work
      world.events.register<DamageEvent>(
        fromDoubleFieldsFactory: (final fields) => DamageEvent(
          targetEntity: fields[0].toInt(),
          sourceEntity: fields[1].toInt(),
          amount: fields[2],
        ),
        sampleEvent: DamageEvent(targetEntity: 0, sourceEntity: 0, amount: 0),
      );
      final writer = world.events.writer<DamageEvent>();
      writer.send(DamageEvent(targetEntity: 1, sourceEntity: 2, amount: 10));
      final reader = world.events.reader<DamageEvent>();
      expect(reader.length, equals(1));
    });

    test('hasRegistered returns correct state', () {
      // Initially not registered
      expect(world.events.hasRegistered<DamageEvent>(), isFalse);

      // After registration
      world.events.register<DamageEvent>(
        fromDoubleFieldsFactory: (final fields) => DamageEvent(
          targetEntity: fields[0].toInt(),
          sourceEntity: fields[1].toInt(),
          amount: fields[2],
        ),
        sampleEvent: DamageEvent(targetEntity: 0, sourceEntity: 0, amount: 0),
      );
      expect(world.events.hasRegistered<DamageEvent>(), isTrue);

      // After unregistration
      world.events.unregister<DamageEvent>();
      expect(world.events.hasRegistered<DamageEvent>(), isFalse);
    });

    test('unregister removes event channel', () {
      // Register and send event
      world.events.register<DamageEvent>(
        fromDoubleFieldsFactory: (final fields) => DamageEvent(
          targetEntity: fields[0].toInt(),
          sourceEntity: fields[1].toInt(),
          amount: fields[2],
        ),
        sampleEvent: DamageEvent(targetEntity: 0, sourceEntity: 0, amount: 0),
      );
      final writer = world.events.writer<DamageEvent>();
      writer.send(DamageEvent(targetEntity: 1, sourceEntity: 2, amount: 10));
      expect(world.events.reader<DamageEvent>().length, equals(1));

      // Unregister should clear and remove
      world.events.unregister<DamageEvent>();

      // Should not be registered anymore
      expect(world.events.hasRegistered<DamageEvent>(), isFalse);

      // Accessing reader/writer should throw again
      expect(
        () => world.events.reader<DamageEvent>(),
        throwsA(isA<EventNotRegisteredException<DamageEvent>>()),
      );
      expect(
        () => world.events.writer<DamageEvent>(),
        throwsA(isA<EventNotRegisteredException<DamageEvent>>()),
      );
    });

    test('iterSimd provides SIMD access for FloatColumn events', () {
      world.events.register<VectorEvent>(
        fromDoubleFieldsFactory: (final fields) =>
            VectorEvent(x: fields[0], y: fields[1], z: fields[2], w: fields[3]),
        sampleEvent: VectorEvent(x: 0, y: 0, z: 0, w: 0),
      );

      final writer = world.events.writer<VectorEvent>();
      writer.send(VectorEvent(x: 1, y: 2, z: 3, w: 4));
      writer.send(VectorEvent(x: 5, y: 6, z: 7, w: 8));

      final reader = world.events.reader<VectorEvent>();
      final simdIter = reader.iterSimd();

      // VectorEvent has 4 double fields, so stride is 4, which is divisible by 4
      // Therefore SIMD should be available
      expect(simdIter, isNotNull);

      // Test SIMD iteration
      final fieldsList = simdIter!.toList();
      expect(fieldsList.length, equals(2)); // 2 events
      expect(fieldsList[0].length, equals(4)); // 4 fields per event
      expect(fieldsList[0][0], equals(1.0)); // x value
      expect(fieldsList[0][1], equals(2.0)); // y value
      expect(fieldsList[0][2], equals(3.0)); // z value
      expect(fieldsList[0][3], equals(4.0)); // w value
    });

    test('EventFactoryValidationError is thrown for invalid factory', () {
      expect(
        () => world.events.register<DamageEvent>(
          fromDoubleFieldsFactory: (final fields) => DamageEvent(
            // Intentionally wrong: mixing up field order
            targetEntity: fields[2].toInt(), // Should be fields[0]
            sourceEntity: fields[0].toInt(), // Should be fields[1]
            amount: fields[1], // Should be fields[2]
          ),
          sampleEvent: DamageEvent(targetEntity: 1, sourceEntity: 2, amount: 3),
        ),
        throwsA(isA<EventFactoryValidationError>()),
      );
    });

    test('EventTrigger runs schedule only when events exist', () {
      var executionCount = 0;
      void testSystem(final World world) {
        executionCount++;
      }

      // Register event channel first
      world.events.register<DamageEvent>(
        fromDoubleFieldsFactory: (final fields) => DamageEvent(
          targetEntity: fields[0].toInt(),
          sourceEntity: fields[1].toInt(),
          amount: fields[2],
        ),
        sampleEvent: DamageEvent(targetEntity: 0, sourceEntity: 0, amount: 0),
      );

      // Create schedule with EventTrigger
      final schedule = Schedule(
        'EventDriven',
        trigger: const EventTrigger<DamageEvent>(),
      )..add(testSystem);

      // Initially no events - schedule should not run
      schedule.run(world);
      expect(executionCount, equals(0));

      // Send an event
      world.events.writer<DamageEvent>().send(
        DamageEvent(targetEntity: 1, sourceEntity: 2, amount: 10),
      );

      // Now schedule should run
      schedule.run(world);
      expect(executionCount, equals(1));

      // Clear events
      world.events.clearAll();

      // Schedule should not run again
      schedule.run(world);
      expect(executionCount, equals(1)); // Still 1, not incremented
    });

    test(
      'EventTrigger throws EventTriggerValidationError for unregistered events',
      () {
        // Create trigger without registering the event channel
        const trigger = EventTrigger<DamageEvent>();

        // Trigger should throw EventTriggerValidationError when executed
        expect(
          () => trigger.shouldRun(world),
          throwsA(isA<EventTriggerValidationError>()),
        );
      },
    );

    test('resources remain single source of truth after cache removal', () {
      // Register event
      world.events.register<DamageEvent>(
        fromDoubleFieldsFactory: (final fields) => DamageEvent(
          targetEntity: fields[0].toInt(),
          sourceEntity: fields[1].toInt(),
          amount: fields[2],
        ),
        sampleEvent: DamageEvent(targetEntity: 0, sourceEntity: 0, amount: 0),
      );

      // Send event
      world.events.writer<DamageEvent>().send(
        DamageEvent(targetEntity: 1, sourceEntity: 2, amount: 10),
      );

      // Verify resource exists and has event
      expect(world.resources.has<EventChannel<DamageEvent>>(), isTrue);
      expect(world.events.reader<DamageEvent>().length, equals(1));

      // Unregister
      world.events.unregister<DamageEvent>();

      // Verify resource is gone
      expect(world.resources.has<EventChannel<DamageEvent>>(), isFalse);
      expect(world.events.hasRegistered<DamageEvent>(), isFalse);

      // Accessing reader should throw
      expect(
        () => world.events.reader<DamageEvent>(),
        throwsA(isA<EventNotRegisteredException<DamageEvent>>()),
      );
    });

    test('clearAll performance with multiple event types', () {
      // Register multiple event types
      world.events.register<DamageEvent>(
        fromDoubleFieldsFactory: (final fields) => DamageEvent(
          targetEntity: fields[0].toInt(),
          sourceEntity: fields[1].toInt(),
          amount: fields[2],
        ),
        sampleEvent: DamageEvent(targetEntity: 0, sourceEntity: 0, amount: 0),
      );

      world.events.register<VectorEvent>(
        fromDoubleFieldsFactory: (final fields) =>
            VectorEvent(x: fields[0], y: fields[1], z: fields[2], w: fields[3]),
        sampleEvent: VectorEvent(x: 0, y: 0, z: 0, w: 0),
      );

      // Send events to both channels
      world.events.writer<DamageEvent>().send(
        DamageEvent(targetEntity: 1, sourceEntity: 2, amount: 10),
      );
      world.events.writer<DamageEvent>().send(
        DamageEvent(targetEntity: 3, sourceEntity: 4, amount: 20),
      );

      world.events.writer<VectorEvent>().send(
        VectorEvent(x: 1, y: 2, z: 3, w: 4),
      );

      // Verify events exist
      expect(world.events.reader<DamageEvent>().length, equals(2));
      expect(world.events.reader<VectorEvent>().length, equals(1));

      // Clear all - should clear both channels efficiently
      world.events.clearAll();

      // Verify all events are cleared
      expect(world.events.reader<DamageEvent>().length, equals(0));
      expect(world.events.reader<VectorEvent>().length, equals(0));

      // Channels should still be registered
      expect(world.events.hasRegistered<DamageEvent>(), isTrue);
      expect(world.events.hasRegistered<VectorEvent>(), isTrue);
    });

    group('Multi-World Isolation', () {
      test('TypedDataEvent registration is isolated per-world', () {
        // Create two separate worlds
        final world1 = World();
        final world2 = World();

        // Register TypedDataEvent in world1 only
        world1.events.register<DamageEvent>(
          fromDoubleFieldsFactory: (final fields) => DamageEvent(
            targetEntity: fields[0].toInt(),
            sourceEntity: fields[1].toInt(),
            amount: fields[2],
          ),
          sampleEvent: DamageEvent(targetEntity: 0, sourceEntity: 0, amount: 0),
        );

        // World1 should have the event registered
        expect(world1.events.hasRegistered<DamageEvent>(), isTrue);
        expect(world1.resources.has<EventChannel<DamageEvent>>(), isTrue);

        // World2 should not have the event registered
        expect(world2.events.hasRegistered<DamageEvent>(), isFalse);
        expect(world2.resources.has<EventChannel<DamageEvent>>(), isFalse);

        // Accessing reader in world2 should throw
        expect(
          () => world2.events.reader<DamageEvent>(),
          throwsA(isA<EventNotRegisteredException<DamageEvent>>()),
        );

        // But world1 should work fine
        final writer1 = world1.events.writer<DamageEvent>();
        writer1.send(DamageEvent(targetEntity: 1, sourceEntity: 2, amount: 10));
        expect(world1.events.reader<DamageEvent>().length, equals(1));
      });

      test(
        'different worlds can register different TypedDataEvents independently',
        () {
          final world1 = World();
          final world2 = World();

          // Register different events in each world
          world1.events.register<DamageEvent>(
            fromDoubleFieldsFactory: (final fields) => DamageEvent(
              targetEntity: fields[0].toInt(),
              sourceEntity: fields[1].toInt(),
              amount: fields[2],
            ),
            sampleEvent: DamageEvent(
              targetEntity: 0,
              sourceEntity: 0,
              amount: 0,
            ),
          );

          world2.events.register<VectorEvent>(
            fromDoubleFieldsFactory: (final fields) => VectorEvent(
              x: fields[0],
              y: fields[1],
              z: fields[2],
              w: fields[3],
            ),
            sampleEvent: VectorEvent(x: 0, y: 0, z: 0, w: 0),
          );

          // Verify isolation
          expect(world1.events.hasRegistered<DamageEvent>(), isTrue);
          expect(world1.events.hasRegistered<VectorEvent>(), isFalse);
          expect(world2.events.hasRegistered<DamageEvent>(), isFalse);
          expect(world2.events.hasRegistered<VectorEvent>(), isTrue);

          // Both worlds should work with their respective events
          world1.events.writer<DamageEvent>().send(
            DamageEvent(targetEntity: 1, sourceEntity: 2, amount: 15),
          );
          world2.events.writer<VectorEvent>().send(
            VectorEvent(x: 1, y: 2, z: 3, w: 4),
          );

          expect(world1.events.reader<DamageEvent>().length, equals(1));
          expect(world2.events.reader<VectorEvent>().length, equals(1));
        },
      );

      test('clearAll is isolated per-world', () {
        final world1 = World();
        final world2 = World();

        // Register and send events in both worlds
        world1.events.register<DamageEvent>(
          fromDoubleFieldsFactory: (final fields) => DamageEvent(
            targetEntity: fields[0].toInt(),
            sourceEntity: fields[1].toInt(),
            amount: fields[2],
          ),
          sampleEvent: DamageEvent(targetEntity: 0, sourceEntity: 0, amount: 0),
        );
        world2.events.register<DamageEvent>(
          fromDoubleFieldsFactory: (final fields) => DamageEvent(
            targetEntity: fields[0].toInt(),
            sourceEntity: fields[1].toInt(),
            amount: fields[2],
          ),
          sampleEvent: DamageEvent(targetEntity: 0, sourceEntity: 0, amount: 0),
        );

        world1.events.writer<DamageEvent>().send(
          DamageEvent(targetEntity: 1, sourceEntity: 2, amount: 10),
        );
        world2.events.writer<DamageEvent>().send(
          DamageEvent(targetEntity: 3, sourceEntity: 4, amount: 20),
        );

        expect(world1.events.reader<DamageEvent>().length, equals(1));
        expect(world2.events.reader<DamageEvent>().length, equals(1));

        // Clear world1 only
        world1.events.clearAll();

        // World1 should be cleared, world2 should remain
        expect(world1.events.reader<DamageEvent>().length, equals(0));
        expect(world2.events.reader<DamageEvent>().length, equals(1));
      });
    });
  });
}

// Test event type
class DamageEvent extends EcsEvent
    with TypedDataEventMixin
    implements TypedDataEvent {
  DamageEvent({
    required this.targetEntity,
    required this.sourceEntity,
    required this.amount,
  });

  final int targetEntity;
  final int sourceEntity;
  final double amount;

  @override
  int get numericFieldCount => 3;

  @override
  List<double> get numericFields => [
    targetEntity.toDouble(),
    sourceEntity.toDouble(),
    amount,
  ];

  @override
  void writeNumericFieldsTo(final Float32List target) {
    target[0] = targetEntity.toDouble();
    target[1] = sourceEntity.toDouble();
    target[2] = amount;
  }

  @override
  void writeNumericIntFieldsTo(final Int32List target) {
    target[0] = targetEntity;
    target[1] = sourceEntity;
    target[2] = amount.toInt();
  }
}

// Test event type with SIMD-compatible stride (4 fields)
class VectorEvent extends EcsEvent
    with TypedDataEventMixin
    implements TypedDataEvent {
  VectorEvent({
    required this.x,
    required this.y,
    required this.z,
    required this.w,
  });

  final double x;
  final double y;
  final double z;
  final double w;

  @override
  int get numericFieldCount => 4;

  @override
  List<double> get numericFields => [x, y, z, w];

  @override
  void writeNumericFieldsTo(final Float32List target) {
    target[0] = x;
    target[1] = y;
    target[2] = z;
    target[3] = w;
  }
}
