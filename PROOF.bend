# The proofs of LAWS.bend. Nothing here is trusted: `bend PROOF.bend` checks
# every def.
#
# The argument: S.keep passes a candidate on only when S.ok holds of it
# (keep_ok, by induction on the candidates), and S.ok is the four checks
# joined by Bool.and, so each check holds of every slot kept (ok_long and
# the others, by induction on the slots).

import Base
import ./Slots.bend as S
import ./LAWS.bend as Laws

# Bool
# ----

def bdisc(b: Bool) -> Type:
  match b:
    case True{}:
      Empty
    case False{}:
      Unit

def ft(h: {False{} == True{} : Bool}) -> Empty:
  %h : bdisc(_)
  Unit{}

def no(-A: Type, h: {False{} == True{} : Bool}) -> A:
  Empty.absurd(A, ft(h))

def and_l(a: Bool, -b: Bool) -> {Bool.and(a, b) == True{} : Bool} -> {a == True{} : Bool}:
  match a:
    case True{}:
      h => {==}
    case False{}:
      h => no({False{} == True{} : Bool}, h)

def and_r(a: Bool, -b: Bool) -> {Bool.and(a, b) == True{} : Bool} -> {b == True{} : Bool}:
  match a:
    case True{}:
      h => h
    case False{}:
      h => no({b == True{} : Bool}, h)

def and_i(a: Bool, -b: Bool) -> {a == True{} : Bool} -> {b == True{} : Bool} -> {Bool.and(a, b) == True{} : Bool}:
  match a:
    case True{}:
      ha => hb => hb
    case False{}:
      ha => hb => no({False{} == True{} : Bool}, ha)

# keep passes on only what passes ok
# ----------------------------------

def put_ok(c: Bool, +x: S.Span, r: List<&2, S.Span>, +from: U32, +len: U32, +ws: List<&2, S.Span>, +bs: List<&2, S.Span>) ->
    {S.ok(from, len, ws, bs, x) == c : Bool} ->
    {S.all.ok(r, from, len, ws, bs) == True{} : Bool} ->
    {S.all.ok(List.filter.put(S.Span, x, r, c), from, len, ws, bs) == True{} : Bool}:
  match c:
    case True{}:
      e => ih => and_i(S.ok(from, len, ws, bs, x), S.all.ok(r, from, len, ws, bs), e, ih)
    case False{}:
      e => ih => ih

def keep_ok(cs: List<&2, S.Span>, +from: U32, +len: U32, +ws: List<&2, S.Span>, +bs: List<&2, S.Span>) ->
    {S.all.ok(S.keep(cs, from, len, ws, bs), from, len, ws, bs) == True{} : Bool}:
  match cs:
    case Nil{}:
      {==}
    case +x <> +t:
      put_ok(S.ok(from, len, ws, bs, x), x, S.keep(t, from, len, ws, bs), from, len, ws, bs,
             {==}, keep_ok(t, from, len, ws, bs))

# ok is the four checks
# ---------------------

def ok_long(xs: List<&2, S.Span>, +from: U32, +len: U32, +ws: List<&2, S.Span>, +bs: List<&2, S.Span>) ->
    {S.all.ok(xs, from, len, ws, bs) == True{} : Bool} -> {S.all.long(xs, len) == True{} : Bool}:
  match xs:
    case Nil{}:
      h => {==}
    case +x <> +t:
      +h => and_i(S.long(len, x), S.all.long(t, len),
                 and_l(S.long(len, x), Bool.and(S.future(from, x), Bool.and(S.inside(ws, x), S.free(bs, x))),
                       and_l(S.ok(from, len, ws, bs, x), S.all.ok(t, from, len, ws, bs), h)),
                 ok_long(t, from, len, ws, bs, and_r(S.ok(from, len, ws, bs, x), S.all.ok(t, from, len, ws, bs), h)))

def ok_future(xs: List<&2, S.Span>, +from: U32, +len: U32, +ws: List<&2, S.Span>, +bs: List<&2, S.Span>) ->
    {S.all.ok(xs, from, len, ws, bs) == True{} : Bool} -> {S.all.future(xs, from) == True{} : Bool}:
  match xs:
    case Nil{}:
      h => {==}
    case +x <> +t:
      +h => and_i(S.future(from, x), S.all.future(t, from),
                 and_l(S.future(from, x), Bool.and(S.inside(ws, x), S.free(bs, x)),
                       and_r(S.long(len, x), Bool.and(S.future(from, x), Bool.and(S.inside(ws, x), S.free(bs, x))),
                             and_l(S.ok(from, len, ws, bs, x), S.all.ok(t, from, len, ws, bs), h))),
                 ok_future(t, from, len, ws, bs, and_r(S.ok(from, len, ws, bs, x), S.all.ok(t, from, len, ws, bs), h)))

def ok_inside(xs: List<&2, S.Span>, +from: U32, +len: U32, +ws: List<&2, S.Span>, +bs: List<&2, S.Span>) ->
    {S.all.ok(xs, from, len, ws, bs) == True{} : Bool} -> {S.all.inside(xs, ws) == True{} : Bool}:
  match xs:
    case Nil{}:
      h => {==}
    case +x <> +t:
      +h => and_i(S.inside(ws, x), S.all.inside(t, ws),
                 and_l(S.inside(ws, x), S.free(bs, x),
                       and_r(S.future(from, x), Bool.and(S.inside(ws, x), S.free(bs, x)),
                             and_r(S.long(len, x), Bool.and(S.future(from, x), Bool.and(S.inside(ws, x), S.free(bs, x))),
                                   and_l(S.ok(from, len, ws, bs, x), S.all.ok(t, from, len, ws, bs), h)))),
                 ok_inside(t, from, len, ws, bs, and_r(S.ok(from, len, ws, bs, x), S.all.ok(t, from, len, ws, bs), h)))

def ok_free(xs: List<&2, S.Span>, +from: U32, +len: U32, +ws: List<&2, S.Span>, +bs: List<&2, S.Span>) ->
    {S.all.ok(xs, from, len, ws, bs) == True{} : Bool} -> {S.all.free(xs, bs) == True{} : Bool}:
  match xs:
    case Nil{}:
      h => {==}
    case +x <> +t:
      +h => and_i(S.free(bs, x), S.all.free(t, bs),
                 and_r(S.inside(ws, x), S.free(bs, x),
                       and_r(S.future(from, x), Bool.and(S.inside(ws, x), S.free(bs, x)),
                             and_r(S.long(len, x), Bool.and(S.future(from, x), Bool.and(S.inside(ws, x), S.free(bs, x))),
                                   and_l(S.ok(from, len, ws, bs, x), S.all.ok(t, from, len, ws, bs), h)))),
                 ok_free(t, from, len, ws, bs, and_r(S.ok(from, len, ws, bs, x), S.all.ok(t, from, len, ws, bs), h)))

# The laws
# --------

def Laws.slots_last_len(from, len, ws, bs):
  ok_long(S.slots(from, len, ws, bs), from, len, ws, bs, keep_ok(S.cands(ws, len), from, len, ws, bs))

def Laws.slots_in_future(from, len, ws, bs):
  ok_future(S.slots(from, len, ws, bs), from, len, ws, bs, keep_ok(S.cands(ws, len), from, len, ws, bs))

def Laws.slots_in_hours(from, len, ws, bs):
  ok_inside(S.slots(from, len, ws, bs), from, len, ws, bs, keep_ok(S.cands(ws, len), from, len, ws, bs))

def Laws.slots_miss_busy(from, len, ws, bs):
  ok_free(S.slots(from, len, ws, bs), from, len, ws, bs, keep_ok(S.cands(ws, len), from, len, ws, bs))
