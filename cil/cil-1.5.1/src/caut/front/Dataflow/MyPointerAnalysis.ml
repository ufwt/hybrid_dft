open Cil

module E = Errormsg

let caut_pointer_alias_dump_file_name = ref "alias.txt"
let caut_func_call_var_alias = ref "funcallalias.txt"


(** 
	We regard function call arguments (CAUT_DF_CALL) as lvals and funtion formals (CAUT_DF_ENTRY) as rvals when entering a function call.
	On the other hand, we regard CAUT_DF_EXIT as lvals and CAUT_DF_RETURN as rvals when returning from a function call.
	Here, a dua decide a set of possible funcall alias.
	
	Note: If you want to calculate funcall alias, you have to manually tag them by designated interfaces.
		  Now, we do not compute funcall alias.
*)
type funcall_alias = {
	
	mutable funcall_alias_dua_id: int; (* dua index *)
	mutable funcall_alias_file_name: string;
	mutable funcall_alias_func_name: string;
	mutable funcall_alias_func_id: int;
	mutable funcall_alias_lval_vid: int; 
	mutable funcall_alias_lval_vname: string;
	mutable funcall_alias_rval_vid: int;
	mutable funcall_alias_rval_vname: string;
	mutable funcall_alias_stmt_id: int;
	mutable funcall_alias_line: int;
}

(** the global funcall alias list *)
let g_funcall_alias_list = ref([]: funcall_alias list)

let print_funcall_alias_list (mylist: funcall_alias list) = 
	E.log "\n========= Funcall Alias ==========\n";
	E.log "id func fun_id lval lval_id rval rval_id stmt_id line\n";
	List.iter
		begin fun alias ->
			E.log "%d %s %d %s %d %s %d %d #%d\n" 
				alias.funcall_alias_dua_id
				alias.funcall_alias_func_name 
				alias.funcall_alias_func_id
				alias.funcall_alias_lval_vname
				alias.funcall_alias_lval_vid
				alias.funcall_alias_rval_vname
				alias.funcall_alias_rval_vid
				alias.funcall_alias_stmt_id
				alias.funcall_alias_line
		end
	 mylist
;;

let dump_funcall_alias_list (filename: string) (mylist: funcall_alias list) =
	let dump_channel = open_out filename in
    List.iter 
		begin fun alias -> 
			output_string dump_channel (string_of_int alias.funcall_alias_dua_id); 
		  	output_string dump_channel " ";
			output_string dump_channel (string_of_int alias.funcall_alias_func_id); 
		  	output_string dump_channel " ";
			output_string dump_channel (string_of_int alias.funcall_alias_stmt_id); 
		  	output_string dump_channel " ";
			output_string dump_channel (string_of_int alias.funcall_alias_lval_vid); 
			output_string dump_channel " ";
			output_string dump_channel (string_of_int alias.funcall_alias_rval_vid); 
			output_string dump_channel "\n";
			flush dump_channel
		end
	 mylist
;;
	

let construct_funcall_alias (mylist: MyUseDefAssocByHand.myDua list) = 
	let list_len = List.length mylist in
	for i=0 to list_len-1 do
		let dua = List.nth mylist i in
		let cps_cnt = List.length dua.MyUseDefAssocByHand.dua_use_context_points in
		for j=0 to (cps_cnt-2) do
			let the_former_cp = List.nth dua.MyUseDefAssocByHand.dua_use_context_points j in
			let the_latter_cp = List.nth dua.MyUseDefAssocByHand.dua_use_context_points (j+1) in
			(* DF_CAUT_CALL (1) --> DF_CAUT_ENTRY (2) *)
			if the_former_cp.MyUseDefAssocByHand.df_context_point_interp_point_type = 1 && 
				the_latter_cp.MyUseDefAssocByHand.df_context_point_interp_point_type = 2 then begin
				let item = {
					funcall_alias_dua_id = dua.MyUseDefAssocByHand.dua_id;
					funcall_alias_file_name = the_former_cp.MyUseDefAssocByHand.df_context_point_file_name;
					funcall_alias_func_name = the_former_cp.MyUseDefAssocByHand.df_context_point_fun_name;
					funcall_alias_func_id = 
the_former_cp.MyUseDefAssocByHand.df_context_point_fun_id;
					funcall_alias_lval_vid = 
the_former_cp.MyUseDefAssocByHand.df_context_point_var_id;
					funcall_alias_lval_vname = 
the_former_cp.MyUseDefAssocByHand.df_context_point_var_name;
					funcall_alias_rval_vid = 
the_latter_cp.MyUseDefAssocByHand.df_context_point_var_id;
					funcall_alias_rval_vname = 
the_latter_cp.MyUseDefAssocByHand.df_context_point_var_name;
					funcall_alias_stmt_id = 
the_former_cp.MyUseDefAssocByHand.df_context_point_stmt_id;
					funcall_alias_line = 
the_former_cp.MyUseDefAssocByHand.df_context_point_line} 
				in

				g_funcall_alias_list := !g_funcall_alias_list @ [item]
				
			end;
			(* CAUT_DF_EXIT (3) --> CAUT_DF_RETURN (4) *)
			if the_former_cp.MyUseDefAssocByHand.df_context_point_interp_point_type = 3 && 
				the_latter_cp.MyUseDefAssocByHand.df_context_point_interp_point_type = 4 then begin
				let item = {

					funcall_alias_dua_id = dua.MyUseDefAssocByHand.dua_id;
					funcall_alias_file_name = the_former_cp.MyUseDefAssocByHand.df_context_point_file_name;
					funcall_alias_func_name = the_former_cp.MyUseDefAssocByHand.df_context_point_fun_name;
					funcall_alias_func_id = 
the_former_cp.MyUseDefAssocByHand.df_context_point_fun_id;
					funcall_alias_lval_vid = 
the_former_cp.MyUseDefAssocByHand.df_context_point_var_id;
					funcall_alias_lval_vname = 
the_former_cp.MyUseDefAssocByHand.df_context_point_var_name;
					funcall_alias_rval_vid = 
the_latter_cp.MyUseDefAssocByHand.df_context_point_var_id;
					funcall_alias_rval_vname = 
the_latter_cp.MyUseDefAssocByHand.df_context_point_var_name;
					funcall_alias_stmt_id = 
the_former_cp.MyUseDefAssocByHand.df_context_point_stmt_id;
					funcall_alias_line = 
the_former_cp.MyUseDefAssocByHand.df_context_point_line} 
				in

				g_funcall_alias_list := !g_funcall_alias_list @ [item]
			end
			
		done
	done;
	print_funcall_alias_list !g_funcall_alias_list
;;

let find_funcall_alias (file: Cil.file) = 
	construct_funcall_alias !(MyUseDefAssocByHand.g_dua_list);
	let dump_file_name = file.fileName ^ "." ^ !caut_func_call_var_alias in
	dump_funcall_alias_list dump_file_name !g_funcall_alias_list
;;

(** pointer alias entry (i.e., variable alias entry)
	Limitations:
		We only consider the following form:
		(1)	p = &v; 
		(2) p = q;
		p,q are one-level pointers, v is a primitive type variable
*)
type pointer_alias_entry={

	mutable pa_file_name: string;
	mutable pa_func_name: string;
	mutable pa_func_id: int;
	mutable pa_lval_vid: int;
	mutable pa_lval_vname: string; (* left hand variable *)
	mutable pa_rval_vid: int;
	mutable pa_rval_vname: string; (* right hand variable *)
	mutable pa_stmt_id : int;
	mutable pa_line : int;
}

(** the global list to store pointer alias *)
let g_pointer_alias_entry_list= ref ([]:pointer_alias_entry list)

let print_pointer_alias_entry_list (pa_list: pointer_alias_entry list) = 
	E.log "\n===== Pointer Alias =====\n";
	E.log "file func line sid lval_name lval_id rval_name rval_id\n";
	let list_len = List.length pa_list in
	for i=0 to list_len-1 do
		let pa = List.nth pa_list i in
		E.log "%s %s %d %d %d %s %d %s %d\n" pa.pa_file_name pa.pa_func_name pa.pa_func_id pa.pa_line pa.pa_stmt_id pa.pa_lval_vname pa.pa_lval_vid pa.pa_rval_vname pa.pa_rval_vid
	done;
	E.log "\n"
;;

let dump_pointer_aliases (filename: string) (pa_list: pointer_alias_entry list) = 
	let dump_channel = open_out filename in
    List.iter 
		begin fun pa -> 
			output_string dump_channel (string_of_int pa.pa_func_id);
			output_string dump_channel " ";
			output_string dump_channel (string_of_int pa.pa_stmt_id);
			output_string dump_channel " ";
			output_string dump_channel (string_of_int pa.pa_lval_vid);
			output_string dump_channel " ";
			output_string dump_channel (string_of_int pa.pa_rval_vid);
			output_string dump_channel " ";
			output_string dump_channel (string_of_int pa.pa_line);
			output_string dump_channel " ";
			output_string dump_channel "\n";
			
			flush dump_channel
		end
	 pa_list
;;

class pointerAliasVisitor (file: Cil.file) (func: Cil.fundec) = object(self)
	inherit nopCilVisitor

	(** is $lv a simple VAR with NO_OFFSET *)
	method private isSimpleLval (lv: Cil.lval) : bool = 
		let lh, off = lv in
		match off with
		| Field _ -> false
		| Index _ -> false
		| NoOffset -> 
			(match lh with 
			| Var _ -> true
			| Mem _ -> false)

	(** is $e a simple VAR with NO_OFFSET *)
	method private isExprOfSimpleLval (e: Cil.exp): bool =
		match e with
		| Lval lv ->
			self#isSimpleLval lv
		| _ -> false

	(** is $lv of primitive type *)
	method private isPrimitiveType (lv: Cil.lval): bool =
		match (Cil.typeOfLval lv) with
		| TInt _ | TFloat _ -> true
		| _ -> false
	
	(** is p = &v form ? *)
	method private is_p_equal_to_ref_v (lv: Cil.lval) (e: Cil.exp): bool = 
		if (self#isSimpleLval lv) = true then begin
			match (Cil.typeOfLval lv) with (* check p is a one-level pointer variable *)
			| TPtr _ -> 
				(match e with
				| AddrOf e_lv -> (* check e is "&v" form, v is of primitive type *)
					if (self#isSimpleLval e_lv) = true && (self#isPrimitiveType e_lv) = true then begin
						true
					end else begin
						false
					end
				| _ -> false)
 			| _ -> false
		end else begin
			false
		end
		
	(** is p = q form ? *)
	method private is_p_equal_to_q (lv: Cil.lval) (e: Cil.exp): bool = 
		if (self#isSimpleLval lv) = true then begin
			match (Cil.typeOfLval lv) with (* check p is a one-level pointer variable *)
			| TPtr _ -> 
				if (self#isExprOfSimpleLval e) = true then begin
					match e with
					| Lval e_lv ->
						(match (Cil.typeOfLval e_lv) with (* check q is a one-level pointer variable *)
						| TPtr _ -> true
						| _ -> false)
					| _ -> false
				end else begin
					false
				end
			| _ -> false
		end else begin
			false
		end

	(** get var name and id from lval *)
	method private get_vname_and_vid_from_lval (lv: Cil.lval) = 
		let lh, off = lv in
		match lh with
		| Var v -> (v.vname, v.vid)
		| _ -> ("",0) (* impossible reach here *)

	(** get var name and id from e (&v) *)
	method private get_vname_and_vid_from_e_ref_var (e: Cil.exp) = 
		match e with
		| AddrOf e_lv -> (* check e is "&v" form, v is of primitive type *)
			self#get_vname_and_vid_from_lval e_lv
		| _ -> ("",0)

	method private get_vname_and_vid_from_e_lv (e: Cil.exp) =
		match e with
		| Lval lv ->
			self#get_vname_and_vid_from_lval lv
		| _ -> ("",0)

	method vstmt st = 
		match st.skind with
		| Instr (insl) ->
			List.iter
				begin fun ins ->
					(match ins with
					| Set (lv, e, loc) ->
						if (self#is_p_equal_to_ref_v lv e) = true then begin (* is p = &v form ? *)
							let lv_vname, lv_vid = self#get_vname_and_vid_from_lval lv in
							let rv_vname, rv_vid = self#get_vname_and_vid_from_e_ref_var e in
							let item = { pa_file_name = file.fileName;
										 pa_func_name = func.svar.vname;
										 pa_func_id = func.svar.vid;
										 pa_stmt_id = st.sid;
										 pa_line = loc.line;
										 pa_lval_vname = lv_vname;
									     pa_lval_vid = lv_vid;
										 pa_rval_vname = rv_vname;
									     pa_rval_vid = rv_vid }
							in
							g_pointer_alias_entry_list := !g_pointer_alias_entry_list @ [item]
						end else if (self#is_p_equal_to_q lv e) = true then begin (* is p = q form ? *)
							let lv_vname, lv_vid = self#get_vname_and_vid_from_lval lv in
							let rv_vname, rv_vid = self#get_vname_and_vid_from_e_lv e in
							let item = { pa_file_name = file.fileName;
										 pa_func_name = func.svar.vname;
										 pa_func_id = func.svar.vid;
										 pa_stmt_id = st.sid;
										 pa_line = loc.line;
										 pa_lval_vname = lv_vname;
									     pa_lval_vid = lv_vid;
										 pa_rval_vname = rv_vname;
									     pa_rval_vid = rv_vid }
							in
							g_pointer_alias_entry_list := !g_pointer_alias_entry_list @ [item]
						end else begin
							()
						end
					| _ -> ()
					)
				end
			 insl;
			 DoChildren
		| _ -> DoChildren

end;;

(** find pointer alias assignment instructions *)
let find_pointer_alias (file: Cil.file) =
	List.iter
		begin fun g ->
			match g with
			| GFun (func, loc) ->
				if func.svar.vname = !MyDfSetting.caut_def_use_fun_name || 
					func.svar.vname = !MyDfSetting.caut_df_context_fun_name || 
					func.svar.vname = "testme" then (* skip self-created functions *)
					() 
				else begin
					ignore (Cil.visitCilFunction (new pointerAliasVisitor file func) func)
				end
			| _ -> ()
		end
	  file.globals;
	print_pointer_alias_entry_list !g_pointer_alias_entry_list
;;

(** transform pointer aliases into their counterparts in the simplified code.
	because after code simplification their stmt ids may change
	We need to update it.
*)
let transform_pointer_alias_into_simplified (file: Cil.file) (to_transform: int)= 

	let find_pointer_analysis_stmt func line = (* find the stmt where the pointer alias locates by line in func *)
		List.find
			begin fun st ->
				match st.skind with
				| Instr (instrl) ->
					List.exists (* does it exists ? *)
						begin fun ins ->
							match ins with
							| Set (_, _, loc)  -> (* only consider the SET instruction *)
								if loc.line = line then
									true
								else
									false
							| _ -> false
						end
					  instrl
				| _ -> false
			end
		 func.sallstmts
	in
	if to_transform = 1 then begin
		List.iter
			begin fun pa ->
				let func = FindCil.fundec_by_name file pa.pa_func_name in
				(* find pa's stmt id in the simplified code version *)
				let pa_stmt = find_pointer_analysis_stmt func pa.pa_line in
				pa.pa_stmt_id <- pa_stmt.sid
			end
		  !g_pointer_alias_entry_list
	end;
	print_pointer_alias_entry_list !g_pointer_alias_entry_list;
	E.log "[transform_pointer_alias_into_simplified] \n";
	let dump_file_name = file.fileName ^ "." ^ !caut_pointer_alias_dump_file_name in
	dump_pointer_aliases dump_file_name !g_pointer_alias_entry_list
;;


let feature : featureDescr = 
  { fd_name = "ptralias";              
    fd_enabled = ref false;
    fd_description = "find pointer alias in a simple manner";
    fd_extraopt = [	
		];
    fd_doit = 
    (function (f: file) -> 
      find_pointer_alias f);
    fd_post_check = true
  }
