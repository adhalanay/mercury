/*
** Copyright (C) 1994-2004 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** mercury_engine.h - definitions for the Mercury runtime engine.
**
** For documentation, see also the comments in mercury_engine.c.
*/

#ifndef	MERCURY_ENGINE_H
#define	MERCURY_ENGINE_H

	/*
	** include mercury_regs.h first so that we don't have
	** any function prototypes before the global register
	** declarations.
	*/
#include "mercury_regs.h"		/* for MR_NUM_REAL_REGS */

#include <setjmp.h>

#include "mercury_std.h"		/* for `MR_bool' */
#include "mercury_types.h"		/* for `MR_Code *' */
#include "mercury_goto.h"		/* for `MR_define_entry()' */
#include "mercury_thread.h"		/* for pthread types */
#include "mercury_context.h"		/* for MR_Context, MR_IF_USE_TRAIL */
#include "mercury_conf.h"		/* for MR_CONSERVATIVE_GC */

/*---------------------------------------------------------------------------*/

/*
** Global flags that control the behaviour of the Mercury engine(s)
*/

extern	MR_bool	MR_debugflag[];

/*
** These #defines, except MR_MAXFLAG, should not be used anywhere
** except in the immediately following block of #defines, and in the
** array that maps these names to their slots in the source file.
*/

#define	MR_PROGFLAG			0
#define	MR_GOTOFLAG			1
#define	MR_CALLFLAG			2
#define	MR_HEAPFLAG			3
#define	MR_DETSTACKFLAG			4
#define	MR_NONDSTACKFLAG		5
#define	MR_FINALFLAG			6
#define	MR_MEMFLAG			7
#define	MR_SREGFLAG			8
#define	MR_TRACEFLAG			9
#define	MR_TABLEFLAG			10
#define	MR_TABLEHASHFLAG		11
#define	MR_TABLESTACKFLAG		12
#define	MR_UNBUFFLAG			13
#define	MR_AGC_FLAG 			14
#define	MR_ORDINARY_REG_FLAG		15
#define	MR_ANY_REG_FLAG 		16
#define	MR_PRINT_LOCN_FLAG 		17
#define	MR_LLD_DEBUG_ENABLED_FLAG 	18
#define	MR_NOT_NEAREST_FLAG 		19
#define	MR_DEBUG_SLOTS_FLAG		20
#define	MR_DETAILFLAG			21
#define	MR_MAXFLAG			22
/* MR_DETAILFLAG should be the last real flag */

/*
** The macros control different kinds of low level debugging messages.
** Usually, their values are all false.
**
** MR_progdebug controls whether we want to get several mostly explicitly
** programmed diagnostics.
**
** MR_sregdebug controls whether we want to print the values of the special
** registers (e.g. those that point to the stack) at some diagnostic points.
**
** MR_ordregdebug controls whether we want to print the values of the ordinary
** registers (e.g. r1, r2 etc) at some diagnostic points.
**
** MR_anyregdebug controls whether we want to print the values of the any
** registers, either special or ordinary, at some diagnostic points.
**
** MR_gotodebug controls whether we should generate diagnostics at gotos.
**
** MR_calldebug controls whether we should generate diagnostics when control
** crosses procedure boundaries, i.e. calls, exits, redos and fails.
**
** MR_detstackdebug and MR_nondstackdebug control whether we should generate
** diagnostics when incrementing and decrementing the pointers to the
** respective stacks.
**
** MR_heapdebug controls whether we should generate diagnostics when we
** allocate memory on the heap.
**
** MR_tabledebug controls whether we should generate diagnostics for tabling
** operations. MR_tablestackdebug control whether these should include the
** contents of stack segments manipulated by minimal model tabling.
** MR_hashdebug controls whether these should include details of hash table
** accesses.
**
** MR_agcdebug controls whether we should generate diagnostics for accurate
** gc operations.
**
** MR_detaildebug controls whether we want more or less detail in some
** diagnostics.
**
** MR_unbufdebug controls whether the runtime will make stdout and stderr
** unbuffered.
**
** MR_memdebug controls whether we want to get diagnostics on the setup of
** memory zones.
**
** MR_finaldebug controls whether we want to get diagnostics showing how
** execution reaches the end of the program.
**
** MR_printlocndebug controls whether we want to get diagnostics showing how
** the runtime system looks up locations recorded in RTTI data structures.
**
** MR_lld_debug_enabled turns on the generation of diagnostic output even when
** they would otherwise be disabled.
**
** MR_not_nearest_flag, if set, tells minimal model tabling to save stack
** segments only to the nearest generator, not to the nearest common ancestor
** of the consumer being suspended and its generator.
**
** MR_debug_slots_flag controls whether dumps of nondet stack frames will
** print the values of the fixed stack slots used by the debugger, in the
** stack frames of procedures compiled with debugging.
*/

#define	MR_progdebug		MR_debugflag[MR_PROGFLAG]
#define	MR_gotodebug		MR_debugflag[MR_GOTOFLAG]
#define	MR_calldebug		MR_debugflag[MR_CALLFLAG]
#define	MR_heapdebug		MR_debugflag[MR_HEAPFLAG]
#define	MR_detstackdebug	MR_debugflag[MR_DETSTACKFLAG]
#define	MR_nondstackdebug	MR_debugflag[MR_NONDSTACKFLAG]
#define	MR_finaldebug		MR_debugflag[MR_FINALFLAG]
#define	MR_memdebug		MR_debugflag[MR_MEMFLAG]
#define	MR_sregdebug		MR_debugflag[MR_SREGFLAG]
#define	MR_tracedebug		MR_debugflag[MR_TRACEFLAG]
#define	MR_tabledebug		MR_debugflag[MR_TABLEFLAG]
#define	MR_hashdebug		MR_debugflag[MR_TABLEHASHFLAG]
#define	MR_tablestackdebug	MR_debugflag[MR_TABLESTACKFLAG]
#define	MR_unbufdebug		MR_debugflag[MR_UNBUFFLAG]
#define	MR_agc_debug		MR_debugflag[MR_AGC_FLAG]
#define	MR_ordregdebug		MR_debugflag[MR_ORDINARY_REG_FLAG]
#define	MR_anyregdebug		MR_debugflag[MR_ANY_REG_FLAG]
#define	MR_printlocndebug	MR_debugflag[MR_PRINT_LOCN_FLAG]
#define	MR_lld_debug_enabled	MR_debugflag[MR_LLD_DEBUG_ENABLED_FLAG]
#define	MR_not_nearest_flag	MR_debugflag[MR_NOT_NEAREST_FLAG]
#define	MR_debug_slots_flag	MR_debugflag[MR_DEBUG_SLOTS_FLAG]
#define	MR_detaildebug		MR_debugflag[MR_DETAILFLAG]

typedef struct {
	const char		*MR_debug_flag_name;
	int			MR_debug_flag_index;
} MR_Debug_Flag_Info;

extern	MR_Debug_Flag_Info	MR_debug_flag_info[MR_MAXFLAG];

	/* 
	** MR_setjmp and MR_longjmp are wrappers around setjmp and longjmp 
	** to ensure that
	**	 call C -> setjmp -> call Mercury -> call C -> longjmp 
	** works correctly. This is used by the exception handling code for
	** the ODBC interface, and probably shouldn't be used for anything
	** else.
	*/ 

typedef struct {
		jmp_buf *mercury_env;	/* 
					** used to save
					** MR_ENGINE(MR_eng_jmp_buf )
					*/
		jmp_buf env;		/* 
					** used by calls to setjmp and longjmp 
					*/
		MR_Word *saved_succip;
		MR_Word *saved_sp;
		MR_Word *saved_curfr;
		MR_Word *saved_maxfr;
		MR_IF_USE_TRAIL(MR_TrailEntry *saved_trail_ptr;)
		MR_IF_USE_TRAIL(MR_Unsigned saved_ticket_counter;)
		MR_IF_USE_TRAIL(MR_Unsigned saved_ticket_high_water;)

#if MR_NUM_REAL_REGS > 0
		MR_Word regs[MR_NUM_REAL_REGS];
#endif /* MR_NUM_REAL_REGS > 0 */

	} MR_jmp_buf;

/*---------------------------------------------------------------------------*/

/*
** Replacements for setjmp() and longjmp() that work
** across calls to Mercury code.
*/

	/*
	** MR_setjmp(MR_jmp_buf *env, longjmp_label)
	**
	** Save MR_ENGINE(MR_eng_jmp_buf), save the Mercury state,
	** call setjmp(env),  then fall through.
	**
	** When setjmp returns via a call to longjmp, control will pass to
	** longjmp_label.
	**
	** Notes:
	** - The Mercury registers must be valid before the call to MR_setjmp.
	** - The general-purpose registers MR_r1, MR_r2... are not restored
	** and must be saved by the caller.
	** - In grades without conservative garbage collection, the caller
	** must save and restore hp, sol_hp, heap_zone 
	** and solutions_heap_zone.
	*/
#define MR_setjmp(setjmp_env, longjmp_label)				\
	    do {							\
		(setjmp_env)->mercury_env = MR_ENGINE(MR_eng_jmp_buf);	\
		MR_save_regs_to_mem((setjmp_env)->regs);		\
		(setjmp_env)->saved_succip = MR_succip;			\
		(setjmp_env)->saved_sp = MR_sp;				\
		(setjmp_env)->saved_curfr = MR_curfr;			\
		(setjmp_env)->saved_maxfr = MR_maxfr;			\
		MR_IF_USE_TRAIL((setjmp_env)->saved_trail_ptr = 	\
				MR_trail_ptr);				\
		MR_IF_USE_TRAIL((setjmp_env)->saved_ticket_counter =	\
				MR_ticket_counter);			\
		MR_IF_USE_TRAIL((setjmp_env)->saved_ticket_high_water =	\
				MR_ticket_high_water);			\
		if (setjmp((setjmp_env)->env)) {			\
			MR_ENGINE(MR_eng_jmp_buf) = (setjmp_env)->mercury_env;\
			MR_restore_regs_from_mem((setjmp_env)->regs);	\
			MR_succip = (setjmp_env)->saved_succip;		\
			MR_sp = (setjmp_env)->saved_sp;			\
			MR_curfr = (setjmp_env)->saved_curfr;		\
			MR_maxfr = (setjmp_env)->saved_maxfr;		\
			MR_IF_USE_TRAIL(MR_trail_ptr = 			\
					(setjmp_env)->saved_trail_ptr);	\
			MR_IF_USE_TRAIL(MR_ticket_counter = 		\
				(setjmp_env)->saved_ticket_counter);	\
			MR_IF_USE_TRAIL(MR_ticket_high_water = 		\
				(setjmp_env)->saved_ticket_high_water);	\
			goto longjmp_label;				\
		}							\
	    } while (0)

	/*
	** MR_longjmp(MR_jmp_buf *env)
	** 
	** Call longjmp(), MR_setjmp() will handle the rest.
	*/
#define MR_longjmp(setjmp_env)	longjmp((setjmp_env)->env, 1)

/*---------------------------------------------------------------------------*/

#ifdef	MR_THREAD_SAFE
typedef struct MR_mercury_thread_list_struct {
	MercuryThread				thread;
	struct MR_mercury_thread_list_struct	*next;
} MercuryThreadList;
#endif

/*
** The Mercury engine structure.
**	Normally there is one of these for each Posix thread.
*/

typedef struct MR_mercury_engine_struct {
	MR_Word		MR_eng_fake_reg[MR_MAX_FAKE_REG];
		/* The fake reg vector for this engine. */
#ifndef MR_CONSERVATIVE_GC
	MR_Word		*MR_eng_hp;
		/* The heap pointer for this engine */
	MR_Word		*MR_eng_sol_hp;
		/* The solutions heap pointer for this engine */
	MR_Word		*MR_eng_global_hp;
		/* The global heap pointer for this engine */
#endif
	MR_Context	*MR_eng_this_context;
		/*
		** MR_eng_this_context points to the context currently
		** executing in this engine.
		*/
	MR_Context	MR_eng_context;
		/*
		** MR_eng_context stores all the context information
		** for the context executing in this engine.
		*/
#ifdef	MR_THREAD_SAFE
	MercuryThread	MR_eng_owner_thread;
	unsigned	MR_eng_c_depth;
	MercuryThreadList *MR_eng_saved_owners;
		/*
		** These three fields are used to ensure that when a
		** thread executing C code calls the Mercury engine
		** associated with that thread, the Mercury code
		** will finish in the same engine and return appropriately.
		** Each time C calls Mercury in a thread, the c_depth
		** is incremented, and the owner_thread field of the current
		** context is set to the id of the thread. While the
		** owner_thread is set, the context will not be scheduled
		** for execution by any other thread. When the call to
		** the Mercury engine finishes, c_depth is decremented and
		** the owner_thread field of the current context is restored
		** to its previous value.
		** The list `saved_owners' is used in call_engine_inner
		** to store the owner of a context across calls into Mercury.
		** At the moment this is only used for sanity checking - that
		** execution never returns into C in the wrong thread.
		*/
#endif
	jmp_buf		*MR_eng_jmp_buf;
	MR_Word		*MR_eng_exception;
#ifndef	MR_CONSERVATIVE_GC
	MR_MemoryZone	*MR_eng_heap_zone;
  #ifdef MR_MIGHT_RECLAIM_HP_ON_FAILURE
	MR_MemoryZone	*MR_eng_solutions_heap_zone;
	MR_MemoryZone	*MR_eng_global_heap_zone;
  #endif
#endif
#ifdef	MR_NATIVE_GC
	MR_MemoryZone	*MR_eng_heap_zone2;
  #ifdef MR_DEBUG_AGC_PRINT_VARS
	MR_MemoryZone	*MR_eng_debug_heap_zone;
  #endif
#endif
} MercuryEngine;

/*
** MR_engine_base refers to the engine in which execution is taking place.
** In the non-thread-safe situation, it is just a global variable.
** In the thread-safe situation, MR_engine_base is either a global
** register (if one is available), or a macro that accesses thread-local
** storage. We provide two macros, MR_ENGINE(x) and MR_CONTEXT(x),
** that can be used in both kinds of situations to refer to fields
** of the engine structure, and to fields of the engine's current context.
*/

#ifdef	MR_THREAD_SAFE

  extern MercuryThreadKey	MR_engine_base_key;

  #define MR_thread_engine_base \
	((MercuryEngine *) MR_GETSPECIFIC(MR_engine_base_key))

  #if MR_NUM_REAL_REGS > 0
    #define	MR_ENGINE_BASE_REGISTER
  	/*
	** MR_engine_base is defined in machdeps/{arch}.h
	*/
  #else
	#define	MR_engine_base	MR_thread_engine_base
  #endif

  #define MR_ENGINE(x)		(((MercuryEngine *) MR_engine_base)->x)
  #define MR_cur_engine()	((MercuryEngine *) MR_engine_base)
  #define MR_get_engine()	((MercuryEngine *) MR_thread_engine_base)

#else 	/* !MR_THREAD_SAFE */

  extern MercuryEngine	MR_engine_base;
  #define MR_ENGINE(x)		(MR_engine_base.x)
  #define MR_cur_engine()	(&MR_engine_base)
  #define MR_get_engine()	(&MR_engine_base)

#endif	/* !MR_THREAD_SAFE */

#define	MR_CONTEXT(x)		(MR_ENGINE(MR_eng_context).x)

#ifndef MR_CONSERVATIVE_GC
  #define MR_IF_NOT_CONSERVATIVE_GC(x)	x
#else
  #define MR_IF_NOT_CONSERVATIVE_GC(x)
#endif

#define MR_load_engine_regs(eng)					\
  	do {								\
		MR_IF_NOT_CONSERVATIVE_GC(MR_hp = (eng)->MR_eng_hp;)	\
		MR_IF_NOT_CONSERVATIVE_GC(MR_sol_hp =			\
			(eng)->MR_eng_sol_hp;)				\
		MR_IF_NOT_CONSERVATIVE_GC(MR_global_hp =		\
			(eng)->MR_eng_global_hp;)			\
	} while (0)

#define MR_save_engine_regs(eng)					\
  	do {								\
		MR_IF_NOT_CONSERVATIVE_GC((eng)->MR_eng_hp = MR_hp;)	\
		MR_IF_NOT_CONSERVATIVE_GC((eng)->MR_eng_sol_hp =	\
			MR_sol_hp;)					\
		MR_IF_NOT_CONSERVATIVE_GC((eng)->MR_eng_global_hp =	\
			MR_global_hp;)					\
	} while (0)

/*
** Functions for creating/destroying a MercuryEngine.
*/
extern	MercuryEngine	*MR_create_engine(void);
extern	void		MR_destroy_engine(MercuryEngine *engine);

/*
** Functions for initializing/finalizing a MercuryEngine.
** These are like create/destroy except that they don't allocate/deallocate
** the MercuryEngine structure.
*/
extern	void		MR_init_engine(MercuryEngine *engine);
extern	void		MR_finalize_engine(MercuryEngine *engine);

/*
** Functions that act on the current Mercury engine.
** See the comments in mercury_engine.c for documentation on MR_call_engine().
*/
extern	MR_Word		*MR_call_engine(MR_Code *entry_point,
				MR_bool catch_exceptions);
extern	void		MR_terminate_engine(void);
extern	void		MR_dump_prev_locations(void);

/*---------------------------------------------------------------------------*/

/*
** Builtin labels that point to commonly used code fragments.
*/

MR_declare_entry(MR_do_redo);
MR_declare_entry(MR_do_fail);
MR_declare_entry(MR_do_reset_hp_fail);
MR_declare_entry(MR_do_reset_framevar0_fail);
MR_declare_entry(MR_do_succeed);
MR_declare_entry(MR_do_not_reached);
MR_declare_entry(MR_exception_handler_do_fail);

#endif /* not MERCURY_ENGINE_H */
