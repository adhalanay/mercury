%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 2015 The Mercury team.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% This module implements the first pass of module_qual.m; it records
% what entities are available from which modules and with what permissions.
%

:- module parse_tree.module_qual.qual_errors.
:- interface.

:- import_module mdbcomp.
:- import_module mdbcomp.prim_data.
:- import_module parse_tree.prog_data.

%---------------------------------------------------------------------------%
%
% Facilities for recording the contexts of errors.
%

:- type mq_constraint_error_context
    --->    mqcec_class_defn(prog_context,
                % The name of the type class beging defined, and its arity.
                class_name,
                int
            )
    ;       mqcec_class_method(prog_context,
                % The identity of the class method the constraint is on:
                % whether it is predicate or function, and its name.
                % Its arity would be nice, but it is tricky to calculate
                % in the presence of with_type.
                pred_or_func,
                string
            )
    ;       mqcec_instance_defn(prog_context,
                % The name of the class the instance is for, and the
                % instance type vector.
                class_name,
                list(mer_type)
            )
    ;       mqcec_type_defn_constructor(prog_context,
                % The name of the type whose definition the constraint is in.
                type_ctor,

                % The function symbol the constraint is on.
                string
            )
    ;       mqcec_pred_decl(prog_context,
                % The identity of the entity the constraint is on:
                % whether it is predicate or function, and its name.
                % Its arity would be nice, but it is tricky to calculate
                % in the presence of with_type.
                pred_or_func,
                sym_name,
                int
            ).

:- type mq_error_context
    --->    mqec_type_defn(prog_context,
                % The name of the type constructor whose definition we are in.
                type_ctor
            )
    ;       mqec_constructor_arg(prog_context,
                % The name of the type constructor whose definition we are in.
                type_ctor,

                % The name of the function symbol.
                string,

                % The argument number of the type.
                int,

                % The name of the field, if it has one.
                maybe(ctor_field_name)
            )
    ;       mqec_typeclass_constraint_name(
                % The context the constraint is in.
                mq_constraint_error_context
            )
    ;       mqec_typeclass_constraint(
                % The name and arity of the typeclass the constraint is for.
                sym_name,
                int,

                % The context the constraint is in.
                mq_constraint_error_context
            )
    ;       mqec_inst(prog_context,
                % The name of the inst.
                mq_id
            )
    ;       mqec_mode(prog_context,
                % The name of the mode.
                mq_id
            )
    ;       mqec_pred_or_func(prog_context,
                % Whether it is a predicate or function declaration, ...
                pred_or_func,

                % and its name.
                mq_id
            )
    ;       mqec_pred_or_func_mode(prog_context,
                maybe(pred_or_func),
                mq_id
            )
    ;       mqec_pragma(prog_context,
                pragma_type
            )
    ;       mqec_lambda_expr(prog_context)
    ;       mqec_clause_mode_annotation(prog_context)
    ;       mqec_type_qual(prog_context)
    ;       mqec_class(prog_context,
                mq_id
            )
    ;       mqec_instance(prog_context,
                mq_id
            )
    ;       mqec_mutable(prog_context,
                string
            )
    ;       mqec_event_spec_attr(prog_context,
                % The event name.
                string,

                % The attribute name.
                string
            ).

%---------------------------------------------------------------------------%

    % Report an undefined type, inst or mode.
    %
:- pred report_undefined_mq_id(mq_info::in, mq_error_context::in,
    mq_id::in, id_type::in, list(module_name)::in, set(int)::in,
    list(error_spec)::in, list(error_spec)::out) is det.

    % Report an error where a type, inst, mode or typeclass had
    % multiple possible matches.
    %
:- pred report_ambiguous_match(mq_error_context::in, mq_id::in, id_type::in,
    list(module_name)::in, list(module_name)::in,
    list(error_spec)::in, list(error_spec)::out) is det.

:- pred report_may_not_use_in_interface(mq_error_context::in,
    id_type::in, sym_name::in, arity::in,
    list(error_spec)::in, list(error_spec)::out) is det.

    % Output an error message about an ill-formed user_inst.
    %
:- pred report_invalid_user_inst(sym_name::in, list(mer_inst)::in,
    mq_error_context::in, list(error_spec)::in, list(error_spec)::out) is det.

    % Warn about a module imported in the interface that is not used
    % in the interface.
    %
:- pred warn_unused_interface_import(module_name::in,
    pair(module_name, one_or_more(prog_context))::in,
    list(error_spec)::in, list(error_spec)::out) is det.

%---------------------------------------------------------------------------%

:- implementation.

:- import_module parse_tree.prog_out.
:- import_module parse_tree.prog_util.

%---------------------------------------------------------------------------%
%
% Error reporting predicates.
%

report_undefined_mq_id(Info, ErrorContext, Id, IdType,
        UnusableModules, PossibleAritiesSet, !Specs) :-
    mq_error_context_to_pieces(ErrorContext, Context, ErrorContextPieces),
    id_type_to_string(IdType, IdStr),
    Pieces1 = [words("In")] ++ ErrorContextPieces ++ [suffix(":"), nl,
        words("error: undefined"), fixed(IdStr),
        sym_name_and_arity(id_to_sym_name_and_arity(Id)), suffix("."), nl],
    ( if
        % If it is a qualified symbol, then check whether the specified module
        % has been imported.

        Id = mq_id(qualified(ModuleName, _), _Arity),
        mq_info_get_this_module(Info, ThisModuleName),
        mq_info_get_imported_modules(Info, ImportedModuleNames),
        AvailModuleNames =
            [ThisModuleName | set.to_sorted_list(ImportedModuleNames)],
        module_name_matches_some(ModuleName, AvailModuleNames) = no
    then
        Pieces2 = [words("(The module"), sym_name(ModuleName),
            words("has not been imported.)"), nl]
    else
        (
            UnusableModules = [],
            Pieces2 = []
        ;
            UnusableModules = [_ | UnusableModulesTail],
            (
                UnusableModulesTail = [],
                ModuleWord = "module",
                HasWord = "has"
            ;
                UnusableModulesTail = [_ | _],
                ModuleWord = "modules",
                HasWord = "have"
            ),
            UnusableSymNames = list.map(wrap_module_name, UnusableModules),
            Pieces2 = [words("(The"), fixed(ModuleWord)] ++
                component_list_to_pieces(UnusableSymNames) ++
                [fixed(HasWord),
                    words("not been imported in the interface.)"), nl]
        )
    ),
    set.to_sorted_list(PossibleAritiesSet, PossibleArities),
    ( if
        PossibleArities = [_ | _],
        Pieces2 = []
    then
        Id = mq_id(SymName, _),
        id_types_to_string(IdType, IdsStr),
        IsAre = choose_number(PossibleArities, "is a", "are"),
        KindKinds = choose_number(PossibleArities, IdStr, IdsStr),
        ArityArities = choose_number(PossibleArities, "arity", "arities"),
        list.map(string.int_to_string, PossibleArities, PossibleArityStrs),
        PossibleAritiesPieces = list_to_pieces(PossibleArityStrs),
        Pieces3 = [words("(There"), words(IsAre), words(KindKinds),
            words("named"), quote(unqualify_name(SymName)),
            words("with"), words(ArityArities)] ++
            PossibleAritiesPieces ++ [suffix(".)"), nl]
    else
        Pieces3 = []
    ),
    Msg = simple_msg(Context, [always(Pieces1 ++ Pieces2 ++ Pieces3)]),
    Spec = error_spec(severity_error, phase_parse_tree_to_hlds, [Msg]),
    !:Specs = [Spec | !.Specs].

:- func module_name_matches_some(module_name, list(module_name)) = bool.

module_name_matches_some(_SearchModuleName, []) = no.
module_name_matches_some(SearchModuleName, [ModuleName | ModuleNames]) =
        Matches :-
    ( if partial_sym_name_matches_full(SearchModuleName, ModuleName) then
        Matches = yes
    else
        Matches = module_name_matches_some(SearchModuleName, ModuleNames)
    ).

report_ambiguous_match(ErrorContext, Id, IdType,
        UsableModuleNames, UnusableModuleNames, !Specs) :-
    mq_error_context_to_pieces(ErrorContext, Context, ErrorContextPieces),
    id_type_to_string(IdType, IdStr),
    UsableModuleSymNames = list.map(wrap_module_name, UsableModuleNames),
    MainPieces = [words("In")] ++ ErrorContextPieces ++ [suffix(":"), nl,
        words("ambiguity error: multiple possible matches for"),
        fixed(IdStr), wrap_id(Id), suffix("."), nl,
        words("The possible matches are in modules")] ++
        UsableModuleSymNames ++ [suffix("."), nl],
    (
        UnusableModuleNames = [],
        UnusablePieces = []
    ;
        (
            UnusableModuleNames = [_],
            MatchWord = "match"
        ;
            UnusableModuleNames = [_, _ | _],
            MatchWord = "matches"
        ),
        UnusableModuleSymNames =
            list.map(wrap_module_name, UnusableModuleNames),
        UnusablePieces = [words("The"), words(MatchWord),
            words("in modules")] ++ UnusableModuleSymNames ++
            [words("may not be used in the interface."), nl]
    ),
    VerbosePieces = [words("An explicit module qualifier"),
        words("may be necessary."), nl],
    Msg = simple_msg(Context,
        [always(MainPieces), always(UnusablePieces),
        verbose_only(verbose_always, VerbosePieces)]),
    Spec = error_spec(severity_error, phase_parse_tree_to_hlds, [Msg]),
    !:Specs = [Spec | !.Specs].

%---------------------------------------------------------------------------%

report_may_not_use_in_interface(ErrorContext, IdType,
        BadSymName, BadArity, !Specs) :-
    mq_error_context_to_pieces(ErrorContext, Context, ErrorContextPieces),
    id_type_to_string(IdType, IdStr),
    SNA = sym_name_and_arity(BadSymName / BadArity),
    MainPieces = [words("In")] ++ ErrorContextPieces ++ [suffix(":"), nl,
        words("error: the"), fixed(IdStr), SNA, words("is not exported,"),
        words("and thus it may not be used in the interface."), nl],
    Msg = simple_msg(Context, [always(MainPieces)]),
    Spec = error_spec(severity_error, phase_parse_tree_to_hlds, [Msg]),
    !:Specs = [Spec | !.Specs].

%---------------------------------------------------------------------------%

report_invalid_user_inst(_SymName, _Insts, ErrorContext, !Specs) :-
    mq_error_context_to_pieces(ErrorContext, Context, ErrorContextPieces),
    Pieces = [words("In")] ++ ErrorContextPieces ++ [suffix(":"), nl,
        words("error: variable used as inst constructor."), nl],
    Msg = simple_msg(Context, [always(Pieces)]),
    Spec = error_spec(severity_error, phase_parse_tree_to_hlds, [Msg]),
    !:Specs = [Spec | !.Specs].

%---------------------------------------------------------------------------%

warn_unused_interface_import(ParentModuleName,
        ImportedModuleName - ImportContexts, !Specs) :-
    ImportContexts = one_or_more(HeadContext, TailContexts),
    HeadPieces =
        [words("In module"), sym_name(ParentModuleName), suffix(":"), nl,
        words("warning: module"), sym_name(ImportedModuleName),
        words("is imported in the interface,"),
        words("but it is not used in the interface."), nl],
    HeadMsg = simple_msg(HeadContext,
        [option_is_set(warn_interface_imports, yes, [always(HeadPieces)])]),
    % TailContexts is almost always [], we add TailMsgs just in case it isn't.
    list.map(warn_redundant_import_context(ImportedModuleName),
        TailContexts, TailMsgs),
    Severity = severity_conditional(warn_interface_imports, yes,
        severity_warning, no),
    Spec = error_spec(Severity, phase_parse_tree_to_hlds,
        [HeadMsg | TailMsgs]),
    !:Specs = [Spec | !.Specs].

:- pred warn_redundant_import_context(module_name::in, prog_context::in,
    error_msg::out) is det.

warn_redundant_import_context(ImportedModuleName, Context, Msg) :-
    Pieces = [words("Module"), sym_name(ImportedModuleName),
        words("is also redundantly imported here."), nl],
    Msg = simple_msg(Context,
        [option_is_set(warn_interface_imports, yes, [always(Pieces)])]).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- pred mq_constraint_error_context_to_pieces(mq_constraint_error_context::in,
    prog_context::out, string::out, list(format_component)::out) is det.

mq_constraint_error_context_to_pieces(ConstraintErrorContext,
        Context, Start, Pieces) :-
    (
        ConstraintErrorContext = mqcec_class_defn(Context, ClassName, Arity),
        Start = "in",
        Pieces = [words("definition of type class"),
            sym_name_and_arity(ClassName / Arity)]
    ;
        ConstraintErrorContext = mqcec_class_method(Context,
            PredOrFunc, MethodName),
        Start = "on",
        Pieces = [words("class method"),
            p_or_f(PredOrFunc), quote(MethodName)]
    ;
        ConstraintErrorContext = mqcec_instance_defn(Context,
            ClassName, ArgTypes),
        Start = "on",
        Pieces = [words("instance definition for"),
            sym_name_and_arity(ClassName / list.length(ArgTypes))]
    ;
        ConstraintErrorContext = mqcec_type_defn_constructor(Context,
            TypeCtor, FunctionSymbol),
        Start = "on",
        TypeCtor = type_ctor(TypeCtorSymName, TypeCtorArity),
        Pieces = [words("function symbol"), quote(FunctionSymbol),
            words("for type constructor"),
            sym_name_and_arity(TypeCtorSymName / TypeCtorArity)]
    ;
        ConstraintErrorContext = mqcec_pred_decl(Context,
            PredOrFunc, SymName, OrigArity),
        Start = "on",
        adjust_func_arity(PredOrFunc, OrigArity, Arity),
        Pieces = [words("declaration of "),
            fixed(pred_or_func_to_full_str(PredOrFunc)),
            sym_name_and_arity(SymName / Arity)]
    ).

:- pred mq_error_context_to_pieces(mq_error_context::in,
    prog_context::out, list(format_component)::out) is det.

mq_error_context_to_pieces(ErrorContext, Context,Pieces) :-
    (
        ErrorContext = mqec_type_defn(Context, TypeCtor),
        Pieces = [words("definition of type"), wrap_type_ctor(TypeCtor)]
    ;
        ErrorContext = mqec_constructor_arg(Context, ContainingTypeCtor,
            FunctionSymbol, ArgNum, MaybeCtorFieldName),
        (
            MaybeCtorFieldName = no,
            FieldNamePieces = []
        ;
            MaybeCtorFieldName = yes(CtorFieldName),
            CtorFieldName = ctor_field_name(FieldSymName, _FieldContext),
            FieldNamePieces = [words("(field name"),
                quote(unqualify_name(FieldSymName)), suffix(")")]
        ),
        Pieces = [words("the"), nth_fixed(ArgNum), words("argument of"),
            words("function symbol"), quote(FunctionSymbol)] ++
            FieldNamePieces ++
            [words("of the type"), wrap_type_ctor(ContainingTypeCtor)]
    ;
        ErrorContext = mqec_typeclass_constraint_name(ConstraintErrorContext),
        mq_constraint_error_context_to_pieces(ConstraintErrorContext,
            Context, _Start, Pieces)
    ;
        ErrorContext = mqec_typeclass_constraint(ClassName, Arity,
            ConstraintErrorContext),
        mq_constraint_error_context_to_pieces(ConstraintErrorContext,
            Context, Start, ConstraintErrorContextPieces),
        Pieces = [words("type class constraint for "),
            sym_name_and_arity(ClassName / Arity), words(Start) |
            ConstraintErrorContextPieces]
    ;
        ErrorContext = mqec_mode(Context, Id),
        Pieces = [words("definition of mode"), wrap_id(Id)]
    ;
        ErrorContext = mqec_inst(Context, Id),
        Pieces = [words("definition of inst"), wrap_id(Id)]
    ;
        ErrorContext = mqec_pred_or_func(Context, PredOrFunc, Id),
        Id = mq_id(SymName, OrigArity),
        adjust_func_arity(PredOrFunc, OrigArity, Arity),
        Pieces = [words("declaration of "),
            fixed(pred_or_func_to_full_str(PredOrFunc)),
            sym_name_and_arity(SymName / Arity)]
    ;
        ErrorContext = mqec_pred_or_func_mode(Context, MaybePredOrFunc, Id),
        Id = mq_id(SymName, OrigArity),
        (
            MaybePredOrFunc = yes(PredOrFunc),
            adjust_func_arity(PredOrFunc, OrigArity, Arity),
            Pieces = [words("mode declaration for"),
                fixed(pred_or_func_to_full_str(PredOrFunc)),
                sym_name_and_arity(SymName / Arity)]
        ;
            MaybePredOrFunc = no,
            Pieces = [words("mode declaration for"),
                sym_name_and_arity(SymName / OrigArity)]
        )
    ;
        ErrorContext = mqec_lambda_expr(Context),
        Pieces = [words("mode declaration for lambda expression")]
    ;
        ErrorContext = mqec_clause_mode_annotation(Context),
        Pieces = [words("clause mode annotation")]
    ;
        ErrorContext = mqec_pragma(Context, Pragma),
        (
            Pragma = pragma_foreign_decl(_),
            PragmaName = "foreign_decl"
        ;
            Pragma = pragma_foreign_code(_),
            PragmaName = "foreign_code"
        ;
            Pragma = pragma_foreign_proc(_),
            PragmaName = "foreign_proc"
        ;
            Pragma = pragma_foreign_import_module(_),
            PragmaName = "foreign_import_module"
        ;
            Pragma = pragma_foreign_proc_export(_),
            PragmaName = "foreign_proc_export"
        ;
            Pragma = pragma_foreign_export_enum(_),
            PragmaName = "foreign_export_enum"
        ;
            Pragma = pragma_foreign_enum(_),
            PragmaName = "foreign_enum"
        ;
            Pragma = pragma_external_proc(_),
            PragmaName = "external_proc"
        ;
            Pragma = pragma_type_spec(_),
            PragmaName = "type_spec"
        ;
            Pragma = pragma_inline(_),
            PragmaName = "inline"
        ;
            Pragma = pragma_no_inline(_),
            PragmaName = "no_inline"
        ;
            Pragma = pragma_unused_args(_),
            PragmaName = "unused_args"
        ;
            Pragma = pragma_exceptions(_),
            PragmaName = "exceptions"
        ;
            Pragma = pragma_trailing_info(_),
            PragmaName = "trailing_info"
        ;
            Pragma = pragma_mm_tabling_info(_),
            PragmaName = "mm_tabling_info"
        ;
            Pragma = pragma_obsolete(_),
            PragmaName = "obsolete"
        ;
            Pragma = pragma_no_detism_warning(_),
            PragmaName = "no_detism_warning"
        ;
            Pragma = pragma_tabled(_),
            PragmaName = "tabled"
        ;
            Pragma = pragma_fact_table(_),
            PragmaName = "fact_table"
        ;
            Pragma = pragma_reserve_tag(_),
            PragmaName = "reserve_tag"
        ;
            Pragma = pragma_oisu(_),
            PragmaName = "oisu"
        ;
            Pragma = pragma_promise_eqv_clauses(_),
            PragmaName = "promise_equivalent_clauses"
        ;
            Pragma = pragma_promise_pure(_),
            PragmaName = "promise_pure"
        ;
            Pragma = pragma_promise_semipure(_),
            PragmaName = "promise_semipure"
        ;
            Pragma = pragma_termination_info(_),
            PragmaName = "termination_info"
        ;
            Pragma = pragma_termination2_info(_),
            PragmaName = "termination2_info"
        ;
            Pragma = pragma_terminates(_),
            PragmaName = "terminates"
        ;
            Pragma = pragma_does_not_terminate(_),
            PragmaName = "does_not_terminate"
        ;
            Pragma = pragma_check_termination(_),
            PragmaName = "check_termination"
        ;
            Pragma = pragma_mode_check_clauses(_),
            PragmaName = "mode_check_clauses"
        ;
            Pragma = pragma_structure_sharing(_),
            PragmaName = "structure_sharing"
        ;
            Pragma = pragma_structure_reuse(_),
            PragmaName = "structure_reuse"
        ;
            Pragma = pragma_require_feature_set(_),
            PragmaName = "require_feature_set"
        ),
        Pieces = [words("pragma"), words(PragmaName)]
    ;
        ErrorContext = mqec_type_qual(Context),
        Pieces = [words("explicit type qualification")]
    ;
        ErrorContext = mqec_class(Context, Id),
        Pieces = [words("declaration of typeclass"), wrap_id(Id)]
    ;
        ErrorContext = mqec_instance(Context, Id),
        Pieces = [words("declaration of instance of typeclass"), wrap_id(Id)]
    ;
        ErrorContext = mqec_mutable(Context, Name),
        Pieces = [words("declaration for mutable "), quote(Name)]
    ;
        ErrorContext = mqec_event_spec_attr(Context, EventName, AttrName),
        Pieces = [words("attribute"), quote(AttrName),
            words("for"), quote(EventName)]
    ).

:- pred id_type_to_string(id_type::in, string::out) is det.

id_type_to_string(type_id, "type").
id_type_to_string(mode_id, "mode").
id_type_to_string(inst_id, "inst").
id_type_to_string(class_id, "typeclass").

:- pred id_types_to_string(id_type::in, string::out) is det.

id_types_to_string(type_id, "types").
id_types_to_string(mode_id, "modes").
id_types_to_string(inst_id, "insts").
id_types_to_string(class_id, "typeclasses").

%---------------------------------------------------------------------------%

:- func id_to_sym_name_and_arity(mq_id) = sym_name_and_arity.

id_to_sym_name_and_arity(mq_id(SymName, Arity)) = SymName / Arity.

:- func wrap_module_name(module_name) = format_component.

wrap_module_name(SymName) = sym_name(SymName).

:- func wrap_type_ctor(type_ctor) = format_component.

wrap_type_ctor(type_ctor(SymName, Arity)) =
    sym_name_and_arity(SymName / Arity).

:- func wrap_id(mq_id) = format_component.

wrap_id(mq_id(SymName, Arity)) = sym_name_and_arity(SymName / Arity).

%---------------------------------------------------------------------------%
:- end_module parse_tree.module_qual.qual_errors.
%---------------------------------------------------------------------------%