module type Vertex =
sig
  type t
  type bound
  val sup : bound -> bound -> bound
  val inf : bound -> bound -> bound
  val compare : t -> t -> int
  (* val print : t -> Format.formatter -> unit *)
end

module Make (V : Vertex) =
  (* XXX Change the [V] signature so that [Common.position] is a parameter. 
     Also add printers for vertices to [V] so that the module can export printing of a graph. *)
struct
  type elt = V.t
  type bound = V.bound

  module S = Set.Make(struct
    type t = V.t
    let compare = V.compare
  end)

  module G = Map.Make(V)

  type t = (S.t * S.t * V.bound option * V.bound option) G.t

  let empty = G.empty

  let sup x y = match x, y with
    | None, _ -> y
    | _, None -> x
    | Some x, Some y -> Some (V.sup x y)

  let inf x y = match x, y with
    | None, _ -> y
    | _, None -> x
    | Some x, Some y -> Some (V.inf x y)

  let get x (g : t) =
    try G.find x g with Not_found -> (S.empty, S.empty, None, None)

  let add_edge x y (g : t) =
    let (inx, outx, infx, supx) = get x g
    and (iny, outy, infy, supy) = get y g in
    let left = S.add x (S.diff inx iny)
    and right = S.add y (S.diff outy outx) in
    let extend_left l grph =
      let (inl, outl, infl, supl) = get l grph in
      G.add l (inl, S.union outl right, infl, inf supl supy) grph
    and extend_right r grph =
      let (inr, outr, infr, supr) = get r grph in
      G.add r (S.union inr left, outr, sup infx infr, supr) grph in
    S.fold extend_left left (S.fold extend_right right g)

  let add_vertex x (g : t) =
    if G.mem x g then g else G.add x (S.empty, S.empty, None, None) g

  let add_upper_bound x new_up_b (g : t) =
    let new_up_b = Some new_up_b in
    let (inx, outx, infx, supx) = get x g in
    let g = S.fold (fun y g ->
                      let (iny, outy, infy, supy) = get y g in
                      G.add y (iny, outy, infy, inf supy new_up_b) g) inx g 
    in
    G.add x (inx, outx, infx, inf supx new_up_b) g 

  let add_lower_bound x new_low_b (g : t) =
    let new_low_b = Some new_low_b in
    let (inx, outx, infx, supx) = get x g in
    let g = S.fold (fun y g ->
                      let (iny, outy, infy, supy) = get y g in
                      G.add y (iny, outy, sup infy new_low_b, supy) g) inx g 
    in
    G.add x (inx, outx, sup infx new_low_b, supx) g 

  let remove_vertex x (g : t) =
    (* We must remove [x] as a key from [g], as well as an element of any in- our out-set *)
    let remove_x = S.filter (fun y -> x <> y) in
    (* XXX What do we do about lower and upper bounds of the discarded vertex? *)
    let (inx, outx, _, _) = get x g in
      S.elements inx, S.elements outx,
      G.fold
        (fun y (iny, outy, infy, supy) g -> G.add y (remove_x iny, remove_x outy, infy, supy) g)
        (G.remove x g)
        G.empty

  let fold_edges f grph acc =
    G.fold (fun x (_, outx, _, _) acc -> S.fold (fun y acc -> f x y acc) outx acc) grph acc

  let join grph1 grph2 =
    fold_edges add_edge grph1 grph2

  let union = G.fold G.add

  let bounds grph =
    G.fold (fun x (inx, outx, infx, supx) acc -> (x, infx, supx) :: acc) grph []

  let filter_edges p grph =
    let g = G.fold (fun x (inx, outx, infx, supx) acc -> G.add x (S.empty, S.empty, infx, supx) acc) grph G.empty in
    fold_edges (fun x y acc -> if p x y then add_edge x y acc else acc) grph g

  let map f fb grph =
    let g = G.fold (fun x (inx, outx, infx, supx) acc -> G.add (f x) (S.empty, S.empty, Common.option_map fb infx, Common.option_map fb supx) acc) grph G.empty in
    fold_edges (fun x y sbst_grph -> add_edge (f x) (f y) sbst_grph) grph g

  let simplify pos neg grph =
    let add x (inx, outx, _, _) sbst =
      if List.mem x pos && S.cardinal inx = 1 then (x, S.choose inx) :: sbst
      else if List.mem x neg && S.cardinal outx = 1 then (x, S.choose outx) :: sbst
      else sbst
    and collect_substitution (x, y) (used, sbst) =
      if List.mem y used then
        used, sbst
      else
        (x :: used), (x, y) :: sbst
    in
    let sbst = G.fold add grph [] in
    let _, sbst = List.fold_right collect_substitution sbst ([], []) in
    sbst


  let collect pos neg grph =
    let pos = List.fold_right S.add pos S.empty
    and neg = List.fold_right S.add neg S.empty in
    let collect x (inx, outx, infx, supx) (pos_prop, neg_prop, grph) =
      let x_pos = S.mem x pos
      and x_neg = S.mem x neg in
      let inx, infx = if x_pos then (S.inter neg inx, infx) else (S.empty, None)
      and outx, supx = if x_neg then (S.inter pos outx, supx) else (S.empty, None) in
      match S.cardinal inx + S.cardinal outx, infx, supx with
      | 0, None, None -> pos_prop, neg_prop, grph
      | _, _, _ ->
          let grph = G.add x (inx, outx, infx, supx) grph in
          begin match x_pos, x_neg with
          | true, true -> pos_prop, neg_prop, grph
          | false, true -> pos_prop, ((x, (outx, supx)) :: neg_prop), grph
          | true, false -> ((x, (inx, infx)) :: pos_prop), neg_prop, grph
          | false, false -> assert false
          end
    in
    let pos_prop, neg_prop, grph = G.fold collect grph ([], [], G.empty) in
    let pos_prop = List.sort (fun (_, prop) (_, prop') -> Pervasives.compare prop prop') pos_prop
    and neg_prop = List.sort (fun (_, prop) (_, prop') -> Pervasives.compare prop prop') neg_prop in
    let similar_subst lst =
      let rec gather_aux acc current current_prop = function
      | [] -> current :: acc
      | (x, prop) :: rest ->
          if prop = current_prop then
            gather_aux acc (x :: current) current_prop rest
          else
            gather_aux (current :: acc) [x] prop rest
      in
      let rec add_subst group sbst =
        match group with
        | [] -> assert false
        | x :: xs -> List.map (fun y -> (x, y)) xs @ sbst
      in
      match lst with
      | [] -> []
      | (x, prop) :: rest ->
        let groups = gather_aux [] [x] prop rest in
        List.fold_right add_subst groups []
    in
    let pos_subst = similar_subst pos_prop
    and neg_subst = similar_subst neg_prop
  in
  pos_subst @ neg_subst, grph


 (*    let print grph ppf =
      fold_vertices
        (fun x inx outx () ->
          Print.print ppf "@[%t <= %t <= %t@];@."
            (Print.sequence "," V.print (List.map fst inx))
            (V.print x)
            (Print.sequence "," V.print (List.map fst outx))
        )
        grph () *)
end