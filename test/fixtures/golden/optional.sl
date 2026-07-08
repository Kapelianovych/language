public type Optional<A> = Some(A) | None

public isSome = <A>(self: Optional<A>): boolean
  match self
  | Some(_) => true
  | None => false
