public type Container<T> = {
  wrap: (T): T
  unwrap: (T): T
}

opaque module Box<T>: Container<T> = {
  public wrap = (x) x
  public unwrap = (x) x
}

public r1 = Box.wrap(5)
public r2 = Box.unwrap(true)
