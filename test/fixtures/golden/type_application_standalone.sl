public module Box<T> = {
  public wrap = (x: T): T x
}

public specialized = Box<number>
public direct = Box<number>.wrap(5)
public result = specialized.wrap(5)
