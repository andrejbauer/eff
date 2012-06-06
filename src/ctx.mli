(** Type contexts

    Type contexts assign type schemes to variables, and are used for type
    inference. A type scheme consists of a type and a list of universally
    quantified type parameters.
*)

(** The types of contexts and type schemes. *)
type ty_scheme = Type.param list * Type.ty
type context

(** [empty] is the empty context. *)
val empty : context

(** [lookup ?pos ctx x] returns a fresh instance of the type scheme assigned
    to the variable [x] in the context [ctx]. The optional position is used in
    error reporting when the variable is not bound in the context. *)
val lookup : ?pos:Common.position -> context -> Common.variable -> Type.ty

(** [extend x ty_scheme ctx] returns the context [ctx] extended with
    a variable [x] bound to the type scheme [ty_scheme]. *)
val extend :
  Common.variable -> ty_scheme -> context -> context

(** [extend_ty x ty ctx] returns the context [ctx] extended with a variable [x]
    bound to the type [ty]. The type is promoted to a type scheme with no
    generalized type parameters. *)
val extend_ty :
  Common.variable -> Type.ty -> context -> context

(** [subst_ctx sbst ctx] returns a substitution of [ctx] under [sbst]. *)
val subst_ctx : Type.substitution -> context -> context

(** [generalize ctx poly ty] generalizes the type [ty] in context [ctx] to a
    type scheme. If [poly] is [true], all free type parameters in [ty] that do
    not appear in [ctx] are universally quantified. *)
val generalize : context -> bool -> Type.ty -> ty_scheme