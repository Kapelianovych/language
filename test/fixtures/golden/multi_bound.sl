public type Logger = {
  info: (number): number
}

public type Named = {
  tag: number
}

opaque module Combo: Logger + Named = {
  public info = (n) n + 1
  public tag = 5
}

public identity = <A: Logger + Named>(x: A): A x
public result = identity(Combo)
