:- module(boolean, [infer_boolean/4]).

infer_boolean(
  Boolean,
  InferenceState,
  InferenceState,
  inferred([], [], type_constant(boolean(Boolean)))
).
