(**
Modified on Dec 20, 2008, add the helper#doConcreteValueAnalysis, to insert the function store_concrete_value_int/float. Stanley
*)

open Cil
open Int64
open Pretty
open CautSqlite3Interface
module E = Errormsg

(* command line arguments *)
let cf_file_name = ref ""
let cf_unit_name = ref ""
let cf_instrument_function_call = ref false
let cf_generate_type_system = ref false
let cf_unit_testing = ref false (* unit testing level *)
let cf_program_br_testing = ref false (* branch testing at program level *)
let cf_program_df_testing = ref false (* on demand data flow testing at program level *)
let cf_cegar_instrumentation = ref false
let cf_cbmc_instrumentation_one = ref false
let cf_cbmc_instrumentation_all = ref false
let cf_model_checker = ref "" (* the name of the selected model checker *)
let cf_var_defs_data_file = ref "" (* the file name of var defs for offline instrumentation *)
let cf_duas_data_file = ref "" (* the file name of duas for offline instrumentation *)
let cf_offline_instrumentation = ref false
let cf_klee_instrumentation = ref false 
let cf_nondet_to_klee_make_symbolic = ref false

let caut_runtime_interfaces = ref [
	"load_to_heap_int";
	"load_to_heap_float";
	"apply_op"; 
	"store_to_var_table";
	"store_concrete_value_int";
	"store_concrete_value_float";
	"argu_push";
	"para_num_stack_push";
	"para_pop";
	"branch";
	"store_input_var";
	"print_testcase";
	"df_stmt_monitor";
	"set_main_function_id";
	"cover_condition_fun";
	]

let is_caut_runtime_interfaces (func_name: string) : bool = 
	List.exists
		begin fun interface ->
			if interface = func_name then
				true
			else
				false
		end
	  !caut_runtime_interfaces;;

let effect_list = ref ([] : bool list list)

let rt_branch_id_list = ref([]:int list)

(**Module Slicing of Side Effect.*)

let if_compute = ref true

(** Type ppt for point-to realtionship.*)
type  ptt = Pt of Cil.lval * Cil.lval * int

(** Get the variable name of the specified lval.*)
let rec get_lval_varname (lv : Cil.lval) : string = 
	match lv with
		(Var(vv), _) -> vv.vname
		| (Mem(e), _) -> 
			(match e with 
				Lval(lvv) -> get_lval_varname lvv
				| AddrOf(lvv) -> get_lval_varname lvv
				| _ -> "0"
			)

(** Print lval, if it is a deference of pointer, print * before its name.*)
let rec print_lval (lv : Cil.lval) : unit = 
	match lv with
		(Var(v), _) -> print_string v.vname;
		| (Mem(e), _) -> 
			(match e with
				Lval(lvv) -> 
					print_string "*";
					print_lval lvv;
				| _ -> ()
			)

(** Print the lvals in var list *)
let print_lval_list (lst : Cil.lval list) : unit = 
	print_string "#";
	List.iter (fun x -> print_lval x; print_string " ";) lst;
	print_string "\n"

(** Get the level of the specified pointer type.*)
let rec get_ptrtype_level (ttype : Cil.typ) : int = 
	match ttype with
		TPtr(t, _) -> 1 + (get_ptrtype_level t)
		| _ -> 0

(** Get the level of ptr lval.*)
let rec get_ptr_level (lv : Cil.lval) : int = 
	match lv with 
		(Var(v), _) -> get_ptrtype_level v.vtype
		| (Mem(e), _) -> (match e with
					Lval(lvv) -> get_ptr_level lvv
					| _ -> 1
				)

(** Pick out all the lvals from the specified Cil.exp *)
let rec get_lvals_from_exp (exp : Cil.exp) : (lval list) = 
	match exp with
		Lval(lv) -> [lv]
		| SizeOfE(e) -> get_lvals_from_exp e
		| UnOp(_, e, _) -> get_lvals_from_exp e
		| BinOp(_, e1, e2, _) -> (get_lvals_from_exp e1) @ (get_lvals_from_exp  e2)
		| CastE(_, e) -> get_lvals_from_exp e
		| AddrOf(lv) -> [lv] (*@ (find_pointed_relationship lv)*)
		| StartOf(lv) -> [lv] (*@ (find_pointed_relationship lv)*)
		| _ -> []

(** Compare whether the two variables are the same one.*)
let comp_lval (lv1 : Cil.lval) (lv2 : Cil.lval) : bool = 
	match lv1 with
		(Var(v1), _) -> 
			(match lv2 with
				(Var(v2), _) -> v1.vname = v2.vname
				| _ -> false
			)
		| (Mem(e1), _) ->	
			(match lv2 with
				(Mem(e2), _) -> 
					if (get_ptr_level lv1) = (get_ptr_level lv2) then
						(get_lval_varname lv1) = (get_lval_varname lv2)
					else
						false
				| _ -> false
			)

(** add a lval into the list if it does not exist in the list.*)
let add_to_lval_list (lv : Cil.lval) (lst : Cil.lval list) : (Cil.lval list) = 
	if (List.exists (fun x -> comp_lval x lv) lst) then
		lst
	else 
		lst @ [lv]

(** concact two Cil.lval lists. *)
let concact_lval_list (lst1 : Cil.lval list) (lst2 : Cil.lval list) : (Cil.lval list) =
	let tmp_lst = ref lst1 in
	List.iter (fun x ->
		tmp_lst := add_to_lval_list x lst1
	)lst2;
	!tmp_lst

(** The class of pointerStatusAnalysis *)
class pointerStatusAnalysis = object(self)
	(** the point-to set for storing the point-to relationships.*)
	val mutable point_to_set = ([] : ptt list)

	(** print*)
	method print_point_to =
		List.iter(fun x ->
			match x with Pt(f, t, l) ->
				print_string "(";
				print_lval f;
				print_string ",";
				print_lval t;
				print_string ")\n";
		) point_to_set;

	(**find out the lvals which are pointed by the lv of Cil.lval type. *)
	method find_pointto_relationship (lv : Cil.lval) : (lval list) = 
		let rst = ref ([] : Cil.lval list) in
		List.iter (fun x ->
			match x with 
				(Pt(f, t, _)) ->
					(match comp_lval lv f with
						true -> rst := !rst @ [t]
						| _ -> ()
					)
		) point_to_set;
		!rst

	(**find out all the lvals which are pointed by lv directly or indirectly, including multi-level. *)
	method find_all_pointto_relationships (lv : Cil.lval) : (lval list) = 
		let rst1 = self#find_pointto_relationship lv in
		if (List.length rst1 <> 0) then
		begin
			let rst2 = ref ([] : Cil.lval list) in
			List.iter (fun x ->
				rst2 := !rst2 @ (self#find_all_pointto_relationships x)
			) rst1;
			rst1 @ !rst2
		end
		else
		begin
			rst1
		end

	(**remove the point-to relationships of lv. *)
	method remove_pointto_relationship_at_level (lv : Cil.lval) (lvl : int) : unit = 
		let tmp = ref ([] : ptt list) in
		List.iter (fun x ->
			match x with (Pt(f, _, l)) -> 
				(match (comp_lval f lv) && (l = lvl) with
					false -> tmp := !tmp @ [x]
					| _ -> ()
				)
		) point_to_set;
		point_to_set <- !tmp
	
	(**add the relationship (flv, tlv) into the point-to set.*)
	method add_pointto_relationship (flv : Cil.lval) (tlv : Cil.lval) (lvl : int): unit = 
		(* *)
		let add_pt_to_list (pt_tpl : ptt) (lst : ptt list) : (ptt list) = 
			if List.exists (fun x -> match x with (Pt(fx, tx, _)) ->
				match pt_tpl with (Pt(f, t, _)) -> ((comp_lval f fx) && (comp_lval t tx))
			) lst then lst
			else lst @ [pt_tpl]
		in
		(** Delete the old point-to relationship of flv if they are in the same level.*)
		self#remove_pointto_relationship_at_level flv lvl;
		(** Insert the new relationship formed by (flv, rlv).*)
		let rst = self#find_pointto_relationship tlv in
		match (List.length rst) with
			0 -> (* *)
				point_to_set <- add_pt_to_list (Pt(flv, tlv, lvl)) (point_to_set)
			| _ -> (* *)
				List.iter (fun x ->
					point_to_set <- add_pt_to_list (Pt(flv, x, lvl)) (point_to_set)
				) rst

	(* *)
	method find_alias (lst : Cil.lval list) : (Cil.lval list) = 
		let tmp_lst = ref lst in
		(** Add *p when meeting variable that are pointed by p.*)
		List.iter (fun lv -> 
			List.iter(fun pt ->
				match pt with
					Pt(f, t, _) -> 
						if comp_lval t lv then
							tmp_lst := add_to_lval_list (Mem(Lval(f)), NoOffset) (!tmp_lst)
			) point_to_set
		) !tmp_lst;
		(** Add lvals, which is pointed by p, when meeting *p.*)
		List.iter (fun lv ->
			match lv with 
				(Mem(e), _) -> 
					(match e with 
						Lval(elv) -> List.iter (fun x -> match x with
							Pt(f, t, _) -> if (comp_lval f elv) then 
								tmp_lst := add_to_lval_list t !tmp_lst;
							) point_to_set;
							| _ -> ()
					)
				| _ -> ()
		)!tmp_lst;
		!tmp_lst
end

(** the test-driven function name*)
let drivenUnit = ref "testme"

(*def for variables taken by _cf__getInput*)
(*let var_list = ref []*)
type struct_has_ptr_init = CompInit of bool * compinfo

let unknownLoc = {line = -1; file = ""; byte = 0}

(* *********************************************************************** *)
(* *)
type array_type_init = ArrType of bool * typ
(* *)
type struct_type_init = StructType of bool * typ
(* *)
type ptr_type_init = PtrType of bool * typ
(* *********************************************************************** *)

type tree_value = TTrue | TFalse | TRoot | TNone

(* *)
class tcgCondVisitor = object(self)
inherit nopCilVisitor
  	method vstmt st = match st.skind with
			If (e,b1,b2,loc) ->
				let else_stmt = mkEmptyStmt () in
				b2.bstmts <- [else_stmt] @ b2.bstmts;
				DoChildren
		| _ ->
				DoChildren
end

class analysisHelper = object(self)

	val mutable struct_list = ([] : struct_has_ptr_init list)
	(*val mutable array_list = ([] : typ list)*)
	val mutable new_struct_list = ([] : struct_has_ptr_init list)
	val mutable completed_struct_list = ([] : struct_has_ptr_init list)
	val mutable var_list = ([] : varinfo option list)
	val mutable init_count = 0

	(* **************************Added by Stanley*********************************** *)		
	val mutable struct_type_list = ([] : struct_type_init list)
	val mutable array_type_list  = ([] : array_type_init  list)
	val mutable ptr_type_list    = ([] : ptr_type_init    list)
	(* **************************Added by Stanley*********************************** *)

	method set_var_list l = var_list <- l
	method get_var_list  = var_list
	method incrInitCount = let c = init_count in init_count <- c + 1;c
	method resetInitCount = init_count <- 0
	(*method get_struct_list = struct_list*)
	

	(*Get the list of array_type_init *)
	method get_array_list = array_type_list
	
	(*Get the list of ptr_type_init *)
	method get_ptr_list = ptr_type_list

	(*Set the list of array_type_init *)
	method set_array_list lst = array_type_list <- lst
	
	(*Set the list of ptr_type_init *)
	method set_ptr_list lst = ptr_type_list <- lst

	(* Should be modified later... *)
	(*method add_struct_list (shpi:struct_has_ptr_init) = 
		let item = try List.find (fun item -> match item with CompInit(_,c) -> 
							c.cname = (match shpi with CompInit(_,t) -> t.cname)) struct_list
	     		   with Not_found -> struct_list <- shpi::struct_list;shpi in
		struct_list <- List.map (fun t -> match item with CompInit(b,c) ->
						    (match t with CompInit(bt,ct) -> 
							(match c.cname = ct.cname with 
								true -> (match b || bt with 
									   	    true -> CompInit(true,c) 
									 	  | false -> t
									) 
								| false -> t
							)
						    )
					) struct_list*)

 
	method add_struct_list (ct : typ) =
		let ct_name = (match ct with TComp(s, _) -> s.cname		(* Get the type name string of the ct (struct type) *)
					| _ -> "INVALID TYPE") in
		try ignore (List.find (fun elmt -> 				(* anonymous funtion: Check whether the type is in the list*)
					let item_name = (match elmt with 
								StructType(_, t) -> (match t with 
												TComp(c, _) -> c.cname
												| _ -> ""))
					in
					ct_name = item_name) struct_type_list)
			with Not_found -> struct_type_list <- StructType(false, ct) :: struct_type_list; ()
		(* let ct_com = match ct with StructType(_, t) -> t in
			try ignore(List.find (fun item -> let item_typ = match item with StructType(_, s) -> s in
							let item_name = match item_typ with TComp(name, _) -> name
											 | _ -> "" in
						ct_com.cname = item_name.cname) struct_type_list)
		with Not_found -> struct_type_list <- StructType(false, ct) :: struct_type_list; ()*)
	
	(* Get the struct list *)
	method get_struct_list = struct_type_list
	
	(* set the content of struct list *)
	method set_struct_list lst = struct_type_list <- lst
	
	(* ***************************Added by Stanley******************************************************* *)
	(* *)
	method add_array_list (arrType : typ) = 
		let rec f t = match t with				(* *)
				TArray(at, _, _) -> f at
				| _ -> t
			in let rt = f arrType in			(* *)
					try ignore (List.find (fun item -> 
						match item with 
							ArrType(_, t) -> (self#type_compare t rt)) array_type_list)
					with Not_found -> array_type_list <- ArrType(false, rt) :: array_type_list; ()
	
	(* ***************************Added by Stanley******************************************************* *)					
	method add_ptr_list (ptrTyp : typ) = 
			ignore(try List.find (fun item ->		(* Add the type passed in into the list if it is not contained yet. *)
					match item with			(* This anonymous funciton is used for checking whether it is contained already. *)
						PtrType(_,t) ->	(self#type_compare t ptrTyp)) ptr_type_list
			with Not_found -> ptr_type_list <- PtrType(false, ptrTyp) :: ptr_type_list; PtrType(false, ptrTyp)
			);
			match ptrTyp with				(* Add the child level pointer types of current one. *)
				TPtr(t, _) -> 
					(match t with 			(* The element t is of type pointer. *)
						TPtr(_, _) -> ignore(self#add_ptr_list t); true
					| _ -> false)
				| _ -> false
	(* ***************************Added by Stanley******************************************************* *)
	

	method add_new_struct_list (shpi:struct_has_ptr_init) = 
		let item = try List.find (fun item -> match item with CompInit(_,c) -> 
							c.cname = (match shpi with CompInit(_,t) -> t.cname)) struct_list
	     		   with Not_found -> new_struct_list <- shpi::new_struct_list;shpi in
		new_struct_list <- List.map (fun t -> match item with CompInit(b,c) ->
						    (match t with CompInit(bt,ct) -> 
							(match c.cname = ct.cname with 
								true -> (match b || bt with 
									   	    true -> CompInit(true,c) 
									 	  | false -> t
									) 
								| false -> t
							)
						    )
					) new_struct_list
(* ******************************************************************************************************************************* *)
	method getListsStatus  =
		(*List.iter (fun item -> match item
				with PtrType(b, _) -> match b with
							true -> print_string "true\t";
							| false -> print_string "false\t";
			) self#get_ptr_list*)
		let whetherPtrListFinished  = 
			try ignore(List.find (fun item -> match item
				with PtrType(b, _) -> b = false) self#get_ptr_list); false
			with Not_found -> true
		in
		let whetherArrayListFinished = 
			try ignore(List.find (fun item -> match item
					with ArrType(b, _) -> b = false) self#get_array_list); false
			with Not_found -> true
		in
		let whetherStructListFinished = 
			try ignore(List.find (fun item -> match item
					with StructType(b, _) -> b = false) self#get_struct_list); false;
			with Not_found -> true
		in
		let result = whetherPtrListFinished && whetherArrayListFinished && whetherStructListFinished
		in
		result 

	(* unit->bool removes all things exist in completed list, compares and adds all non-existed items from new_struct_list and indicates if there are still some structs in struct_list *)
	(* true->still some structs exists *)
	(* false->clear list *) 
	method update_struct_list = 
		match List.length new_struct_list with
		 0 -> false
		| _ -> struct_list <- new_struct_list;new_struct_list <- [];true

	(* add to completed list *)
	method complete_struct_init (shpi:struct_has_ptr_init) = 
		completed_struct_list <- shpi::completed_struct_list


(*	method getPreviousFieldSizeString f = 
		let rec get_next (l:fieldinfo list) (fi:fieldinfo) = 
			let item = (List.hd l) in 
			match item.fname = fi.fname with 
			true -> List.hd (List.tl l) 
			| _ -> get_next (List.tl l) fi
		in
		let comp = f.fcomp in
		let flist = List.rev comp.cfields in
		let fn = try let fi = get_next flist f in Some fi with Failure x -> None in
		let rec get_type_size_string fn = 
		(match fn with
		 None -> ""
		| Some(fi) -> (let typStr = (match fi.ftype with
					TVoid(_) -> "unsigned long" 
					| TInt(IChar,_) -> "char" | TInt(ISChar,_) -> "signed char" | TInt(IUChar,_) -> "unsigned char" 
					| TInt(IInt,_) -> "int"   | TInt(IUInt,_) -> "unsigned int" | TInt(IShort,_) -> "short" 
					| TInt(IUShort,_) -> "unsigned short" | TInt(ILong,_) -> "long"
					| TInt(IULong,_) -> "unsigned long" | TInt(ILongLong,_) -> "long long" | TInt(IULongLong,_) -> "unsigned long long" 
					| TFloat(FFloat,_) -> "float" | TFloat(FDouble,_) -> "double" | TFloat(FLongDouble,_) -> "long double"
					| TArray (_,_,_) -> "NOT SUPPORTED" | TFun(_,_,_,_) -> "unsigned long" 
					| TNamed(t,_) -> (Printf.sprintf "struct %s" t.tname)
					| TComp(c,_) -> (Printf.sprintf "struct %s" c.cname) | TEnum(e,_) -> e.ename | _ -> "unsigned long") 		
			     in Printf.sprintf "+sizeof(%s)" typStr))
		in get_type_size_string fn
*)
(*	method getTypString t = 
			match t with
					TVoid(_) -> "void" 
					| TInt(IChar,_) -> "char" | TInt(ISChar,_) -> "signed char" | TInt(IUChar,_) -> "unsigned char" 
					| TInt(IInt,_) -> "int"   | TInt(IUInt,_) -> "unsigned int" | TInt(IShort,_) -> "short" 
					| TInt(IUShort,_) -> "unsigned short" | TInt(ILong,_) -> "long"
					| TInt(IULong,_) -> "unsigned long" | TInt(ILongLong,_) -> "long long" | TInt(IULongLong,_) -> "unsigned long long" 
					| TFloat(FFloat,_) -> "float" | TFloat(FDouble,_) -> "double" | TFloat(FLongDouble,_) -> "long double"
					| TArray (tt,_,_) -> self#getTypString tt | TFun(_,_,_,_) -> "unsigned long" 
					| TNamed(t,_) -> t.tname
					| TComp(c,_) -> (Printf.sprintf "struct %s" c.cname) | TEnum(e,_) -> (Printf.sprintf "enum %s" e.ename) | _ -> "unsigned long"
*)
	method getSizeOfTypString t = 
			match t with
					TVoid(_) -> "4096" 
					| TInt(IChar,_) -> "sizeof(char)" | TInt(ISChar,_) -> "sizeof(signed char)" | TInt(IUChar,_) -> "sizeof(unsigned char)" 
					| TInt(IInt,_) -> "sizeof(int)"   | TInt(IUInt,_) -> "sizeof(unsigned int)" | TInt(IShort,_) -> "sizeof(short)" 
					| TInt(IUShort,_) -> "sizeof(unsigned short)" | TInt(ILong,_) -> "sizeof(long)"
					| TInt(IULong,_) -> "sizeof(unsigned long)" | TInt(ILongLong,_) -> "sizeof(long long)" | TInt(IULongLong,_) -> "sizeof(unsigned long long)" 
					| TFloat(FFloat,_) -> "sizeof(float)" | TFloat(FDouble,_) -> "sizeof(double)" | TFloat(FLongDouble,_) -> "sizeof(long double)"
					| TArray (tt,_,_) -> self#getSizeOfTypString tt | TFun(_,_,_,_) -> "sizeof(unsigned long)" 
					| TNamed(t,_) -> Printf.sprintf "sizeof(%s)" t.tname
					| TComp(c,_) -> (Printf.sprintf "sizeof(struct %s)" c.cname) | TEnum(e,_) -> (Printf.sprintf "sizeof(enum %s)" e.ename) | _ -> "sizeof(unsigned long)"


	method getTypNameString t = 
			match t with
					TVoid(_) -> "void" 
					| TInt(IChar,_) -> "char" | TInt(ISChar,_) -> "signed_char" | TInt(IUChar,_) -> "unsigned_char" 
					| TInt(IInt,_) -> "int"   | TInt(IUInt,_) -> "unsigned_int" | TInt(IShort,_) -> "short" 
					| TInt(IUShort,_) -> "unsigned_short" | TInt(ILong,_) -> "long"
					| TInt(IULong,_) -> "unsigned_long" | TInt(ILongLong,_) -> "long_long" | TInt(IULongLong,_) -> "unsigned_long_long" 
					| TFloat(FFloat,_) -> "float" | TFloat(FDouble,_) -> "double" | TFloat(FLongDouble,_) -> "long_double"
					| TArray (tt,_,_) -> self#getTypNameString tt | TFun(_,_,_,_) -> "unsigned_long" 
					| TPtr(tt, _) -> let (ptr_type, ptr_level) = self#getPtrDimension t in
							 let ptr_name = self#getTypNameString ptr_type in
							Printf.sprintf "_%s_of_level_%d" ptr_name ptr_level
					| TNamed(t,_) -> t.tname
					| TComp(c,_) -> c.cname | TEnum(e,_) -> e.ename | _ -> "unsigned_long"


(* "%sget_test_case_%s(%s,%s);%s" *)
(* "%sget_test_case_ptr_%s(%s,%s);%s" *)
(*	method getFieldInitFunc t field = self#getStructFieldInitFunc t field *)
		
(* Wang Zheng: this function should be rewritten *)
(*	method getStructFieldInitFunc t f = 
		(*let offset = self#getPreviousFieldSizeString f in*)
		match t with
		  TInt(IInt,_) -> Printf.sprintf "\tget_test_case_int((unsigned long)&(((struct %s  * ) addr)->%s));\r\n" f.fcomp.cname f.fname  (* Int Type *)
		| TInt(IUInt,_) -> Printf.sprintf "\tget_test_case_int((unsigned long)&(((struct %s  * ) addr)->%s));\r\n" f.fcomp.cname f.fname (* unsigned int type *)
		| TInt(ILong,_) -> Printf.sprintf "\tget_test_case_long((unsigned long)&(((struct %s  * ) addr)->%s));\r\n" f.fcomp.cname f.fname (* long type *)
		| TInt(IULong,_) -> Printf.sprintf "\tget_test_case_long((unsigned long)&(((struct %s  * ) addr)->%s));\r\n" f.fcomp.cname f.fname (* ulong type *)
		| TInt(IChar,_) -> Printf.sprintf "\tget_test_case_char((unsigned long)&(((struct %s  * ) addr)->%s));\r\n" f.fcomp.cname f.fname
		| TInt(ISChar,_) -> Printf.sprintf "\tget_test_case_char((unsigned long)&(((struct %s  * ) addr)->%s));\r\n" f.fcomp.cname f.fname
		| TInt(IUChar,_) -> Printf.sprintf "\tget_test_case_char((unsigned long)&(((struct %s  * ) addr)->%s));\r\n" f.fcomp.cname f.fname
		| TFloat(_, _) -> Printf.sprintf "\tget_test_case_double((unsigned long)&(((struct %s  * ) addr)->%s));\r\n" f.fcomp.cname f.fname (* double type *)
		| TPtr(t,_) -> self#getStructFieldInitPtrFunc t f (* pointer type *)
		| TComp(c,_) -> let v = CompInit(false,c) in self#add_new_struct_list v;Printf.sprintf "\tget_test_case_%s((unsigned long)&(((struct %s  * ) addr)->%s));\r\n" c.cname f.fcomp.cname f.fname  (* need impl *)
		| TNamed (et,_) -> self#getStructFieldInitFunc et.ttype f
		| _ ->  Printf.sprintf "\tget_test_case_int((unsigned long)&(((struct %s  * ) addr)->%s));\r\n" f.fcomp.cname f.fname (* need impl *)
*)
(*
	method getStructFieldInitPtrFunc t f = 
		(*let offset = self#getPreviousFieldSizeString f in*)
		match t with
		  TInt(IInt,_) -> Printf.sprintf "\tget_test_case_ptr_int((unsigned long)&(((struct %s  * ) addr)->%s));\r\n" f.fcomp.cname f.fname  (* Int Type *)
		| TInt(IUInt,_) -> Printf.sprintf "\tget_test_case_ptr_int((unsigned long)&(((struct %s  * ) addr)->%s));\r\n" f.fcomp.cname f.fname  (* Int Type *) (* unsigned int type *)
		| TInt(ILong,_) -> Printf.sprintf "\tget_test_case_ptr_long((unsigned long)&(((struct %s  * ) addr)->%s));\r\n" f.fcomp.cname f.fname  (* Int Type *) (* long type *)
		| TInt(IULong,_) -> Printf.sprintf "\tget_test_case_ptr_long((unsigned long)&(((struct %s  * ) addr)->%s));\r\n" f.fcomp.cname f.fname  (* Int Type *) (* ulong type *)
		| TInt(IChar,_) -> Printf.sprintf "\tget_test_case_ptr_int((unsigned long)&(((struct %s  * ) addr)->%s));\r\n" f.fcomp.cname f.fname  (* Int Type *) (* char type *)
		| TFloat(_, _) -> Printf.sprintf "\tget_test_case_ptr_double((unsigned long)&(((struct %s  * ) addr)->%s));\r\n" f.fcomp.cname f.fname  (* Int Type *) (* double type *)
		| TPtr(t,_) -> self#getStructFieldInitPtrFunc t f (*"\t//NOT SUPPORTED TYPE\r\n"*) (* pointer type *)
		| TComp(c,_) -> let v = CompInit(true,c) in self#add_new_struct_list v;Printf.sprintf "\tget_test_case_ptr_%s((unsigned long)&(((struct %s  * ) addr)->%s));\r\n" c.cname f.fcomp.cname f.fname (* need impl *)
		| TNamed (et,_) -> self#getStructFieldInitPtrFunc et.ttype f
		| _ -> "\t//NOT SUPPORTED TYPE\r\n" (* need impl *)

*)
	(* **************************************************************************************************** *)
	method getInitFunc t = 
		match t with
			  TInt(IInt,_) -> "get_test_case_int((unsigned long)addr);" (* Int Type *)
		| TInt(IUInt,_) -> "get_test_case_int((unsigned long)addr);"(* unsigned int type *)
		| TInt(ILong,_) -> "get_test_case_long((unsigned long)addr);" (* long type *)
		| TInt(IULong,_) -> "get_test_case_long((unsigned long)addr);" (* ulong type *)
		| TInt(IChar,_) -> "get_test_case_char((unsigned long)addr);"
		| TInt(ISChar,_) -> "get_test_case_char((unsigned long)addr);"
		| TInt(IUChar,_) -> "get_test_case_char((unsigned long)addr);"
		| TInt(IShort,_) -> "get_test_case_short((unsigned long)addr);"
		| TInt(IUShort,_) -> "get_test_case_short((unsigned long)addr);"
		| TFloat(_, _) -> "get_test_case_double((unsigned long)addr);" (* double type *)
		| TPtr(tp,_) -> ignore(self#add_ptr_list t);
			 	Printf.sprintf "get_test_case_ptr%s((unsigned long)addr);" (self#getTypNameString t) (* pointer type *)
		| TComp(c,_) ->	ignore(self#add_struct_list t);	(* *)
				Printf.sprintf "get_test_case_struct_%s((unsigned long)addr);" (self#getTypNameString t)
				(* let v = CompInit(true,c) in self#add_struct_list v;Printf.sprintf "get_test_case_ptr_%s(addr);" c.cname ;*)(* need impl *)
		| TArray(tt, Some(e), _) ->  (* *)
					ignore(self#add_array_list tt);
					Printf.sprintf "get_test_case_array_%s(addr, %d);" (self#getTypNameString t) (self#getArrayDimension t)
		| TNamed (et,_) -> self#getInitFunc et.ttype
		| TVoid (_) -> "get_test_case_void((unsigned long) addr);"
		| _ -> "get_test_case_int((unsigned long)addr);" (* need impl *)
		
	method getRecordFunc t = 
		match t with
		TArray(tt,Some(e),_) -> Printf.sprintf "test_case_record_add(addr, %d, %d);" (self#getTypValue tt) (self#getArrayDimension t)
		| _ -> Printf.sprintf "test_case_record_add(addr, %d, 0);" (self#getTypValue t)

	(*method getInitPtrFunc t = 
		match t with
		  TInt(IInt,_) -> "\t\tget_test_case_ptr_int((void *)addr);\r\n\t\tbreak;\r\n" (* Int Type *)
		| TInt(IUInt,_) -> "\t\tget_test_case_ptr_int((void *)addr);\r\n\t\tbreak;\r\n" (* unsigned int type *)
		| TInt(ILong,_) -> "\t\tget_test_case_ptr_long((void *)addr);\r\n\t\tbreak;\r\n" (* long type *)
		| TInt(IULong,_) -> "\t\tget_test_case_ptr_long((void *)addr);\r\n\t\tbreak;\r\n" (* ulong type *)
		| TFloat(_, _) -> "\t\tget_test_case_ptr_double((void *)addr);\r\n\t\tbreak;\r\n" (* double type *)
		| TPtr(t,_) -> self#getInitPtrFunc t(*"\t\t//NOT SUPPORTED TYPE\r\n\t\tbreak;\r\n"*) (* pointer type *)
		| TComp(c,_) -> let v = CompInit(true,c) in self#add_struct_list v;Printf.sprintf "\t\tget_test_case_ptr_%s(addr);\r\n\t\ttest_case_record_add(addr, 14, 0);\r\n\t\tbreak;\r\n" c.cname (* need impl *)
		| TNamed (et,_) -> self#getInitPtrFunc et.ttype
		| _ -> "\t\t//NOT SUPPORTED TYPE\r\n\t\tbreak;\r\n" (* need impl *)*)

(* ********************************************************************************************************************** *)
	(*method getInitPtrFunc t =
		let (s, n) = self#getPtrDimension t
		in
		match n with
			0 -> Printf.sprintf "\t\tget_test_case_%s((void *)addr);\r\n\t\ttest_case_record_add(addr, 14, 0);\r\n\tbreak;\r\n" self 
			| _ -> Printf.sprintf "\t\tget_test_case_ptr_%s_of_level_%d((unsigned long)addr);\r\n\t\ttest_case_record_add(addr, 14, 0);\r\n\tbreak;\r\n" s n *)
(* ********************************************************************************************************************* *)

	method type_compare t1 t2 = (self#getTypNameString t1) = (self#getTypNameString t2)

(* ********************************************************************************************************************** *)
	method getConstTypValue c = 
		match c with
			(*integer*)
		  CInt64(_,ik,_) -> let v = match ik with
					IChar -> 15 | ISChar -> 15 | IUChar -> 16 | IInt -> 11 | IUInt | IBool -> 17 
					| IShort -> 18 | IUShort -> 19 | ILong -> 12 | IULong -> 20 | ILongLong -> 21 | IULongLong -> 22 in v
		| CChr(_) -> 15
		| CEnum(_,_,_) -> 11
			(*float*)
		| CReal(_,fk,_) -> let v = match fk with
					FFloat -> 13 | FDouble -> 13 | FLongDouble -> 13 in v
		(*string*)
		| CStr(_) -> 14
		| CWStr(_) -> 14

(* ********************************************************************************************************************** *)
	method getPtrDimension ptr =
		match ptr with
			TPtr(t, _) -> let (s, n) = self#getPtrDimension t
					in
					(s, n + 1)
			|_ -> (ptr, 0)
	
(* ********************************************************************************************************************** *)
	method getArrayDimension arr = 
		match arr with
			TArray(t, Some(e), _) -> 
						let res = (match e with
							Const(cinfo) -> (match cinfo with 
										CInt64(a, _, _) -> to_int a
										| _ -> 1)
							| _ -> 1)
						in
						res * (self#getArrayDimension t)
						
			| _ -> 1

(* ********************************************************************************************************************** *)
	method getTypValue t = 
		match t with
			TInt(IChar,_) -> 15 
		| TInt(ISChar,_) -> 15
		| TInt(IUChar,_) -> 16
		| TInt(IInt,_) -> 11 
		| TInt(IUInt,_) -> 17 
		| TInt(IShort,_) -> 18
		| TInt(IUShort,_) -> 19
		| TInt(ILong,_) -> 12
		| TInt(IULong,_) -> 20
		| TInt(ILongLong,_) -> 21
		| TInt(IULongLong,_) -> 22
		| TFloat(_, _) -> 13 (* double type *)
		| TPtr(_,_) -> 14 (* pointer type *)
		| TNamed (ti,_) -> self#getTypValue (unrollType ti.ttype)
		| TEnum (_,_)  -> 11
		(* TVoid,TFun,TArray,TComp,TBuiltin_va_list do not need to consider *)
		| _ -> 0 (* need impl *)

	(*Only look for lvalue, addrof and cast*)
	method doExprToVarinfo expr = 
		match expr with
			Lval((Var(vr),_)) -> Some vr
		| CastE(t,e) -> self#doExprToVarinfo e
		| AddrOf(lv) -> self#doExprToVarinfo (Lval(lv))
		| _ -> None

	(*store_concrete_value_int/float*)
	(* 
		match lval with
		| Lval(Var,_)  -> 
					Var.type == _Float --> load_float((double)lval)
					Var.type == _ --> load_int((long)lval)
		| Lval(Mem,_)  -> 
					--> load_int((long)lval)
	*)
	method doConcreteValueAnalysis lv loc = 
		let load_fun v = match v.vtype with
				TFloat(_, _) -> emptyFunction "store_concrete_value_float"
			| _ -> emptyFunction "store_concrete_value_int"
		in
		
		
		let lvv = match lv with 
			  Lval(Var(var), _) -> (match var.vtype with
					TFloat(_, _) -> mkCast ~e:(lv) ~newt:(TFloat(FLongDouble,[])) 
					| _ -> mkCast ~e:(lv) ~newt:(TInt(ILongLong,[])) 
					)
			| Lval(Mem(e), _) -> mkCast ~e:(lv) ~newt:(TInt(ILongLong, []))
			| _ -> lv (* [suting] this is redundant *)
		in
	
		
		match lv with
				Lval(Var(var), _) -> let store_fun = load_fun var in
				[Call(None, Lval((Var(store_fun.svar)), NoOffset), [lvv], loc)]
			| Lval(Mem(e), _) -> let store_fun = emptyFunction "store_concrete_value_int" in
				[Call(None, Lval((Var(store_fun.svar)), NoOffset), [lvv], loc)]
			| _ -> []

	method doOffsetTypeAnalyze hostTyp ofst =
		match ofst with
		NoOffset -> hostTyp
		| Field (fi,o) -> self#doOffsetTypeAnalyze fi.ftype o
		| Index (e,o) -> hostTyp		

	method doArguAnalyze expr loc =
			let argu_fun = emptyFunction "argu_push" in
			let paraAddr = match expr with
			|	Lval((host,offset)) -> (* it must be a variable and not a mem like *p *)
					let r = mkAddrOf((host,offset)) in
					mkCast ~e:(r) ~newt:(TInt(IULong,[]))
			|	_ ->
					let r = integer 0 in (* including string constant *)
					mkCast ~e:(r) ~newt:(TInt(IULong,[]))
			in
			let paraTyp = match expr with
			|	Const(c) ->
					let constTyp = self#getConstTypValue c in
					integer constTyp
			|	Lval((host,offset)) ->
					let varTyp = match host with
					|	Var(vr) ->
							self#getTypValue vr.vtype
					|	_ ->	(* Mem( *p ) must not appear in a function call *)
							0
					in
					integer varTyp
			|	AddrOf(_) ->
					integer 14 (* TYPE_POINT *)
			| _ ->
					integer 0
			in
			Call(None,Lval((Var(argu_fun.svar)),NoOffset),[paraAddr;paraTyp],loc)
			
	method doCondAnalyze expr loc = 
		self#doExprAnalyzeInternal expr loc 1
		
	method doExprAnalyze expr loc =
		self#doExprAnalyzeInternal expr loc 2
	
  (* load_to_heap interface definition *)
  (* load_to_heap(unsigned long addr, long value, enum _value_type type *)
  method doExprAnalyzeInternal expr loc expTyp(* OP_BOOLEAN=1 OP_ARITHMETIC=2*) = (* analyze expr *)
  (* insert 'load_to_heap' and 'applyOp' runtime interfaces *)
    match expr with
    (* binary expr *)
    | BinOp(op,exp1,exp2,t) ->		
		let dump = false in
		if dump = true then
			ignore ( E.log "BinOp\n");  
		let opTyp (* operator types *) = match op with
			PlusA -> 21
		| PlusPI -> 25
		| IndexPI -> 25
		| MinusA -> 22
		| MinusPI -> 26
		| MinusPP -> 22
		| Mult -> 23
		| Div -> 24
		| Lt -> 16
		| Gt -> 11
		| Le -> 15
		| Ge -> 12
		| Eq -> 13
		| Ne -> 14
		| BAnd -> 31 (* bitwise and *)
		| BXor -> 33 (* exclusive or *)
		| BOr -> 32  (* inclusive or *)
		| Shiftlt -> 34 (* shift left *)
		| Shiftrt ->  35 (* shift right *)
		| _ -> -1
		in
		let applyOp_fun = emptyFunction "apply_op" in
		let applyOp_instr = [Call(None,Lval((Var(applyOp_fun.svar)),NoOffset),integer expTyp :: integer opTyp ::[],loc)] in
		let load1_instr = self#doExprAnalyze exp1 loc in
		let load2_instr = self#doExprAnalyze exp2 loc in
		load1_instr @ load2_instr @ applyOp_instr
			
    (* constant expr *)
    | Const(c) ->
		let dump = false in
		if dump = true then
			ignore ( E.log "Const\n");  
		let constTyp = self#getConstTypValue c in
		let load_fun = match c with
			CReal(_,_,_) -> [emptyFunction "load_to_heap_float"]
		|	_ -> [emptyFunction "load_to_heap_int"] 
		in
		(* p1: the const address , is zero *)
		let p1 = mkCast ~e:(integer 0) ~newt:(TInt(IULong,[])) in
		(* p2: the expr value , CStr and CWStr is special *)
		let p2 = match c with
			CStr(_) ->
				let cast1 = mkCast ~e:(expr) ~newt:(TPtr(TInt(IChar, []),[])) in
				mkCast ~e:(cast1) ~newt:(TInt(ILongLong,[]))
		|	CWStr(_) ->
				let cast1 = mkCast ~e:(expr) ~newt:(TPtr(TInt(IChar, []),[])) in
				mkCast ~e:(cast1) ~newt:(TInt(ILongLong,[]))
		| _ -> expr
		in			
		[Call(None,Lval((Var((List.hd load_fun).svar)),NoOffset),p1::p2::integer constTyp::[],loc)]
			
     (* lvalue *)
     | Lval((host,offset)) ->(* ---------------------------------------------*)
        let dump = false in
        if dump = true then
		ignore ( E.log "Lval\n"); 
		let load_instr = match host with
		| Var(vr) -> (* x *)
			let vType = self#getTypValue vr.vtype in
			let rec load_fun_f vt = match vt with
			| TInt(_,_) ->
			[emptyFunction "load_to_heap_int"]
			| TPtr(_,_) ->
			[emptyFunction "load_to_heap_int"]
			| TFloat(_,_) ->
			[emptyFunction "load_to_heap_float"]
			| TNamed (vi,_) -> 
	 		load_fun_f (unrollType vi.ttype)
			| TEnum (_,_)  -> 
			[emptyFunction "load_to_heap_int"]
			| _ -> 
			if dump = true then
				ignore( E.log "[cf.ml->765] Really Reaching Here?? \n");
			[emptyFunction "load_to_heap_int"](* need impl *) (******** problem here******)
			in
			let load_fun = load_fun_f vr.vtype in (* create "load" interface *)
			(* the address addr*)
			let addr = mkCast ~e:(mkAddrOf (host,offset)) ~newt:(TInt(IULong,[])) in
			let rec expr_t_f t e = match t with
			  TInt(_,_) ->
					mkCast ~e:(e) ~newt:(TInt(ILongLong,[]))
			| TPtr(_,_) ->
					mkCast ~e:(e) ~newt:(TInt(ILongLong,[]))
			| TFloat(_,_) ->
					mkCast ~e:(e) ~newt:(TFloat(FLongDouble,[]))
			| TNamed (vi,_) -> expr_t_f (unrollType vi.ttype) e
			| TEnum (_,_)  -> 
					 mkCast ~e:(e) ~newt:(TInt(ILongLong,[]))
			| _ -> 
				if dump = true then
					ignore( E.log "[cf.ml->783] Really Reaching Here?? \n");
				e (* need impl *)
			in
			
			let expr_t = expr_t_f vr.vtype expr in
			let load_instr = [Call(None,Lval((Var((List.hd load_fun).svar)),NoOffset),addr::expr_t::integer vType::[],loc)] in
			let typed_instr = match expTyp with (* this case must not appear in Mem(e) *)
				(* treat if(b) as if(b!=0) *) 
				1 -> (* logic *)
					let p1 = mkCast ~e:(integer 0) ~newt:(TInt(IULong,[])) in
					let p2 = integer 0 in
					let l = Call(None,Lval((Var((List.hd load_fun).svar)),NoOffset),p1::p2::integer vType::[],loc) in
					let applyOp_fun = emptyFunction "apply_op" in
					let applyOp_instr = Call(None,Lval((Var(applyOp_fun.svar)),NoOffset),integer expTyp :: integer 14 (*!=*) ::[],loc) in
					[l;applyOp_instr]
			 |	_ -> (* arith *)
					[]
			in load_instr @ typed_instr
				|	Mem (e) -> (* *(expr) *)
						let r = match e with
							Lval((h,o)) -> (* *x *)
								let instr = match h with
								|	Var(vr) -> (* x *)
										let rt =match vr.vtype with
												TPtr(t,_) -> (* t *) vr.vtype  (* Note: load _pointer type var *)
											| _ -> vr.vtype
										in
										let vType = self#getTypValue rt in
										let load_fun = [emptyFunction "load_to_heap_int"] in
										let expr_t = mkCast ~e:(e) ~newt:(TInt(ILongLong,[])) in
										let addr = mkCast ~e:(mkAddrOf (h,o)) ~newt:(TInt(IULong,[])) in
										let applyOp_fun = emptyFunction "apply_op" in 
										[Call(None,Lval((Var((List.hd load_fun).svar)),NoOffset),addr::expr_t::integer vType::[],loc); Call(None,Lval((Var(applyOp_fun.svar)),NoOffset),integer expTyp :: integer 28(* * *) ::[],loc)]
								|	_ -> self#doExprAnalyze e loc (* impossible matching *)
								in instr
							(* may appear when cil is processing struct *)
							(* *((typ * )p) *)
							|	CastE(t,ex) ->
									let realT = match t with (* typ *)
										TPtr(rt,_) -> rt
									| _ ->	t
									in
									let vType = self#getTypValue realT in
									let load_fun = [emptyFunction "load_to_heap_int"] in
									let expr_t = mkCast ~e:(CastE(t,ex)) ~newt:(TInt(ILongLong,[])) in
									let addr = match ex with
												Lval(l) -> mkCast ~e:(mkAddrOf l) ~newt:(TInt(IULong,[]))
									    | _ -> mkCast ~e:(CastE(t,ex)) ~newt:(TInt(IULong,[])) (*impossible match*)
									in
									let applyOp_fun = emptyFunction "apply_op" in
									[Call(None,Lval((Var((List.hd load_fun).svar)),NoOffset),addr::expr_t::integer vType::[],loc); Call(None,Lval((Var(applyOp_fun.svar)),NoOffset),integer expTyp :: integer 28 ::[],loc)]
							| _ -> self#doExprAnalyze e loc (* impossible matching *)
						in r
				in load_instr
		(* type casting *)
	|	CastE(_,e) ->
			let dump = false in
			if dump = true then
				ignore ( E.log "CastE\n"); 
			self#doExprAnalyze e loc
  (* unary expr skip *)
  | UnOp(op,e,t) ->
	let dump = false in
	if dump = true then			
		ignore ( E.log "UnOp\n"); 
	let r = match op with
	| Neg ->
	    let typR = match expTyp with
		1 -> (* logic , convert -e to e*)
			self#doExprAnalyzeInternal e loc expTyp
	       | _ -> (* arith, covert to 0 minus e *)
			let bin = BinOp(MinusA,integer 0,e,t) in
			self#doExprAnalyzeInternal bin loc expTyp
	    in typR
	| LNot -> (* covert !a to a==0 *)
	     if dump = true then
		ignore ( E.log "[cf.ml->866] Really Reaching Here??"); 
	     let bin = BinOp(Eq,e,integer 0,t) in
	     self#doExprAnalyzeInternal bin loc expTyp
	| BNot -> (* do not support BNot, do nothing *)
	     let applyOp_fun = emptyFunction "apply_op" in
	     let applyOp_instr = [Call(None,Lval((Var(applyOp_fun.svar)),NoOffset), Cil.integer expTyp :: Cil.integer 29 ::[],loc)] in (* 29 for BNot *)
	     let load_instr = self#doExprAnalyze e loc in
	     load_instr @ applyOp_instr
        in r
				
    (* ref &x skip *)
    | AddrOf (lv) ->(*  load_to_heap_(int|float)(&p,(long) p, 14); *)
		let dump = false in
		if dump = true then
			ignore ( E.log "AddrOf\n"); 
		let load_fun = [emptyFunction "load_to_heap_int"] in
		let expr_t = mkCast ~e:(Lval(lv)) ~newt:(TInt(ILongLong,[])) in
		let p1 = mkCast ~e:(expr) ~newt:(TInt(IULong,[])) in
		let applyOp_fun = emptyFunction "apply_op" in
		let addrOfVarInfo = self#doExprToVarinfo expr in
		let addrOfVarType = match addrOfVarInfo with
					  Some(varTypeInfo) -> self#getTypValue varTypeInfo.vtype
					| None -> 
						if dump = true then
							ignore( E.log "[cf.ml->867] Really Reaching Here??\n");
						11 in
		[Call(None,Lval((Var((List.hd load_fun).svar)),NoOffset),p1::expr_t::integer  addrOfVarType::[],loc);Call(None,Lval((Var(applyOp_fun.svar)),NoOffset),integer expTyp :: integer 27 ::[],loc)]
		(* the beginning of an array *)
		|	StartOf (lv) ->
				let dump = false in
				if dump = true then
					ignore ( E.log "StartOf\n"); 
				let load_fun = [emptyFunction "load_to_heap_int"] in
				let expr_t = mkCast ~e:(Lval(lv)) ~newt:(TInt(ILongLong,[])) in
				let p1 = mkCast ~e:(expr) ~newt:(TInt(IULong,[])) in
				[Call(None,Lval((Var((List.hd load_fun).svar)),NoOffset),p1::expr_t::integer 14::[],loc)]
		|	_ -> (* need impl *)
				[]

end
	
	

class tcgInstAnalyzeVisitor helper = object(self)
  inherit nopCilVisitor
  
	val mutable instr_list = ([] : instr list)
	val mutable driverFlag = false

	(** handle uninstrumented function's return value *)
	method private handle_return_lval (lv : Cil.lval) (loc: Cil.location) : Cil.instr list = 
		let lv_type = Cil.typeOfLval lv in (* check its return value's type: float or int ? *)
		let is_ret_int = 
			match lv_type with
			| TFloat _ -> (* float *)
		 		false
			| _ ->	(* int *)
				true
		in
		if is_ret_int = true then begin
			let handle_return_fun = emptyFunction "handle_uninterpreted_function_return_int" in
			let arg_lv = Cil.mkCast ~e:(Lval(lv)) ~newt:(TInt(ILongLong,[])) in
			let arg_typ_value = helper#getTypValue lv_type in (* get its type value in CAUT *)
			[Call(None,Lval((Var(handle_return_fun.svar)),NoOffset),[arg_lv; (Cil.integer arg_typ_value)],loc)]
		end else begin
			let handle_return_fun = emptyFunction "handle_uninterpreted_function_return_float" in
			let arg_lv = Cil.mkCast ~e:(Lval(lv)) ~newt:(TFloat(FLongDouble,[]))  in
			let arg_typ_value = helper#getTypValue lv_type in (* get its type value in CAUT *)
			[Call(None,Lval((Var(handle_return_fun.svar)),NoOffset),[arg_lv; (Cil.integer arg_typ_value)],loc)]
		end

  	(* store_to_var_table(unsigned long addr); *)
    method vinst inst =
	
	match inst with		
	(** assignment *)
	(* load_to_heap --> set_instr --> store_to_var_table  --> store_concrete_value *)
    | Set((host,offset),expr,loc) ->
		
			let dump = false in
			if dump = true then 
				ignore (E.log "#line: %d\n" loc.line);
    	(* analyze left hand *)
    	(* insert 'store_to_var_table' func *)
    	let argo = match host with
    		Var(vr) -> (* x = expr *)
			  	mkAddrOf((Var(vr),offset)) (* &x *)
			| Mem(e) -> (* *x = expr *)
			  	e (* x *)
			in
			let argu = mkCast ~e:(argo) ~newt:(TInt(IULong,[])) in (* (unsigned long) argo *)
			let store_fun = emptyFunction "store_to_var_table" in
			let store_instr = Call(None,Lval((Var(store_fun.svar)),NoOffset),[argu],loc) in
			if dump = true then
				ignore (E.log "store_instr: %s\n" (sprint 20 (d_instr () store_instr)) );
			let symbolic_instr = helper#doExprAnalyze expr loc in (* do right-hand expr analysis and instr load_to_heap *)
			if dump = true then begin
				ignore (E.log "symbolic_instr: \n");
				List.iter (fun instr_t -> E.log "%s\n" (sprint 20 (d_instr () instr_t)) ) symbolic_instr ;
				ignore (E.log "\n")
			end;
			instr_list <- store_instr :: instr_list;
			instr_list <- symbolic_instr @ instr_list;
			(* insert instr_list *)
		  self#queueInstr instr_list;
			if dump = true then 
				ignore(E.log "queueInstr Return\n");
			instr_list <- []; (* set instr_list null *)
			(*store_concrete_value*)
			let lv = Lval(host, offset) in
			let store_value_instr = helper#doConcreteValueAnalysis lv loc in
			if dump= true then
					List.iter (fun instr_t -> E.log "store_value_instr: %s\n\n" (sprint 20 (d_instr () instr_t)) ) store_value_instr;
			let final_instr =  [inst] @ store_value_instr in
			ChangeTo final_instr

	(** no-return-value Call*)
	(* instrumented functions: argu_push --> para_num_stack_push --> call_instr 
	   uninstrumented functions: argu_push --> para_num_stack_push --> call_instr --> para_num_stack_pop
	*)	 
	| Call(None,exp,explist,loc) ->
		
		let dump = false in
		if dump = true then ignore (E.log "Call (No-Return)\n");
				
	  	let instrl = match exp with (* filter the input func *)
			  | Lval((Var(vr),_)) ->
					
  				if dump = true then ignore (E.log "Call : %s\n" vr.vname );
								
				if (is_caut_runtime_interfaces vr.vname) = true then begin (* skip CAUT-instrumentation interfaces *)
					if dump = true then ignore (E.log "Skip Internal Functions!\n");
					[] 
				end else if vr.vname = "_cf__getInput" then begin (* process _cf__getInput() *)
					ignore(helper#set_var_list (List.append helper#get_var_list (List.map (function item -> helper#doExprToVarinfo item) explist)));
					[]
				end else begin
					
					let argu_num = List.length explist in (* create "para_num_stack_push" interface *)
					let para_num_fun = emptyFunction "para_num_stack_push" in
					let para_num_instr = [Call(None,Lval((Var(para_num_fun.svar)),NoOffset),[integer argu_num],loc)] in
					
					let argu_instr = 
						List.map 
							begin fun e -> (* create "argu_push" interface *)
								helper#doArguAnalyze e loc
							end
						  explist in
					let is_instrumented_function = (* check whether it is an instrumented function *)
						List.exists 
							begin fun func_name ->
								if func_name = vr.vname then
									true
								else
									false
							end
						  !(MyFuncInstrument.g_instrumentedFunctionList) in
					if is_instrumented_function = true then begin
						(* E.log "line:%d is instrumented function\n" loc.line; *)
						argu_instr @ para_num_instr @ [inst]
					end
					else begin (* for un-instrumented function, clear its stack after its return *)
						(* E.log "line:%d is un-instrumented function\n" loc.line; *)
						let clean_stack_fun = emptyFunction "para_num_stack_pop" in
						let clean_stack_fun_instr = [Call(None,Lval((Var(clean_stack_fun.svar)),NoOffset),[],loc)] in
						argu_instr @ para_num_instr @ [inst] @ clean_stack_fun_instr
					end
				end
		
			 | _ -> []
		  in
			
		if dump = true then begin  (* DEBUG: output instrumented call instruction *)
			ignore (E.log "Call No-Return Instr:\n");
			List.iter 
				begin fun t -> 
				  E.log "%a\n\n" d_instr t
				end
			 instrl
		end;
					
		(match List.length instrl with (* Change the original call instruction *)
		 0 -> DoChildren
		| _ -> ChangeTo instrl)

	(** return-value Call *)
	(* instrumented functions: argu_push --> para_num_stack_push --> call_instr --> store_to_var_table --> store_concrete_value 
	   uninstrumented functions: argu_push --> para_num_stack_push --> call_instr --> para_num_stack_pop --> store_to_var_table --> store_concrete_value 
	*)
	| Call(Some(host,offset),exp,explist,loc) ->
		
			let dump = false in
			if dump = true then ignore (E.log "Call Return\n");
				
			(* para_num_stack_push *)
			let argu_num = List.length explist in
			let para_num_fun = emptyFunction "para_num_stack_push" in
			let para_num_instr = Call(None,Lval((Var(para_num_fun.svar)),NoOffset),[integer argu_num],loc) in

			(* store_to_var_table &  store_return_value*)
			let store_fun = emptyFunction "store_to_var_table" in
			let argo = match host with
				| Var(vr) -> 
						mkAddrOf((Var(vr),NoOffset))
				| Mem(e) ->
						e
			in
			let argu = mkCast ~e:(argo) ~newt:(TInt(IULong,[])) in
			let store_instr = [Call(None,Lval((Var(store_fun.svar)),NoOffset),[argu],loc)](*;Call(None,Lval((Var(store_fun2.svar)),NoOffset),[argu],loc)] *)
			in
			(* argu_push *)
			let argu_instr = List.map (function item ->
				helper#doArguAnalyze item loc) explist in

			(*store_concrete_value*)
			let lv = Lval(host, offset) in
			let store_value_inst = helper#doConcreteValueAnalysis lv loc in

			let call_name = MyCilUtility.getfunNameFromExp exp in
			let is_instrumented_function = (* check whether it is an instrumented function *)
				List.exists 
					begin fun func_name ->
						if func_name = call_name then
							true
						else
							false
					end
				  !(MyFuncInstrument.g_instrumentedFunctionList) in
			let func_list =
				(if is_instrumented_function = true then
			 		argu_instr @[para_num_instr;inst] @ store_instr @ store_value_inst
				else begin (* for un-instrumented function, clear its stack after its return *)
					let clean_stack_fun = emptyFunction "para_num_stack_pop" in
					let clean_stack_fun_instr = [Call(None,Lval((Var(clean_stack_fun.svar)),NoOffset),[],loc)] in
					(* handle uninstrumented function's return value *)
					let handle_return_fun_instr = self#handle_return_lval (host,offset) loc in

					(* store uninstrumented function's return value *)
					let store_return_fun = emptyFunction "store_uninterpreted_function_return" in
					let store_return_fun_instr = [Call(None,Lval((Var(store_return_fun.svar)),NoOffset),[argu],loc)] in
					argu_instr @[para_num_instr;inst] @ clean_stack_fun_instr @ handle_return_fun_instr @ store_return_fun_instr @ store_value_inst
				end)
			in (*let func_list = argu_instr @[para_num_instr;inst] @ store_instr @ store_value_inst (*@ stack_clean_instr*)*)
			ChangeTo func_list

  | _ -> DoChildren

	(*method vstmt st*)
end

(** function counter *)
let tcgFuncAnalyzeVisitor_func_cnt = ref 0

(** analyze function formal parameters
	insert "set_main_function_id" and "para_pop" interfaces 
*)
class tcgFuncAnalyzeVisitor helper = object(self)
  inherit nopCilVisitor
	
	(* instr set_main_func_id and para_pop on the top of func *)
	method vfunc f = 
		let funcid_fun = emptyFunction "set_main_function_id" in
		let funcid_instr = [mkStmtOneInstr(Call(None,Lval((Var(funcid_fun.svar)),NoOffset),[integer !tcgFuncAnalyzeVisitor_func_cnt],unknownLoc))] in
		let pop_fun = emptyFunction "para_pop" in
		let pop_instr = List.map (function item -> 
			let addr = mkAddrOf((Var(item),NoOffset)) in
			let param = mkCast ~e:(addr) ~newt:(TInt(IULong,[])) in
			let instr = Call(None,Lval((Var(pop_fun.svar)),NoOffset),[param],unknownLoc) in
			mkStmtOneInstr instr
			)	f.sformals in 
		f.sbody.bstmts <-  funcid_instr @ pop_instr @ f.sbody.bstmts;
		DoChildren
end

(** get line number of a "stmt" *)
(*
let rec getLineNumber (stmt_t:stmt) : int = try (match stmt_t.skind with
	| Instr (instrs) ->
		(match (List.hd instrs) with
		|Set (lv, exp, loc) -> loc.line
		|Call (lv, exp, expl, loc) -> loc.line
		|Asm (at, strl, l, l2, l3, loc) -> loc.line
		)
	| Return (e, loc) -> loc.line
	| Goto (r, loc) -> loc.line
	| Break (loc) -> loc.line
	| Continue (loc) -> loc.line
	| If (exp, bl, bl2, loc) -> loc.line
	| Switch (exp, bl, stl, loc) -> loc.line
	| Loop (bl1, loc, s, s2) -> loc.line
	| Block (block) -> 
		getLineNumber (List.hd block.bstmts)
	| TryFinally (bl, bl2, loc) -> loc.line
	| TryExcept (bl, a, bl2, loc) -> loc.line) with Failure("hd") -> -1
*)

(** analyze if stmt 
	insert "branch" interface
*)
class tcgStmtAnalyzeVisitor helper = object(self)
  inherit nopCilVisitor

	method vstmt st = 
		let dump = false in
			if dump = true then
			begin
				ignore ( E.log "tcgStmtAnalyzeVisitor\n" );
				ignore( E.log "tcg if stmt :\n %s" (sprint 20 (d_stmt () st)))
			end;
		match st.skind with
		(* generate "branch" monitoring interfaces for if stmt *)
		| If (e,b1,b2,loc) ->
			let instr_list = helper#doCondAnalyze e !currentLoc in
			(* convert instr_list to stmt_list *)
			let stmt_list = List.map (function item ->
				mkStmtOneInstr item  (*val mkStmtOneInstr : instr -> stmt *)
			) instr_list in
			let branch_fun = emptyFunction "branch" in
			(* branch(#line,branch_id,branch_choice,tcgFuncAnalyzeVisitor_func_cnt) *)
			let then_instr = Call(None,Lval((Var(branch_fun.svar)),NoOffset),[Cil.integer loc.line;integer st.sid;integer 1;integer !tcgFuncAnalyzeVisitor_func_cnt],!currentLoc) in
			let then_stmt = mkStmtOneInstr then_instr in
			let else_instr = Call(None,Lval((Var(branch_fun.svar)),NoOffset),[Cil.integer loc.line;integer st.sid;integer 0;integer !tcgFuncAnalyzeVisitor_func_cnt],!currentLoc) in
			let else_stmt = mkStmtOneInstr else_instr in				
			b1.bstmts <- stmt_list @ [then_stmt] @ b1.bstmts;
			b2.bstmts <- stmt_list @ [else_stmt] @ b2.bstmts;
			DoChildren
		| Return (Some exp,loc) ->
				let instr = helper#doExprAnalyze exp loc
				in self#queueInstr instr;
				DoChildren
		| _ ->
				DoChildren
end

class tcgPreProcessAnalyzeVisitor helper = object(self)
  inherit nopCilVisitor
	val mutable funcd_list = ([] : fundec list)

	(* \B1\A3\B4浱ǰ\B5ĺ\AF\CA\FD\A3\AC\D2\F2Ϊ\D4ں\F3\C3\E6\B5\C4method vstmt\D6\D0\D0\E8Ҫ\D3õ\BD\B4\CB\D0\C5Ϣ *)
	method vfunc fd = funcd_list <- [fd]; DoChildren

	
	method vstmt st = 
		let dump = false in
		match st.skind with		
		(* make sure the expr in if stmt is a binary relation expr : <,>,<=,>=,==,!= .
		   and operators are simple lvals.
		*)
		| If (e,b1,b2,loc) ->
				if dump = true then begin
					E.log "%s -->\n" (sprint 20 (d_stmt () st)) ;
					E.log "sid: %d\n" st.sid		
				end;
				(match e with
					
					|BinOp(Lt,_,_,_)|BinOp(Gt,_,_,_)|BinOp(Le,_,_,_)|BinOp(Ge,_,_,_) 
					|BinOp(Eq,_,_,_)|BinOp(Ne,_,_,_)->   (* if( x> y) *)
						if dump = true then begin
							E.log "%s -->\n" (sprint 20 (d_stmt () st)) ;
							E.log "sid: %d\n" st.sid
						end;
						DoChildren 
					| UnOp(LNot,ee,_) ->  
						if dump = true then begin
							E.log "e:%s\n" (sprint 20 (d_exp () e)) ;
							E.log "ee:%s\n" (sprint 20 (d_exp () ee)) 
						end;
						(
						match ee with (* if( !(x>y) ) *) 
						|BinOp(Lt,_,_,_)|BinOp(Gt,_,_,_)|BinOp(Le,_,_,_)|BinOp(Ge,_,_,_) 
						|BinOp(Eq,_,_,_)|BinOp(Ne,_,_,_)-> 
							if dump = true then begin
								E.log "%s -->\n" (sprint 20 (d_stmt () st)) ;
								E.log "sid: %d\n" st.sid
							end;
							(* st.skind <- If( ee, b1, b2, loc) ; *)
							DoChildren
						| _ ->  (* if( !(x) )  or if( !(x+2) ) *) 
							(* convert to a binary relation expr *)
							if dump = true then begin
								E.log "%s -->\n" (sprint 20 (d_stmt () st)) ;
								E.log "sid: %d\n" st.sid
							end;
							st.skind <- If( BinOp(Eq,ee,Cil.zero,Cil.intType), b1, b2, loc) ;
							DoChildren
						)
					| _ ->  (* if( x )  or if( x+2 ) *) 
						(* convert to a binary relation expr *)
						st.skind <- If( BinOp(Ne,e,Cil.zero,Cil.intType), b1, b2, loc) ;
						if dump = true then begin
							E.log "%s -->\n" (sprint 20 (d_stmt () st)) ;
							E.log "sid: %d\n" st.sid
						end;
						DoChildren
				)
		| Return (Some e,loc) ->
				(match e with
					| Lval((h,o)) -> 
						(match h with
							| Mem(me) -> let v = makeTempVar (List.hd funcd_list) (typeOf e) in
									let instr = [Set ((Var(v),NoOffset), e, loc)] in
									self#queueInstr instr;
									let new_ret_stmt = mkStmt (Return(Some(Lval((Var v, NoOffset))),loc)) in
									new_ret_stmt.sid <- st.sid;
									ChangeTo (new_ret_stmt)
							| _ -> DoChildren)
					| _ -> DoChildren)
		| _ ->	DoChildren
end


(* ********************************************************************************************************************** *)
(* only do one substitution *)
(*
b=a;
call(b);
[b1;b2;b3] -> [a1;a2;a3]
*)
class tcgInputAnalyzeVisitor helper = object(self)
  inherit nopCilVisitor
	method vinst inst = match inst with
	Set((Var(vr),_),expr,_) ->
	    ignore( 
		match (List.exists (fun v -> match v with Some(v)->v.vid = vr.vid | None -> false) helper#get_var_list) with
		true -> ignore (
			let exprVar = helper#doExprToVarinfo expr in
			match exprVar with
			  Some(variable) -> ignore(
						helper#set_var_list (List.map (
							fun item ->
							  match item with
							   Some(v)-> (match v.vid = vr.vid with
								       true -> Some(variable) (*substitution*)
								      |false -> Some(v))
							  | None -> None							
						) helper#get_var_list)
					    );Some(variable)
			 | None -> None
 			);
			true
		| false -> false	
	    );		
		SkipChildren
	| _ -> SkipChildren
end

(* ********************************************************************************************************************** *)
(* generate initialization decl for struct *)
(* void get_test_case_%s(unsigned long, unsigned long); *)
(* void get_test_case_ptr_%s(unsigned long, unsigned long); *)
let genStructInputDecl buf comp helper =
  ignore (
  	(*match comp with
	 CompInit(true,c) -> Buffer.add_string buf (Printf.sprintf "void get_test_case_%s(unsigned long);\r\n" c.cname);
			     Buffer.add_string buf (Printf.sprintf "void get_test_case_ptr_%s(unsigned long);\r\n" c.cname)
	|CompInit(false,c)-> Buffer.add_string buf (Printf.sprintf "void get_test_case_%s(unsigned long);\r\n" c.cname)*)

	match comp with 
		TComp(c, _) -> Buffer.add_string buf (Printf.sprintf "void get_test_case_struct_%s(unsigned long);\r\n" c.cname)
		| _ -> ()
  )

(* ********************************************************************************************************************** *)
let genStructInputFunc buf comp helper = 
ignore(
	let struct_name = match comp with TComp(c, _) -> c.cname
					| _ -> ""
	in
	let fieldsList = match comp with TComp(c, _) -> c.cfields
					| _ -> []
	in
	Buffer.add_string buf (Printf.sprintf "void get_test_case_struct_%s(unsigned long address)\r\n" struct_name);
	Buffer.add_string buf (Printf.sprintf "{\r\n\tstruct %s* tmp;\r\n" struct_name);
	Buffer.add_string buf "\tunsigned long addr;\r\n";
	Buffer.add_string buf (Printf.sprintf "\ttmp = (struct %s*) address;\r\n" struct_name);

	List.iter (fun field -> let str = helper#getInitFunc field.ftype in
			Buffer.add_string buf (Printf.sprintf "\taddr = (unsigned long)&(tmp->%s);\r\n\t%s\r\n" field.fname str);
			(*Buffer.add_string buf (Printf.sprintf "\t%s\t\r\n" str)*)
		)fieldsList; 
	
	Buffer.add_string buf "\r\n}\r\n";

	(* Mark *)
	helper#set_struct_list (List.map (fun item -> match item with
		StructType(_, tt) -> (match tt with TComp(tc, _) -> (match tc.cname = struct_name with 
											true -> StructType(true, tt)
											| _ -> item)
							| _ -> item) ) helper#get_struct_list)
)

(* ********************************************************************************************************************** *)
let genStructInput buf_decl buf_def helper = 
ignore(
  (*List.iter (fun comp -> genStructInputDecl buf_decl comp helper) helper#get_struct_list;
  List.iter (fun comp -> genStructInputDef buf_def comp helper) helper#get_struct_list;*)

  List.iter (fun item -> match item with 
				StructType(false, com_typ) -> genStructInputDecl buf_decl com_typ helper
				| _ -> () ) helper#get_struct_list;
  List.iter (fun item -> match item with
				StructType(false, com_typ) -> genStructInputFunc buf_def com_typ helper
				| _ -> () ) helper#get_struct_list;
)
				
(*  match helper#update_struct_list with
	true -> ignore(genStructInput buf_decl buf_def helper)
	| false -> ignore 0*)

(* ******************************Added by Stanley****************************************************************************************** *)
let genArrayInputFuncDecl buf arr helper = 
ignore(
  let arrInfo = match arr with
			ArrType(_, t) -> helper#getTypNameString t
  in
  Buffer.add_string buf (Printf.sprintf "void get_test_case_array_%s(unsigned long, int);\r\n" arrInfo);
)

(* *****************************Added by Stanley******************************************************************************************* *)
(*generate array input function*)
let genArrayInputFunc buf arr helper =
 ignore(
	let t = match arr with
		ArrType(_, t) -> t
	in
	let str = helper#getInitFunc t 
	in
	let arrInfo = helper#getTypNameString t
	in
	Buffer.add_string buf (Printf.sprintf "void get_test_case_array_%s(unsigned long addr, int index)\r\n" arrInfo);
	Buffer.add_string buf "{\r\n";
	Buffer.add_string buf "\tint i;\r\n";
	Buffer.add_string buf (Printf.sprintf "\tarray_declaration(addr, index, %d, %s);\r\n" (helper#getTypValue t)  (helper#getSizeOfTypString t));
	Buffer.add_string buf "\tfor(i = 0; i < index; i++)\r\n";
	Buffer.add_string buf "\t{\r\n";
	Buffer.add_string buf (Printf.sprintf "\t\t%s\r\n" str);
	Buffer.add_string buf (Printf.sprintf "\t\taddr += %s;\r\n" (helper#getSizeOfTypString t));
	Buffer.add_string buf "\t}\r\n";
	Buffer.add_string buf "}\r\n\r\n";
	
	(*Mark *)
	helper#set_array_list (List.map (fun item -> match item with
		ArrType(_, tt) -> (match (helper#type_compare tt t) with true -> ArrType(true,tt) | false -> item) ) helper#get_array_list)
  )
			
(* ************************Added by Stanley***************************************************************** *)
(* generate arrary input*)
let genArrayInput decl_buf def_buf helper = 
  ignore(
	List.iter (fun arr -> 
			match arr with
				ArrType(false, _) -> genArrayInputFuncDecl decl_buf arr helper
				| _ -> ()) helper#get_array_list;
	List.iter (fun arr -> 
			match arr with
				ArrType(false, _) -> genArrayInputFunc def_buf arr helper
				| _ -> ()) helper#get_array_list;
  )

(* ************************Added by Stanley***************************************************************** *)
(* function genPtrInputDecl *)
let genPtrInputDecl buf ptr helper = 
ignore(
	let t = match ptr with
		PtrType(_, t) -> t
	in
	let (s, n) = helper#getPtrDimension t
	in
	Buffer.add_string buf (Printf.sprintf "void get_test_case_ptr_%s_of_level_%d(unsigned long);\r\n" (helper#getTypNameString s) n)
)

(* ************************Added by Stanley***************************************************************** *)
(* function genPtrInputFunc *)
let genPtrInputFunc buf ptr helper =
ignore(
	let str = match ptr with 
		PtrType(_, TPtr(pt, _)) -> helper#getInitFunc pt
		| _ -> ""
	in
	let t = match ptr with
		PtrType(_, t) -> t
	in
	let (s, n) = helper#getPtrDimension t
	in
	let sizeStr = match n with
		1 -> helper#getSizeOfTypString s
		| _ -> "sizeof(void *)"
	in
	Buffer.add_string buf (Printf.sprintf "void get_test_case_ptr_%s_of_level_%d(unsigned long addr_old)\r\n" (helper#getTypNameString s) n);
	Buffer.add_string buf "{\r\n";
	Buffer.add_string buf (Printf.sprintf "\tlong addr = abstract_ptr_handle(addr_old, %s);\r\n" sizeStr);
	Buffer.add_string buf "\tif(addr > 0)\r\n\t{\r\n";		
	Buffer.add_string buf (Printf.sprintf "\t\t%s\r\n" str);
	Buffer.add_string buf "\t}\r\n}\r\n";

	(* Mark the type that generates input to be true. *)

	helper#set_ptr_list (List.map (fun item -> match item with
			PtrType(_, tt) -> (match (helper#type_compare tt t) with true -> PtrType(true,tt) | false -> item)) helper#get_ptr_list)
)

(* *************************Added by Stanley**************************************************************** *)
(* function genPtrInput *)
let genPtrInput decl_buf def_buf helper =
ignore(
	List.iter (fun ptr -> 
			match ptr with 
				PtrType(false, _) -> genPtrInputDecl decl_buf ptr helper
				| _ -> ()) helper#get_ptr_list;
	List.iter (fun ptr -> match ptr with
				PtrType(false,_) -> genPtrInputFunc def_buf ptr helper
				| _ -> ()) helper#get_ptr_list;
)

(* ****************************************************************************************************************** *)
(*initialization for basic data type *)
let genInput buf varopt helper =
  ignore (  
  	match varopt with
	  Some(var) -> ignore(
			let initFunc = helper#getInitFunc var.vtype in
			(*let recordFunc = helper#getRecordFunc var.vtype in*)
			let caselbl = Printf.sprintf "\tcase %d:\r\n" helper#incrInitCount in
			Buffer.add_string buf caselbl;
			Buffer.add_string buf (Printf.sprintf "\t\t%s\r\n\t\tbreak;\r\n" initFunc)
			);
			Some(var)
	| None -> None
  )

(* *************************Added by Stanley************************************************************************** *)
(* function genCustomInput *)
let rec genCustomInput decl_buf def_buf helper = 
ignore(
	genStructInput decl_buf def_buf helper;
	genArrayInput decl_buf def_buf helper;
	genPtrInput decl_buf def_buf helper;
	let result = helper#getListsStatus
	in
	match result with
		false -> genCustomInput decl_buf def_buf helper
		|true -> ()
)


(* ******************************************************************************************************************** *)
(* _cf__getInput body *)
let genCFINPUT helper =
ignore(
  let buf = Buffer.create 1024 in
  let def_buf = Buffer.create 1024 in
  let decl_buf = Buffer.create 1024 in
  Buffer.add_string buf "void _cf__getInput(unsigned long addr)\r\n{\r\n";(* _cf__getInput(usigned long addr) { *)
  Buffer.add_string buf "\tint id = get_input_id();\r\n";(* int id = get_input_id(); *)
  Buffer.add_string buf "\tswitch(id)\r\n\t{\r\n";(* switch(id) { *)
  helper#resetInitCount;
  List.iter (fun var -> genInput buf var helper) helper#get_var_list;
  Buffer.add_string buf "\t}\r\n";(* } *)
  Buffer.add_string buf "}\r\n";(* } *)

  genCustomInput decl_buf def_buf helper;

  print_string (Buffer.contents decl_buf);
  print_string (Buffer.contents def_buf);
  print_string (Buffer.contents buf);
) 

(* ********************************************************************************************************************** *)
let genMain () =
  if !cf_unit_testing = true then begin
	if !cf_generate_type_system = true then begin
  		Printf.printf "void main(int argc, char *argv[])\r\n{\r\n\tinit_caut(argc,argv);\r\n\tinit_coverage_driven_testing_framework();\r\n\t__CAUT_register_types();\r\n\twhile(1){\r\n\t\tinit_caut_exec();\r\n\t\t%s();\r\n\t\tsolve_caut_exec();\r\n\t}\r\n}\r\n" !drivenUnit
	end else begin
		Printf.printf "void main(int argc, char *argv[])\r\n{\r\n\tinit_caut(argc,argv);\r\n\tinit_coverage_driven_testing_framework();\r\n\twhile(1){\r\n\t\tinit_caut_exec();\r\n\t\t%s();\r\n\t\tsolve_caut_exec();\r\n\t}\r\n}\r\n" !drivenUnit
	end
  end else if !cf_program_br_testing = true || !cf_program_df_testing then begin
	if !cf_generate_type_system = true then begin
    	Printf.printf "void main(int argc, char *argv[])\r\n{\r\n\tinit_caut(argc,argv);\r\n";
    	if !cf_program_br_testing = true then 
    		Printf.printf "\tinit_program_testing_framework(1);\r\n";
    	if !cf_program_df_testing = true then
    		Printf.printf "\tinit_program_testing_framework(2);\r\n";
    	Printf.printf "\t__CAUT_register_types();\r\n\twhile(1){\r\n\t\tinit_caut_exec();\r\n\t\t%s();\r\n" !drivenUnit;
    	
    	if !cf_program_br_testing = true then 
    		Printf.printf "\t\tsolve_caut_exec_program_testing(1);\r\n\t}\r\n}\r\n";
    	if !cf_program_df_testing = true then
    		Printf.printf "\t\tsolve_caut_exec_program_testing(2);\r\n\t}\r\n}\r\n"
    	
	end else begin
		Printf.printf "void main(int argc, char *argv[])\r\n{\r\n\tinit_caut(argc,argv);\r\n";
    	if !cf_program_br_testing = true then 
    		Printf.printf "\tinit_program_testing_framework(1);\r\n";
    	if !cf_program_df_testing = true then
    		Printf.printf "\tinit_program_testing_framework(2);\r\n";
    	Printf.printf "\r\n\twhile(1){\r\n\t\tinit_caut_exec();\r\n\t\t%s();\r\n" !drivenUnit;
    	
    	if !cf_program_br_testing = true then 
    		Printf.printf "\t\tsolve_caut_exec_program_testing(1);\r\n\t}\r\n}\r\n";
    	if !cf_program_df_testing = true then
    		Printf.printf "\t\tsolve_caut_exec_program_testing(2);\r\n\t}\r\n}\r\n"
	end
  end else begin
	ignore (E.log "**** Choose Unit Testing or Program Testing ? ****\n");
	exit 2 (* terminate the process *)
  end
  
(* ********************************************************************************************************************** *)

class rtbranchVisitor (l:int) (db_helper:cautFrontDatabaseHelper) (db_handler:Sqlite3.db) = object(self)
	inherit nopCilVisitor
	
	method vstmt (s: stmt) = 
		match s.skind with
		| If(e,bt,bf,loc) ->
			if loc.line = l then
				rt_branch_id_list := !rt_branch_id_list @ [s.sid];
			DoChildren
		| _ ->	DoChildren
end;;

class fitnessIfStmtVisitor = object(self)
	inherit nopCilVisitor

	method vstmt st = 
		let fitness_fun = emptyFunction "cover_condition_fun" in 
		match st.skind with
		| If(e,bt,bf,loc) -> 
			(
			match e with
			| BinOp(bop,e1,e2,t) ->
				let bop_typ = ( match bop with
					| Lt -> 16 | Gt -> 11 | Le -> 15
					| Ge-> 12 | Eq->13 | Ne ->14 | _ -> -1) in
				
				let instr = Call(None,Lval((Var(fitness_fun.svar)),NoOffset),[(Cil.integer st.sid); BinOp(MinusA,e1,e2,Cil.intType); (Cil.integer bop_typ)],!currentLoc) in
				self#queueInstr [instr];
				DoChildren

			| _ -> DoChildren
			)
		| _ -> DoChildren
end;;


(** Insert data flow testing interface 
	Note: If a stmt's sid equals to -1, it must be a runtime interfaces created by CAUT kernel.
	  	  It's safe to directly skip it.
	<obsolete>
*)
class dfMonitorVisitor = object(self)
   inherit nopCilVisitor
 
   method vstmt st = 
	 let df_fun = Cil.emptyFunction "df_stmt_monitor" in
	 let df_monitor_call = Call(None,Lval(Var df_fun.svar,NoOffset),[Cil.integer !tcgFuncAnalyzeVisitor_func_cnt; Cil.integer st.sid;
	 Cil.integer (!currentLoc.line)], !currentLoc) in
	 if st.sid = -1 then 
		 SkipChildren
	 else
		 ChangeDoChildrenPost(st, fun s -> self#queueInstr [df_monitor_call]; s)
 
end;;

(** Also Insert data flow testing interface,
	The idea is similar with the above class, but in this class we comply with the p-use coverage definition.
*)
class dfMonitorVisitor2 = object(self)
	inherit nopCilVisitor
	
	method vstmt st = 
		let df_fun = Cil.emptyFunction "df_stmt_monitor" in
		let action s = 
			match s.skind with
			| If(e, b1, b2, loc) -> 
				(* df_stmt_monitor(func_id, stmt_id, branch_choice, line_no); 	
					when it is a if-true branch, then $branch_choice = 1;
					when it is a if-false branch, then $branch_choice = 0;
				*)
	 			let df_monitor_call_at_true_branch = Call(None,Lval(Var df_fun.svar,NoOffset),[Cil.integer !tcgFuncAnalyzeVisitor_func_cnt; Cil.integer st.sid; Cil.one; Cil.integer (!currentLoc.line)], !currentLoc) in
	 			b1.bstmts <- (Cil.mkStmtOneInstr df_monitor_call_at_true_branch)  :: b1.bstmts; 
	 			
	 			let df_monitor_call_at_false_branch = Call(None,Lval(Var df_fun.svar,NoOffset),[Cil.integer !tcgFuncAnalyzeVisitor_func_cnt; Cil.integer st.sid; Cil.zero; Cil.integer (!currentLoc.line)], !currentLoc) in
				b2.bstmts <- (Cil.mkStmtOneInstr df_monitor_call_at_false_branch)  :: b2.bstmts; 
				(* return s *)
    			s
			| _ ->
				s
	 	in
	 	if st.sid = -1 then 
			SkipChildren
	 	else begin
	 		match st.skind with
	 		| If _ -> ChangeDoChildrenPost(st, action)
	 		| _ ->  
	 			(* when it is a non-if stmt, then $branch_choice = -1 *)
	 			let df_monitor_call = Call(None,Lval(Var df_fun.svar,NoOffset),[Cil.integer !tcgFuncAnalyzeVisitor_func_cnt; Cil.integer st.sid; Cil.mone; Cil.integer (!currentLoc.line)], !currentLoc) in
	 			ChangeDoChildrenPost(st, fun s -> self#queueInstr [df_monitor_call]; s)
	 	end
		 
end;;

(** transform "nondet_int/float/long/double" or "__VERIFIER_nondet_int/long/float/double" stubs to "klee_make_symbolic":
   int a = nondet_int(); --> int a; klee_make_symbolic(&a, sizeof(a), "a");
   int a = __VERIFIER_nondet_int(); --> int a; klee_make_symbolic(&a, sizeof(a), "a");
*)
class nondetKleeVisitor = object(self)
	inherit nopCilVisitor
			
	method vinst inst = 
	   match inst with
	   | Call (Some lv, e, el, loc) ->
		(match e with
		| Lval e_lv ->
		     (match e_lv with
		     | (Var(var), _) -> 
			if var.vname = "nondet_int" || var.vname = "nondet_long" || var.vname = "nondet_float" || var.vname = "nondet_double" || 
			   var.vname = "__VERIFIER_nondet_int" || var.vname = "__VERIFIER_nondet_long" || var.vname = "__VERIFIER_nondet_float" || var.vname = "__VERIFIER_nondet_double"
				then begin
	      		  let klee_make_symbolic_stub = emptyFunction "klee_make_symbolic" in  
			  let lv_name = 
				(match lv with
				| (Var(var), _) -> var.vname
				| _ -> "" (* impossible to reach here *)
				)
			  in
			  let klee_stub_instr = [Call(None, Lval((Var(klee_make_symbolic_stub.svar)), NoOffset), AddrOf(lv)::SizeOf(Cil.typeOfLval(lv))::Const(CStr(lv_name))::[], loc)] in
			  ChangeTo klee_stub_instr
			end else begin
		          SkipChildren
			end
		     | _ -> SkipChildren
                     )
		| _ -> SkipChildren
                )
	   | _ -> SkipChildren

end;;



(** set up map table between orginal branch id and runtime branch id.
	The mapping is based on such an observation:
	The sequence of the automic conditions in a composite decision could be kept after
	the simplification on this decision.
*)
let set_up_map_table (f:file)= 
	
	let dump =true in
	if dump = true then
		E.log "set up mapping table...\n";

	(* db name *)
	let db_name = Buffer.create 20 in
	Buffer.add_string db_name !cf_file_name;
	Buffer.add_string db_name ".db";
	if dump = true then
		E.log "load %s ...\n" (Buffer.contents db_name);
	
	(* open db *)
	let db_helper = (new cautFrontDatabaseHelper) in
	let db_handler = db_helper#caut_open_database (Buffer.contents db_name) in
	if dump = false then
		E.log "%s" "**********create/open database succeed************\n";

	let branch_node_line_list = (db_helper#query_caut_tb db_handler "node_list" ["line_no"] ["is_branch"] ["1"]) in
	if dump = true then begin
		E.log "branch node line : ";
		List.iter (function (id:string) -> E.log "%s " id) branch_node_line_list;
		E.log "\n"
	end;
        
	if dump = true then 
			E.log "update %s ...\n" (Buffer.contents db_name);
	let len = List.length branch_node_line_list in
	E.log "total branches: %d\n" len;
	let rt_branch_id_list_buf = Buffer.create 20 in
	for i=0 to len-1 do
		let line = List.nth branch_node_line_list i in
		visitCilFile (new rtbranchVisitor (int_of_string line) db_helper db_handler) f;
		
		
		for j=0 to (List.length !rt_branch_id_list)-1 do
			Buffer.add_string rt_branch_id_list_buf (string_of_int (List.nth !rt_branch_id_list j));
			if j< (List.length !rt_branch_id_list)-1 then
				Buffer.add_string rt_branch_id_list_buf ";"
		done;

		let buf_value = (Buffer.contents rt_branch_id_list_buf) in
		if dump = true then begin
			E.log "rt branch id list: ";
			E.log "%s\n" buf_value
		end;

		(* update db --> store cond_id_list field for branch node*)
		ignore(db_helper#update_caut_tb db_handler db_helper#get_caut_cfg_node_list_tb_name 
			["cond_id_list"] [buf_value] ["line_no";"is_branch"] [line;"1"] );
		
		(* clear *)
		rt_branch_id_list:=[];
		Buffer.clear rt_branch_id_list_buf	
	done;
	
	(* close db *)
	ignore (db_helper#caut_close_database db_handler ) 

(** create runtime monitoring interfaces for functions *)
let doCreateRuntimeMonitoringInterfaces (f: file) (anah: analysisHelper) (g: global) = 
	match g with
	| GFun(func,loc) ->
		(* skip instrumenting CAUT's own monitoring interfaces *)
		if (func.svar.vname = "__CAUT_register_types") then 
		()
		else begin
			if !cf_unit_testing = true then begin
				(* only instrument the unit under test *)
				if (func.svar.vname = !cf_unit_name || func.svar.vname = "testme" ) then begin
					E.log "func: %s\n" func.svar.vname;
					tcgFuncAnalyzeVisitor_func_cnt := func.svar.vid; (* get the function id *)
					(* analyze instructions and insert data flow analysis interfaces *)
					ignore (visitCilFunction (new tcgInstAnalyzeVisitor anah) func);
					(* anaylze function entry and exit and insert function stack interfaces *)
					ignore (visitCilFunction (new tcgFuncAnalyzeVisitor anah) func);
					(* analyze if statement and insert "branch" interfaces *)
		 			ignore (visitCilFunction (new tcgStmtAnalyzeVisitor anah) func);
					(* create monitoring interfaces for FITNESS guided path exploration *)
		  			ignore (visitCilFunction (new fitnessIfStmtVisitor) func)
				end
			end else if !cf_program_br_testing = true || !cf_program_df_testing = true then begin
				
				E.log "func: %s\n" func.svar.vname;
				tcgFuncAnalyzeVisitor_func_cnt := func.svar.vid; (* get the function id *)
				(* analyze instructions and insert data flow analysis interfaces *)
				ignore (visitCilFunction (new tcgInstAnalyzeVisitor anah) func);
				(* anaylze function entry and exit and insert function stack interfaces *)
				ignore (visitCilFunction (new tcgFuncAnalyzeVisitor anah) func);
				(* analyze if statement and insert "branch" interfaces *)
	 			ignore (visitCilFunction (new tcgStmtAnalyzeVisitor anah) func);
				ignore (visitCilFunction (new dfMonitorVisitor2) func)
				 (* create monitoring interfaces for FITNESS guided path exploration *)
	  			(* ignore (visitCilFunction (new fitnessIfStmtVisitor) func) *)
				
			end else begin
				ignore (E.log "**** Choose Unit Testing or Program Testing! ****\n");
				exit 2 (* terminate the process *)
			end
				
		end
	| _ -> ()

	
(** preparation work for test case generation *)
let tcg (f : file)  =

	(* check the consistency of the command line *)
	(* check_command_line_consistency (); *)

	(* program level testing & unit level testing --> find out all instrumented functions  *)
	if !cf_program_br_testing = true || !cf_program_df_testing = true || !cf_unit_testing = true then begin
		MyFuncInstrument.find_all_instruemented_funcs f
	end;

       (* unit testing level --> automatically comment function call instructions in the UUT and pad "testme" function at the  *)
  	if !cf_unit_testing = true && !cf_instrument_function_call = true then begin
	  (* TODO separate function call instrumentation and testme function padding *)
	  ignore ( Cautstorevar.docautcreateInstruction f !cf_unit_name); 
	  let debug = false in
	  if debug = true then
	  	E.log "I am here : %s --> prepare for unit testing... \n" !cf_unit_name
  	end;
 

  let helper:analysisHelper = new analysisHelper in
  (* preprocess if stmt before code simplification, before this "--domakeCFG" is invoked on the commmand line *)
  visitCilFile (new tcgPreProcessAnalyzeVisitor helper) f;

  E.log "\n\n[Cf.ml]Simplify Code, Recompute CFG ...\n";
  E.log "[CIL]revert branch choices of IF stmts ...\n\n";
  (* simplify our code to CIL three adress code, needed by CAUT *)
  iterGlobals f Simplify.doGlobal;
  (* clear cfg info computed by "--domakeCFG" on the command line *)
  Cfg.clearFileCFG f;
  (* compute cfg info again *)
  Cfg.computeFileCFG f;

	
  (* set up the mapping info table of branches in orgianl (decision-not-simplified) and modified (decision-simplified code *)
  set_up_map_table f;
  

  (* on demand data flow testing at program level *)
  if !cf_program_df_testing = true then begin
	MyDataflowTesting.operate_data_flow_testing_on_simplified_code f
  end;
	  
  (* record branches *)
  (*if !cf_program_br_testing = true || !cf_program_df_testing = true then begin
 	MyBranchRecorder.do_record_branch f
  end;*)

  (* generate type system to facilitate printing test cases *)
  if !cf_generate_type_system = true then begin
  	ignore (Cauttyps.default_process f);
        let debug = false in
	if debug = true then
		E.log "I am here : %s --> analyze var types... \n" !cf_unit_name
	end;
	  
  if !cf_unit_testing = true then	
	E.log "\n==== In Unit Testing Mode ... ====\n"
  else
	E.log "\n==== In Program Testing Mode ... ====\n"
  ;

  (* instrument runtime monitoring interfaces for CAUT kernel *)
  iterGlobals f (doCreateRuntimeMonitoringInterfaces f helper);

  (* i do not know what it is doing ? *)
  visitCilFile (new tcgInputAnalyzeVisitor helper) f;
	
  (* generate "get_test_case" interfaces for input vars*)
  genCFINPUT helper;
 
  (* generate MAIN entry *)
  genMain ();
	  
  f
 

(* pure data flow analysis extracts def-use pairs from the program under test, and do nothing else *)
let do_klee_job (f:file) =

   (* analyze def-use pairs first, and then do program transformation *)
   MyDataflowTesting.setup_dataflow_testing_environment f;
   E.log "--> finish pure df analysis\n";

   if !cf_nondet_to_klee_make_symbolic = true then begin
	E.log "--> transform nondet_int/long/float/double to klee_make_symbolic \n";
	let transform_nondet_to_klee (g: Cil.global) =
	    match g with
	    | GFun (func, loc) ->
		ignore (visitCilFunction (new nondetKleeVisitor) func)
	    | _ -> ()
        in
	Cil.iterGlobals f (transform_nondet_to_klee)
   end;

   (* record all if branches *)
   (* MyBranchRecorder.do_record_branch f; *)

   E.log "--> insert \"df_stmt_monitor()\" interface for KLEE\n";
   (* insert "df_stmt_monitor()" interfaces for each statements. Refer to "caut.h" for details. *)
   let insert_df_runtime_interfaces (g: Cil.global) =
	match g with
        | GFun (func, loc) ->
	    (* set the function id *)
	    tcgFuncAnalyzeVisitor_func_cnt := func.svar.vid; 
	    ignore (visitCilFunction (new dfMonitorVisitor2) func)
	| _ -> ()
   in
   Cil.iterGlobals f (insert_df_runtime_interfaces)
   

(* ********************************************************************************************************************** *)
let do_main_job (f : file)  =
  if !cf_klee_instrumentation = true then begin
	E.log " --> intrument the program for klee to do data flow testing \n";
	(* intrument the program for klee to do data flow testing *)
	ignore (do_klee_job f)

  end else if !cf_cegar_instrumentation = true && !cf_model_checker != ""  then begin
	E.log " --> intrument the program for blast/cpachecker to do data flow testing \n";
    (* instrument the prgoram for blast/cpachecker to do data flow testing *)
    CEGARTransformation.set_cegar_model_checker !cf_model_checker;
    CEGARTransformation.set_offline_instrumentation !cf_offline_instrumentation;
    CEGARTransformation.set_duas_data_file !cf_duas_data_file;
    CEGARTransformation.set_var_defs_data_file !cf_var_defs_data_file;
  	CEGARTransformation.do_cegar_job f 

  end else if !cf_cbmc_instrumentation_one = true && !cf_model_checker != "" then begin
	E.log " --> intrument the program for cbmc to do data flow testing \n";
    (* instrument the program for cbmc to do data flow testing *)
    CBMCTransform.set_cbmc_instrumentation_all_mode false;
    CBMCTransform.set_offline_instrumentation !cf_offline_instrumentation;
    CBMCTransform.set_duas_data_file !cf_duas_data_file;
    CBMCTransform.set_var_defs_data_file !cf_var_defs_data_file;
    CBMCTransform.set_cbmc_model_checker !cf_model_checker;
	CBMCTransform.do_cbmc_job f 

  end else if !cf_cbmc_instrumentation_all = true && !cf_model_checker != "" then begin
    E.log " --> intrument the program for cbmc with all duas to do data flow testing \n";
    (* instrument the program for cbmc with all duas to do data flow testing *)
    CBMCTransform.set_cbmc_instrumentation_all_mode true;
    CBMCTransform.set_cbmc_model_checker !cf_model_checker;
    CBMCTransform.do_cbmc_job f

  end else begin
  	ignore (tcg f)
  end

(* ********************************************************************************************************************** *)


let feature : featureDescr = 
  { fd_name = "tcg";              
    fd_enabled = ref false;
    fd_description = "test-case generation";
    fd_extraopt = [
			("-cffile", Arg.Set_string cf_file_name, " set the file name");
   			("-cfunit", Arg.Set_string cf_unit_name, "set the unit name");
			("--instrument_funcation_call", Arg.Set cf_instrument_function_call, "instrument funcation calls in unit testing level");
			("--generate_type_system", Arg.Set cf_generate_type_system, "generate type system in order to facilitate printing test case");
			("--unit_testing", Arg.Set cf_unit_testing, "unit testing level");
		    ("--interp_br_testing", Arg.Set cf_program_br_testing, "branch testing at program level");
			("--interp_df_testing", Arg.Set cf_program_df_testing, "on demand data flow testing at program level");
			("--entry_fn", Arg.Set_string MyDfSetting.caut_df_entry_fn, "set the entry function in data flow testing");
			("--dua_by_hand", Arg.Set MyDfSetting.caut_df_dua_by_hand, "find duas by hand, otherwise find duas by the RD computation automatically");

            (* options for cegar model checkers *)
			("--cegar_instrumentation", Arg.Set cf_cegar_instrumentation, "instrument the program for cegar model checkers: blast/cpachecker");
			("--cegar_dua_id", Arg.Set_int CEGARTransformation.cegar_dua_id, "set the target dua id");

            (* options for cbmc *)
			("--cbmc_instrumentation_one", Arg.Set cf_cbmc_instrumentation_one, "instrument the program for cbmc");
			("--cbmc_dua_id", Arg.Set_int CBMCTransform.cbmc_dua_id, "set the target dua id");
            ("--cbmc_instrumentation_all", Arg.Set cf_cbmc_instrumentation_all, "instrument the program for cbmc with all duas");

            ("--model_checker", Arg.Set_string cf_model_checker, "select the model checker: blast, cpachecker, cbmc");
            ("--offline_instrumentation", Arg.Set cf_offline_instrumentation, "set offline instrumentation mode for model checkers");
            ("--duas_data_file", Arg.Set_string cf_duas_data_file, "set the duas data file for offline instrumentation");
            ("--var_defs_data_file", Arg.Set_string cf_var_defs_data_file, "set var defs data file offline instrumentation");

			(* options for pure data flow analysis and KLEE *)
            ("--klee_instrumentation", Arg.Set cf_klee_instrumentation, "instrument the program for klee");
			("--transform_nondet_to_klee_make_symbolic", Arg.Set cf_nondet_to_klee_make_symbolic, "transform nondet_int to klee_make_symbolic, work with --klee_instrumentation");
		  ];
    fd_doit = 
    (function (f: file) -> 
      do_main_job f);
    fd_post_check = true
  }
