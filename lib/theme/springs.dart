import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// Spring system — §6 Animation Language. Shape's animation is physics-based,
/// not duration-based. These map 1:1 to the spec's three named springs and are
/// used both as [SpringDescription] (for `AnimationController.animateWith`) and
/// as approximate [Curve]s where implicit animations are convenient.
class ShapeSprings {
  ShapeSprings._();

  /// Orb expand, halo appear. ~220ms.
  static const snappy =
      SpringDescription(mass: 1.0, stiffness: 400, damping: 32);

  /// Sheet slide-up, menu reveal. ~340ms.
  static const responsive =
      SpringDescription(mass: 1.0, stiffness: 280, damping: 28);

  /// Property value update, tooltip fade. ~480ms.
  static const gentle =
      SpringDescription(mass: 1.0, stiffness: 180, damping: 24);
}

/// A [Curve] backed by a [SpringSimulation], so implicit-animation widgets
/// (AnimatedScale, AnimatedSlide, ...) can share the exact spring physics from
/// [ShapeSprings] instead of a bezier approximation.
class SpringCurve extends Curve {
  SpringCurve(this.spring, {double velocity = 0})
      : _sim = SpringSimulation(spring, 0, 1, velocity);

  final SpringDescription spring;
  final SpringSimulation _sim;

  @override
  double transformInternal(double t) {
    // Sample the simulation across a normalised ~1s window. Spring durations
    // in the spec all settle well under one second.
    return _sim.x(t) + (1 - _sim.x(1.0)) * t;
  }
}

final snappyCurve = SpringCurve(ShapeSprings.snappy);
final responsiveCurve = SpringCurve(ShapeSprings.responsive);
final gentleCurve = SpringCurve(ShapeSprings.gentle);
