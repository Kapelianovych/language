public type Incrementer = {
  bump: (number): number
}

opaque module Counter: Incrementer = {
  public bump = (n) n + 1
}

public main = Counter.bump(5)
