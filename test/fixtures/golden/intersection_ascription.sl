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

public useAsLogger = (x: Logger) x.info(1)
public useAsNamed = (x: Named) x.tag
public r1 = useAsLogger(Combo)
public r2 = useAsNamed(Combo)
