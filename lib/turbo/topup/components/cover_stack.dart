import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays its children over each other, later ones on top, at the size of the
/// largest, and stretches every child to that size.
///
/// The top-up dialog keeps the card form mounted under the review so Stripe
/// keeps the card details. In a [Stack] a review shorter than the form ended
/// part way down it, and the review card's bottom edge and shadow showed as
/// a line across the dialog. Stretched, the review's edge is the dialog's.
class CoverStack extends MultiChildRenderObjectWidget {
  const CoverStack({super.key, required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderCoverStack();
}

class CoverStackParentData extends ContainerBoxParentData<RenderBox> {}

class RenderCoverStack extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, CoverStackParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, CoverStackParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! CoverStackParentData) {
      child.parentData = CoverStackParentData();
    }
  }

  @override
  void performLayout() {
    var width = 0.0;
    var height = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(constraints.loosen(), parentUsesSize: true);
      width = math.max(width, child.size.width);
      height = math.max(height, child.size.height);
    }
    size = constraints.constrain(Size(width, height));
    final stretched = BoxConstraints.tight(size);
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (child.size != size) child.layout(stretched);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
