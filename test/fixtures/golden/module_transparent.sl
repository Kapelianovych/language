public module Counter = {
  start = 0
  public next = (n) n + 1
}

public main = Counter.next(Counter.next(5))
