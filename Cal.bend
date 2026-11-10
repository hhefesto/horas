import Base
import ./Json.bend as J
import ../bend-frp/Frp.bend as F

# The calendar: what an event is, and how two copies of the calendar become
# one.
#
# Every replica (olimpo, delfos, Google Calendar) holds a copy. A copy is a
# set of records, one per event id, each the latest version of its event that
# this replica has seen, stamped with when and where it was made. Two copies
# join by keeping, for every id, the version with the greater stamp. That join
# does not care in what order, or how often, copies meet: so the replicas agree
# as soon as each has heard, directly or through another, every edit.
#
# A deleted event stays as a record whose body is not live (a tombstone), so
# that its deletion beats the versions before it everywhere.

type When is Data:
  NoTime{}
  # an all-day event's date, "2026-11-29" (the end is the day after the last)
  Day{+date: String}
  # "2026-11-29T18:00:00-06:00" in the zone "America/Mexico_City"
  At{+time: String, +zone: String}

type Body is Data:
  Body{+live: Bool, +title: String, +notes: String, +place: String,
       +start: When, +end: When, +rrule: List<&2, String>}

# When (UTC, "2026-11-10T15:30:12.123Z"), then a counter for edits in the same
# millisecond, then which replica: a total order, so no two edits tie.
type Stamp is Data:
  Stamp{+t: String, +n: U32, +who: String}

type Rec is Data:
  Rec{+id: String, +at: Stamp, +body: Body}

def Rec.id(r: Rec) -> String:
  match r:
    case Rec{i, s, b}:
      i

def Rec.at(r: Rec) -> Stamp:
  match r:
    case Rec{i, s, b}:
      s

def Rec.body(r: Rec) -> Body:
  match r:
    case Rec{i, s, b}:
      b

def Body.live(b: Body) -> Bool:
  match b:
    case Body{l, ti, no, pl, st, en, rr}:
      l

def Body.title(b: Body) -> String:
  match b:
    case Body{l, ti, no, pl, st, en, rr}:
      ti

def Body.start(b: Body) -> When:
  match b:
    case Body{l, ti, no, pl, st, en, rr}:
      st

# Order
# -----

def Cmp.then(c: Cmp, d: Cmp) -> Cmp:
  match c:
    case LT{}:
      LT{}
    case EQ{}:
      d
    case GT{}:
      GT{}

def Stamp.order(a: Stamp, b: Stamp) -> Cmp:
  match a b:
    case Stamp{t1, n1, w1} Stamp{t2, n2, w2}:
      Cmp.then(String.order(t1, t2), Cmp.then(U32.cmp(n1, n2), String.order(w1, w2)))

def Stamp.is_gt(a: Stamp, b: Stamp) -> Bool:
  Cmp.is_gt(Stamp.order(a, b))

# The stamp as Google keeps it (in an event's private extended properties).
def Stamp.show(s: Stamp) -> String:
  match s:
    case Stamp{t, n, w}:
      t ++ "|" ++ U32.show(n) ++ "|" ++ w

def Stamp.parts(ps: List<&2, String>) -> Maybe<&2, Stamp>:
  match ps:
    case +t <> +n <> +w <> Nil{}:
      Maybe.map(&2, U32, Stamp, k => Stamp{t, k, w}, U32.read(n))
    case _:
      None{}

def Stamp.read(s: String) -> Maybe<&2, Stamp>:
  Stamp.parts(String.split(s, '|'))

# The next stamp for an edit made now at replica who, after every stamp this
# replica has seen (so a clock set back cannot make an edit lose).
def Stamp.next.if(later: Bool, +now: String, +who: String, +t: String, +n: U32) -> Stamp:
  match later:
    case True{}:
      Stamp{now, 0, who}
    case False{}:
      Stamp{t, (n + 1 : U32), who}

def Stamp.next(+now: String, +who: String, last: Stamp) -> Stamp:
  match last:
    case Stamp{+t, +n, w}:
      Stamp.next.if(String.is_gt(now, t), now, who, t, n)

def Stamp.zero() -> Stamp:
  Stamp{"", 0, ""}

def Stamp.max(a: Stamp, +b: Stamp) -> Stamp:
  match a:
    case +x:
      Bool.pick(Stamp, Stamp.is_gt(x, b), x, b)

# The body as one string, its fields in a fixed order: what the tie-break
# compares and what Google's copy is checked against.
def When.json(w: When) -> J.Json:
  match w:
    case NoTime{}:
      J.JNull{}
    case Day{d}:
      J.JObj{J.JField{"date", J.JStr{d}, J.JNil{}}}
    case At{t, z}:
      J.JObj{J.JField{"dateTime", J.JStr{t}, J.JField{"timeZone", J.JStr{z}, J.JNil{}}}}

def When.of(+j: J.Json) -> When:
  Bool.pick(When, J.Json.has(j, "date"), Day{J.Json.at(j, "date")},
  Bool.pick(When, J.Json.has(j, "dateTime"), At{J.Json.at(j, "dateTime"), J.Json.at(j, "timeZone")},
    NoTime{}))

def Body.json(b: Body) -> J.Json:
  match b:
    case Body{l, ti, no, pl, st, en, rr}:
      J.JObj{
        J.JField{"status", J.JStr{Bool.pick(String, l, "confirmed", "cancelled")},
        J.JField{"summary", J.JStr{ti},
        J.JField{"description", J.JStr{no},
        J.JField{"location", J.JStr{pl},
        J.JField{"start", When.json(st),
        J.JField{"end", When.json(en),
        J.JField{"recurrence", J.JArr{J.Json.strs(rr)},
        J.JNil{}}}}}}}}}

def Body.of(+j: J.Json) -> Body:
  Body{Bool.not(String.eq(J.Json.at(j, "status"), "cancelled")),
       J.Json.at(j, "summary"), J.Json.at(j, "description"), J.Json.at(j, "location"),
       When.of(J.Json.get(j, "start")), When.of(J.Json.get(j, "end")),
       J.Json.texts(J.Json.get(j, "recurrence"))}

def Body.canon(b: Body) -> String:
  J.Json.show(Body.json(b))

# FNV-1a, 32 bits, as eight hex digits: a check that Google still holds the
# body a replica wrote, not a secret.
def fnv(s: String, +h: U32) -> U32:
  match s:
    case SNil{}:
      h
    case SCon{c, t}:
      fnv(t, ((h .^. Char.to_u32(c)) * 16777619 : U32))

def hash.show(+h: U32) -> String:
  J.hex4((h >> 16n : U32)) ++ J.hex4((h .&. 65535 : U32))

def Body.hash(b: Body) -> String:
  hash.show(fnv(Body.canon(b), 2166136261))

def Body.same(a: Body, b: Body) -> Bool:
  String.eq(Body.canon(a), Body.canon(b))

# Joining
# -------

def Rec.later.by(c: Cmp, x: Rec, y: Rec) -> Rec:
  match c:
    case LT{}:
      y
    case EQ{}:
      x
    case GT{}:
      x

# Of two versions of one event, the later; at equal stamps (which separate
# replicas never make), the one whose body sorts last, so the choice is the
# same whichever comes first.
def Rec.later(+x: Rec, +y: Rec) -> Rec:
  Rec.later.by(Cmp.then(Stamp.order(Rec.at(x), Rec.at(y)),
                        String.order(Body.canon(Rec.body(x)), Body.canon(Rec.body(y)))), x, y)

type JSt is Data:
  JSt{+acc: List<&2, Rec>, +xs: List<&2, Rec>, +ys: List<&2, Rec>}

def join.cmp(c: Cmp, acc: List<&2, Rec>, +x: Rec, xt: List<&2, Rec>, +y: Rec, yt: List<&2, Rec>) -> JSt:
  match c:
    case LT{}:
      JSt{x <> acc, xt, y <> yt}
    case EQ{}:
      JSt{Rec.later(x, y) <> acc, xt, yt}
    case GT{}:
      JSt{y <> acc, x <> xt, yt}

def join.step3(acc: List<&2, Rec>, xs: List<&2, Rec>, ys: List<&2, Rec>) -> JSt:
  match xs ys:
    case Nil{} Nil{}:
      JSt{acc, Nil{}, Nil{}}
    case Nil{} y <> yt:
      JSt{y <> acc, Nil{}, yt}
    case x <> xt Nil{}:
      JSt{x <> acc, xt, Nil{}}
    case +x <> xt +y <> yt:
      join.cmp(String.order(Rec.id(x), Rec.id(y)), acc, x, xt, y, yt)

def join.step(st: JSt) -> JSt:
  match st:
    case JSt{acc, xs, ys}:
      join.step3(acc, xs, ys)

def join.flush(st: JSt) -> List<&2, Rec>:
  match st:
    case JSt{acc, xs, ys}:
      List.reverse.go(&2, Rec, acc, List.append(&2, Rec, xs, ys))

# Each step takes at least one record off xs or ys, so their lengths are fuel
# enough.
def join.go(fuel: Nat, st: JSt) -> List<&2, Rec>:
  match fuel:
    case 0n:
      join.flush(st)
    case 1n+f:
      join.go(f, join.step(st))

# Two copies of the calendar (each sorted by id, one record per id) as one.
def join(+a: List<&2, Rec>, +b: List<&2, Rec>) -> List<&2, Rec>:
  join.go(Nat.add(List.length(&2, Rec, a), List.length(&2, Rec, b)), JSt{Nil{}, a, b})

# Sorting a list of records from anywhere (Google's pages, a file) into a copy.
def Copy.of(xs: List<&2, Rec>) -> List<&2, Rec>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      join([x], Copy.of(t))

def Copy.find(xs: List<&2, Rec>, +id: String) -> Maybe<&2, Rec>:
  match xs:
    case Nil{}:
      None{}
    case +x <> t:
      Bool.pick(Maybe<&2, Rec>, String.eq(Rec.id(x), id), Some{x}, Copy.find(t, id))

# The ids that start with p (a command may name an event by a prefix).
def Copy.prefixed(xs: List<&2, Rec>, +p: String) -> List<&2, Rec>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      List.filter.put(Rec, x, Copy.prefixed(t, p), String.starts_with(Rec.id(x), p))

# The latest stamp in a copy.
def Copy.last(xs: List<&2, Rec>, +m: Stamp) -> Stamp:
  match xs:
    case Nil{}:
      m
    case x <> t:
      Copy.last(t, Stamp.max(Rec.at(x), m))

# The calendar as a bend-frp machine
# ----------------------------------

# What can happen to a replica's copy: an edit here, a peer's copy, Google's
# changes. Each is a list of records; its meaning is the join.
type In is Data:
  Edit{+recs: List<&2, Rec>}
  Peer{+name: String, +recs: List<&2, Rec>}
  Pulled{+recs: List<&2, Rec>}

def In.recs(i: In) -> List<&2, Rec>:
  match i:
    case Edit{r}:
      r
    case Peer{n, r}:
      r
    case Pulled{r}:
      r

def apply(s: List<&2, Rec>, i: In) -> List<&2, Rec>:
  join(s, Copy.of(In.recs(i)))

def cal.step(s: List<&2, Rec>, i: In) -> List<&2, Rec> & List<&2, Rec>:
  F.accum.step(~In, ~List<&2, Rec>, ~apply, s, i)

# The copy after the inputs: bend-frp's accum, the calendar as a behavior of
# the events that reach it (its last value is the copy now).
def Cal.run(+s: List<&2, Rec>, ins: List<&2, In>) -> List<&2, Rec>:
  List.foldl(~&2, ~List<&2, Rec>, ~List<&2, Rec>, ~(a => b => b), F.Run.from(~List<&2, Rec>, ~In, ~List<&2, Rec>, ~cal.step, ins, s), s)

# Ids
# ---

# Google takes an event id of 5 to 1024 characters from 0-9 and a-v (base32hex),
# so a replica makes its own ids that way and every replica shares them.
def b32.char(+v: U32) -> Char:
  Bool.pick(Char, U32.is_lt(v, 10), Char.from_u32((v + 48 : U32)), Char.from_u32((v + 87 : U32)))

def b32.of(n: Nat, +x: U32) -> String:
  match n:
    case 0n:
      SNil{}
    case 1n+p:
      SCon{b32.char((x .&. 31 : U32)), b32.of(p, (x >> 5n : U32))}

def Id.of(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}:
      ""
    case +x <> t:
      b32.of(6n, x) ++ Id.of(t)

# Showing
# -------

def When.key(w: When) -> String:
  match w:
    case NoTime{}:
      ""
    case Day{d}:
      d ++ "T00:00"
    case At{t, z}:
      t

def When.show(w: When) -> String:
  match w:
    case NoTime{}:
      "-"
    case Day{d}:
      d
    case At{t, z}:
      String.take(t, 10n) ++ " " ++ String.take(String.drop(t, 11n), 5n)

def Rec.key(+r: Rec) -> String:
  When.key(Body.start(Rec.body(r))) ++ Rec.id(r)

def Rec.before(a: Rec, b: Rec) -> Bool:
  String.is_le(Rec.key(a), Rec.key(b))

def Rec.show(r: Rec) -> String:
  match r:
    case Rec{+i, s, Body{l, ti, no, pl, st, en, rr}}:
      String.take(i, 8n) ++ "  " ++ When.show(st) ++ " .. " ++ When.show(en) ++ "  " ++ ti

def Rec.detail(r: Rec) -> String:
  match r:
    case Rec{i, s, Body{l, ti, no, pl, st, en, rr}}:
      "id:      " ++ i ++ "\n" ++
      "title:   " ++ ti ++ "\n" ++
      "start:   " ++ When.show(st) ++ "\n" ++
      "end:     " ++ When.show(en) ++ "\n" ++
      "place:   " ++ pl ++ "\n" ++
      "stamp:   " ++ Stamp.show(s) ++ "\n" ++
      "live:    " ++ Bool.pick(String, l, "yes", "no (deleted)") ++ "\n" ++
      "notes:\n" ++ no

def Rec.live(r: Rec) -> Bool:
  Body.live(Rec.body(r))

def Copy.agenda(xs: List<&2, Rec>) -> List<&2, Rec>:
  List.sort(~Rec, ~Rec.before, List.filter(~Rec, ~Rec.live, xs))

# Files
# -----

def Stamp.json(s: Stamp) -> J.Json:
  J.JStr{Stamp.show(s)}

def Rec.json(r: Rec) -> J.Json:
  match r:
    case Rec{i, s, b}:
      J.JObj{J.JField{"id", J.JStr{i}, J.JField{"stamp", Stamp.json(s), J.JField{"body", Body.json(b), J.JNil{}}}}}

def Rec.of.go(+j: J.Json) -> Rec:
  Rec{J.Json.at(j, "id"), Maybe.default(&2, Stamp, Stamp.read(J.Json.at(j, "stamp")), Stamp.zero()),
      Body.of(J.Json.get(j, "body"))}

def Rec.of(j: J.Json) -> Rec:
  Rec.of.go(j)

def Copy.json.go(xs: List<&2, Rec>) -> J.Json:
  match xs:
    case Nil{}:
      J.JNil{}
    case x <> t:
      J.JCons{Rec.json(x), Copy.json.go(t)}

def Copy.json(xs: List<&2, Rec>) -> J.Json:
  J.JArr{Copy.json.go(xs)}

def Recs.of(xs: List<&2, J.Json>) -> List<&2, Rec>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      Rec.of(x) <> Recs.of(t)

def Copy.of.json(j: J.Json) -> List<&2, Rec>:
  Copy.of(Recs.of(J.Json.items(j)))
