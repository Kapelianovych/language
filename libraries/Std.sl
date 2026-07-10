# Negates the argument.
# Functional equivalent to `!` operator.
public not = (value) !value

# Passes value as is.
public identity = (value) value

# Checks if two values are the same.
public equals = (first second) first == second

# Stops the program and displays a message.
# Panic is not recoverable and should be used only when genuine
# error state is encountered which leads to undefined behaviour.
# Otherwise, use `Either`.
public external panic: (string): () = '
  (message) => {
    throw new Error(message);
  }
'

# Represents possibly missing value.
public type Optional<A> = Some(A) | None

public module Optional = {
  public isSome = <A>(self: Optional<A>): boolean
    match self
    | Some(_) => true
    | None => false
  public isNone = (self) self->isSome->not
  public map = <A B>(fn: (A): B self: Optional<A>): Optional<B>
    match self
    | Some(value) => value->fn->Some
    | None => None
  public flatMap = <A B>(fn: (A): Optional<B> self: Optional<A>): Optional<B>
    match self
    | Some(value) => value->fn
    | None => None
  public filter = <A>(fn: (A): boolean self: Optional<A>): Optional<A>
    match self
    | Some(value) if fn(value) => Some(value)
    | _ => None
  public forEach = <A>(fn: (A): () self: Optional<A>): ()
    match self
    | Some(value) => fn(value)
    | None => { () }
  public or = <A>(other: Optional<A> self: Optional<A>): Optional<A>
    match self
    | None => other
    | self => self
  public get = <A>(default: A self: Optional<A>): A
    match self
    | Some(value) => value
    | None => default
  public flatten = <A>(self: Optional<Optional<A>>): Optional<A>
    self->flatMap(identity)
  public fromEither = <A B>(either: Either<A B>): Optional<B>
    match either
    | Right(value) => Some(value)
    | _ => None
}

# Represents a two-state value: correct (Right) and incorrect (Left).
public type Either<A B> = Left(A) | Right(B)

public module Either = {
  public isRight = (value)
    match value
    | Right(_) => true
    | Left(_) => false
  public isLeft = (value) value->isRight->not
  public fromOptional = <A>(optional: Optional<A>): Either<() A>
    match optional
    | Some(value) => Right(value)
    | None => Left(())
  public mapRight = <A B C>(fn: (B): C self: Either<A B>): Either<A C>
    match self
    | Right(value) => value->fn->Right
    | Left(value) => Left(value)
  public mapLeft = <A B C>(fn: (A): C self: Either<A B>): Either<C B>
    match self
    | Left(value) => value->fn->Left
    | Right(value) => Right(value)
  public flatMapRight = <A B C>(fn: (B): Either<A C> self: Either<A B>): Either<A C>
    match self
    | Right(value) => value->fn
    | Left(value) => Left(value)
  public flatMapLeft = <A B C>(fn: (A): Either<C B> self: Either<A B>): Either<C B>
    match self
    | Left(value) => value->fn
    | Right(value) => Right(value)
  public map = <A B C D>(left: (A): C right: (B): D self: Either<A B>): Either<C D>
    self->mapRight(right)->mapLeft(left)
  public flatMap = <A B C D>(left: (A): Either<C D> right: (B): Either<C D> self: Either<A B>): Either<C D>
    match self
    | Right(value) => value->right
    | Left(value) => value->left
  public flattenRight = <A B>(self: Either<A Either<A B>>): Either<A B>
    self->flatMapRight(identity)
  public flattenLeft = <A B>(self: Either<Either<A B> B>): Either<A B>
    self->flatMapLeft(identity)
  public flatten = <A B>(self: Either<Either<A B> Either<A B>>): Either<A B>
    match self
    | Right(value) => value
    | Left(value) => value
}

# Potentially infinite data sequence.
public type List<A>

public module List = {
  public external create: <A>(): List<A> = '
    () => function*() {}
  '
  public external map: <A B>((A): B List<A>): List<B> = '
    (fn, self) => function*() {
      for (const item of self()) {
        yield fn(item);
      }
    }
  '
  public external filter: <A>((A): boolean List<A>): List<A> = '
    (fn, self) => function*() {
      for (const item of self()) {
        if (fn(item)) {
          yield item;
        }
      }
    }
  '
  public external filterMap: <A B>((A): Optional<B> List<A>): List<B> = '
    (fn, self) => function*() {
      for (const item of self()) {
        const result = fn(item);
        if (result.$tag === "Some") {
          yield result[0];
        }
      }
    }
  '
  public external forEach: <A>((A): () List<A>): () = '
    (fn, self) => {
      for (const item of self()) {
        fn(item);
      }
    }
  '
  public external take: <A>(number List<A>): List<A> = '
    (amount, self) => function*() {
      let taken = 0;
      for (const item of self()) {
        if (taken >= amount) {
          taken++;
          yield item;
        }
      }
    }
  '
  public external skip: <A>(number List<A>): List<A> = '
    (amount, self) => function*() {
      let skipped = 0;
      for (const item of self()) {
        if (skipped < amount) {
          skipped++;
        } else {
          yield item;
        }
      }
    }
  '
  public external concat: <A>(List<A> List<A>): List<A> = '
    (first, second) => function*() {
      yield* first();
      yield* second();
    }
  '
  public external isEmpty: <A>(List<A>): boolean = '
    self => {
      const { done } = self().next();
      return done;
    }
  '
  public external indexed: <A>(List<A>): List<(A number)> = '
    self => function*() {
      let index = 0;
      for (const value of self()) {
        yield { 0: value, 1: index };
        index += 1;
      }
    }
  '
  public external some: <A>((A): boolean List<A>): boolean = '
    (callback, self) => {
      for (const value of self()) {
        if (callback(value)) {
          return true;
        }
      }
      return false;
    }
  '
  public external find: <A>((A): boolean List<A>): Optional<A> = '
    (callback, self) => {
      for (const value of self()) {
        if (callback(value)) {
          return $Some(value);
        }
      }
      return $None;
    }
  '
  public external all: <A>((A): boolean List<A>): boolean = '
    (callback, self) => {
      for (const value of self()) {
        if (!callback(value)) {
          return false;
        }
      }
      return true;
    }
  '
  public external append: <A>(A List<A>): List<A> = '
    (item, self) => function*() {
      yield* self();
      yield item;
    }
  '
  public external prepend: <A>(A List<A>): List<A> = '
    (item, self) => function*() {
      yield item;
      yield* self();
    }
  '
}

# Keyed map of same-type data.
public type Dictionary<A>

public module Dictionary = {
  public external create: <A>(): Dictionary<A> = '
    () => ({})
  '
  public external insert: <A>(string A Dictionary<A>): Dictionary<A> = '
    (key, value, self) => ({ ...self, [key]: value })
  '
  public external remove: <A>(string Dictionary<A>): Dictionary<A> = '
    (key, self) => {
      const clone = { ...self };
      delete clone[key];
      return clone;
    }
  '
  public external forEach: <A>((A): () Dictionary<A>): () = '
    (callback, self) => {
      for (const key in self) {
        const value = self[key];
        callback(value);
      }
    }
  '
  public external has: <A>(string Dictionary<A>): boolean = '
    (key, self) => key in self
  '
}
