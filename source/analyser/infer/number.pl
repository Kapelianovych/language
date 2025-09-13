:- module(number, [infer_number/4]).

infer_number(
  Number,
  InferenceState,
  InferenceState,
  inferred([], [], type_constant(number(Number)))
).
