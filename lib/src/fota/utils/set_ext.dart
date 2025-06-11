extension SetUtil<E> on Set<E> {
  Set<E> concat(Set<E> another) {
    var copy = toSet();
    copy.addAll(another);
    return copy;
  }
}
