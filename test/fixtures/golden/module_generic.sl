public module Box<T> = {
  public wrap = (x: T): T x
}

public a = Box.wrap(5)
public b = Box.wrap(true)
