%-----------------------------------------------------------------------------%
% Copyright (C) 1993-2003 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% LLDS - The Low-Level Data Structure.

% This module defines the LLDS data structure itself.

% Main authors: conway, fjh.

%-----------------------------------------------------------------------------%

:- module ll_backend__llds.

:- interface.

:- import_module backend_libs__builtin_ops.
:- import_module backend_libs__code_model.
:- import_module backend_libs__foreign.
:- import_module backend_libs__proc_label.
:- import_module backend_libs__rtti.
:- import_module hlds__hlds_goal.
:- import_module hlds__hlds_pred.
:- import_module libs__tree.
:- import_module ll_backend__layout.
:- import_module parse_tree__inst.
:- import_module parse_tree__prog_data.

:- import_module bool, list, assoc_list, map, set, std_util, counter, term.

%-----------------------------------------------------------------------------%

% foreign_interface_info holds information used when generating
% code that uses the foreign language interface.
:- type foreign_interface_info
	---> foreign_interface_info(
		module_name,
		% info about stuff imported from C:
		foreign_decl_info,
		foreign_import_module_info,
		foreign_body_info,
		% info about stuff exported to C:
		foreign_export_decls,
		foreign_export_defns
	).

%-----------------------------------------------------------------------------%

%
% The type `c_file' is the actual LLDS.
%
:- type c_file	
	--->	c_file(
			module_name,
			foreign_decl_info,
			list(user_foreign_code),
			list(foreign_export),
			list(comp_gen_c_var),
			list(comp_gen_c_data),
			list(comp_gen_c_module)
		).

	% Global variables generated by the compiler.
:- type comp_gen_c_var
	--->	tabling_pointer_var(
			module_name,		% The basename of this C file.
			proc_label		% The id of the procedure
						% whose table this variable
						% represents.
		).

	% Global data generated by the compiler. Usually readonly,
	% with one exception: data containing code addresses must
	% be initialized.
:- type comp_gen_c_data
	--->	common_data(
			module_name,		% The basename of this C file.
			int,			% The id number of the cell.
			int,			% The id number of the C type
						% giving the types of the args.
						% The data_addr referring to
						% this common_data will be
						% data_addr(ModuleName,
						% common(CellNum, TypeNum)).
			assoc_list(rval, llds_type)
						% The arguments of the create,
						% together with their types.
		)
	;	rtti_data(
			rtti_data
		)
	;	layout_data(
			layout_data
		).

:- type comp_gen_c_module
	--->	comp_gen_c_module(
			string,			% the name of this C module
			list(c_procedure) 	% code
		).

:- type c_procedure
	--->	c_procedure(
			string,			% predicate name
			int,			% arity
			pred_proc_id,		% the pred_proc_id this code
			list(instruction),	% the code for this procedure
			proc_label,		% proc_label of this procedure
			counter,		% source for new label numbers
			may_alter_rtti		% The compiler is allowed to
						% perform optimizations on this
						% c_procedure that could alter
						% RTTI information (e.g. the
						% set of variables live at
						% a label) only if this field
						% is set to `may_alter_rtti'.
		).

:- type may_alter_rtti
	--->	may_alter_rtti
	;	must_not_alter_rtti.

:- type llds_proc_id	==	int.

	% we build up instructions as trees and then flatten
	% the tree to get a list.
:- type code_tree	==	tree(list(instruction)).

:- type instruction	==	pair(instr, string).
			%	instruction, comment

:- type nondet_tail_call
	--->	no_tail_call
				% At the point of the call, the procedure has
				% more alternatives.
				%
				% Under these conditions, the call cannot be
				% transformed into a tail call.
	;	checked_tail_call
				% At the point of the call, the procedure has
				% no more alternatives, and curfr and maxfr
				% are not guaranteed to be identical.
				%
				% Under these conditions, the call can be
				% transformed into a tail call whenever its
				% return address leads to the procedure
				% epilogue AND curfr and maxfr are found
				% to be identical at runtime.
	;	unchecked_tail_call.
				% At the point of the call the procedure has no
				% more alternatives, and curfr and maxfr are
				% guaranteed to be identical.
				%
				% Under these conditions, the call can be
				% transformed into a tail call whenever its
				% return address leads to the procedure
				% epilogue.

:- type call_model
	--->	det
	;	semidet
	;	nondet(nondet_tail_call).

	% `instr' defines the various LLDS virtual machine instructions.
	% Each instruction gets compiled to a simple piece of C code
	% or a macro invocation.
:- type instr
	--->	comment(string)
			% Insert a comment into the output code.

	;	livevals(set(lval))
			% A list of which registers and stack locations
			% are currently live.

	;	block(int, int, list(instruction))
			% block(NumIntTemps, NumFloatTemps, Instrs):
			% A list of instructions that make use of
			% some local temporary variables.

	;	assign(lval, rval)
			% assign(Location, Value):
			% Assign the value specified by rval to the location
			% specified by lval.

	;	call(code_addr, code_addr, list(liveinfo), term__context,
				goal_path, call_model)
			% call(Target, Continuation, _, _, _) is the same as
			% succip = Continuation; goto(Target).
			% The third argument is the live value info for the
			% values live on return. The fourth argument gives
			% the context of the call. The fifth gives the goal
			% path of the call in the body of the procedure; it is
			% meaningful only if execution tracing is enabled.
			% The last gives the code model of the called
			% procedure, and if it is model_non, says whether
			% tail recursion elimination is potentially applicable
			% to the call.

	;	mkframe(nondet_frame_info, code_addr)
			% mkframe(NondetFrameInfo, CodeAddr) creates a nondet
			% stack frame. NondetFrameInfo says whether the frame
			% is an ordinary frame, containing the variables of a
			% model_non procedure, or a temp frame used only for
			% its redoip/redofr slots. If the former, it also
			% gives the details of the size of the variable parts
			% of the frame (temp frames have no variable sized
			% parts). CodeAddr is the code address to branch to
			% when trying to generate the next solution from this
			% choice point.

	;	label(label)
			% Defines a label that can be used as the
			% target of calls, gotos, etc.

	;	goto(code_addr)
			% goto(Target)
			% Branch to the specified address.
			% Note that jumps to do_fail, do_redo, etc., can get
			% optimized into the invocations of macros
			% fail(), redo(), etc..

	;	computed_goto(rval, list(label))
			% Evaluate rval, which should be an integer,
			% and jump to the (rval+1)th label in the list.
			% e.g. computed_goto(2, [A, B, C, D])
			% will branch to label C.

	;	c_code(string, c_code_live_lvals)
			% Do whatever is specified by the string,
			% which can be any piece of C code that
			% does not have any non-local flow of control.

	;	if_val(rval, code_addr)
			% If rval is true, then goto code_addr.

	;	incr_hp(lval, maybe(tag), maybe(int), rval, string)
			% Get a memory block of a size given by an rval
			% and put its address in the given lval,
			% possibly after incrementing it by N words
			% (if the maybe(int) is bound to `yes(N)')
			% and/or after tagging it with a given tag.
			% The string gives the name of the type constructor
			% of the memory cell for use in memory profiling.

	;	mark_hp(lval)
			% Tell the heap sub-system to store a marker
			% (for later use in restore_hp/1 instructions)
			% in the specified lval

	;	restore_hp(rval)
			% The rval must be a marker as returned by mark_hp/1.
			% The effect is to deallocate all the memory which
			% was allocated since that call to mark_hp.

	;	free_heap(rval)
			% Notify the garbage collector that the heap space
			% associated with the top-level cell of the rval is
			% no longer needed.
			% `free' is useless but harmless without conservative
			% garbage collection.

	;	store_ticket(lval)
			% Allocate a new "ticket" and store it in the lval.
			%
			% Operational semantics:
			% 	MR_ticket_counter = ++MR_ticket_high_water;
			% 	lval = MR_trail_ptr;

	;	reset_ticket(rval, reset_trail_reason)
			% The rval must specify a ticket allocated with
			% `store_ticket' and not yet invalidated, pruned or
			% deallocated.
			% If reset_trail_reason is `undo', `exception', or
			% `retry', restore any mutable global state to the
			% state it was in when the ticket was obtained with
			% store_ticket(); invalidates any tickets allocated
			% after this one.
			% If reset_trail_reason is `commit' or `solve', leave
			% the state unchanged, just check that it is safe to
			% commit to this solution (i.e. that there are no
			% outstanding delayed goals -- this is the
			% "floundering" check).
			% Note that we do not discard trail entries after
			% commits, because that would in general be unsafe.
			%
			% Any invalidated ticket which has not yet been
			% backtracked over should be pruned with
			% `prune_ticket' or `prune_tickets_to'.
			% Any invalidated ticket which has been backtracked
			% over is useless and should be deallocated with
			% `discard_ticket'.
			%
			% Operational semantics:
			% 	MR_untrail_to(rval, reset_trail_reason);

	;	prune_ticket
			% Invalidates the most-recently allocated ticket.
			%
			% Operational semantics:
			%	--MR_ticket_counter;

	;	discard_ticket
			% Deallocates the most-recently allocated ticket.
			%
			% Operational semantics:
			%	MR_ticket_high_water = --MR_ticket_counter;

	;	mark_ticket_stack(lval)
			% Tell the trail sub-system to store a ticket counter
			% (for later use in prune_tickets_to)
			% in the specified lval.
			%
			% Operational semantics:
			%	lval = MR_ticket_counter;

	;	prune_tickets_to(rval)
			% The rval must be a ticket counter obtained via
			% `mark_ticket_stack' and not yet invalidated.
			% Prunes any trail tickets allocated after
			% the corresponding call to mark_ticket_stack.
			% Invalidates any later ticket counters.
			%
			% Operational semantics:
			%	MR_ticket_counter = rval;

%	;	discard_tickets_to(rval)	% this is only used in
						% the hand-written code in
						% library/exception.m
			% The rval must be a ticket counter obtained via
			% `mark_ticket_stack' and not yet invalidated.
			% Deallocates any trail tickets allocated after
			% the corresponding call to mark_ticket_stack.
			% Invalidates any later ticket counters.
			%
			% Operational semantics:
			%	MR_ticket_counter = rval;
			%	MR_ticket_high_water = MR_ticket_counter;

	;	incr_sp(int, string)
			% Increment the det stack pointer. The string is
			% the name of the procedure, for use in stack dumps.
			% It is used only in grades in which stack dumps are
			% enabled (i.e. not in grades where SPEED is defined).

	;	decr_sp(int)
			% Decrement the det stack pointer.

	;	pragma_c(list(pragma_c_decl), list(pragma_c_component),
				may_call_mercury, maybe(label), maybe(label),
				maybe(label), maybe(label), bool)
			% The first argument says what local variable
			% declarations are required for the following
			% components, which in turn can specify how
			% the inputs should be placed in their variables,
			% how the outputs should be picked up from their
			% variables, and C code both from the program
			% and the compiler. These components can be
			% sequenced in various ways. This flexibility
			% is needed for nondet pragma C codes, which
			% need different copies of several components
			% for different paths tthrough the code.
			%
			% The third argument says whether the user C code
			% components may call Mercury; certain optimizations
			% can be performed across pragma_c instructions that
			% cannot call Mercury.
			%
			% Some components in some pragma_c instructions
			% refer to a Mercury label. If they do, we must
			% prevent the label from being optimized away.
			% To make it known to labelopt, we mention it in
			% the fourth, fifth or sixth arg. The fourth argument
			% may give the name of a label whose name is fixed
			% because it embedded in raw C code, and which does
			% not have a layout structure. The fifth and sixth
			% arguments may give the names of labels whose names
			% are fixed because they do have an associated label
			% layout structure. The label in the fifth argument
			% may appear in C code; the label in the sixth argument
			% may not (such a label may therefore may be deleted
			% from the LLDS code if it is not referred to from
			% anywhere else). The seventh argument may give the
			% name of a label that can be changed (because it is
			% not mentioned in C code and has no associated layout
			% structure, being mentioned only in pragma_c_fail_to
			% components).
			%
			% The last argument says whether the contents
			% of the pragma C code can refer to stack slots.
			% User-written shouldn't refer to stack slots,
			% the question is whether the compiler-generated
			% C code does.

	;	init_sync_term(lval, int)
			% Initialize a synchronization term.
			% the first arguement contains the lvalue into
			% which we will store the synchronization term,
			% and the second argument indicates how many
			% branches we expect to join at the end of the
			% parallel conjunction.
			% (See the documentation in par_conj_gen.m and
			% runtime/mercury_context.{c,h} for further
			% information about synchronisation terms.)

	;	fork(label, label, int)
			% Create a new context.
			% fork(Child, Parent, NumSlots) creates a new thread
			% which will start executing at Child. After spawning
			% execution in the child, control branches to Parent.
			% NumSlots is the number of stack slots that need to
			% be copied to the child's stack (see comments in
			% runtime/mercury_context.{h,c}).

	;	join_and_terminate(lval)
			% Signal that this thread of execution has finished in
			% the current parallel conjunction, then terminate it.
			% The synchronisation term is specified by the
			% given lval. (See the documentation in par_conj_gen.m
			% and runtime/mercury_context.{c,h} for further
			% information about synchronisation terms.)

	;	join_and_continue(lval, label)
			% Signal that this thread of execution has finished
			% in the current parallel conjunction, then branch to
			% the given label. The synchronisation
			% term is specified by the given lval.
	.

:- type nondet_frame_info
	--->	temp_frame(
			temp_frame_type
		)
	;	ordinary_frame(
			string, 		% Name of the predicate.
			int,			% Number of framevar slots.
			maybe(pragma_c_struct)	% If yes, the frame should
						% also contain this struct
						% (for use by a model_non
						% pragma C code).
		).

:- type c_code_live_lvals
	--->	no_live_lvals_info	% There is no information available
					% about the live lvals used in
					% the c_code.

	;	live_lvals_info(	
			set(lval)	% The set of lvals defined before the
					% c_code that are live inside the
					% c_code.
		).

	% Temporary frames on the nondet stack exist only to provide a failure
	% environment, i.e. a place to store a redoip and a redofr. Accurate
	% garbage collection and execution tracing need to know how to
	% interpret the layout information associated with the label whose
	% address is in the redoip slot. If the label is in a procedure that
	% stores its variables on the nondet stack, the redofr slot will give
	% the address of the relevant stack frame. If the label is in a
	% procedure that stores its variables on the det stack, the temporary
	% frame will contain an extra slot containing the address of the
	% relevant frame on the det stack.
:- type temp_frame_type
	--->	det_stack_proc
	;	nondet_stack_proc.

	% Procedures defined by nondet pragma C codes must have some way of
	% preserving information after a success, so that when control
	% backtracks to the procedure, the C code knows what to do.
	% Our implementation saves this information in a C struct.
	% Programmers must include the declaration of the fields of this
	% C struct in the `pragma c_code' declaration itself.
	% A pragma_c_struct holds information about this C struct.
:- type pragma_c_struct
	--->	pragma_c_struct(
			string,		% The name of the struct tag.
			string,		% The field declarations, supplied
					% by the user in the `pragma c_code'
					% declaration.
			maybe(prog_context)
					% Where the field declarations
					% originally appeared.
		).

	% A pragma_c_decl holds the information needed for the declaration
	% of a local variable in a block of C code emitted for a pragma_c
	% instruction.
:- type pragma_c_decl
	--->	pragma_c_arg_decl(
			% This local variable corresponds to a procedure arg.
			type,	% The Mercury type of the argument.
			string,	% The string which is used to describe the
				% type in the C code.
			string	% The name of the local variable that
				% will hold the value of that argument
				% inside the C block.
		)
	;	pragma_c_struct_ptr_decl(
			% This local variable holds the address of the
			% save struct.
			string,	% The name of the C struct tag of the save
				% struct; the type of the local variable
				% will be a pointer to a struct with this tag.
			string	% The name of the local variable.
		).

	% A pragma_c_component holds one component of a pragma_c instruction.
:- type pragma_c_component
	--->	pragma_c_inputs(list(pragma_c_input))
	;	pragma_c_outputs(list(pragma_c_output))
	;	pragma_c_user_code(maybe(prog_context), string)
	;	pragma_c_raw_code(string, c_code_live_lvals)
	;	pragma_c_fail_to(label)
	;	pragma_c_noop.

	% A pragma_c_input represents the code that initializes one
	% of the input variables for a pragma_c instruction.
:- type pragma_c_input
	--->	pragma_c_input(string, type, rval, maybe(string)).
				% variable name, type, variable value,
				% maybe C type if foreign type.

	% A pragma_c_output represents the code that stores one of
	% of the outputs for a pragma_c instruction.
:- type pragma_c_output
	--->	pragma_c_output(lval, type, string, maybe(string)).
				% where to put the output val, type and name
				% of variable containing the output val
				% followed by maybe C type if foreign type.

	% see runtime/mercury_trail.h
:- type reset_trail_reason
	--->	undo
	;	commit
	;	solve
	;	exception
	;	retry
	;	gc
	.

	% Each call instruction has a list of liveinfo, which stores
	% information about which variables are live after the call
	% (that is, on return).  The information is intended for use by
	% the non-conservative garbage collector.
:- type liveinfo
	--->	live_lvalue(
			layout_locn,
				% What location does this lifeinfo structure
				% refer to?
			live_value_type,
				% What is the type of this live value?
			map(tvar, set(layout_locn))
				% For each tvar that is a parameter of the
				% type of this value, give the set of
				% locations where the type_info variable
				% describing the actual type bound to the
				% type parameter may be found.
				%
				% We record all the locations of the typeinfo,
				% in case different paths of arriving a this
				% program point leave the typeinfo in different
				% sets of locations. However, there must be at
				% least type_info location that is valid
				% along all paths leading to this point.
		).

	% For an explanation of this type, see the comment on
	% stack_layout__represent_locn.
:- type layout_locn
	--->	direct(lval)
	;	indirect(lval, int).

	% live_value_type describes the different sorts of data that
	% can be considered live.
:- type live_value_type
	--->	succip				% A stored succip.
	;	curfr				% A stored curfr.
	;	maxfr				% A stored maxfr.
	;	redoip				% A stored redoip.
	;	redofr				% A stored redofr.
	;	hp				% A stored heap pointer.
	;	trail_ptr			% A stored trail pointer.
	;	ticket				% A stored ticket.
	;	var(prog_var, string, type, llds_inst)
						% A variable (the var number
						% and name are for execution
						% tracing; we have to store
						% the name here because when
						% we want to use the
						% live_value_type, we won't
						% have access to the varset).
	;	unwanted.			% Something we don't need,
						% or at least don't need
						% information about.

	% For recording information about the inst of a variable for use
	% by the garbage collector or the debugger, we don't need to know
	% what functors its parts are bound to, or which parts of it are
	% unique; we just need to know which parts of it are bound.
	% If we used the HLDS type inst to represent the instantiatedness
	% in the LLDS, we would find that insts that the LLDS wants to treat
	% as the same would compare as different. The live_value_types and
	% var_infos containing them would compare as different as well,
	% which can lead to a variable being listed more than once in
	% a label's list of live variable.
	%
	% At the moment, the LLDS only handles ground insts. When this changes,
	% the argument type of partial will have to be changed.
:- type llds_inst
	--->	ground
	;	partial((inst)).

	% An lval represents a data location or register that can be used
	% as the target of an assignment.
:- type lval --->

	/* virtual machine registers */

		reg(reg_type, int)
				% One of the general-purpose virtual machine
				% registers (either an int or float reg).

	;	succip		% Virtual machine register holding the
				% return address for det/semidet code.

	;	maxfr		% Virtual machine register holding a pointer
				% to the top of nondet stack.

	;	curfr		% Virtual machine register holding a pointer
				% to the current nondet stack frame.

	;	hp		% Virtual machine register holding the heap
				% pointer.

	;	sp		% Virtual machine register point to the
				% top of det stack.

	;	temp(reg_type, int)
				% A local temporary register.
				% These temporary registers are actually
				% local variables declared in `block'
				% instructions.  They may only be
				% used inside blocks.  The code generator
				% doesn't generate these; they are introduced
				% by value numbering.  The basic idea is
				% to improve efficiency by using local
				% variables that the C compiler may be
				% able to allocate in a register rather than
				% using stack slots.

	/* values on the stack */

	;	stackvar(int)	% A det stack slot. The number is the offset
				% relative to the current value of `sp'.
				% These are used in both det and semidet code.
				% Stackvar slot numbers start at 1.

	;	framevar(int)	% A nondet stack slot. The reference is
				% relative to the current value of `curfr'.
				% These are used in nondet code.
				% Framevar slot numbers start at 1.

	;	succip(rval)	% The succip slot of the specified
				% nondet stack frame; holds the code address
				% to jump to on successful exit from this
				% nondet procedure.

	;	redoip(rval)	% The redoip slot of the specified
				% nondet stack frame; holds the code address
				% to jump to on failure.

	;	redofr(rval)	% the redofr slot of the specified
				% nondet stack frame; holds the address of
				% the frame that the curfr register should be
				% set to when backtracking through the redoip
				% slot.

	;	succfr(rval)	% The succfr slot of the specified
				% nondet stack frame; holds the address of
				% caller's nondet stack frame.  On successful
				% exit from this nondet procedure, we will
				% set curfr to this value.

	;	prevfr(rval)	% The prevfr slot of the specified
				% nondet stack frame; holds the address of
				% the previous frame on the nondet stack.

	/* values on the heap */

	;	field(maybe(tag), rval, rval)
				% field(Tag, Address, FieldNum)
				% selects a field of a compound term.
				% Address is a tagged pointer to a cell
				% on the heap; the offset into the cell
				% is FieldNum words. If Tag is yes, the
				% arg gives the value of the tag; if it is
				% no, the tag bits will have to be masked off.
				% The value of the tag should be given if
				% it is known, since this will lead to
				% faster code.

	/* values somewhere in memory */

	;	mem_ref(rval)	% A word in the heap, in the det stack or
				% in the nondet stack. The rval should have
				% originally come from a mem_addr rval.

	/* pseudo-values */

	;	lvar(prog_var).	% The location of the specified variable.
				% `var' lvals are used during code generation,
				% but should not be present in the LLDS at any
				% stage after code generation.

	% An rval is an expression that represents a value.
:- type rval	
	--->	lval(lval)
		% The value of an `lval' rval is just the value stored in
		% the specified lval.

	;	var(prog_var)
		% The value of a `var' rval is just the value of the
		% specified variable.
		% `var' rvals are used during code generation,
		% but should not be present in the LLDS at any
		% stage after code generation.

	;	mkword(tag, rval)
		% Given a pointer and a tag, mkword returns a tagged pointer.

	;	const(rval_const)

	;	unop(unary_op, rval)

	;	binop(binary_op, rval, rval)

	;	mem_addr(mem_ref).
		% The address of a word in the heap, the det stack or
		% the nondet stack.

:- type mem_ref
	--->	stackvar_ref(int)		% stack slot number
	;	framevar_ref(int)		% stack slot number
	;	heap_ref(rval, int, int).	% the cell pointer,
						% the tag to subtract,
						% and the field number

:- type rval_const
	--->	true
	;	false
	;	int_const(int)
	;	float_const(float)
	;	string_const(string)
	;	multi_string_const(int, string)
			% a string containing embedded NULLs,
			% whose real length is given by the integer,
			% and not the location of the first NULL
	;	code_addr_const(code_addr)
	;	data_addr_const(data_addr, maybe(int))
			% if the second arg is yes(Offset), then increment the
			% address of the first by Offset words
	;	label_entry(label).
			% the address of the label (uses MR_ENTRY macro).

:- type data_addr
	--->	data_addr(module_name, data_name)
			% module name; which var
	;	rtti_addr(rtti_id)
	;	layout_addr(layout_name).

:- type data_name
	--->	common(int, int)
			% The first int is the cell number; the second is the
			% cell type number.
	;	tabling_pointer(proc_label).
			% A variable that contains a pointer that points to
			% the table used to implement memoization, loopcheck
			% or minimal model semantics for the given procedure.

:- type reg_type	
	--->	r		% general-purpose (integer) regs
	;	f.		% floating point regs

:- type label
	--->	local(int, proc_label)	% not proc entry; internal to a
					% procedure
	;	c_local(proc_label)	% proc entry; internal to a C module
	;	local(proc_label)	% proc entry; internal to a Mercury
					% module
	;	exported(proc_label).	% proc entry; exported from a Mercury
					% module

:- type code_addr
	--->	label(label)		% A label defined in this Mercury
					% module.
	;	imported(proc_label)	% A label from another Mercury module.
	;	succip			% The address in the `succip'
					% register.
	;	do_succeed(bool)	% The bool is `yes' if there are any
					% alternatives left.  If the bool is
					% `no', we do a succeed_discard()
					% rather than a succeed().
	;	do_redo
	;	do_fail

	;	do_trace_redo_fail_shallow
	;	do_trace_redo_fail_deep
					% Labels in the runtime, the code
					% at which calls MR_trace with a
					% REDO event and then fails. The
					% shallow variety only does this
					% if the from_full flag was set
					% on entry to the given procedure.
	;	do_call_closure
	;	do_call_class_method
	;	do_not_reached.		% We should never jump to this address.

	% A tag (used in mkword, create and field expressions
	% and in incr_hp instructions) is a small integer.
:- type tag	==	int.

	% We categorize the data types used in the LLDS into
	% a small number of categories, for purposes such as
	% choosing the right sort of register for a given value
	% to avoid unnecessary boxing/unboxing of floats.
:- type llds_type
	--->	bool		% A boolean value
				% represented using the C type `MR_Integer'.
	;	int_least8	% A signed value that fits that contains
				% at least eight bits, represented using the
				% C type MR_int_least8_t. Intended for use in
				% static data declarations, not for data
				% that gets stored in registers, stack slots
				% etc.
	;	uint_least8	% An unsigned version of int_least8,
				% represented using the C type
				% MR_uint_least8_t.
	;	int_least16	% A signed value that fits that contains
				% at least sixteen bits, represented using the
				% C type MR_int_least16_t. Intended for use in
				% static data declarations, not for data
				% that gets stored in registers, stack slots
				% etc.
	;	uint_least16	% An unsigned version of int_least16,
				% represented using the C type
				% MR_uint_least16_t.
	;	int_least32	% A signed value that fits that contains
				% at least 32 bits, represented using the
				% C type MR_int_least32_t. Intended for use in
				% static data declarations, not for data
				% that gets stored in registers, stack slots
				% etc.
	;	uint_least32	% An unsigned version of intleast_32,
				% represented using the C type uint_least32_t.
	;	integer		% A Mercury `int', represented in C as a
				% value of type `MR_Integer' (which is
				% a signed integral type of the same
				% size as a pointer).
	;	unsigned	% Something whose C type is `MR_Unsigned'
				% (the unsigned equivalent of `MR_Integer').
	;	float		% A Mercury `float', represented in C as a
				% value of type `MR_Float' (which may be either
				% `float' or `double', but is usually
				% `double').
	;	string		% A Mercury string; represented in C as a
				% value of type `MR_String'.
	;	data_ptr	% A pointer to data; represented in C
				% as a value of C type `MR_Word *'.
	;	code_ptr	% A pointer to code; represented in C
				% as a value of C type `MR_Code *'.
	;	word.		% Something that can be assigned to a value
				% of C type `MR_Word', i.e., something whose
				% size is a word but which may be either
				% signed or unsigned
				% (used for registers, stack slots, etc).

:- func llds__stack_slot_num_to_lval(code_model, int) = lval.

:- pred llds__wrap_rtti_data(rtti_data::in, comp_gen_c_data::out) is det.

	% given a non-var rval, figure out its type
:- pred llds__rval_type(rval::in, llds_type::out) is det.

	% given a non-var lval, figure out its type
:- pred llds__lval_type(lval::in, llds_type::out) is det.

	% given a constant, figure out its type
:- pred llds__const_type(rval_const::in, llds_type::out) is det.

	% given a unary operator, figure out its return type
:- pred llds__unop_return_type(unary_op::in, llds_type::out) is det.

	% given a unary operator, figure out the type of its argument
:- pred llds__unop_arg_type(unary_op::in, llds_type::out) is det.

	% given a binary operator, figure out its return type
:- pred llds__binop_return_type(binary_op::in, llds_type::out) is det.

	% given a register, figure out its type
:- pred llds__register_type(reg_type::in, llds_type::out) is det.

:- func get_proc_label(label) = proc_label.

:- func get_defining_module_name(proc_label) = module_name.

:- implementation.

:- import_module require.

llds__stack_slot_num_to_lval(CodeModel, SlotNum) =
	(if CodeModel = model_non then
		framevar(SlotNum)
	else
		stackvar(SlotNum)
	).

llds__wrap_rtti_data(RttiData, rtti_data(RttiData)).

llds__lval_type(reg(RegType, _), Type) :-
	llds__register_type(RegType, Type).
llds__lval_type(succip, code_ptr).
llds__lval_type(maxfr, data_ptr).
llds__lval_type(curfr, data_ptr).
llds__lval_type(hp, data_ptr).
llds__lval_type(sp, data_ptr).
llds__lval_type(temp(RegType, _), Type) :-
	llds__register_type(RegType, Type).
llds__lval_type(stackvar(_), word).
llds__lval_type(framevar(_), word).
llds__lval_type(succip(_), code_ptr).
llds__lval_type(redoip(_), code_ptr).
llds__lval_type(redofr(_), data_ptr).
llds__lval_type(succfr(_), data_ptr).
llds__lval_type(prevfr(_), data_ptr).
llds__lval_type(field(_, _, _), word).
llds__lval_type(lvar(_), _) :-
	error("lvar unexpected in llds__lval_type").
llds__lval_type(mem_ref(_), word).

llds__rval_type(lval(Lval), Type) :-
	llds__lval_type(Lval, Type).
llds__rval_type(var(_), _) :-
	error("var unexpected in llds__rval_type").
	%
	% Note that mkword and data_addr consts must be of type data_ptr,
	% not of type word, to ensure that static consts containing
	% them get type `const Word *', not type `Word'; this is
	% necessary because casts from pointer to int must not be used
	% in the initializers for constant expressions -- if they are,
	% then lcc barfs, and gcc generates bogus code on some systems,
	% (e.g. IRIX with shared libs).  If the second argument to mkword
	% is an integer, not a pointer, then we will end up casting it
	% to a pointer, but casts from integer to pointer are OK, it's
	% only the reverse direction we need to avoid.
	%
llds__rval_type(mkword(_, _), data_ptr).
llds__rval_type(const(Const), Type) :-
	llds__const_type(Const, Type).
llds__rval_type(unop(UnOp, _), Type) :-
	llds__unop_return_type(UnOp, Type).
llds__rval_type(binop(BinOp, _, _), Type) :-
	llds__binop_return_type(BinOp, Type).
llds__rval_type(mem_addr(_), data_ptr).

llds__const_type(true, bool).
llds__const_type(false, bool).
llds__const_type(int_const(_), integer).
llds__const_type(float_const(_), float).
llds__const_type(string_const(_), string).
llds__const_type(multi_string_const(_, _), string).
llds__const_type(code_addr_const(_), code_ptr).
llds__const_type(data_addr_const(_, _), data_ptr).
llds__const_type(label_entry(_), code_ptr).

llds__unop_return_type(mktag, word).
llds__unop_return_type(tag, word).
llds__unop_return_type(unmktag, word).
llds__unop_return_type(strip_tag, word).
llds__unop_return_type(mkbody, word).
llds__unop_return_type(unmkbody, word).
llds__unop_return_type(hash_string, integer).
llds__unop_return_type(bitwise_complement, integer).
llds__unop_return_type(not, bool).

llds__unop_arg_type(mktag, word).
llds__unop_arg_type(tag, word).
llds__unop_arg_type(unmktag, word).
llds__unop_arg_type(strip_tag, word).
llds__unop_arg_type(mkbody, word).
llds__unop_arg_type(unmkbody, word).
llds__unop_arg_type(hash_string, string).
llds__unop_arg_type(bitwise_complement, integer).
llds__unop_arg_type(not, bool).

llds__binop_return_type((+), integer).
llds__binop_return_type((-), integer).
llds__binop_return_type((*), integer).
llds__binop_return_type((/), integer).
llds__binop_return_type((mod), integer).
llds__binop_return_type((<<), integer).
llds__binop_return_type((>>), integer).
llds__binop_return_type((&), integer).
llds__binop_return_type(('|'), integer).
llds__binop_return_type((^), integer).
llds__binop_return_type((and), bool).
llds__binop_return_type((or), bool).
llds__binop_return_type(eq, bool).
llds__binop_return_type(ne, bool).
llds__binop_return_type(array_index(_Type), word).
llds__binop_return_type(str_eq, bool).
llds__binop_return_type(str_ne, bool).
llds__binop_return_type(str_lt, bool).
llds__binop_return_type(str_gt, bool).
llds__binop_return_type(str_le, bool).
llds__binop_return_type(str_ge, bool).
llds__binop_return_type((<), bool).
llds__binop_return_type((>), bool).
llds__binop_return_type((<=), bool).
llds__binop_return_type((>=), bool).
llds__binop_return_type(unsigned_le, bool).
llds__binop_return_type(float_plus, float).
llds__binop_return_type(float_minus, float).
llds__binop_return_type(float_times, float).
llds__binop_return_type(float_divide, float).
llds__binop_return_type(float_eq, bool).
llds__binop_return_type(float_ne, bool).
llds__binop_return_type(float_lt, bool).
llds__binop_return_type(float_gt, bool).
llds__binop_return_type(float_le, bool).
llds__binop_return_type(float_ge, bool).
llds__binop_return_type(body, word).

llds__register_type(r, word).
llds__register_type(f, float).

get_proc_label(exported(ProcLabel)) = ProcLabel.
get_proc_label(local(ProcLabel)) = ProcLabel.
get_proc_label(c_local(ProcLabel)) = ProcLabel.
get_proc_label(local(_, ProcLabel)) = ProcLabel.

get_defining_module_name(proc(ModuleName, _, _, _, _, _)) = ModuleName.
get_defining_module_name(special_proc(ModuleName, _, _, _, _, _)) = ModuleName.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
