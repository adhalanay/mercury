%-----------------------------------------------------------------------------%
% Copyright (C) 1995-2000,2002-2003 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% file: special_pred.m
% main author: fjh

% Certain predicates are implicitly defined for every type by the compiler.
% This module defines most of the characteristics of those predicates.
% (The actual code for these predicates is generated in unify_proc.m.)

%-----------------------------------------------------------------------------%

:- module hlds__special_pred.
:- interface.

:- import_module hlds__hlds_data.
:- import_module hlds__hlds_module.
:- import_module hlds__hlds_pred.
:- import_module parse_tree__prog_data.

:- import_module list, map, std_util.

:- type special_pred_map	==	map(special_pred, pred_id).

:- type special_pred		==	pair(special_pred_id, type_ctor).

:- type special_pred_id
	--->	unify
	;	index
	;	compare.

	% Return the predicate name we should use for the given special_pred
	% for the given type constructor.
:- func special_pred_name(special_pred_id, type_ctor) = string.

	% This predicate always returns determinism `semidet' for 
	% unification procedures.  For types with only one value, the 
	% unification is actually `det', however we need to pretend it
	% is `semidet' so that it can be called correctly from the 
	% polymorphic `unify' procedure.
:- pred special_pred_interface(special_pred_id, type, list(type),
	list(mode), determinism).
:- mode special_pred_interface(in, in, out, out, out) is det.

	% special_pred_name_arity(SpecialPredType, GenericPredName, Arity):
	%	true iff there is a special predicate of category
	%	SpecialPredType, called builtin:GenericPredName/Arity.
:- pred special_pred_name_arity(special_pred_id, string, int).
:- mode special_pred_name_arity(in, out, out) is det.
:- mode special_pred_name_arity(out, in, out) is semidet.

:- pred special_pred_mode_num(special_pred_id, int).
:- mode special_pred_mode_num(in, out) is det.

:- pred special_pred_list(list(special_pred_id)).
:- mode special_pred_list(out) is det.

	% Given a special pred id and the list of its arguments, work out
	% which argument specifies the type that this special predicate is for.
	% Note that this gets called after the polymorphism.m pass, so
	% type_info arguments may have been inserted at the start; hence we
	% find the type at a known position from the end of the list
	% (by using list__reverse).

	% Currently for most of the special predicates the type variable
	% can be found in the last type argument, except for index, for
	% which it is the second-last argument.

:- pred special_pred_get_type(special_pred_id, list(prog_var), prog_var).
:- mode special_pred_get_type(in, in, out) is semidet.

:- pred special_pred_get_type_det(special_pred_id, list(prog_var), prog_var).
:- mode special_pred_get_type_det(in, in, out) is det.

:- pred special_pred_description(special_pred_id, string).
:- mode special_pred_description(in, out) is det.

	%
	% Succeeds if the declarations and clauses for the special predicates
	% for the given type generated only when required.
	% This will succeed for imported types for which the special
	% predicates do not need typechecking.
	%
:- pred special_pred_is_generated_lazily(module_info, type_ctor).
:- mode special_pred_is_generated_lazily(in, in) is semidet.

:- pred special_pred_is_generated_lazily(module_info, type_ctor,
		hlds_type_body, import_status).
:- mode special_pred_is_generated_lazily(in, in, in, in) is semidet.

	%
	% A compiler-generated predicate only needs type checking if
	%	(a) it is a user-defined equality pred
	% or	(b) it is the unification or comparison predicate for an
	%           existially quantified type.
	%
:- pred special_pred_for_type_needs_typecheck(module_info, hlds_type_body).
:- mode special_pred_for_type_needs_typecheck(in, in) is semidet.

	% Succeed if the type can have clauses generated for
	% its special predicates. This will fail for abstract
	% types and types for which the RTTI information is
	% defined by hand.
:- pred can_generate_special_pred_clauses_for_type(module_info, type_ctor,
		hlds_type_body).
:- mode can_generate_special_pred_clauses_for_type(in, in, in) is semidet.

:- implementation.

:- import_module check_hlds__mode_util.
:- import_module check_hlds__type_util.
:- import_module libs__globals.
:- import_module libs__options.
:- import_module parse_tree__prog_util.

:- import_module bool, require.

special_pred_list([unify, index, compare]).

special_pred_name_arity(unify, "unify", 2).
special_pred_name_arity(index, "index", 2).
special_pred_name_arity(compare, "compare", 3).

	% mode num for special procs is always 0 (the first mode)
special_pred_mode_num(_, 0).

special_pred_name(unify, _TypeCtor) = "__Unify__".
special_pred_name(index, _TypeCtor) = "__Index__".
special_pred_name(compare, _TypeCtor) = "__Compare__".

special_pred_interface(unify, Type, [Type, Type], [In, In], semidet) :-
	in_mode(In).
special_pred_interface(index, Type, [Type, int_type], [In, Out], det) :-
	in_mode(In),
	out_mode(Out).
special_pred_interface(compare, Type, [comparison_result_type, Type, Type],
		[Uo, In, In], det) :-
	in_mode(In),
	uo_mode(Uo).

special_pred_get_type(unify, Types, T) :-
	list__reverse(Types, [T | _]).
special_pred_get_type(index, Types, T) :-
	list__reverse(Types, [_, T | _]).
special_pred_get_type(compare, Types, T) :-
	list__reverse(Types, [T | _]).

special_pred_get_type_det(SpecialId, ArgTypes, Type) :-
	( special_pred_get_type(SpecialId, ArgTypes, TypePrime) ->
		Type = TypePrime
	;
		error("special_pred_get_type_det: special_pred_get_type failed")
	).

special_pred_description(unify, "unification predicate").
special_pred_description(compare, "comparison predicate").
special_pred_description(index, "indexing predicate").

special_pred_is_generated_lazily(ModuleInfo, TypeCtor) :-
	TypeCategory = classify_type_ctor(ModuleInfo, TypeCtor),
	(
		TypeCategory = tuple_type
	;
		( TypeCategory = user_ctor_type ; TypeCategory = enum_type ),
		module_info_types(ModuleInfo, Types),
		map__search(Types, TypeCtor, TypeDefn),
		hlds_data__get_type_defn_body(TypeDefn, Body),
		hlds_data__get_type_defn_status(TypeDefn, Status),
		special_pred_is_generated_lazily_2(ModuleInfo,
			TypeCtor, Body, Status)
	).

special_pred_is_generated_lazily(ModuleInfo, TypeCtor, Body, Status) :-
	TypeCategory = classify_type_ctor(ModuleInfo, TypeCtor),
	(
		TypeCategory = tuple_type
	;
		( TypeCategory = user_ctor_type ; TypeCategory = enum_type ),
		special_pred_is_generated_lazily_2(ModuleInfo,
			TypeCtor, Body, Status)
	).

:- pred special_pred_is_generated_lazily_2(module_info,
	type_ctor, hlds_type_body, import_status).
:- mode special_pred_is_generated_lazily_2(in, in, in, in) is semidet.

special_pred_is_generated_lazily_2(ModuleInfo, _TypeCtor, Body, Status) :-
	(
		status_defined_in_this_module(Status, no)
	;
		module_info_globals(ModuleInfo, Globals),
		globals__lookup_bool_option(Globals, special_preds, no)
	),

	%
	% We can't generate clauses for unification predicates for
	% foreign types lazily because they call the polymorphic procedure
	% private_builtin__nyi_foreign_type_unify.
	% polymorphism__process_generated_pred can't handle calls to
	% polymorphic procedures after the initial polymorphism pass.
	%
	Body \= foreign_type(_, _),

	% The special predicates for types with user-defined
	% equality or existentially typed constructors are always
	% generated immediately by make_hlds.m.
	\+ special_pred_for_type_needs_typecheck(ModuleInfo, Body).

special_pred_for_type_needs_typecheck(ModuleInfo, Body) :-
	(
		type_body_has_user_defined_equality_pred(ModuleInfo, Body,
			unify_compare(_, _))
	;
		Ctors = Body ^ du_type_ctors,
		list__member(Ctor, Ctors),
		Ctor = ctor(ExistQTVars, _, _, _),
		ExistQTVars \= []
	).

can_generate_special_pred_clauses_for_type(ModuleInfo, TypeCtor, Body) :-
	Body \= abstract_type(_),
	\+ type_ctor_has_hand_defined_rtti(TypeCtor, Body),
	\+ type_body_has_user_defined_equality_pred(ModuleInfo, Body,
		abstract_noncanonical_type).

%-----------------------------------------------------------------------------%
