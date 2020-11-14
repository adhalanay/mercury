%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 2009-2012 The University of Melbourne.
% Copyright (C) 2014-2018 The Mercury team.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: hlds_out_util.m.
% Author: zs.
%
%---------------------------------------------------------------------------%

:- module hlds.hlds_out.hlds_out_util.
:- interface.

:- import_module hlds.hlds_class.
:- import_module hlds.hlds_goal.
:- import_module hlds.hlds_module.
:- import_module hlds.hlds_pred.
:- import_module hlds.status.
:- import_module libs.
:- import_module libs.globals.
:- import_module mdbcomp.
:- import_module mdbcomp.sym_name.
:- import_module parse_tree.
:- import_module parse_tree.error_util.
:- import_module parse_tree.parse_tree_out_info.
:- import_module parse_tree.parse_tree_out_term.
:- import_module parse_tree.prog_data.

:- import_module io.
:- import_module list.
:- import_module maybe.
:- import_module pair.
:- import_module term.

%---------------------------------------------------------------------------%

:- type hlds_out_info
    --->    hlds_out_info(
                hoi_dump_hlds_options           :: string,
                hoi_dump_hlds_options_backup    :: string,
                hoi_dump_hlds_pred_ids          :: list(string),
                hoi_dump_hlds_pred_names        :: list(string),
                hoi_mercury_to_mercury          :: merc_out_info
            ).

:- func init_hlds_out_info(globals, output_lang) = hlds_out_info.

%---------------------------------------------------------------------------%

:- type is_first
    --->    is_first
    ;       is_not_first.

:- type is_last
    --->    is_last
    ;       is_not_last.

%---------------------------------------------------------------------------%

    % pred_id_to_string returns a string such as
    %       predicate `foo.bar/3'
    % or    function `foo.myfoo/5'
    % except in some special cases where the predicate name is mangled
    % and we can print a more meaningful identification of the predicate
    % in question.
    %
:- func pred_id_to_string(module_info, pred_id) = string.

    % Do the same job as pred_id_to_string, but don't look up the pred_info
    % in the module_info; get it directly from the caller.
    %
:- func pred_info_id_to_string(pred_info) = string.

    % Do the same job as pred_id_to_string, only for a procedure.
    %
:- func pred_proc_id_to_string(module_info, pred_proc_id) = string.
:- func pred_proc_id_pair_to_string(module_info, pred_id, proc_id) = string.

%---------------------------------------------------------------------------%

    % unify_context_to_pieces generates a message such as
    %   foo.m:123:   in argument 3 of functor `foo/5':
    %   foo.m:123:   in unification of `X' and `blah':
    % based on the unify_context and prog_context.
    %
:- pred unify_context_to_pieces(unify_context::in,
    list(format_component)::in, list(format_component)::out) is det.

    % unify_context_first_to_pieces is the same as above, except that
    % it also takes and returns a flag which specifies whether this is the
    % start of a sentence. If the first argument is `is_first', then it means
    % this is the first line of an error message, so the message starts with
    % a capital letter, e.g.
    %   foo.m:123:   In argument 3 of functor `foo/5':
    %   foo.m:123:   in unification of `X' and `blah':
    % The flag returned as the second argument will be `is_not_first'
    % unless nothing was generated, in which case it will be the same
    % as the first argument.
    %
:- pred unify_context_first_to_pieces(is_first::in, is_first::out,
    unify_context::in,
    list(format_component)::in, list(format_component)::out) is det.

%---------------------------------------------------------------------------%

    % maybe_output_context_comment(Stream, Indent, Suffix, Context, !IO):
    %
    % If the given context is meaningful, output it in a form suitable
    % for a comment in HLDS dumps, followed by Suffix.
    %
:- pred maybe_output_context_comment(io.text_output_stream::in, int::in,
    string::in, term.context::in, io::di, io::uo) is det.

%---------------------------------------------------------------------------%

:- func call_id_to_string(call_id) = string.

:- func generic_call_id_to_string(generic_call_id) = string.

:- func cast_type_to_string(cast_kind) = string.

    % Generate a message of the form "argument %i of call to pred_or_func
    % `foo/n'". The pred_markers argument is used to tell if the calling
    % predicate is a type class method implementation; if so, we omit the
    % "call to" part, since the user didn't write any explicit call.
    %
:- func call_arg_id_to_string(call_id, int, pred_markers) = string.

%---------------------------------------------------------------------------%

    % Return a printable representation of a functor and its arguments.
    % The prog_varset gives the names of any variables.
    %
:- func functor_to_string(prog_varset, var_name_print, const, list(prog_var))
    = string.

:- func functor_to_string_maybe_needs_quotes(prog_varset, var_name_print,
    needs_quotes, const, list(prog_var)) = string.

:- func qualified_functor_to_string(prog_varset, var_name_print,
    module_name, const, list(prog_var)) = string.

:- func qualified_functor_with_term_args_to_string(prog_varset, var_name_print,
    module_name, const, list(prog_term)) = string.

    % Return a printable representation of a cons_id and arguments.
    % The prog_varset gives the names of any variables, while the module_info
    % allows the interpretation of cons_ids that are shrouded references
    % to procedures.
    %
:- func functor_cons_id_to_string(module_info, prog_varset, var_name_print,
    cons_id, list(prog_var)) = string.

:- type maybe_qualify_cons_id
    --->    qualify_cons_id
    ;       do_not_qualify_cons_id.

:- func cons_id_and_vars_or_arity_to_string(prog_varset,
    maybe_qualify_cons_id, cons_id, maybe(list(prog_var))) = string.

%---------------------------------------------------------------------------%

:- pred write_constraint_proof_map(io.text_output_stream::in, int::in,
    var_name_print::in, tvarset::in, constraint_proof_map::in,
    io::di, io::uo) is det.

%---------------------------------------------------------------------------%

    % Return a string representing a list of variables and their
    % corresponding modes (e.g. for a lambda expressions). The varsets
    % give the context.
    %
:- func var_modes_to_string(prog_varset, inst_varset, var_name_print,
    list(prog_var), list(mer_mode)) = string.

:- func var_mode_to_string(prog_varset, inst_varset, var_name_print,
    pair(prog_var, mer_mode)) = string.

%---------------------------------------------------------------------------%

:- func type_import_status_to_string(type_status) = string.
:- func inst_import_status_to_string(inst_status) = string.
:- func mode_import_status_to_string(mode_status) = string.
:- func typeclass_import_status_to_string(typeclass_status) = string.
:- func instance_import_status_to_string(instance_status) = string.
:- func pred_import_status_to_string(pred_status) = string.

%---------------------------------------------------------------------------%

    % Write out a list of integers as a Mercury list.
    %
:- pred write_intlist(io.text_output_stream::in, list(int)::in,
    io::di, io::uo) is det.

%---------------------------------------------------------------------------%

    % Write out the given indent level (two spaces per indent).
    %
:- pred write_indent(io.text_output_stream::in, int::in, io::di, io::uo) is det.

    % Return the indent for the given level as a string.
    %
:- func indent_string(int) = string.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module hlds.hlds_rtti.
:- import_module hlds.special_pred.
:- import_module libs.options.
:- import_module mdbcomp.builtin_modules.
:- import_module mdbcomp.prim_data.
:- import_module parse_tree.mercury_to_mercury.
:- import_module parse_tree.parse_tree_out_inst.
:- import_module parse_tree.prog_out.
:- import_module parse_tree.prog_item.  % undesirable dependency

:- import_module assoc_list.
:- import_module int.
:- import_module map.
:- import_module string.
:- import_module term_io.
:- import_module varset.

%---------------------------------------------------------------------------%

init_hlds_out_info(Globals, Lang) = Info :-
    globals.lookup_string_option(Globals, dump_hlds_options, DumpOptions),
    globals.lookup_accumulating_option(Globals, dump_hlds_pred_id, Ids),
    globals.lookup_accumulating_option(Globals, dump_hlds_pred_name, Names),
    MercInfo = init_merc_out_info(Globals, unqualified_item_names, Lang),
    Info = hlds_out_info(DumpOptions, DumpOptions, Ids, Names, MercInfo).

%---------------------------------------------------------------------------%
%
% Write out the ids of predicates and procedures.
%

pred_id_to_string(ModuleInfo, PredId) = Str :-
    module_info_get_preds(ModuleInfo, PredTable),
    ( if map.search(PredTable, PredId, PredInfo) then
        Str = pred_info_id_to_string(PredInfo)
    else
        % The predicate has been deleted, so we print what we can.
        pred_id_to_int(PredId, PredIdInt),
        Str = "deleted predicate " ++ int_to_string(PredIdInt)
    ).

pred_info_id_to_string(PredInfo) = Str :-
    % XXX CLEANUP Either this function should replace write_origin in
    % hlds_out_pred.m, or vice versa.
    Module = pred_info_module(PredInfo),
    Name = pred_info_name(PredInfo),
    Arity = pred_info_orig_arity(PredInfo),
    PredOrFunc = pred_info_is_pred_or_func(PredInfo),
    pred_info_get_origin(PredInfo, Origin),
    (
        Origin = origin_special_pred(SpecialId, TypeCtor),
        special_pred_description(SpecialId, Descr),
        TypeCtor = type_ctor(_TypeSymName, TypeArity),
        ( if TypeArity = 0 then
            ForStr = " for type "
        else
            ForStr = " for type constructor "
        ),
        Str = Descr ++ ForStr ++ type_name_to_string(TypeCtor)
    ;
        Origin = origin_instance_method(MethodName, MethodConstraints),
        MethodConstraints = instance_method_constraints(ClassId,
            InstanceTypes, _, _),
        MethodStr = pf_sym_name_orig_arity_to_string(PredOrFunc, MethodName,
            Arity),
        ClassId = class_id(ClassName, _),
        ClassStr = sym_name_to_string(ClassName),
        TypeStrs = mercury_type_list_to_string(varset.init, InstanceTypes),
        string.format("instance method %s for `%s(%s)'",
            [s(MethodStr), s(ClassStr), s(TypeStrs)], Str)
    ;
        Origin = origin_class_method(ClassId, MethodId),
        ClassId = class_id(ClassSymName, ClassArity),
        MethodId = pf_sym_name_arity(MethodPredOrFunc,
            MethodSymName, MethodArity),
        string.format("class method %s %s/%d for %s/%d",
            [s(pred_or_func_to_string(MethodPredOrFunc)),
            s(sym_name_to_string(MethodSymName)), i(MethodArity),
            s(sym_name_to_string(ClassSymName)), i(ClassArity)], Str)
    ;
        Origin = origin_assertion(FileName, LineNumber),
        ( if pred_info_is_promise(PredInfo, PromiseType) then
            Str = string.format("`%s' declaration (%s:%d)",
                [s(prog_out.promise_to_string(PromiseType)),
                s(FileName), i(LineNumber)])
        else
            SymName = qualified(Module, Name),
            Str = pf_sym_name_orig_arity_to_string(PredOrFunc, SymName, Arity)
        )
    ;
        Origin = origin_tabling(BasePredId, TablingAuxPredKind),
        BasePredIdStr = pf_sym_name_orig_arity_to_string(BasePredId),
        (
            TablingAuxPredKind = tabling_aux_pred_stats,
            Str = "table statistics predicate for " ++ BasePredIdStr
        ;
            TablingAuxPredKind = tabling_aux_pred_reset,
            Str = "table reset predicate for " ++ BasePredIdStr
        )
    ;
        Origin = origin_solver_type(TypeCtorSymName, TypeCtorArity,
            SolverAuxPredKind),
        TypeStr = sym_name_arity_to_string(
            sym_name_arity(TypeCtorSymName, TypeCtorArity)),
        (
            SolverAuxPredKind = solver_type_to_ground_pred,
            Str = "to ground representation predicate for " ++ TypeStr
        ;
            SolverAuxPredKind = solver_type_to_any_pred,
            Str = "to any representation predicate for " ++ TypeStr
        ;
            SolverAuxPredKind = solver_type_from_ground_pred,
            Str = "from ground representation predicate for " ++ TypeStr
        ;
            SolverAuxPredKind = solver_type_from_any_pred,
            Str = "from any representation predicate for " ++ TypeStr
        )
    ;
        ( Origin = origin_transformed(_, _, _)
        ; Origin = origin_created(_)
        ; Origin = origin_mutable(_, _, _)
        ; Origin = origin_lambda(_, _, _)
        ; Origin = origin_initialise
        ; Origin = origin_finalise
        ; Origin = origin_user(_)
        ),
        SymName = qualified(Module, Name),
        Str = pf_sym_name_orig_arity_to_string(PredOrFunc, SymName, Arity)
    ).

pred_proc_id_to_string(ModuleInfo, proc(PredId, ProcId)) =
    pred_proc_id_pair_to_string(ModuleInfo, PredId, ProcId).

pred_proc_id_pair_to_string(ModuleInfo, PredId, ProcId) = Str :-
    proc_id_to_int(ProcId, ModeNum),
    Str = pred_id_to_string(ModuleInfo, PredId)
        ++ " mode " ++ int_to_string(ModeNum).

%---------------------------------------------------------------------------%
%
% Write out the contexts of unifications.
%

unify_context_to_pieces(UnifyContext, !Pieces) :-
    unify_context_first_to_pieces(is_not_first, _, UnifyContext, !Pieces).

unify_context_first_to_pieces(!First, UnifyContext, !Pieces) :-
    UnifyContext = unify_context(MainContext, RevSubContexts),
    list.reverse(RevSubContexts, SubContexts),
    unify_main_context_to_pieces(!First, MainContext, !Pieces),
    unify_sub_contexts_to_pieces(!First, SubContexts, !Pieces).

:- pred unify_main_context_to_pieces(is_first::in, is_first::out,
    unify_main_context::in,
    list(format_component)::in, list(format_component)::out) is det.

unify_main_context_to_pieces(!First, MainContext, !Pieces) :-
    (
        MainContext = umc_explicit
    ;
        MainContext = umc_head(ArgNum),
        start_in_message_to_pieces(!.First, !Pieces),
        !:First = is_not_first,
        ArgNumStr = int_to_string(ArgNum),
        !:Pieces = !.Pieces ++
            [words("argument"), fixed(ArgNumStr), words("of clause head:"), nl]
    ;
        MainContext = umc_head_result,
        start_in_message_to_pieces(!.First, !Pieces),
        !:First = is_not_first,
        !:Pieces = !.Pieces ++
            [words("function result term of clause head:"), nl]
    ;
        MainContext = umc_call(CallId, ArgNum),
        start_in_message_to_pieces(!.First, !Pieces),
        !:First = is_not_first,
        % The markers argument below is used only for type class method
        % implementations defined using the named syntax rather than
        % the clause syntax, and the bodies of such procedures should
        % only contain a single call, so we shouldn't get unifications
        % nested inside calls. Hence we can safely initialize the
        % markers to empty here. (Anyway the worst possible consequence
        % is slightly sub-optimal text for an error message.)
        init_markers(Markers),
        ArgIdStr = call_arg_id_to_string(CallId, ArgNum, Markers),
        !:Pieces = !.Pieces ++ [words(ArgIdStr), suffix(":"), nl]
    ;
        MainContext = umc_implicit(Source),
        start_in_message_to_pieces(!.First, !Pieces),
        string.format("implicit %s unification:\n", [s(Source)], Msg),
        !:Pieces = !.Pieces ++ [words(Msg), nl]
    ).

:- pred unify_sub_contexts_to_pieces(is_first::in, is_first::out,
    unify_sub_contexts::in,
    list(format_component)::in, list(format_component)::out) is det.

unify_sub_contexts_to_pieces(!First, [], !Pieces).
unify_sub_contexts_to_pieces(!First, [SubContext | SubContexts], !Pieces) :-
    ( if
        contexts_describe_list_element([SubContext | SubContexts],
            0, ElementNum, AfterContexts)
    then
        in_element_to_pieces(!.First, ElementNum, !Pieces),
        !:First = is_not_first,
        unify_sub_contexts_to_pieces(!First, AfterContexts, !Pieces)
    else
        in_argument_to_pieces(!.First, SubContext, !Pieces),
        !:First = is_not_first,
        unify_sub_contexts_to_pieces(!First, SubContexts, !Pieces)
    ).

:- pred contexts_describe_list_element(unify_sub_contexts::in,
    int::in, int::out, unify_sub_contexts::out) is semidet.

contexts_describe_list_element([SubContext | SubContexts],
        NumElementsBefore, ElementNum, AfterContexts) :-
    SubContext = unify_sub_context(ConsId, ArgNum),
    ConsId = cons(Functor, 2, _TypeCtor),
    % We ignore _TypeCtor since it may not have been set yet.
    (
        Functor = unqualified("[|]")
    ;
        Functor = qualified(ModuleSymName, "[|]"),
        is_std_lib_module_name(ModuleSymName, "list")
    ),
    (
        ArgNum = 1,
        ElementNum = NumElementsBefore,
        AfterContexts = SubContexts
    ;
        ArgNum = 2,
        contexts_describe_list_element(SubContexts,
            NumElementsBefore + 1, ElementNum, AfterContexts)
    ).

:- pred in_argument_to_pieces(is_first::in, unify_sub_context::in,
    list(format_component)::in, list(format_component)::out) is det.

in_argument_to_pieces(First, SubContext, !Pieces) :-
    start_in_message_to_pieces(First, !Pieces),
    SubContext = unify_sub_context(ConsId, ArgNum),
    ArgNumStr = int_to_string(ArgNum),
    % XXX Using cons_id_and_arity_to_string here results in the
    % quotes being in the wrong place.
    ConsIdStr = cons_id_and_arity_to_string(ConsId),
    !:Pieces = !.Pieces ++ [words("argument"), fixed(ArgNumStr),
        words("of functor"), quote(ConsIdStr), suffix(":"), nl].

:- pred in_element_to_pieces(is_first::in, int::in,
    list(format_component)::in, list(format_component)::out) is det.

in_element_to_pieces(First, ElementNum, !Pieces) :-
    start_in_message_to_pieces(First, !Pieces),
    ElementNumStr = int_to_string(ElementNum),
    !:Pieces = !.Pieces ++ [words("list element"),
        prefix("#"), fixed(ElementNumStr), suffix(":"), nl].

:- pred start_in_message_to_pieces(is_first::in,
    list(format_component)::in, list(format_component)::out) is det.

start_in_message_to_pieces(First, !Pieces) :-
    (
        First = is_first,
        % It is possible for First to be yes and !.Pieces to be nonempty,
        % since !.Pieces may contain stuff from before the unify context.
        !:Pieces = !.Pieces ++ [words("In")]
    ;
        First = is_not_first,
        !:Pieces = !.Pieces ++ [words("in")]
    ).

%---------------------------------------------------------------------------%

maybe_output_context_comment(Stream, Indent, Suffix, Context, !IO) :-
    term.context_file(Context, FileName),
    term.context_line(Context, LineNumber),
    ( if FileName = "" then
        true
    else
        write_indent(Stream, Indent, !IO),
        io.format(Stream, "%% context: file `%s', line %d%s\n",
            [s(FileName), i(LineNumber), s(Suffix)], !IO)
    ).

%---------------------------------------------------------------------------%
%
% Write out ids of calls.
%

call_id_to_string(plain_call_id(PredCallId)) =
    pf_sym_name_orig_arity_to_string(PredCallId).
call_id_to_string(generic_call_id(GenericCallId)) =
    generic_call_id_to_string(GenericCallId).

generic_call_id_to_string(gcid_higher_order(Purity, PredOrFunc, _)) =
    purity_prefix_to_string(Purity) ++ "higher-order "
    ++ prog_out.pred_or_func_to_full_str(PredOrFunc) ++ " call".
generic_call_id_to_string(gcid_class_method(_ClassId, MethodId)) =
    pf_sym_name_orig_arity_to_string(MethodId).
generic_call_id_to_string(gcid_event_call(EventName)) =
    "event " ++ EventName.
generic_call_id_to_string(gcid_cast(CastType)) =
    cast_type_to_string(CastType).

cast_type_to_string(unsafe_type_cast) = "unsafe_type_cast".
cast_type_to_string(unsafe_type_inst_cast) = "unsafe_type_inst_cast".
cast_type_to_string(equiv_type_cast) = "equiv_type_cast".
cast_type_to_string(exists_cast) = "exists_cast".

call_arg_id_to_string(CallId, ArgNum, PredMarkers) = Str :-
    ( if ArgNum =< 0 then
        % Argument numbers that are less than or equal to zero
        % are used for the type_info and typeclass_info arguments
        % that are introduced by polymorphism.m.
        % I think argument number equal to zero might also be used
        % in some other cases when we just don't have any information
        % about which argument it is.
        % For both of these, we just say "in call to"
        % rather than "in argument N of call to".
        Str1 = ""
    else
        Str1 = arg_number_to_string(CallId, ArgNum) ++ " of "
    ),
    ( if
        (
            % The text printed for generic calls other than
            % `class_method' does not need the "call to"
            % prefix ("in call to higher-order call" is redundant,
            % it's much better to just say "in higher-order call").
            CallId = generic_call_id(GenericCallId),
            not GenericCallId = gcid_class_method(_, _)
        ;
            % For calls from type class instance implementations
            % that were defined using the named syntax rather
            % than the clause syntax, we also omit the "call to",
            % since in that case there was no explicit call in
            % the user's source code.
            check_marker(PredMarkers, marker_named_class_instance_method)
        )
    then
        Str2 = Str1
    else
        Str2 = Str1 ++ "call to "
    ),
    Str = Str2 ++ call_id_to_string(CallId).

:- func arg_number_to_string(call_id, int) = string.

arg_number_to_string(CallId, ArgNum) = Str :-
    (
        CallId = plain_call_id(pf_sym_name_arity(PredOrFunc, _, Arity)),
        ( if
            PredOrFunc = pf_function,
            Arity = ArgNum
        then
            Str = "the return value"
        else
            Str = "argument " ++ int_to_string(ArgNum)
        )
    ;
        CallId = generic_call_id(GenericCallId),
        (
            GenericCallId = gcid_higher_order(_Purity, PredOrFunc, Arity),
            ( if
                PredOrFunc = pf_function,
                ArgNum = Arity
            then
                Str = "the return value"
            else
                % Make error messages for higher-order calls
                % such as `P(A, B)' clearer.
                Main = "argument " ++ int_to_string(ArgNum),
                PredOrFuncStr = prog_out.pred_or_func_to_full_str(PredOrFunc),
                ( if ArgNum = 1 then
                    Expl = "the " ++ PredOrFuncStr ++ " term"
                else
                    Expl = "argument " ++ int_to_string(ArgNum - 1)
                        ++ " of the called " ++ PredOrFuncStr
                ),
                Str = Main ++ " (i.e. " ++ Expl ++ ")"
            )
        ;
            ( GenericCallId = gcid_class_method(_, _)
            ; GenericCallId = gcid_event_call(_)
            ; GenericCallId = gcid_cast(_)
            ),
            Str = "argument " ++ int_to_string(ArgNum)
        )
    ).

%---------------------------------------------------------------------------%
%
% Write out functors.
%

functor_to_string(VarSet, VarNamePrint, Functor, ArgVars)  =
    functor_to_string_maybe_needs_quotes(VarSet, VarNamePrint,
        not_next_to_graphic_token, Functor, ArgVars).

functor_to_string_maybe_needs_quotes(VarSet, VarNamePrint, NextToGraphicToken,
        Functor, ArgVars) = Str :-
    term.context_init(Context),
    term.var_list_to_term_list(ArgVars, ArgTerms),
    Term = term.functor(Functor, ArgTerms, Context),
    Str = mercury_term_nq_to_string(VarSet, VarNamePrint, NextToGraphicToken,
        Term).

qualified_functor_to_string(VarSet, VarNamePrint, ModuleName, Functor,
        ArgVars) = Str :-
    ModuleNameStr = mercury_bracketed_sym_name_to_string(ModuleName),
    FunctorStr = functor_to_string_maybe_needs_quotes(VarSet, VarNamePrint,
        next_to_graphic_token, Functor, ArgVars),
    Str = ModuleNameStr ++ "." ++ FunctorStr.

qualified_functor_with_term_args_to_string(VarSet, VarNamePrint,
        ModuleName, Functor, ArgTerms) = Str :-
    ModuleNameStr = mercury_bracketed_sym_name_to_string(ModuleName),
    term.context_init(Context),
    Term = term.functor(Functor, ArgTerms, Context),
    TermStr = mercury_term_nq_to_string(VarSet, VarNamePrint,
        next_to_graphic_token, Term),
    Str = ModuleNameStr ++ "." ++ TermStr.

functor_cons_id_to_string(ModuleInfo, VarSet, VarNamePrint, ConsId, ArgVars)
        = Str :-
    (
        ConsId = cons(SymName, _, _),
        (
            SymName = qualified(Module, Name),
            Str = qualified_functor_to_string(VarSet, VarNamePrint,
                Module, term.atom(Name), ArgVars)
        ;
            SymName = unqualified(Name),
            Str = functor_to_string_maybe_needs_quotes(VarSet, VarNamePrint,
                next_to_graphic_token, term.atom(Name), ArgVars)
        )
    ;
        ConsId = tuple_cons(_),
        Str = functor_to_string_maybe_needs_quotes(VarSet, VarNamePrint,
            next_to_graphic_token, term.atom("{}"), ArgVars)
    ;
        ConsId = int_const(Int),
        Str = int_to_string(Int)
    ;
        ConsId = uint_const(UInt),
        Str = uint_to_string(UInt) ++ "u"
    ;
        ConsId = int8_const(Int8),
        Str = int8_to_string(Int8) ++ "i8"
    ;
        ConsId = uint8_const(UInt8),
        Str = uint8_to_string(UInt8) ++ "u8"
    ;
        ConsId = int16_const(Int16),
        Str = int16_to_string(Int16) ++ "i16"
    ;
        ConsId = uint16_const(UInt16),
        Str = uint16_to_string(UInt16) ++ "u16"
    ;
        ConsId = int32_const(Int32),
        Str = int32_to_string(Int32) ++ "i32"
    ;
        ConsId = uint32_const(UInt32),
        Str = uint32_to_string(UInt32) ++ "u32"
    ;
        ConsId = int64_const(Int64),
        Str = int64_to_string(Int64) ++ "i64"
    ;
        ConsId = uint64_const(UInt64),
        Str = uint64_to_string(UInt64) ++ "u64"
    ;
        ConsId = float_const(Float),
        Str = functor_to_string(VarSet, VarNamePrint,
            term.float(Float), ArgVars)
    ;
        ConsId = char_const(Char),
        % XXX The strings ('z') and ('\n') should always denote
        % the last letter of the alphabet and the newline character
        % respectively. We need to decide whether forms such as (z)
        % and 'z' should acceptable too. I (zs) think that 'z' should
        % be acceptable to the scanner and parser (which currently it isn't),
        % but (z) should not be.
        Str = "(" ++ term_io.quoted_char(Char) ++ ")"
    ;
        ConsId = string_const(String),
        Str = functor_to_string(VarSet, VarNamePrint,
            term.string(String), ArgVars)
    ;
        ConsId = impl_defined_const(Name),
        Str = "$" ++ Name
    ;
        ConsId = closure_cons(ShroudedPredProcId, _),
        proc(PredId, _) = unshroud_pred_proc_id(ShroudedPredProcId),
        module_info_pred_info(ModuleInfo, PredId, PredInfo),
        PredModule = pred_info_module(PredInfo),
        PredName = pred_info_name(PredInfo),
        PredSymName = qualified(PredModule, PredName),
        PredConsId = cons(PredSymName, list.length(ArgVars),
            cons_id_dummy_type_ctor),
        Str = functor_cons_id_to_string(ModuleInfo, VarSet, VarNamePrint,
            PredConsId, ArgVars)
    ;
        ConsId = type_ctor_info_const(Module, Name, Arity),
        Str = "type_ctor_info("""
            ++ prog_out.sym_name_to_escaped_string(Module)
            ++ """, """ ++ Name ++ """, " ++ int_to_string(Arity) ++ ")"
    ;
        ConsId = base_typeclass_info_const(Module, ClassId, _, Instance),
        ClassId = class_id(Name, Arity),
        Str = "base_typeclass_info("""
            ++ prog_out.sym_name_to_escaped_string(Module) ++ """, "
            ++ "class_id(" ++ prog_out.sym_name_to_escaped_string(Name)
            ++ ", " ++ int_to_string(Arity) ++ "), " ++ Instance ++ ")"
    ;
        ConsId = type_info_cell_constructor(_),
        Str = functor_to_string_maybe_needs_quotes(VarSet, VarNamePrint,
            next_to_graphic_token,
            term.atom("type_info_cell_constructor"), ArgVars)
    ;
        ConsId = typeclass_info_cell_constructor,
        Str = functor_to_string_maybe_needs_quotes(VarSet, VarNamePrint,
            next_to_graphic_token,
            term.atom("typeclass_info_cell_constructor"), ArgVars)
    ;
        ConsId = type_info_const(TIConstNum),
        Str = "type_info_const(" ++ int_to_string(TIConstNum) ++ ")"
    ;
        ConsId = typeclass_info_const(TCIConstNum),
        Str = "typeclass_info_const(" ++ int_to_string(TCIConstNum) ++ ")"
    ;
        ConsId = ground_term_const(ConstNum, SubConsId),
        SubStr = functor_cons_id_to_string(ModuleInfo, VarSet, VarNamePrint,
            SubConsId, []),
        Str = "ground_term_const(" ++ int_to_string(ConstNum) ++ ", " ++
            SubStr ++ ")"
    ;
        ConsId = tabling_info_const(ShroudedPredProcId),
        proc(PredId, ProcId) = unshroud_pred_proc_id(ShroudedPredProcId),
        proc_id_to_int(ProcId, ProcIdInt),
        Str = "tabling_info_const("
            ++ pred_id_to_string(ModuleInfo, PredId)
            ++ ", " ++ int_to_string(ProcIdInt) ++ ")"
    ;
        ConsId = table_io_entry_desc(ShroudedPredProcId),
        proc(PredId, ProcId) = unshroud_pred_proc_id(ShroudedPredProcId),
        proc_id_to_int(ProcId, ProcIdInt),
        Str = "table_io_entry_desc("
            ++ pred_id_to_string(ModuleInfo, PredId)
            ++ " (mode " ++ int_to_string(ProcIdInt) ++ "))"
    ;
        ConsId = deep_profiling_proc_layout(ShroudedPredProcId),
        proc(PredId, ProcId) = unshroud_pred_proc_id(ShroudedPredProcId),
        proc_id_to_int(ProcId, ProcIdInt),
        Str = "deep_profiling_proc_layout("
            ++ pred_id_to_string(ModuleInfo, PredId)
            ++ " (mode " ++ int_to_string(ProcIdInt) ++ "))"
    ).

cons_id_and_vars_or_arity_to_string(VarSet, Qual, ConsId, MaybeArgVars)
        = String :-
    (
        ConsId = cons(SymName0, Arity, _TypeCtor),
        (
            Qual = qualify_cons_id,
            SymName = SymName0
        ;
            Qual = do_not_qualify_cons_id,
            SymName = unqualified(unqualify_name(SymName0))
        ),
        SymNameString0 = sym_name_to_string(SymName),
        ( if string.contains_char(SymNameString0, '*') then
            % We need to protect against the * appearing next to a /
            Stuff = (pred(Char::in, Str0::in, Str::out) is det :-
                ( if Char = ('*') then
                    string.append(Str0, "star", Str)
                else
                    string.char_to_string(Char, CharStr),
                    string.append(Str0, CharStr, Str)
                )
            ),
            string.foldl(Stuff, SymNameString0, "", SymNameString1)
        else
            SymNameString1 = SymNameString0
        ),
        SymNameString = term_io.escaped_string(SymNameString1),
        (
            MaybeArgVars = no,
            String = SymNameString ++ "/" ++ string.int_to_string(Arity)
        ;
            MaybeArgVars = yes(ArgVars),
            (
                ArgVars = [],
                String = SymNameString ++ "/" ++ string.int_to_string(Arity)
            ;
                ArgVars = [_ | _],
                ArgStr = mercury_vars_to_name_only(VarSet, ArgVars),
                String = SymNameString ++ "(" ++ ArgStr ++ ")"
            )
        )
    ;
        ConsId = tuple_cons(Arity),
        (
            MaybeArgVars = no,
            String = "{}/" ++ string.int_to_string(Arity)
        ;
            MaybeArgVars = yes(ArgVars),
            (
                ArgVars = [],
                String = "{}/" ++ string.int_to_string(Arity)
            ;
                ArgVars = [_ | _],
                ArgStr = mercury_vars_to_name_only(VarSet, ArgVars),
                String = "{" ++ ArgStr ++ "}"
            )
        )
    ;
        ConsId = int_const(Int),
        string.int_to_string(Int, String)
    ;
        ConsId = uint_const(UInt),
        String = uint_to_string(UInt) ++ "u"
    ;
        ConsId = int8_const(Int8),
        String = string.int8_to_string(Int8) ++ "i8"
    ;
        ConsId = uint8_const(UInt8),
        String = string.uint8_to_string(UInt8) ++ "u8"
    ;
        ConsId = int16_const(Int16),
        String = string.int16_to_string(Int16) ++ "i16"
    ;
        ConsId = uint16_const(UInt16),
        String = string.uint16_to_string(UInt16) ++ "u16"
    ;
        ConsId = int32_const(Int32),
        String = string.int32_to_string(Int32) ++ "i32"
    ;
        ConsId = uint32_const(UInt32),
        String = string.uint32_to_string(UInt32) ++ "u32"
    ;
        ConsId = int64_const(Int64),
        String = string.int64_to_string(Int64) ++ "i64"
    ;
        ConsId = uint64_const(UInt64),
        String = string.uint64_to_string(UInt64) ++ "u64"
    ;
        ConsId = float_const(Float),
        String = float_to_string(Float)
    ;
        ConsId = char_const(CharConst),
        String = term_io.quoted_char(CharConst)
    ;
        ConsId = string_const(StringConst),
        String = term_io.quoted_string(StringConst)
    ;
        ConsId = impl_defined_const(Name),
        String = "$" ++ Name
    ;
        ConsId = closure_cons(PredProcId, _),
        PredProcId = shrouded_pred_proc_id(PredId, ProcId),
        String =
            "<pred " ++ int_to_string(PredId) ++
            " proc " ++ int_to_string(ProcId) ++ ">"
    ;
        ConsId = type_ctor_info_const(Module, Ctor, Arity),
        String =
            "<type_ctor_info " ++ sym_name_to_string(Module) ++ "." ++
            Ctor ++ "/" ++ int_to_string(Arity) ++ ">"
    ;
        ConsId = base_typeclass_info_const(_, _, _, _),
        String = "<base_typeclass_info>"
    ;
        ConsId = type_info_cell_constructor(_),
        String = "<type_info_cell_constructor>"
    ;
        ConsId = typeclass_info_cell_constructor,
        String = "<typeclass_info_cell_constructor>"
    ;
        ConsId = type_info_const(_),
        String = "<type_info_const>"
    ;
        ConsId = typeclass_info_const(_),
        String = "<typeclass_info_const>"
    ;
        ConsId = ground_term_const(_, _),
        String = "<ground_term_const>"
    ;
        ConsId = tabling_info_const(PredProcId),
        PredProcId = shrouded_pred_proc_id(PredId, ProcId),
        String =
            "<tabling_info " ++ int_to_string(PredId) ++
            ", " ++ int_to_string(ProcId) ++ ">"
    ;
        ConsId = table_io_entry_desc(PredProcId),
        PredProcId = shrouded_pred_proc_id(PredId, ProcId),
        String =
            "<table_io_entry_desc " ++ int_to_string(PredId) ++ ", " ++
            int_to_string(ProcId) ++ ">"
    ;
        ConsId = deep_profiling_proc_layout(PredProcId),
        PredProcId = shrouded_pred_proc_id(PredId, ProcId),
        String =
            "<deep_profiling_proc_layout " ++ int_to_string(PredId) ++ ", " ++
            int_to_string(ProcId) ++ ">"
    ).

%---------------------------------------------------------------------------%
%
% Write out constraint proofs.
%

write_constraint_proof_map(Stream, Indent, VarNamePrint, TVarSet,
        ProofMap, !IO) :-
    write_indent(Stream, Indent, !IO),
    io.write_string(Stream, "% Proofs: \n", !IO),
    map.to_assoc_list(ProofMap, ProofsList),
    write_out_list(write_constraint_proof(Indent, VarNamePrint, TVarSet),
        "\n", ProofsList, Stream, !IO).

:- pred write_constraint_proof(int::in, var_name_print::in, tvarset::in,
    pair(prog_constraint, constraint_proof)::in,
    io.text_output_stream::in, io::di, io::uo) is det.

write_constraint_proof(Indent, VarNamePrint, TVarSet, Constraint - Proof,
        Stream, !IO) :-
    write_indent(Stream, Indent, !IO),
    io.write_string(Stream, "% ", !IO),
    mercury_output_constraint(TVarSet, VarNamePrint, Constraint, Stream, !IO),
    io.write_string(Stream, ": ", !IO),
    (
        Proof = apply_instance(Num),
        io.write_string(Stream, "apply instance decl #", !IO),
        io.write_int(Stream, Num, !IO)
    ;
        Proof = superclass(Super),
        io.write_string(Stream, "super class of ", !IO),
        mercury_output_constraint(TVarSet, VarNamePrint, Super, Stream, !IO)
    ).

%---------------------------------------------------------------------------%
%
% Write out modes.
%

var_modes_to_string(VarSet, InstVarSet, VarNamePrint, Vars, Modes) = Str :-
    assoc_list.from_corresponding_lists(Vars, Modes, VarModes),
    Strs = list.map(var_mode_to_string(VarSet, InstVarSet, VarNamePrint),
        VarModes),
    Str = string.join_list(", ", Strs).

var_mode_to_string(VarSet, InstVarSet, VarNamePrint, Var - Mode) =
    mercury_var_to_string(VarSet, VarNamePrint, Var)
        ++ "::" ++ mercury_mode_to_string(output_debug, InstVarSet, Mode).

%---------------------------------------------------------------------------%
%
% Write out statuses.
%

type_import_status_to_string(type_status(OldImportStatus)) =
    old_import_status_to_string(OldImportStatus).
inst_import_status_to_string(inst_status(InstModeStatus)) =
    instmode_status_to_string(InstModeStatus).
mode_import_status_to_string(mode_status(InstModeStatus)) =
    instmode_status_to_string(InstModeStatus).
typeclass_import_status_to_string(typeclass_status(OldImportStatus)) =
    old_import_status_to_string(OldImportStatus).
instance_import_status_to_string(instance_status(OldImportStatus)) =
    old_import_status_to_string(OldImportStatus).
pred_import_status_to_string(pred_status(OldImportStatus)) =
    old_import_status_to_string(OldImportStatus).

:- func instmode_status_to_string(new_instmode_status) = string.

instmode_status_to_string(InstModeStatus) = Str :-
    (
        InstModeStatus = instmode_defined_in_this_module(InstModeExport),
        (
            InstModeExport = instmode_export_nowhere,
            Str = "this_module(export_nowhere)"
        ;
            InstModeExport = instmode_export_only_submodules,
            Str = "this_module(export_only_submodules)"
        ;
            InstModeExport = instmode_export_anywhere,
            Str = "this_module(export_anywhere)"
        )
    ;
        InstModeStatus = instmode_defined_in_other_module(InstModeImport),
        (
            InstModeImport = instmode_import_plain,
            Str = "other_module(import_plain)"
        ;
            InstModeImport = instmode_import_abstract,
            Str = "other_module(import_abstract)"
        ;
            InstModeImport = instmode_import_opt,
            Str = "other_module(import_opt)"
        )
    ).

:- func old_import_status_to_string(old_import_status) = string.

old_import_status_to_string(status_local) =
    "local".
old_import_status_to_string(status_exported) =
    "exported".
old_import_status_to_string(status_opt_exported) =
    "opt_exported".
old_import_status_to_string(status_abstract_exported) =
    "abstract_exported".
old_import_status_to_string(status_pseudo_exported) =
    "pseudo_exported".
old_import_status_to_string(status_imported(import_locn_interface)) =
    "imported in the interface".
old_import_status_to_string(status_imported(import_locn_implementation)) =
    "imported in the implementation".
old_import_status_to_string(status_imported(
        import_locn_ancestor_int0_interface)) =
    "imported by an ancestor in its interface".
old_import_status_to_string(status_imported(
        import_locn_ancestor_int0_implementation)) =
    "imported by an ancestor in its implementation".
old_import_status_to_string(status_imported(import_locn_import_by_ancestor)) =
    "imported by a module imported by an ancestor".
old_import_status_to_string(status_external(Status)) =
    "external (and " ++ old_import_status_to_string(Status) ++ ")".
old_import_status_to_string(status_abstract_imported) =
    "abstract_imported".
old_import_status_to_string(status_opt_imported) =
    "opt_imported".
old_import_status_to_string(status_pseudo_imported) =
    "pseudo_imported".
old_import_status_to_string(status_exported_to_submodules) =
    "exported_to_submodules".

%---------------------------------------------------------------------------%
%
% Write out lists of integers as Mercury terms.
%

write_intlist(Stream, IntList, !IO) :-
    (
        IntList = [],
        io.write_string(Stream, "[]", !IO)
    ;
        IntList = [H | T],
        io.write_string(Stream, "[", !IO),
        write_intlist_lag(Stream, H, T, !IO),
        io.write_string(Stream, "]", !IO)
    ).

:- pred write_intlist_lag(io.text_output_stream::in, int::in, list(int)::in,
    io::di, io::uo) is det.

write_intlist_lag(Stream, H, T, !IO) :-
    io.write_int(Stream, H, !IO),
    (
        T = [TH | TT],
        io.write_string(Stream, ", ", !IO),
        write_intlist_lag(Stream, TH, TT, !IO)
    ;
        T = []
    ).

%---------------------------------------------------------------------------%
%
% Write out indentation.
%

write_indent(Stream, Indent, !IO) :-
    ( if Indent = 0 then
        true
    else
        io.write_string(Stream, "  ", !IO),
        write_indent(Stream, Indent - 1, !IO)
    ).

indent_string(Indent) = Str :-
    ( if Indent = 0 then
        Str = ""
    else
        Str = "  " ++ indent_string(Indent - 1)
    ).

%---------------------------------------------------------------------------%
:- end_module hlds.hlds_out.hlds_out_util.
%---------------------------------------------------------------------------%
