%-----------------------------------------------------------------------------%
% Copyright (C) 1997-1999 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
% 
% File      : post_typecheck.m
% Author    : fjh
% Purpose   : finish off type checking.
%
% This module does the final parts of type analysis:
%
%	- it resolves predicate overloading
%	  (perhaps it ought to also resolve function overloading,
%	  converting unifications that are function calls into
%	  HLDS call instructions, but currently that is done
%	  in polymorphism.m)
%
%	- it checks for unbound type variables and if there are any,
%	  it reports an error (or a warning, binding them to the type `void').
%
% These actions cannot be done until after type inference is complete,
% so they need to be a separate "post-typecheck pass".  For efficiency
% reasons, this is in fact done at the same time as purity analysis --
% the routines here are called from purity.m rather than mercury_compile.m.
%
% This module also copies the clause_info structure
% to the proc_info structures. This is done in the post_typecheck pass
% and not at the start of modecheck because modecheck may be
% reinvoked after HLDS transformations. Any transformation that
% needs typechecking should work with the clause_info structure.
% Type information is also propagated into the modes of procedures
% by this pass if the ModeError parameter is no. 
% ModeError should be yes if any undefined modes	
% were found by previous passes.
%

:- module post_typecheck.
:- interface.
:- import_module hlds_goal, hlds_module, hlds_pred, prog_data.
:- import_module list, io, bool.

	% check_type_bindings(PredId, PredInfo, ModuleInfo, ReportErrors):
	%
	% Check that all Aditi predicates have an `aditi__state' argument.
	% Check that the all of the types which have been inferred
	% for the variables in the clause do not contain any unbound type
	% variables other than those that occur in the types of head
	% variables, and that there are no unsatisfied type class
	% constraints, and if ReportErrors = yes, print appropriate
	% warning/error messages.
	% Also bind any unbound type variables to the type `void'.
	% Note that when checking assertions we take the conservative
	% approach of warning about unbound type variables.  There may
	% be cases for which this doesn't make sense.
	%
:- pred post_typecheck__check_type_bindings(pred_id, pred_info, module_info,
		bool, pred_info, int, io__state, io__state).
:- mode post_typecheck__check_type_bindings(in, in, in, in, out, out, di, uo)
		is det.

	% Handle any unresolved overloading for a predicate call.
	%
:- pred post_typecheck__resolve_pred_overloading(pred_id, list(prog_var),
		pred_info, module_info, sym_name, sym_name, pred_id).
:- mode post_typecheck__resolve_pred_overloading(in, in, in, in, in,
		out, out) is det.

	% Resolve overloading and fill in the argument modes
	% of a call to an Aditi builtin.
	% Check that a relation modified by one of the Aditi update
	% goals is a base relation.
	%
:- pred post_typecheck__finish_aditi_builtin(module_info, pred_info,
		list(prog_var), term__context, aditi_builtin, aditi_builtin,
		simple_call_id, simple_call_id, list(mode),
		io__state, io__state).
:- mode post_typecheck__finish_aditi_builtin(in, in, in, in,
		in, out, in, out, out, di, uo) is det.

	% Do the stuff needed to initialize the pred_infos and proc_infos
	% so that a pred is ready for running polymorphism and then
	% mode checking.
	% Also check that all predicates with an `aditi' marker have
	% an `aditi:state' argument.
	%
:- pred post_typecheck__finish_pred(module_info, pred_id, pred_info, pred_info,
		io__state, io__state).
:- mode post_typecheck__finish_pred(in, in, in, out, di, uo) is det.

:- pred post_typecheck__finish_imported_pred(module_info, pred_id,
		pred_info, pred_info, io__state, io__state).
:- mode post_typecheck__finish_imported_pred(in, in, in, out, di, uo) is det.

:- pred post_typecheck__finish_ill_typed_pred(module_info, pred_id,
		pred_info, pred_info, io__state, io__state).
:- mode post_typecheck__finish_ill_typed_pred(in, in, in, out, di, uo) is det.

	% Now that the assertion has finished being typechecked,
	% remove it from further processing and store it in the
	% assertion_table.
:- pred post_typecheck__finish_assertion(module_info, pred_id,
		module_info) is det.
:- mode post_typecheck__finish_assertion(in, in, out) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module (assertion), typecheck, clause_to_proc.
:- import_module mode_util, inst_match, (inst).
:- import_module mercury_to_mercury, prog_out, hlds_data, hlds_out, type_util.
:- import_module globals, options.

:- import_module map, set, assoc_list, bool, std_util, term, require, int.

%-----------------------------------------------------------------------------%
%			Check for unbound type variables
%
%  Check that the all of the types which have been inferred
%  for the variables in the clause do not contain any unbound type
%  variables other than those that occur in the types of head
%  variables, and that there are no unsatisfied type class constraints.

post_typecheck__check_type_bindings(PredId, PredInfo0, ModuleInfo, ReportErrs,
		PredInfo, NumErrors, IOState0, IOState) :-
	(
		ReportErrs = yes,
		pred_info_get_unproven_body_constraints(PredInfo0,
			UnprovenConstraints0),
		UnprovenConstraints0 \= []
	->
		list__sort_and_remove_dups(UnprovenConstraints0,
			UnprovenConstraints),
		report_unsatisfied_constraints(UnprovenConstraints,
			PredId, PredInfo0, ModuleInfo, IOState0, IOState1),
		list__length(UnprovenConstraints, NumErrors)
	;
		NumErrors = 0,
		IOState1 = IOState0
	),
		
	pred_info_clauses_info(PredInfo0, ClausesInfo0),
	pred_info_get_head_type_params(PredInfo0, HeadTypeParams),
	clauses_info_varset(ClausesInfo0, VarSet),
	clauses_info_vartypes(ClausesInfo0, VarTypesMap0),
	map__to_assoc_list(VarTypesMap0, VarTypesList),
	set__init(Set0),
	check_type_bindings_2(VarTypesList, HeadTypeParams,
			[], Errs, Set0, Set),
	( Errs = [] ->
		PredInfo = PredInfo0,
		IOState2 = IOState1
	;
		( ReportErrs = yes ->
			%
			% report the warning
			%
			report_unresolved_type_warning(Errs, PredId, PredInfo0,
				ModuleInfo, VarSet, IOState1, IOState2)
		;
			IOState2 = IOState1
		),

		%
		% bind all the type variables in `Set' to `void' ...
		%
		pred_info_context(PredInfo0, Context),
		bind_type_vars_to_void(Set, Context, VarTypesMap0, VarTypesMap),
		clauses_info_set_vartypes(ClausesInfo0, VarTypesMap,
			ClausesInfo),
		pred_info_set_clauses_info(PredInfo0, ClausesInfo, PredInfo)
	),

	%
	% Check that all Aditi predicates have an `aditi__state' argument.
	% This must be done after typechecking because of type inference --
	% the types of some Aditi predicates may not be known before.
	%
	pred_info_get_markers(PredInfo, Markers),
	pred_info_arg_types(PredInfo, ArgTypes),
	( check_marker(Markers, aditi) ->
		list__filter(type_is_aditi_state, ArgTypes, AditiStateTypes),
		( AditiStateTypes = [], ReportErrs = yes ->
			report_no_aditi_state(PredInfo, IOState2, IOState)
		; AditiStateTypes = [_, _ | _] ->
			report_multiple_aditi_states(PredInfo,
				IOState2, IOState)
		;
			IOState = IOState2
		)
	;
		IOState = IOState2
	).

:- pred check_type_bindings_2(assoc_list(prog_var, (type)), list(tvar),
		assoc_list(prog_var, (type)), assoc_list(prog_var, (type)),
		set(tvar), set(tvar)).
:- mode check_type_bindings_2(in, in, in, out, in, out) is det.

check_type_bindings_2([], _, Errs, Errs, Set, Set).
check_type_bindings_2([Var - Type | VarTypes], HeadTypeParams,
			Errs0, Errs, Set0, Set) :-
	term__vars(Type, TVars),
	set__list_to_set(TVars, TVarsSet0),
	set__delete_list(TVarsSet0, HeadTypeParams, TVarsSet1),
	( \+ set__empty(TVarsSet1) ->
		Errs1 = [Var - Type | Errs0],
		set__union(Set0, TVarsSet1, Set1)
	;
		Errs1 = Errs0,
		Set0 = Set1
	),
	check_type_bindings_2(VarTypes, HeadTypeParams,
		Errs1, Errs, Set1, Set).

%
% bind all the type variables in `UnboundTypeVarsSet' to the type `void' ...
%
:- pred bind_type_vars_to_void(set(tvar), prog_context,
				map(prog_var, type), map(prog_var, type)).
:- mode bind_type_vars_to_void(in, in, in, out) is det.

bind_type_vars_to_void(UnboundTypeVarsSet, Context,
		VarTypesMap0, VarTypesMap) :-
	%
	% first create a pair of corresponding lists (UnboundTypeVars, Voids)
	% that map the unbound type variables to void
	%
	set__to_sorted_list(UnboundTypeVarsSet, UnboundTypeVars),
	list__length(UnboundTypeVars, Length),
	Void = term__functor(term__atom("void"), [], Context),
	list__duplicate(Length, Void, Voids),

	%
	% then apply the substitution we just created to the variable types
	%
	map__keys(VarTypesMap0, Vars),
	map__values(VarTypesMap0, Types0),
	term__substitute_corresponding_list(UnboundTypeVars, Voids,
		Types0, Types),
	map__from_corresponding_lists(Vars, Types, VarTypesMap).

%-----------------------------------------------------------------------------%
%
% report an error: unsatisfied type class constraints
%
:- pred report_unsatisfied_constraints(list(class_constraint),
		pred_id, pred_info, module_info, io__state, io__state).
:- mode report_unsatisfied_constraints(in, in, in, in, di, uo) is det.

report_unsatisfied_constraints(Constraints, PredId, PredInfo, ModuleInfo) -->
	io__set_exit_status(1),

	{ pred_info_typevarset(PredInfo, TVarSet) },
	{ pred_info_context(PredInfo, Context) },

        prog_out__write_context(Context),
	io__write_string("In "),
	hlds_out__write_pred_id(ModuleInfo, PredId),
	io__write_string(":\n"),

	prog_out__write_context(Context),
	io__write_string(
		"  type error: unsatisfied typeclass constraint(s):\n"),

	prog_out__write_context(Context),
	io__write_string("  "),
	io__write_list(Constraints, ", ", mercury_output_constraint(TVarSet)),
	io__write_string(".\n").

%
% report a warning: uninstantiated type parameter
%
:- pred report_unresolved_type_warning(assoc_list(prog_var, (type)), pred_id,
		pred_info, module_info, prog_varset, io__state, io__state).
:- mode report_unresolved_type_warning(in, in, in, in, in, di, uo) is det.

report_unresolved_type_warning(Errs, PredId, PredInfo, ModuleInfo, VarSet) -->
	globals__io_lookup_bool_option(halt_at_warn, HaltAtWarn),
	( { HaltAtWarn = yes } ->
		 io__set_exit_status(1)
	;
		[]
	),

	{ pred_info_typevarset(PredInfo, TypeVarSet) },
	{ pred_info_context(PredInfo, Context) },

        prog_out__write_context(Context),
	io__write_string("In "),
	hlds_out__write_pred_id(ModuleInfo, PredId),
	io__write_string(":\n"),

        prog_out__write_context(Context),
	io__write_string("  warning: unresolved polymorphism.\n"),
	prog_out__write_context(Context),
	( { Errs = [_] } ->
		io__write_string("  The variable with an unbound type was:\n")
	;
		io__write_string("  The variables with unbound types were:\n")
	),
	write_type_var_list(Errs, Context, VarSet, TypeVarSet),
	prog_out__write_context(Context),
	io__write_string("  The unbound type variable(s) will be implicitly\n"),
	prog_out__write_context(Context),
	io__write_string("  bound to the builtin type `void'.\n"),
	globals__io_lookup_bool_option(verbose_errors, VerboseErrors),
	( { VerboseErrors = yes } ->
		io__write_strings([
"\tThe body of the clause contains a call to a polymorphic predicate,\n",
"\tbut I can't determine which version should be called,\n",
"\tbecause the type variables listed above didn't get bound.\n",
% "\tYou may need to use an explicit type qualifier.\n",
% XXX improve error message
"\t(I ought to tell you which call caused the problem, but I'm afraid\n",
"\tyou'll have to work it out yourself.  My apologies.)\n"
			])
	;
		[]
	).

:- pred write_type_var_list(assoc_list(prog_var, (type)), prog_context,
			prog_varset, tvarset, io__state, io__state).
:- mode write_type_var_list(in, in, in, in, di, uo) is det.

write_type_var_list([], _, _, _) --> [].
write_type_var_list([Var - Type | Rest], Context, VarSet, TVarSet) -->
	prog_out__write_context(Context),
	io__write_string("      "),
	mercury_output_var(Var, VarSet, no),
	io__write_string(" :: "),
	mercury_output_term(Type, TVarSet, no),
	io__write_string("\n"),
	write_type_var_list(Rest, Context, VarSet, TVarSet).

%-----------------------------------------------------------------------------%
%			resolve predicate overloading

% In the case of a call to an overloaded predicate, typecheck.m
% does not figure out the correct pred_id.  We must do that here.

post_typecheck__resolve_pred_overloading(PredId0, Args0, CallerPredInfo,
		ModuleInfo, PredName0, PredName, PredId) :-
	( invalid_pred_id(PredId0) ->
		%
		% Find the set of candidate pred_ids for predicates which
		% have the specified name and arity
		% 
		pred_info_typevarset(CallerPredInfo, TVarSet),
		pred_info_clauses_info(CallerPredInfo, ClausesInfo),
		clauses_info_vartypes(ClausesInfo, VarTypes),
		map__apply_to_list(Args0, VarTypes, ArgTypes),
		typecheck__resolve_pred_overloading(ModuleInfo,
			ArgTypes, TVarSet, PredName0, PredName, PredId)
        ;
		PredId = PredId0,
		PredName = PredName0
        ).

%-----------------------------------------------------------------------------%

post_typecheck__finish_aditi_builtin(_, _, _, _, aditi_call(_, _, _, _),
		_, _, _, _) -->
	% These are only added by magic.m.
	{ error("post_typecheck__finish_aditi_builtin: aditi_call") }.
post_typecheck__finish_aditi_builtin(ModuleInfo, CallerPredInfo,
		Args, Context, aditi_insert(PredId0), Builtin,
		PredOrFunc - SymName0/Arity, InsertCallId,
		Modes, IO0, IO) :-
	% make_hlds.m checks the arity, so this is guaranteed to succeed.
	get_state_args_det(Args, OtherArgs, _, _),

	% The tuple to insert has the same argument types as
	% the relation being inserted into.
	post_typecheck__resolve_pred_overloading(PredId0, OtherArgs,
		CallerPredInfo, ModuleInfo, SymName0, SymName, PredId),

	Builtin = aditi_insert(PredId),
	InsertCallId = PredOrFunc - SymName/Arity,

	module_info_pred_info(ModuleInfo, PredId, RelationPredInfo),
	check_base_relation(Context, RelationPredInfo,
		Builtin, InsertCallId, IO0, IO),

	% `aditi_insert' calls do not use the `aditi_state' argument
	% in the tuple to insert, so set its mode to `unused'.
	% The other arguments all have mode `in'.
	pred_info_arg_types(RelationPredInfo, ArgTypes),
	in_mode(InMode),
	aditi_builtin_modes(InMode, (aditi_top_down),
		ArgTypes, InsertArgModes),
	list__append(InsertArgModes, [aditi_di_mode, aditi_uo_mode], Modes).

post_typecheck__finish_aditi_builtin(ModuleInfo, CallerPredInfo, Args, Context,
		aditi_delete(PredId0, Syntax), aditi_delete(PredId, Syntax),
		PredOrFunc - SymName0/Arity, PredOrFunc - SymName/Arity,
		Modes, IO0, IO) :-
	AdjustArgTypes = (pred(X::in, X::out) is det),
	resolve_aditi_builtin_overloading(ModuleInfo, CallerPredInfo, Args,
		AdjustArgTypes, PredId0, PredId, SymName0, SymName),

	Builtin = aditi_delete(PredId, Syntax),
	DeleteCallId = PredOrFunc - SymName/Arity,

	module_info_pred_info(ModuleInfo, PredId, RelationPredInfo),
	check_base_relation(Context, RelationPredInfo,
		Builtin, DeleteCallId, IO0, IO),

	pred_info_arg_types(RelationPredInfo, ArgTypes),
	in_mode(InMode),
	aditi_builtin_modes(InMode, (aditi_top_down),
		ArgTypes, DeleteArgModes),
	Inst = ground(shared, yes(pred_inst_info(PredOrFunc,
		DeleteArgModes, semidet))),
	Modes = [(Inst -> Inst), aditi_di_mode, aditi_uo_mode].

post_typecheck__finish_aditi_builtin(ModuleInfo, CallerPredInfo, Args, Context,
		aditi_bulk_operation(Op, PredId0), Builtin,
		PredOrFunc - SymName0/Arity, BulkOpCallId, Modes, IO0, IO) :-
	AdjustArgTypes = (pred(X::in, X::out) is det),
	resolve_aditi_builtin_overloading(ModuleInfo, CallerPredInfo, Args,
		AdjustArgTypes, PredId0, PredId, SymName0, SymName),

	Builtin = aditi_bulk_operation(Op, PredId),
	BulkOpCallId = PredOrFunc - SymName/Arity,

	module_info_pred_info(ModuleInfo, PredId, RelationPredInfo),
	check_base_relation(Context, RelationPredInfo,
		Builtin, BulkOpCallId, IO0, IO),

	pred_info_arg_types(RelationPredInfo, ArgTypes),
	out_mode(OutMode),
	aditi_builtin_modes(OutMode, (aditi_bottom_up), ArgTypes, OpArgModes),
	Inst = ground(shared, yes(pred_inst_info(PredOrFunc,
		OpArgModes, nondet))),
	Modes = [(Inst -> Inst), aditi_di_mode, aditi_uo_mode].

post_typecheck__finish_aditi_builtin(ModuleInfo, CallerPredInfo, Args, Context,
		aditi_modify(PredId0, Syntax), Builtin,
		PredOrFunc - SymName0/Arity, ModifyCallId, Modes, IO0, IO) :-

	% The argument types of the closure passed to `aditi_modify'
	% contain two copies of the arguments of the base relation -
	% one set input and one set output.
	AdjustArgTypes =
	    (pred(Types0::in, Types::out) is det :-
		list__length(Types0, Length),
		HalfLength is Length // 2,
		( list__split_list(HalfLength, Types0, Types1, _) ->
			Types = Types1
		;
			error(
			"post_typecheck__finish_aditi_builtin: aditi_modify")
		)
	    ),
	resolve_aditi_builtin_overloading(ModuleInfo, CallerPredInfo, Args,
		AdjustArgTypes, PredId0, PredId, SymName0, SymName),

	Builtin = aditi_modify(PredId, Syntax),
	ModifyCallId = PredOrFunc - SymName/Arity,

	module_info_pred_info(ModuleInfo, PredId, RelationPredInfo),
	check_base_relation(Context, RelationPredInfo,
		Builtin, ModifyCallId, IO0, IO),

	% Set up the modes of the closure passed to the call to `aditi_modify'.
	pred_info_arg_types(RelationPredInfo, ArgTypes),
	in_mode(InMode),
	out_mode(OutMode),
	aditi_builtin_modes(InMode, (aditi_top_down), ArgTypes, InputArgModes),
	aditi_builtin_modes(OutMode, (aditi_top_down),
		ArgTypes, OutputArgModes),
	list__append(InputArgModes, OutputArgModes, ModifyArgModes),
	Inst = ground(shared,
		yes(pred_inst_info(predicate, ModifyArgModes, semidet))),
	Modes = [(Inst -> Inst), aditi_di_mode, aditi_uo_mode].

	% Use the type of the closure passed to an `aditi_delete',
	% `aditi_bulk_insert', `aditi_bulk_delete' or `aditi_modify'
	% call to work out which predicate is being updated.
:- pred resolve_aditi_builtin_overloading(module_info, pred_info,
		list(prog_var), pred(list(type), list(type)),
		pred_id, pred_id, sym_name, sym_name).
:- mode resolve_aditi_builtin_overloading(in, in, in, pred(in, out) is det,
		in, out, in, out) is det.

resolve_aditi_builtin_overloading(ModuleInfo, CallerPredInfo, Args,
		AdjustArgTypes, PredId0, PredId, SymName0, SymName) :-
	% make_hlds.m checks the arity, so this is guaranteed to succeed.
	get_state_args_det(Args, OtherArgs, _, _),
	( invalid_pred_id(PredId0) ->
		(
			OtherArgs = [HOArg],
			pred_info_typevarset(CallerPredInfo, TVarSet),
			pred_info_clauses_info(CallerPredInfo, ClausesInfo),
			clauses_info_vartypes(ClausesInfo, VarTypes),
			map__lookup(VarTypes, HOArg, HOArgType),
			type_is_higher_order(HOArgType, predicate,
				(aditi_top_down), ArgTypes0)
		->
			call(AdjustArgTypes, ArgTypes0, ArgTypes),
			typecheck__resolve_pred_overloading(ModuleInfo,
				ArgTypes, TVarSet, SymName0, SymName, PredId)
		;
			error(
			"post_typecheck__resolve_aditi_builtin_overloading")
		)
	;
		PredId = PredId0,
		SymName = SymName0
	).

	% Work out the modes of the arguments of a closure passed
	% to an Aditi update.
	% The `Mode' passed is the mode of all arguments apart
	% from the `aditi__state'.
:- pred aditi_builtin_modes((mode), lambda_eval_method,
		list(type), list(mode)).
:- mode aditi_builtin_modes(in, in, in, out) is det.

aditi_builtin_modes(_, _, [], []).
aditi_builtin_modes(Mode, EvalMethod, [ArgType | ArgTypes],
		[ArgMode | ArgModes]) :-
	( type_is_aditi_state(ArgType) ->
		( EvalMethod = (aditi_top_down) ->
			% The top-down Aditi closures are not allowed
			% to call database predicates, so their aditi__state
			% arguments must have mode `unused'.
			% The `aditi__state's are passed even though
			% they are not used so that the argument
			% list of the closure matches the argument list
			% of the relation being updated.
			unused_mode(ArgMode)
		;
			ArgMode = aditi_ui_mode
		)
	;
		ArgMode = Mode
	),
	aditi_builtin_modes(Mode, EvalMethod, ArgTypes, ArgModes).

	% Report an error if a predicate modified by an Aditi builtin
	% is not a base relation.
:- pred check_base_relation(prog_context, pred_info, aditi_builtin,
		simple_call_id, io__state, io__state).
:- mode check_base_relation(in, in, in, in, di, uo) is det.

check_base_relation(Context, PredInfo, Builtin, CallId) -->
	( { hlds_pred__pred_info_is_base_relation(PredInfo) } ->
		[]
	;
		io__set_exit_status(1),
		prog_out__write_context(Context),
		io__write_string("In "),
		hlds_out__write_call_id(
			generic_call(aditi_builtin(Builtin, CallId))
		),
		io__write_string(":\n"),
		prog_out__write_context(Context),
		io__write_string("  error: the modified "),
		{ pred_info_get_is_pred_or_func(PredInfo, PredOrFunc) },
		hlds_out__write_pred_or_func(PredOrFunc),
		io__write_string(" is not a base relation.\n")
	).

%-----------------------------------------------------------------------------%

	% 
	% Add a default mode for functions if none was specified, and
	% ensure that all constructors occurring in predicate mode 
	% declarations are module qualified.
	% 
post_typecheck__finish_pred(ModuleInfo, PredId, PredInfo0, PredInfo) -->
	{ maybe_add_default_mode(PredInfo0, PredInfo1, _) },
	post_typecheck__propagate_types_into_modes(ModuleInfo, PredId,
		PredInfo1, PredInfo).

	%
	% For ill-typed preds, we just need to set the modes up correctly
	% so that any calls to that pred from correctly-typed predicates
	% won't result in spurious mode errors.
	%
post_typecheck__finish_ill_typed_pred(ModuleInfo, PredId,
			PredInfo0, PredInfo) -->
	post_typecheck__finish_pred(ModuleInfo, PredId, PredInfo0, PredInfo).

	% 
	% For imported preds, we just need to ensure that all
	% constructors occurring in predicate mode declarations are
	% module qualified.
	% 
post_typecheck__finish_imported_pred(ModuleInfo, PredId,
		PredInfo0, PredInfo) -->
	post_typecheck__propagate_types_into_modes(ModuleInfo, PredId,
		PredInfo0, PredInfo).

	%
	% Remove the assertion from the list of pred ids to be processed
	% in the future and place the pred_info associated with the
	% assertion into the assertion table.
	% Also records for each predicate that is used in an assertion
	% which assertion it is used in.
	% 
post_typecheck__finish_assertion(Module0, PredId, Module) :-
		% store into assertion table.
	module_info_assertion_table(Module0, AssertTable0),
	assertion_table_add_assertion(PredId, AssertTable0, Id, AssertTable),
	module_info_set_assertion_table(Module0, AssertTable, Module1),
		
		% Remove from further processing.
	module_info_remove_predid(Module1, PredId, Module2),

		% record which predicates are used in assertions
	assertion__goal(Id, Module2, Goal),
	assertion__record_preds_used_in(Goal, Id, Module2, Module).
	

	% 
	% Ensure that all constructors occurring in predicate mode
	% declarations are module qualified.
	% 
:- pred post_typecheck__propagate_types_into_modes(module_info, pred_id,
		pred_info, pred_info, io__state, io__state).
:- mode post_typecheck__propagate_types_into_modes(in, in, in, out, di, uo)
		is det.
post_typecheck__propagate_types_into_modes(ModuleInfo, PredId, PredInfo0,
		PredInfo) -->
	{ pred_info_arg_types(PredInfo0, ArgTypes) },
	{ pred_info_procedures(PredInfo0, Procs0) },
	{ pred_info_procids(PredInfo0, ProcIds) },

	propagate_types_into_proc_modes(ModuleInfo, PredId, ProcIds, ArgTypes,
			Procs0, Procs),
	{ pred_info_set_procedures(PredInfo0, Procs, PredInfo) }.

%-----------------------------------------------------------------------------%

:- pred propagate_types_into_proc_modes(module_info,
		pred_id, list(proc_id), list(type), proc_table, proc_table,
		io__state, io__state).
:- mode propagate_types_into_proc_modes(in,
		in, in, in, in, out, di, uo) is det.		

propagate_types_into_proc_modes(_, _, [], _, Procs, Procs) --> [].
propagate_types_into_proc_modes(ModuleInfo, PredId,
		[ProcId | ProcIds], ArgTypes, Procs0, Procs) -->
	{ map__lookup(Procs0, ProcId, ProcInfo0) },
	{ proc_info_argmodes(ProcInfo0, ArgModes0) },
	{ propagate_types_into_mode_list(ArgTypes, ModuleInfo,
		ArgModes0, ArgModes) },
	%
	% check for unbound inst vars
	% (this needs to be done after propagate_types_into_mode_list,
	% because we need the insts to be module-qualified; and it
	% needs to be done before mode analysis, to avoid internal errors)
	%
	( { mode_list_contains_inst_var(ArgModes, ModuleInfo, _InstVar) } ->
		unbound_inst_var_error(PredId, ProcInfo0, ModuleInfo),
		% delete this mode, to avoid internal errors
		{ map__det_remove(Procs0, ProcId, _, Procs1) }
	;
		{ proc_info_set_argmodes(ProcInfo0, ArgModes, ProcInfo) },
		{ map__det_update(Procs0, ProcId, ProcInfo, Procs1) }
	),
	propagate_types_into_proc_modes(ModuleInfo, PredId, ProcIds,
		ArgTypes, Procs1, Procs).

:- pred unbound_inst_var_error(pred_id, proc_info, module_info,
				io__state, io__state).
:- mode unbound_inst_var_error(in, in, in, di, uo) is det.

unbound_inst_var_error(PredId, ProcInfo, ModuleInfo) -->
	{ proc_info_context(ProcInfo, Context) },
	io__set_exit_status(1),
	prog_out__write_context(Context),
	io__write_string("In mode declaration for "),
	hlds_out__write_pred_id(ModuleInfo, PredId),
	io__write_string(":\n"),
	prog_out__write_context(Context),
	io__write_string("  error: unbound inst variable(s).\n"),
	prog_out__write_context(Context),
	io__write_string("  (Sorry, polymorphic modes are not supported.)\n").

%-----------------------------------------------------------------------------%

:- pred report_no_aditi_state(pred_info, io__state, io__state).
:- mode report_no_aditi_state(in, di, uo) is det.

report_no_aditi_state(PredInfo) -->
	io__set_exit_status(1),
	{ pred_info_context(PredInfo, Context) },
	prog_out__write_context(Context),
	{ pred_info_module(PredInfo, Module) },
	{ pred_info_name(PredInfo, Name) },
	{ pred_info_arity(PredInfo, Arity) },
	{ pred_info_get_is_pred_or_func(PredInfo, PredOrFunc) },
	io__write_string("Error: `:- pragma aditi' declaration for "),
	hlds_out__write_simple_call_id(PredOrFunc,
		qualified(Module, Name), Arity),
	io__write_string("  without an `aditi:state' argument.\n").

:- pred report_multiple_aditi_states(pred_info, io__state, io__state).
:- mode report_multiple_aditi_states(in, di, uo) is det.

report_multiple_aditi_states(PredInfo) -->
	io__set_exit_status(1),
	{ pred_info_context(PredInfo, Context) },
	prog_out__write_context(Context),
	{ pred_info_module(PredInfo, Module) },
	{ pred_info_name(PredInfo, Name) },
	{ pred_info_arity(PredInfo, Arity) },
	{ pred_info_get_is_pred_or_func(PredInfo, PredOrFunc) },
	io__write_string("Error: `:- pragma aditi' declaration for "),
	hlds_out__write_simple_call_id(PredOrFunc,
		qualified(Module, Name), Arity),
	io__nl,
	prog_out__write_context(Context),
	io__write_string("  with multiple `aditi:state' arguments.\n").

%-----------------------------------------------------------------------------%
