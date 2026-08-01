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

public describe = <A: Logger + Named>(x: A): number x.info(x.tag)
public result = describe(Combo)
