:- module(unicode, [unicode_character/2,
										between_unicode_range/3]).

:- use_module(library(between)).

%% between_unicode_range(+Lower, +Upper, ?Character).
%
% Checks that Character is between Lower and Upper bounds inclusively.
between_unicode_range(Lower, Upper, Character) :-
	char_code(Character, Code),
	between(Lower, Upper, Code).

%% unicode_character(?Number, ?Character).
%
% Relates the Number to the Character in Unicode table.
unicode_character(Number, Character) :-
	char_code(Character, Code),
	Number = Code.
