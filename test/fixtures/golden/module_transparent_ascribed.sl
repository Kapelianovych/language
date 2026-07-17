public type Adder = {
  add: (number number): number
}

public module MathOps: Adder = {
  public add = (a b) a + b
  public double = (x) x * 2
}

public main = MathOps.add(2 3)
