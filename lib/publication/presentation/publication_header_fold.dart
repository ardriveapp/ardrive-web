/// Whether a publication root's header is folded away, so the list beneath it
/// has the window.
///
/// It folds when the list moves off its top, or when the wheel or a swipe
/// asks for more of a list that has more to show. It unfolds when the user
/// scrolls the list back to its top, or turns the wheel up or swipes down at
/// the top.
///
/// Folding makes the list taller. A short list can then fit, and Flutter
/// moves it back to its top by itself. That move is not the user's, so it
/// must not unfold the header: if it did, the list would be too short again,
/// the next scroll would fold it, and the header would flicker as fast as
/// the wheel turned.
class PublicationHeaderFold {
  bool _folded = false;
  bool _canScroll = false;
  bool _atTop = true;

  bool get folded => _folded;

  /// A folder newly shown starts with its header unfolded.
  void reset() {
    _folded = false;
    _atTop = true;
  }

  /// The list's metrics changed. [moved] is true only for a scroll that
  /// moved it. Returns whether the fold changed.
  bool onScroll({
    required double pixels,
    required double maxScrollExtent,
    required bool moved,
  }) {
    _canScroll = maxScrollExtent > 0;
    _atTop = pixels <= 0;
    if (!moved) return false;
    if (pixels > 0) return _set(true);
    // Back at the top of a list that still scrolls: the user scrolled up.
    // A list that no longer scrolls was put at its top by the fold itself.
    if (_canScroll) return _set(false);
    return false;
  }

  /// The wheel turned by [dy] (down is positive). Returns whether the fold
  /// changed.
  bool onWheel(double dy) {
    if (dy > 0 && _canScroll) return _set(true);
    if (dy < 0 && _atTop) return _set(false);
    return false;
  }

  /// A vertical swipe ended at [velocity] (up is negative). A swipe is the
  /// only way back on a phone whose list fits once the header has folded,
  /// and so never scrolls again. Returns whether the fold changed.
  bool onSwipe(double velocity) {
    if (velocity < 0 && _canScroll) return _set(true);
    if (velocity > 0 && _atTop) return _set(false);
    return false;
  }

  bool _set(bool folded) {
    if (folded == _folded) return false;
    _folded = folded;
    return true;
  }
}
