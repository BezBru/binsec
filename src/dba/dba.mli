(**************************************************************************)
(*  This file is part of BINSEC.                                          *)
(*                                                                        *)
(*  Copyright (C) 2016-2018                                               *)
(*    CEA (Commissariat à l'énergie atomique et aux énergies              *)
(*         alternatives)                                                  *)
(*                                                                        *)
(*  you can redistribute it and/or modify it under the terms of the GNU   *)
(*  Lesser General Public License as published by the Free Software       *)
(*  Foundation, version 2.1.                                              *)
(*                                                                        *)
(*  It is distributed in the hope that it will be useful,                 *)
(*  but WITHOUT ANY WARRANTY; without even the implied warranty of        *)
(*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *)
(*  GNU Lesser General Public License for more details.                   *)
(*                                                                        *)
(*  See the GNU Lesser General Public License version 2.1                 *)
(*  for more details (enclosed in the file licenses/LGPLv2.1).            *)
(*                                                                        *)
(**************************************************************************)

(** Definition of DBA type *)

type endianness =
  | LittleEndian
  | BigEndian

type size = int

type malloc_size = Bigint.t

type id = int
(** An [id] is a local identifier which characterizes an atomic instruction
    inside a Dba.block *)

type address = {
  base : Bitvector.t;
  id : id;
}
(** A DBA [address] is the association of a DBA block address represented by
    [base] and a unique [id].
    The first element of a block has [id] [0]. *)

type addresses = address list

type 'a jump_target =
  | JInner of 'a      (** Jump inside the same block, to a label *)
  | JOuter of address (** Jump outside the block to its first element *)

type tag =
  | Call of address
  | Return (** For call address of return site *)

type state =
  | OK
  | KO
  | Undefined of string
  | Unsupported of string

module Unary_op : sig
  type t =
    | UMinus
    | Not
    | Sext of size
    | Uext of size
    | Restrict of int Interval.t
end

module Binary_op : sig
  type t =
    | Plus
    | Minus
    | Mult
    | DivU
    | DivS
    | ModU
    | ModS
    | Or
    | And
    | Xor
    | Concat
    | LShift
    | RShiftU
    | RShiftS
    | LeftRotate
    | RightRotate
    | Eq (* reified comparison: return a 1-bit value *)
    | Diff
    | LeqU
    | LtU
    | GeqU
    | GtU
    | LeqS
    | LtS
    | GeqS
    | GtS

  val invert : t -> t
  (** [invert t] inverts [t] if it has an inverse version.
      Raise [Failure "BinaryOperator.invert "] otherwise
  *)

  val has_inverse : t -> bool
end

type malloc_status = Freed | Freeable
type restricted_region =
  [ `Stack
  | `Malloc of (int * address) * Bigint.t ]

type region = [ `Constant | restricted_region ]


module rec Expr : sig
  type t = private
    | Var of string * size * VarTag.t option  (* size: bits *)
    | Load of size * endianness * t (* size: bytes *)
    | Cst of region * Bitvector.t
    | Unary of Unary_op.t * t
    | Binary of Binary_op.t * t * t
    | Ite of t *  t *  t (* sugar operator *)

  val size_of : t -> int
  val equal : t -> t -> bool

  val is_constant : t -> bool

  val var : string -> int -> VarTag.t option -> t
  val temporary : size:int -> string -> t
  val constant : ?region:region -> Bitvector.t -> t
  (** [constant ~region bv] creates a constant expression from the bitvector
      [bv] from region [region].
      Default region is [`Constant].
  *)

  val zeros : int -> t
  (** [zeros n] creates a constant expression of value 0 with length [n]*)

  val ones : int -> t
  (** [ones n] creates a constant expression of value 1 with length [n].
      I.e. it has (n - 1) zeros in binary.
  *)

  val one : t
  val _true: t
  val zero : t
  val _false : t
  val binary          : Binary_op.t -> t -> t -> t
  val add                : t -> t -> t
  val sub                : t -> t -> t
  val mul                : t -> t -> t
  val smod               : t -> t -> t
  val umod               : t -> t -> t
  val udiv               : t -> t -> t
  val sdiv               : t -> t -> t
  val append             : t -> t -> t
  val eq                 : t -> t -> t
  val diff               : t -> t -> t
  val ule                : t -> t -> t
  val sle                : t -> t -> t
  val ult                : t -> t -> t
  val slt                : t -> t -> t
  val uge                : t -> t -> t
  val sge                : t -> t -> t
  val ugt                : t -> t -> t
  val sgt                : t -> t -> t

  val unary              : Unary_op.t -> t -> t
  val uminus             : t -> t

  include Sigs.Logical with type t := t

  val sext : int -> t -> t
  (** [sext sz e] performs a signed extension of expression [e] to size [sz] *)

  val uext : int -> t -> t
  (** [uext sz e] performs an unsigned extension expression [e] to size [sz] *)

  val logxor : t -> t -> t

  val shift_left  : t -> t -> t
  val shift_right : t -> t -> t
  val shift_right_signed : t -> t -> t
  (** [shift_(left|right) e q] shifts expression [e] by quantity [q], padding
      with zeroes *)

  val rotate_left  : t -> t -> t
  val rotate_right : t -> t -> t
  (** [rotate_(left|right) e q] rotates expression [e] by quantity [q] *)

  val ite : t -> t -> t -> t
  (** [ite cond then_e else_e] creates [Dba.ExprIte(cond, then_e, else_e)] *)

  val restrict : int -> int -> t -> t
  (** [restrict lo hi e] creates [Dba.ExprUnary(Restrict(lo, hi), e)] if
      [hi >= lo && lo >=0] .
  *)

  val bit_restrict : int -> t -> t
  (** [bit_restrict o e] is [restrict o o e] *)

  val load : Size.Byte.t -> endianness -> t -> t
  (** [load nbytes endianness t] *)

  val is_max : t -> bool
  (** [is_max e] is [true] if [e] is
      - constant; and
      - the maximum unsigned representable for the size of this expression *)
end

and Flag : sig
  type t = private
    | Cmp of Expr.t * Expr.t
    | Sub of Expr.t * Expr.t
    | Test of Expr.t * Expr.t
    | Unspecified

  val comparison  : Expr.t -> Expr.t -> t
  val subtraction : Expr.t -> Expr.t -> t
  val test        : Expr.t -> Expr.t -> t
  val unspecified : t
end

and VarTag : sig
  type t = private
    | Flag of Flag.t
    | Temp

  val flag : Flag.t -> t
  val temp : t
end


type exprs = Expr.t list

type printable =
  | Exp of Expr.t
  | Str of string

module LValue : sig

  type t = private
    | Var of string * size * VarTag.t option (* size in bits *)
    | Restrict of string * size * int Interval.t
    | Store of size * endianness * Expr.t  (* size in bytes *)

  include Sigs.Eq with type t := t

  val size_of : t -> int
  (* [size_of lv] yields the size of [lv] in bits *)

  val var : bitsize:Size.Bit.t -> string -> VarTag.t option -> t
  (** [var name size tagopt] creates a DBA lvalue for a variable *)

  val flag : ?bitsize:Size.Bit.t -> ?flag_t:Flag.t -> string -> t
  (** [flag ~size ~flag_t fname] creates a variable whose flag is of the
      subtype [flag_t].
      - [size] defaults to 1
      - [flag_t] defaults to [Flag.Unspecified]
  *)

  val temporary : string -> Size.Bit.t -> t
  val restrict : string -> Size.Bit.t -> int -> int -> t
  val bit_restrict : string -> Size.Bit.t -> int -> t
  val store : Size.Byte.t -> endianness -> Expr.t -> t

  val temp: Size.Bit.t -> t
  (** [temp n] creates a lvalue representing a temporary of size [n] with name
      [Format.sprintf "temp%d" n]. *)

  val is_expr_translatable : Expr.t -> bool
  (** [is_expr_translatable e] returns true is the expression can have a valid
      lvalue translation *)


  val of_expr : Expr.t -> t
  (** [of_expr e] translates an expression to its lvalue equivalent if possible.

      Use [is_expr_translatable e] to check the feasability of this translation.

      @raise Failure "LValue.of_expr ..." if it is not possible.
  *)

  val to_expr : t -> Expr.t
  (** [to_expr e] translates an lvalue to its equivalent rvalue.  *)

  val bitsize : t -> Size.Bit.t
  (** [bitsize lv] returns the size in bits of [lv].
  *)

  val resize : Size.Bit.t -> t -> t
  (** [resize bitsize lv] patches the lvalue [lv] and gives it a size of
      [bitsize].
  *)
end


module Tag : sig
  type t = tag
  include Sigs.Eq with type t := t
end

module Jump_target : sig
  type 'a t = 'a jump_target

  val outer : address -> 'a t
  val inner : 'a -> 'a t

  val is_inner : 'a t -> bool
  val is_outer : 'a t -> bool
end

module Instr : sig
  type t = private
    | Assign of LValue.t *  Expr.t *  id
    | SJump of id jump_target * tag option
    | DJump of Expr.t * tag option
    | If of Expr.t * id jump_target * id
    | Stop of state option
    | Assert of Expr.t * id
    | Assume of Expr.t * id
    | NondetAssume of LValue.t list * Expr.t * id
    | Nondet of LValue.t * region * id
    | Undef of LValue.t * id
    | Malloc of LValue.t * Expr.t * id
    | Free of Expr.t * id
    | Print of printable list * id

  (** {7 Constructors} *)
  val assign : LValue.t -> Expr.t -> int -> t
  val ite : Expr.t -> id Jump_target.t -> int -> t
  val undefined : LValue.t -> int -> t
  val non_deterministic : LValue.t -> region -> int -> t
  val static_jump : ?tag:Tag.t option -> id Jump_target.t -> t
  val static_inner_jump : ?tag:Tag.t option -> int -> t
  val call : return_address:address -> id Jump_target.t -> t
  val dynamic_jump : ?tag:Tag.t option -> Expr.t -> t

  val malloc : LValue.t -> Expr.t -> int -> t
  val free : Expr.t -> int -> t

  val _assert : Expr.t -> int -> t
  val assume  : Expr.t -> int -> t
  val non_deterministic_assume : LValue.t list -> Expr.t -> int -> t
  val stop : state option -> t

  val print : printable list -> int -> t


end