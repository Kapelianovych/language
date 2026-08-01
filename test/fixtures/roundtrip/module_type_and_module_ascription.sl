public type Logger = {
  info: (string): ()
}

opaque module ConsoleLogger: Logger = {
  public info = (message) ()
}

public module Optional = {
  public isSome = (self) true
}

type Empty = {}
