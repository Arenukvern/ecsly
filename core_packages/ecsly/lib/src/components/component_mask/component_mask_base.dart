// ignore_for_file: sort_constructors_first

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../errors/ecs_errors.dart';
import '../component.dart';

abstract interface class ComponentMask {
  ComponentMask({this.maxComponents = 256});
  final int maxComponents;
  TypedDataList<int> get bits;
  Iterable<ComponentId> get componentIds;
  int get length => bits.length;
  int get wordSize;
  void clear(final ComponentId id);
  bool contains(final ComponentMask other);
  ComponentMask copy();
  int getWord(final int index);
  bool has(final ComponentId id);
  ComponentMask intersection(final ComponentMask other);
  bool intersects(final ComponentMask other);
  void set(final ComponentId id);
  void setWord(final int index, final int value);
  ComponentMask union(final ComponentMask other);
}

/// Base class for ComponentMask implementations.
/// Provides common logic for bitmask operations.
@reopen
@immutable
abstract class ComponentMaskBase extends ComponentMask {
  /// Create an empty mask with default capacity for 256 components
  ComponentMaskBase({
    required this.factory,
    required this.bits,
    super.maxComponents,
  });
  final ComponentMask Function({required int maxComponents}) factory;

  /// Internal storage: each Uint64 holds 64 bits
  /// For 256 components, we need 4 Uint64s
  @override
  final TypedDataList<int> bits;

  /// Get an iterable of all ComponentIds that are set in this mask.
  /// Optimized to iterate only set bits (O(popcount) instead of O(maxComponents)).
  @override
  Iterable<ComponentId> get componentIds sync* {
    for (int wordIndex = 0; wordIndex < length; wordIndex++) {
      var word = getWord(wordIndex);
      if (word == 0) continue; // Skip empty words (O(popcount) optimization)

      // Extract set bits using bit manipulation: O(popcount) per word
      // word & -word gives the lowest set bit, word & (word - 1) clears it
      while (word != 0) {
        // Get the lowest set bit as a power of 2
        final lowestBit = word & -word;

        // Find bit position: lowestBit is a power of 2 (2^bitIndex)
        // bitLength gives the number of bits needed, so bitLength - 1 gives the exponent
        final bitIndex = lowestBit.bitLength - 1;

        final componentIdValue = wordIndex * wordSize + bitIndex;

        // Check if within valid range (0-255)
        if (componentIdValue <= ComponentId.maxValue) {
          yield ComponentId(componentIdValue);
        }

        // Clear the lowest set bit
        word &= word - 1;
      }
    }
  }

  /// Hash code based on bit values
  @override
  int get hashCode {
    var hash = 0;
    for (int i = 0; i < length; i++) {
      hash = (hash * 31 + getWord(i).hashCode) & 0x3FFFFFFF;
    }
    return hash;
  }

  @override
  int get length => bits.length;

  /// Word size in bits - implemented by subclasses
  @override
  int get wordSize;

  /// Equality check
  @override
  bool operator ==(final Object other) {
    if (other is! ComponentMaskBase) return false;
    final minLength = length < other.length ? length : other.length;
    for (int i = 0; i < minLength; i++) {
      if (getWord(i) != other.getWord(i)) return false;
    }
    // Check remaining words are all zero
    if (length > other.length) {
      for (int i = minLength; i < length; i++) {
        if (getWord(i) != 0) return false;
      }
    } else if (other.length > length) {
      for (int i = minLength; i < other.length; i++) {
        if (other.getWord(i) != 0) return false;
      }
    }
    return true;
  }

  /// Clear bit for component ID
  @override
  void clear(final ComponentId id) {
    assert(id.isValid, 'ComponentId $id is not valid');
    final wordIndex = id.value ~/ wordSize;
    final bitIndex = id.value % wordSize;
    if (wordIndex >= length) {
      return; // Already clear if out of bounds
    }
    setWord(wordIndex, getWord(wordIndex) & ~(1 << bitIndex));
  }

  /// Check if this mask contains all components in another mask
  @override
  bool contains(final ComponentMask other) {
    final minLength = length < other.length ? length : other.length;
    for (int i = 0; i < minLength; i++) {
      if ((getWord(i) & other.getWord(i)) != other.getWord(i)) {
        return false;
      }
    }
    // If other mask has more words, check they're all zero
    for (int i = minLength; i < other.length; i++) {
      if (other.getWord(i) != 0) return false;
    }
    return true;
  }

  /// Create a copy of this mask
  @override
  ComponentMask copy() {
    final copy = factory.call(maxComponents: bits.length * wordSize);
    for (int i = 0; i < bits.length; i++) {
      copy.bits[i] = bits[i];
    }
    return copy;
  }

  @override
  int getWord(final int index) => bits[index];

  /// Check if component ID is set
  @override
  bool has(final ComponentId id) {
    if (!id.isValid) return false;
    final wordIndex = id.value ~/ wordSize;
    final bitIndex = id.value % wordSize;
    if (wordIndex >= length) return false;
    return (getWord(wordIndex) & (1 << bitIndex)) != 0;
  }

  /// Intersection of two masks (creates new mask)
  @override
  ComponentMask intersection(final ComponentMask other) {
    final minLength = length < other.length ? length : other.length;
    final result = factory.call(maxComponents: minLength * wordSize);
    for (int i = 0; i < minLength; i++) {
      result.bits[i] = bits[i] & other.bits[i];
    }
    return result;
  }

  /// Check if this mask intersects with another mask
  @override
  bool intersects(final ComponentMask other) {
    final minLength = length < other.length ? length : other.length;
    for (int i = 0; i < minLength; i++) {
      if ((getWord(i) & other.getWord(i)) != 0) {
        return true;
      }
    }
    return false;
  }

  /// Set bit for component ID
  @override
  void set(final ComponentId id) {
    assert(id.isValid, 'ComponentId $id is not valid');
    final wordIndex = id.value ~/ wordSize;
    final bitIndex = id.value % wordSize;
    if (wordIndex >= length) {
      throw EcsStateError(
        'ComponentId $id exceeds mask capacity (${length * wordSize} components)',
      );
    }
    setWord(wordIndex, getWord(wordIndex) | (1 << bitIndex));
  }

  @override
  void setWord(final int index, final int value) => bits[index] = value;

  /// String representation for debugging
  @override
  String toString() {
    final components = <int>[];
    for (int i = 0; i < length; i++) {
      for (int bit = 0; bit < wordSize; bit++) {
        final componentId = i * wordSize + bit;
        if (componentId > ComponentId.maxValue) break;
        if ((getWord(i) & (1 << bit)) != 0) {
          components.add(componentId);
        }
      }
    }
    if (components.isEmpty) {
      return 'ComponentMask(empty)';
    }
    return 'ComponentMask(${components.join(", ")})';
  }

  /// Union of two masks (creates new mask)
  @override
  ComponentMask union(final ComponentMask other) {
    final maxLength = bits.length > other.bits.length
        ? bits.length
        : other.bits.length;
    final result = factory.call(maxComponents: maxLength * wordSize);
    final minLength = bits.length < other.bits.length
        ? bits.length
        : other.bits.length;
    for (int i = 0; i < minLength; i++) {
      result.bits[i] = bits[i] | other.bits[i];
    }
    // Copy remaining words from longer mask
    if (bits.length > other.bits.length) {
      for (int i = minLength; i < bits.length; i++) {
        result.bits[i] = bits[i];
      }
    } else if (other.bits.length > bits.length) {
      for (int i = minLength; i < other.bits.length; i++) {
        result.bits[i] = other.bits[i];
      }
    }
    return result;
  }
}
