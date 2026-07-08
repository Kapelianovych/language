# Negates the argument.
# Functional equivalent to `!` operator.
public not = (value) !value

# Passes value as is.
public identity = (value) value

# Stops the program and displays a message.
# Panic is not recoverable and should be used only when genuine
# error state is encountered which leads to undefined behaviour.
# Otherwise, use `Either`.
public external panic: (string): () = '
  (message) => {
    throw new Error(message);
  }
'

# Maps to ECMAScript's "nullish" type - `T | null | undefined`.
# Provided only for compatibility, use `Optional` instead.
public type Nullish<A>

public module Nullish = {
  public external of: <A>(A): Nullish<A> = 'value => value'
  public external null: <A>(): Nullish<A> = '() => null'
  public external undefined: <A>(): Nullish<A> = '() => undefined'
  public external is: <A>(Nullish<A>): boolean = 'self => self == null'
  public external castOrPanic: <A>(Nullish<A>): A = '
    self => {
      if (self == null) {
        throw new Error("Cannot extract value from Nullish type since there is no value.");
      } else {
        return self;
      }
    }
  '
  public fromOptional = <A>(optional: Optional<A>): Nullish<A>
    match optional
    | Some(value) => of(value)
    | None => undefined()
}

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
  public fromNullish = <A>(value: Nullish<A>): Optional<A>
    match value
    | value if Nullish.is(value) => None
    | value => Some(Nullish.castOrPanic(value))
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
