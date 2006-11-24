%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 1997-2000,2002-2006 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
% 
% File: continuation_info.m.
% Main author: trd.
% Extensive modifications by zs.
% 
% This file defines the data structures the code generator uses to collect
% information that will later be converted into layout tables for accurate
% garbage collection, stack tracing, execution tracing, deep profiling and
% perhaps other purposes.
%
% Information is collected in several passes.
%
%   1 Before we start generating code for a procedure,
%     we initialize the set of internal labels for which we have
%     layout information to the empty set. This set is stored in
%     the code generator state.
%
%   2 During code generation for the procedure, provided the option
%     trace_stack_layouts is set, we add layout information for labels
%     that represent trace ports to the code generator state. If
%     agc_stack_layouts is set, we add layout information for the stack
%     label in each resumption point. And regardless of option settings,
%     we also generate layouts to be attached to any closures we create.
%
%   3 After we finish generating code for a procedure, we record
%     all the static information about the procedure (some of which
%     is available only after code generation), together with the
%     info about internal labels accumulated in the code generator state,
%     in the global_data structure.
%
%   4 If agc_stack_layouts is set, we make a pass over the
%     optimized code recorded in the final LLDS instructions.
%     In this pass, we collect information from call instructions
%     about the internal labels to which calls can return.
%     This info will also go straight into the global_data.
%
% This module defines the data structures used by all passes. It also
% implements the whole of pass 4, and various fractions of the other passes.
%
% stack_layout.m converts the information collected in this module into
% stack_layout tables.
% 
%-----------------------------------------------------------------------------%

:- module ll_backend.continuation_info.
:- interface.

:- import_module hlds.hlds_goal.
:- import_module hlds.hlds_module.
:- import_module hlds.hlds_pred.
:- import_module hlds.hlds_rtti.
:- import_module hlds.instmap.
:- import_module libs.globals.
:- import_module libs.trace_params.
:- import_module ll_backend.global_data.
:- import_module ll_backend.layout.
:- import_module ll_backend.llds.
:- import_module ll_backend.trace_gen.
:- import_module mdbcomp.prim_data.
:- import_module parse_tree.prog_data.

:- import_module assoc_list.
:- import_module bool.
:- import_module list.
:- import_module map.
:- import_module maybe.
:- import_module pair.
:- import_module set.

%-----------------------------------------------------------------------------%

    % Information for any procedure, includes information about the
    % procedure itself, and any internal labels within it.
    %
:- type proc_layout_info
    --->    proc_layout_info(
                rtti_proc_label     :: rtti_proc_label,
                % The identity of the procedure.

                entry_label         :: label,

                detism              :: determinism,
                % Determines which stack is used.

                stack_slot_count    :: int,
                % Number of stack slots.

                succip_slot         :: maybe(int),
                % Location of succip on stack.

                eval_method         :: eval_method,
                % The evaluation method of the procedure.

                eff_trace_level     :: trace_level,
                % The effective trace level of the procedure.

                call_label          :: maybe(label),
                % If the trace level is not none, this contains the label
                % associated with the call event, whose stack layout says
                % which variables were live and where on entry.

                max_trace_reg       :: int,
                % The number of the highest numbered rN register that can
                % contain useful information during a call to MR_trace from
                % within this procedure.

                head_vars           :: list(prog_var),
                % The head variables, in order, including the ones introduced
                % by the compiler.

                arg_modes           :: list(mer_mode),
                % The modes of the head variables.

                proc_body           :: hlds_goal,
                % The body of the procedure.

                needs_body_rep      :: bool,
                % Do we need to include a representation of the procedure body
                % in the exec trace layout?

                initial_instmap     :: instmap,
                % The instmap at the start of the procedure body.

                trace_slot_info     :: trace_slot_info,
                % Info about the stack slots used for tracing.

                need_proc_id        :: bool,
                % Do we require the procedure id section of the procedure
                % layout to be present, even if the option procid_stack_layout
                % is not set?

                varset              :: prog_varset,
                vartypes            :: vartypes,
                % The names and types of all the variables.

                internal_map        :: proc_label_layout_info,
                % Info for each internal label, needed for basic_stack_layouts.

                maybe_table_info    :: maybe(proc_table_info),

                need_all_names      :: bool,
                % True iff we need the names of all the variables.

                deep_prof           :: maybe(proc_layout_proc_static)
        ).

    % Information about the labels internal to a procedure.
    %
:- type proc_label_layout_info == map(int, internal_layout_info).

    % Information for an internal label.
    %
    % There are three ways for the compiler to generate labels for
    % which layouts may be required:
    %
    % (a) as the label associated with a trace port,
    % (b) as the label associated with resume point that gets stored
    %     as a redoip in a nondet stack frame, and
    % (c) as the return label of some kind of call (plain, method or h-o).
    %
    % Label optimizations may redirect a call return away from the
    % originally generated label to another label, possibly one
    % that is associated with a trace port. This optimization may
    % also direct returns from more than one call to the same label.
    %
    % We may be interested in the layout of things at a label for three
    % different reasons: for stack tracing, for accurate gc, and for
    % execution tracing (which may include up-level printing from the
    % debugger).
    %
    % - For stack tracing, we are interested only in call return labels.
    %   Even for these, we need only the pointer to the procedure layout
    %   info; we do not need any information about variables.
    %
    % - For accurate gc, we are interested only in resume point labels
    %   and call return labels. We need to know about all the variables
    %   that can be accessed after the label; this is the intersection of
    %   all the variables denoted as live in the respective labels.
    %   (Variables which are not in the intersection are not guaranteed
    %   to have a meaningful value on all execution paths that lead to the
    %   label.)
    %
    % - For execution tracing, our primary interest is in trace port
    %   labels. At these labels we only want info about named variables,
    %   but we may want this info even if the variable will never be
    %   referred to again.
    %
    %   When the trace level requires support for up-level printing,
    %   execution tracing also requires information about return labels.
    %   The variables about which we want info at these labels is a subset
    %   of the variables agc is interested in (the named subset).
    %   We do not collect this set explicitly. Instead, if we are doing
    %   execution tracing, we collect agc layout info as usual, and
    %   (if we not really doing agc) remove the unnamed variables
    %   in stack_layout.m.
    %
    % For labels which correspond to a trace port (part (a) above),
    % we record information in the first field. Since trace.m generates
    % a unique label for each trace port, this field is never updated
    % once it is set in pass 2.
    %
    % For labels which correspond to redoips (part (b) above), we record
    % information in the second field. Since code_info.m generates
    % unique labels for each resumption point, this field is never updated
    % once it is set in pass 2.
    %
    % For labels which correspond to a call return (part (c) above),
    % we record information in the third field during pass 4. If execution
    % tracing is turned on, then jumpopt.m will not redirect call return
    % addresses, and thus each label will correspond to at most one call
    % return. If execution tracing is turned off, jumpopt.m may redirect
    % call return addresses, which means that a label can serve as the
    % return label for more than one call. In that case, this field can be
    % updated after it is set. This updating requires taking the
    % intersection of the sets of live variables, and gathering up all the
    % contexts into a list. Later, stack_layout.m will pick one (valid)
    % context essentially at random, which is OK because the picked
    % context will not be used for anything, except possibly for debugging
    % native gc.
    %
    % Since a call may return to the label of an internal port, it is
    % possible for both fields to be set. In this case, stack_layout.m
    % will take the union of the relevant info. If neither field is set,
    % then the label's layout is required only for stack tracing.
    %
:- type internal_layout_info
    --->    internal_layout_info(
                maybe(trace_port_layout_info),
                maybe(layout_label_info),
                maybe(return_layout_info)
            ).

:- type trace_port_layout_info
    --->    trace_port_layout_info(
                port_context    :: prog_context,
                port_type       :: trace_port,
                port_is_hidden  :: bool,
                port_path       :: goal_path,
                port_user       :: maybe(user_event_info),
                port_label      :: layout_label_info
            ).

:- type return_layout_info
    --->    return_layout_info(
                assoc_list(code_addr, pair(prog_context, goal_path)),
                layout_label_info
            ).

    % Information about the layout of live data for a label.
    %
:- type layout_label_info
    --->    layout_label_info(
                set(layout_var_info),
                % Live vars and their locations/names.

                map(tvar, set(layout_locn))
                % Locations of polymorphic type vars.
            ).

:- type layout_var_info
    --->    layout_var_info(
                layout_locn,        % The location of the variable.
                live_value_type,    % Info about the variable.
                string              % Where in the compiler this
                                    % layout_var_info was created
            ).

:- type user_attribute
    --->    user_attribute(
                attr_locn               :: rval,
                attr_type               :: mer_type,
                attr_name               :: string
            ).

:- type user_event_info
    --->    user_event_info(
                user_port_number      :: int,
                user_port_name        :: string,
                user_attributes       :: list(user_attribute)
            ).

:- type closure_layout_info
    --->    closure_layout_info(
                list(closure_arg_info),
                % There is one closure_arg_info for each argument of the called
                % procedure, even the args which are not in the closure

                map(tvar, set(layout_locn))
                % Locations of polymorphic type vars,
                % encoded so that rN refers to argument N.
            ).

:- type closure_arg_info
    --->    closure_arg_info(
                mer_type,   % The type of the argument.
                mer_inst    % The initial inst of the argument.

                            % It may be useful in the future to include
                            % info about the final insts and about
                            % the determinism. This would allow us
                            % to implement checked dynamic inst casts,
                            % which may be helpful for dynamic loading.
                            % It may also be useful for printing
                            % closures and for providing user-level
                            % RTTI access.
            ).

:- type slot_contents
    --->    ticket          % A ticket (trail pointer).
    ;       ticket_counter  % A copy of the ticket counter.
    ;       trace_data
    ;       lookup_switch_cur
    ;       lookup_switch_max
    ;       sync_term       % A syncronization term used
                            % at the end of par_conjs.
                            % See par_conj_gen.m for details.
    ;       lval(lval).

    % Call maybe_process_proc_llds on the code of every procedure in the list.
    %
:- pred maybe_process_llds(list(c_procedure)::in,
    module_info::in, global_data::in, global_data::out) is det.

    % Check whether this procedure ought to have any layout structures
    % generated for it. If yes, then update the global_data to
    % include all the continuation labels within a proc. Whether or not
    % the information about a continuation label includes the variables
    % live at that label depends on the values of options.
    %
:- pred maybe_process_proc_llds(list(instruction)::in,
    pred_proc_id::in, module_info::in,
    global_data::in, global_data::out) is det.

    % Check whether the given procedure should have at least (a) a basic
    % stack layout, and (b) a procedure id layout generated for it.
    % The two bools returned answer these two questions respectively.
    %
:- pred basic_stack_layout_for_proc(pred_info::in,
    globals::in, bool::out, bool::out) is det.

    % Generate the layout information we need for the return point of a call.
    %
:- pred generate_return_live_lvalues(
    assoc_list(prog_var, arg_loc)::in, instmap::in, list(prog_var)::in,
    map(prog_var, set(lval))::in, assoc_list(lval, slot_contents)::in,
    proc_info::in, module_info::in, globals::in, bool::in,
    list(liveinfo)::out) is det.

    % Generate the layout information we need for a resumption point,
    % a label where forward execution can restart after backtracking.
    %
:- pred generate_resume_layout(map(prog_var, set(lval))::in,
    assoc_list(lval, slot_contents)::in, instmap::in, proc_info::in,
    module_info::in, layout_label_info::out) is det.

    % Generate the layout information we need to include in a closure.
    %
:- pred generate_closure_layout(module_info::in,
    pred_id::in, proc_id::in, closure_layout_info::out) is det.

    % For each type variable in the given list, find out where the
    % typeinfo var for that type variable is.
    %
:- pred find_typeinfos_for_tvars(list(tvar)::in,
    map(prog_var, set(lval))::in, proc_info::in,
    map(tvar, set(layout_locn))::out) is det.

:- pred generate_table_arg_type_info(proc_info::in,
    assoc_list(prog_var, int)::in, table_arg_infos::out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module check_hlds.inst_match.
:- import_module check_hlds.type_util.
:- import_module hlds.hlds_goal.
:- import_module hlds.hlds_llds.
:- import_module libs.compiler_util.
:- import_module libs.options.
:- import_module ll_backend.code_util.
:- import_module parse_tree.prog_type.

:- import_module int.
:- import_module solutions.
:- import_module string.
:- import_module svmap.
:- import_module svset.
:- import_module term.
:- import_module varset.

%-----------------------------------------------------------------------------%

maybe_process_llds([], _, !GlobalData).
maybe_process_llds([Proc | Procs], ModuleInfo, !GlobalData) :-
    PredProcId = Proc ^ cproc_id,
    Instrs = Proc ^ cproc_code,
    maybe_process_proc_llds(Instrs, PredProcId, ModuleInfo, !GlobalData),
    maybe_process_llds(Procs, ModuleInfo, !GlobalData).

maybe_process_proc_llds(Instructions, PredProcId, ModuleInfo, !ContInfo) :-
    PredProcId = proc(PredId, _),
    module_info_pred_info(ModuleInfo, PredId, PredInfo),
    module_info_get_globals(ModuleInfo, Globals),
    basic_stack_layout_for_proc(PredInfo, Globals, Layout, _),
    (
        Layout = yes,
        globals.want_return_var_layouts(Globals, WantReturnLayout),
        process_proc_llds(PredProcId, Instructions, WantReturnLayout,
            !ContInfo)
    ;
        Layout = no
    ).

:- type call_info
    --->    call_info(
                label,          % The return label.
                code_addr,      % The target of the call.
                list(liveinfo), % What is live on return.
                term.context,  % The position of the call in source.
                goal_path       % The position of the call in the body;
                                % meaningful only if tracing is enabled.
            ).

    % Process the list of instructions for this proc, adding
    % all internal label information to global_data.
    %
:- pred process_proc_llds(pred_proc_id::in, list(instruction)::in, bool::in,
    global_data::in, global_data::out) is det.

process_proc_llds(PredProcId, Instructions, WantReturnInfo, !GlobalData) :-
    % Get all the continuation info from the call instructions.
    global_data_get_proc_layout(!.GlobalData, PredProcId, ProcLayoutInfo0),
    Internals0 = ProcLayoutInfo0^internal_map,
    GetCallInfo = (pred(Instr::in, Call::out) is semidet :-
        Instr = llcall(Target, code_label(ReturnLabel), LiveInfo, Context,
            GoalPath, _) - _Comment,
        Call = call_info(ReturnLabel, Target, LiveInfo, Context, GoalPath)
    ),
    list.filter_map(GetCallInfo, Instructions, Calls),

    % Process the continuation label info.
    list.foldl(process_continuation(WantReturnInfo), Calls,
        Internals0, Internals),

    ProcLayoutInfo = ProcLayoutInfo0^internal_map := Internals,
    global_data_update_proc_layout(PredProcId, ProcLayoutInfo, !GlobalData).

%-----------------------------------------------------------------------------%

    % Collect the liveness information from a single return label
    % and add it to the internals.
    %
:- pred process_continuation(bool::in, call_info::in,
    proc_label_layout_info::in, proc_label_layout_info::out) is det.

process_continuation(WantReturnInfo, CallInfo, !Internals) :-
    CallInfo = call_info(ReturnLabel, Target, LiveInfoList, Context,
        MaybeGoalPath),
    % We could check not only that the return label is an internal label,
    % but also that it belongs to the current procedure, but this would be
    % serious paranoia.
    (
        ReturnLabel = internal_label(ReturnLabelNum, _)
    ;
        ReturnLabel = entry_label(_, _),
        unexpected(this_file, "process_continuation: bad return")
    ),
    ( map.search(!.Internals, ReturnLabelNum, Internal0) ->
        Internal0 = internal_layout_info(Port0, Resume0, Return0)
    ;
        Port0 = no,
        Resume0 = no,
        Return0 = no
    ),
    (
        WantReturnInfo = yes,
        convert_return_data(LiveInfoList, VarInfoSet, TypeInfoMap),
        (
            Return0 = no,
            Layout = layout_label_info(VarInfoSet, TypeInfoMap),
            ReturnInfo = return_layout_info(
                [Target - (Context - MaybeGoalPath)], Layout),
            Return = yes(ReturnInfo)
        ;
            % If a var is known to be dead on return from one call, it cannot
            % be accessed on returning from the other calls that reach the same
            % return address either.
            Return0 = yes(ReturnInfo0),
            ReturnInfo0 = return_layout_info(TargetsContexts0, Layout0),
            Layout0 = layout_label_info(LV0, TV0),
            set.intersect(LV0, VarInfoSet, LV),
            map.intersect(set.intersect, TV0, TypeInfoMap, TV),
            Layout = layout_label_info(LV, TV),
            TargetContexts = [Target - (Context - MaybeGoalPath)
                | TargetsContexts0],
            ReturnInfo = return_layout_info(TargetContexts, Layout),
            Return = yes(ReturnInfo)
        )
    ;
        WantReturnInfo = no,
        Return = Return0
    ),
    Internal = internal_layout_info(Port0, Resume0, Return),
    map.set(!.Internals, ReturnLabelNum, Internal, !:Internals).

:- pred convert_return_data(list(liveinfo)::in,
    set(layout_var_info)::out, map(tvar, set(layout_locn))::out) is det.

convert_return_data(LiveInfos, VarInfoSet, TypeInfoMap) :-
    GetVarInfo = (pred(LiveLval::in, VarInfo::out) is det :-
        LiveLval = live_lvalue(Lval, LiveValueType, _),
        VarInfo = layout_var_info(Lval, LiveValueType, "convert_return_data")
    ),
    list.map(GetVarInfo, LiveInfos, VarInfoList),
    GetTypeInfo = (pred(LiveLval::in, LiveTypeInfoMap::out) is det :-
        LiveLval = live_lvalue(_, _, LiveTypeInfoMap)
    ),
    list.map(GetTypeInfo, LiveInfos, TypeInfoMapList),
    map.init(Empty),
    list.foldl((pred(TIM1::in, TIM2::in, TIM::out) is det :-
            map.union(set.intersect, TIM1, TIM2, TIM)
        ), TypeInfoMapList, Empty, TypeInfoMap),
    set.list_to_set(VarInfoList, VarInfoSet).

:- pred filter_named_vars(list(liveinfo)::in, list(liveinfo)::out) is det.

filter_named_vars([], []).
filter_named_vars([LiveInfo | LiveInfos], Filtered) :-
    filter_named_vars(LiveInfos, Filtered1),
    (
        LiveInfo = live_lvalue(_, LiveType, _),
        LiveType = live_value_var(_, Name, _, _),
        Name \= ""
    ->
        Filtered = [LiveInfo | Filtered1]
    ;
        Filtered = Filtered1
    ).

%-----------------------------------------------------------------------------%

basic_stack_layout_for_proc(PredInfo, Globals, BasicLayout,
        ForceProcIdLayout) :-
    (
        globals.lookup_bool_option(Globals, stack_trace_higher_order, yes),
        some_arg_is_higher_order(PredInfo)
    ->
        BasicLayout = yes,
        ForceProcIdLayout = yes
    ;
        globals.lookup_bool_option(Globals, basic_stack_layout, yes)
    ->
        BasicLayout = yes,
        ForceProcIdLayout = no
    ;
        BasicLayout = no,
        ForceProcIdLayout = no
    ).

:- pred some_arg_is_higher_order(pred_info::in) is semidet.

some_arg_is_higher_order(PredInfo) :-
    pred_info_get_arg_types(PredInfo, ArgTypes),
    some [Type] (
        list.member(Type, ArgTypes),
        type_is_higher_order(Type)
    ).

%-----------------------------------------------------------------------------%

generate_return_live_lvalues(OutputArgLocs, ReturnInstMap, Vars, VarLocs,
        Temps, ProcInfo, ModuleInfo, Globals, OkToDeleteAny, LiveLvalues) :-
    globals.want_return_var_layouts(Globals, WantReturnVarLayout),
    proc_info_get_stack_slots(ProcInfo, StackSlots),
    find_return_var_lvals(Vars, StackSlots, OkToDeleteAny, OutputArgLocs,
        VarLvals),
    generate_var_live_lvalues(VarLvals, ReturnInstMap, VarLocs, ProcInfo,
        ModuleInfo, WantReturnVarLayout, VarLiveLvalues),
    generate_temp_live_lvalues(Temps, TempLiveLvalues),
    list.append(VarLiveLvalues, TempLiveLvalues, LiveLvalues).

:- pred find_return_var_lvals(list(prog_var)::in,
    stack_slots::in, bool::in, assoc_list(prog_var, arg_loc)::in,
    assoc_list(prog_var, lval)::out) is det.

find_return_var_lvals([], _, _, _, []).
find_return_var_lvals([Var | Vars], StackSlots, OkToDeleteAny, OutputArgLocs,
        VarLvals) :-
    find_return_var_lvals(Vars, StackSlots,
        OkToDeleteAny, OutputArgLocs, TailVarLvals),
    ( assoc_list.search(OutputArgLocs, Var, ArgLoc) ->
        % On return, output arguments are in their registers.
        code_util.arg_loc_to_register(ArgLoc, Lval),
        VarLvals = [Var - Lval | TailVarLvals]
    ; map.search(StackSlots, Var, Slot) ->
        % On return, other live variables are in their stack slots.
        VarLvals = [Var - stack_slot_to_lval(Slot) | TailVarLvals]
    ; OkToDeleteAny = yes ->
        VarLvals = TailVarLvals
    ;
        unexpected(this_file, "find_return_var_lvals: no slot")
    ).

:- pred generate_temp_live_lvalues(assoc_list(lval, slot_contents)::in,
    list(liveinfo)::out) is det.

generate_temp_live_lvalues([], []).
generate_temp_live_lvalues([Temp | Temps], [Live | Lives]) :-
    Temp = Slot - Contents,
    live_value_type(Contents, LiveLvalueType),
    map.init(Empty),
    Live = live_lvalue(direct(Slot), LiveLvalueType, Empty),
    generate_temp_live_lvalues(Temps, Lives).

:- pred generate_var_live_lvalues(assoc_list(prog_var, lval)::in, instmap::in,
    map(prog_var, set(lval))::in, proc_info::in, module_info::in,
    bool::in, list(liveinfo)::out) is det.

generate_var_live_lvalues([], _, _, _, _, _, []).
generate_var_live_lvalues([Var - Lval | VarLvals], InstMap, VarLocs, ProcInfo,
        ModuleInfo, WantReturnVarLayout, [Live | Lives]) :-
    (
        WantReturnVarLayout = yes,
        generate_layout_for_var(Var, InstMap, ProcInfo, ModuleInfo,
            LiveValueType, TypeVars),
        find_typeinfos_for_tvars(TypeVars, VarLocs, ProcInfo, TypeParams),
        Live = live_lvalue(direct(Lval), LiveValueType, TypeParams)
    ;
        WantReturnVarLayout = no,
        map.init(Empty),
        Live = live_lvalue(direct(Lval), live_value_unwanted, Empty)
    ),
    generate_var_live_lvalues(VarLvals, InstMap, VarLocs, ProcInfo,
        ModuleInfo, WantReturnVarLayout, Lives).

%---------------------------------------------------------------------------%

generate_resume_layout(ResumeMap, Temps, InstMap, ProcInfo, ModuleInfo,
        Layout) :-
    map.to_assoc_list(ResumeMap, ResumeList),
    set.init(TVars0),
    proc_info_get_vartypes(ProcInfo, VarTypes),
    generate_resume_layout_for_vars(ResumeList, InstMap, VarTypes, ProcInfo,
        ModuleInfo, [], VarInfos, TVars0, TVars),
    set.list_to_set(VarInfos, VarInfoSet),
    set.to_sorted_list(TVars, TVarList),
    find_typeinfos_for_tvars(TVarList, ResumeMap, ProcInfo, TVarInfoMap),
    generate_temp_var_infos(Temps, TempInfos),
    set.list_to_set(TempInfos, TempInfoSet),
    set.union(VarInfoSet, TempInfoSet, AllInfoSet),
    Layout = layout_label_info(AllInfoSet, TVarInfoMap).

:- pred generate_resume_layout_for_vars(assoc_list(prog_var, set(lval))::in,
    instmap::in, vartypes::in, proc_info::in, module_info::in,
    list(layout_var_info)::in, list(layout_var_info)::out,
    set(tvar)::in, set(tvar)::out) is det.

generate_resume_layout_for_vars([], _, _, _, _, !VarInfos, !TVars).
generate_resume_layout_for_vars([Var - LvalSet | VarLvals], InstMap,
        VarTypes, ProcInfo, ModuleInfo, !VarInfos, !TVars) :-
    (
        map.lookup(VarTypes, Var, Type),
        is_dummy_argument_type(ModuleInfo, Type)
    ->
        true
    ;
        generate_resume_layout_for_var(Var, LvalSet, InstMap, ProcInfo,
            ModuleInfo, VarInfo, TypeVars),
        set.insert_list(!.TVars, TypeVars, !:TVars),
        !:VarInfos = [VarInfo | !.VarInfos]
    ),
    generate_resume_layout_for_vars(VarLvals, InstMap, VarTypes, ProcInfo,
        ModuleInfo, !VarInfos, !TVars).

:- pred generate_resume_layout_for_var(prog_var::in, set(lval)::in,
    instmap::in, proc_info::in, module_info::in,
    layout_var_info::out, list(tvar)::out) is det.

generate_resume_layout_for_var(Var, LvalSet, InstMap, ProcInfo, ModuleInfo,
        VarInfo, TypeVars) :-
    set.to_sorted_list(LvalSet, LvalList),
    ( LvalList = [LvalPrime] ->
        Lval = LvalPrime
    ;
        unexpected(this_file, "var has more than one lval in stack resume map")
    ),
    ( Lval = stackvar(N) ->
        expect(N > 0, this_file,
            "generate_resume_layout_for_var: bad stackvar")
    ; Lval = stackvar(N) ->
        expect(N > 0, this_file,
            "generate_resume_layout_for_var: bad framevar")
    ;
        true
    ),
    generate_layout_for_var(Var, InstMap, ProcInfo, ModuleInfo, LiveValueType,
        TypeVars),
    VarInfo = layout_var_info(direct(Lval), LiveValueType,
        "generate_result_layout_for_var").

:- pred generate_temp_var_infos(assoc_list(lval, slot_contents)::in,
    list(layout_var_info)::out) is det.

generate_temp_var_infos([], []).
generate_temp_var_infos([Temp | Temps], [Live | Lives]) :-
    Temp = Slot - Contents,
    live_value_type(Contents, LiveLvalueType),
    Live = layout_var_info(direct(Slot), LiveLvalueType,
        "generate_temp_var_infos"),
    generate_temp_var_infos(Temps, Lives).

%---------------------------------------------------------------------------%

:- pred generate_layout_for_var(prog_var::in, instmap::in, proc_info::in,
    module_info::in, live_value_type::out, list(tvar)::out) is det.

generate_layout_for_var(Var, InstMap, ProcInfo, ModuleInfo, LiveValueType,
        TypeVars) :-
    proc_info_get_varset(ProcInfo, VarSet),
    proc_info_get_vartypes(ProcInfo, VarTypes),
    ( varset.search_name(VarSet, Var, GivenName) ->
        Name = GivenName
    ;
        Name = ""
    ),
    instmap.lookup_var(InstMap, Var, Inst),
    map.lookup(VarTypes, Var, Type),
    ( inst_match.inst_is_ground(ModuleInfo, Inst) ->
        LldsInst = llds_inst_ground
    ;
        LldsInst = llds_inst_partial(Inst)
    ),
    LiveValueType = live_value_var(Var, Name, Type, LldsInst),
    type_vars(Type, TypeVars).

%---------------------------------------------------------------------------%

generate_closure_layout(ModuleInfo, PredId, ProcId, ClosureLayout) :-
    module_info_pred_proc_info(ModuleInfo, PredId, ProcId, PredInfo, ProcInfo),
    proc_info_get_headvars(ProcInfo, HeadVars),
    proc_info_arg_info(ProcInfo, ArgInfos),
    pred_info_get_arg_types(PredInfo, ArgTypes),
    proc_info_get_initial_instmap(ProcInfo, ModuleInfo, InstMap),
    map.init(VarLocs0),
    set.init(TypeVars0),
    (
        build_closure_info(HeadVars, ArgTypes, ArgInfos, ArgLayouts, InstMap,
            VarLocs0, VarLocs, TypeVars0, TypeVars)
    ->
        set.to_sorted_list(TypeVars, TypeVarsList),
        find_typeinfos_for_tvars(TypeVarsList, VarLocs, ProcInfo,
            TypeInfoDataMap),
        ClosureLayout = closure_layout_info(ArgLayouts, TypeInfoDataMap)
    ;
        unexpected(this_file,
            "proc headvars and pred argtypes disagree on arity")
    ).

:- pred build_closure_info(list(prog_var)::in,
    list(mer_type)::in, list(arg_info)::in,  list(closure_arg_info)::out,
    instmap::in, map(prog_var, set(lval))::in,
    map(prog_var, set(lval))::out, set(tvar)::in, set(tvar)::out) is semidet.

build_closure_info([], [], [], [], _, !VarLocs, !TypeVars).
build_closure_info([Var | Vars], [Type | Types],
        [ArgInfo | ArgInfos], [Layout | Layouts], InstMap,
        !VarLocs, !TypeVars) :-
    ArgInfo = arg_info(ArgLoc, _ArgMode),
    instmap.lookup_var(InstMap, Var, Inst),
    Layout = closure_arg_info(Type, Inst),
    set.singleton_set(Locations, reg(reg_r, ArgLoc)),
    svmap.det_insert(Var, Locations, !VarLocs),
    type_vars(Type, VarTypeVars),
    svset.insert_list(VarTypeVars, !TypeVars),
    build_closure_info(Vars, Types, ArgInfos, Layouts, InstMap,
        !VarLocs, !TypeVars).

%---------------------------------------------------------------------------%

find_typeinfos_for_tvars(TypeVars, VarLocs, ProcInfo, TypeInfoDataMap) :-
    proc_info_get_varset(ProcInfo, VarSet),
    proc_info_get_rtti_varmaps(ProcInfo, RttiVarMaps),
    list.map(rtti_lookup_type_info_locn(RttiVarMaps), TypeVars,
        TypeInfoLocns),
    FindLocn = (pred(TypeInfoLocn::in, Locns::out) is det :-
        type_info_locn_var(TypeInfoLocn, TypeInfoVar),
        ( map.search(VarLocs, TypeInfoVar, TypeInfoLvalSet) ->
            ConvertLval = (pred(Locn::out) is nondet :-
                set.member(Lval, TypeInfoLvalSet),
                (
                    TypeInfoLocn = typeclass_info(_, FieldNum),
                    Locn = indirect(Lval, FieldNum)
                ;
                    TypeInfoLocn = type_info(_),
                    Locn = direct(Lval)
                )
            ),
            solutions.solutions_set(ConvertLval, Locns)
        ;
            varset.lookup_name(VarSet, TypeInfoVar, VarString),
            string.format("%s: %s %s",
                [s("find_typeinfos_for_tvars"),
                s("can't find rval for type_info var"),
                s(VarString)], ErrStr),
            unexpected(this_file, ErrStr)
        )
    ),
    list.map(FindLocn, TypeInfoLocns, TypeInfoVarLocns),
    map.from_corresponding_lists(TypeVars, TypeInfoVarLocns, TypeInfoDataMap).

%---------------------------------------------------------------------------%

generate_table_arg_type_info(ProcInfo, NumberedVars, TableArgInfos) :-
    proc_info_get_vartypes(ProcInfo, VarTypes),
    set.init(TypeVars0),
    build_table_arg_info(VarTypes, NumberedVars, ArgLayouts,
        TypeVars0, TypeVars),
    set.to_sorted_list(TypeVars, TypeVarsList),
    find_typeinfos_for_tvars_table(TypeVarsList, NumberedVars, ProcInfo,
        TypeInfoDataMap),
    TableArgInfos = table_arg_infos(ArgLayouts, TypeInfoDataMap).

:- pred build_table_arg_info(vartypes::in,
    assoc_list(prog_var, int)::in, list(table_arg_info)::out,
    set(tvar)::in, set(tvar)::out) is det.

build_table_arg_info(_, [], [], !TypeVars).
build_table_arg_info(VarTypes, [Var - SlotNum | NumberedVars],
        [ArgLayout | ArgLayouts], !TypeVars) :-
    map.lookup(VarTypes, Var, Type),
    ArgLayout = table_arg_info(Var, SlotNum, Type),
    type_vars(Type, VarTypeVars),
    svset.insert_list(VarTypeVars, !TypeVars),
    build_table_arg_info(VarTypes, NumberedVars, ArgLayouts, !TypeVars).

%---------------------------------------------------------------------------%

:- pred find_typeinfos_for_tvars_table(list(tvar)::in,
    assoc_list(prog_var, int)::in, proc_info::in,
    map(tvar, table_locn)::out) is det.

find_typeinfos_for_tvars_table(TypeVars, NumberedVars, ProcInfo,
        TypeInfoDataMap) :-
    proc_info_get_varset(ProcInfo, VarSet),
    proc_info_get_rtti_varmaps(ProcInfo, RttiVarMaps),
    list.map(rtti_lookup_type_info_locn(RttiVarMaps), TypeVars,
        TypeInfoLocns),
    FindLocn = (pred(TypeInfoLocn::in, Locn::out) is det :-
        (
            (
                TypeInfoLocn = typeclass_info(TypeInfoVar, FieldNum),
                assoc_list.search(NumberedVars, TypeInfoVar, Slot),
                LocnPrime = indirect(Slot, FieldNum)
            ;
                TypeInfoLocn = type_info(TypeInfoVar),
                assoc_list.search(NumberedVars, TypeInfoVar, Slot),
                LocnPrime = direct(Slot)
            )
        ->
            Locn = LocnPrime
        ;
            type_info_locn_var(TypeInfoLocn, TypeInfoVar),
            varset.lookup_name(VarSet, TypeInfoVar, VarString),
            string.format("%s: %s %s",
                [s("find_typeinfos_for_tvars_table"),
                s("can't find slot for type_info var"), s(VarString)], ErrStr),
            unexpected(this_file, ErrStr)
        )
    ),
    list.map(FindLocn, TypeInfoLocns, TypeInfoVarLocns),
    map.from_corresponding_lists(TypeVars, TypeInfoVarLocns, TypeInfoDataMap).

%-----------------------------------------------------------------------------%

:- pred live_value_type(slot_contents::in, live_value_type::out) is det.

live_value_type(lval(succip), live_value_succip).
live_value_type(lval(hp), live_value_hp).
live_value_type(lval(maxfr), live_value_maxfr).
live_value_type(lval(curfr), live_value_curfr).
live_value_type(lval(succfr_slot(_)), live_value_unwanted).
live_value_type(lval(prevfr_slot(_)), live_value_unwanted).
live_value_type(lval(redofr_slot(_)), live_value_unwanted).
live_value_type(lval(redoip_slot(_)), live_value_unwanted).
live_value_type(lval(succip_slot(_)), live_value_unwanted).
live_value_type(lval(sp), live_value_unwanted).
live_value_type(lval(parent_sp), live_value_unwanted).
live_value_type(lval(lvar(_)), live_value_unwanted).
live_value_type(lval(field(_, _, _)), live_value_unwanted).
live_value_type(lval(temp(_, _)), live_value_unwanted).
live_value_type(lval(reg(_, _)), live_value_unwanted).
live_value_type(lval(stackvar(_)), live_value_unwanted).
live_value_type(lval(parent_stackvar(_)), live_value_unwanted).
live_value_type(lval(framevar(_)), live_value_unwanted).
live_value_type(lval(mem_ref(_)), live_value_unwanted). % XXX
live_value_type(lval(global_var_ref(_)), live_value_unwanted).
live_value_type(ticket, live_value_unwanted).
    % XXX we may need to modify this, if the GC is going to garbage-collect
    % the trail.
live_value_type(ticket_counter, live_value_unwanted).
live_value_type(lookup_switch_cur, live_value_unwanted).
live_value_type(lookup_switch_max, live_value_unwanted).
live_value_type(sync_term, live_value_unwanted).
live_value_type(trace_data, live_value_unwanted).

%-----------------------------------------------------------------------------%

:- func this_file = string.

this_file = "continuation_info.m".

%-----------------------------------------------------------------------------%
:- end_module continuation_info.
%-----------------------------------------------------------------------------%
