import Base

# Open slots: the times someone may book a call, out of working hours and a
# calendar's busy times.
#
# A time is a whole minute since 1970-01-01 00:00 UTC, as a U32 (good until
# the year 10136). A span is the minutes from a (in it) up to b (not in it).
# Windows are the working hours, as spans; busy spans are the calendar's
# events. A slot is a span of len minutes, and it is open when it
#
#   lasts len minutes                      (long)
#   starts at or after `from` (now)        (future)
#   lies inside one working window         (inside)
#   shares no minute with a busy span      (free)
#
# slots() keeps a candidate only when all four hold, and LAWS.bend states
# that every slot it returns does; PROOF.bend proves it.

type Span is Data:
  Span{+a: U32, +b: U32}

def Span.a(s: Span) -> U32:
  match s:
    case Span{a, b}:
      a

def Span.b(s: Span) -> U32:
  match s:
    case Span{a, b}:
      b

# The four checks
# ---------------

def long(+len: U32, x: Span) -> Bool:
  match x:
    case Span{a, b}:
      U32.is_eq((b - a : U32), len)

def future(+from: U32, x: Span) -> Bool:
  match x:
    case Span{a, b}:
      U32.is_le(from, a)

# x lies within the window w.
def within(x: Span, w: Span) -> Bool:
  match x w:
    case Span{a, b} Span{c, d}:
      Bool.and(U32.is_le(c, a), U32.is_le(b, d))

def inside(ws: List<&2, Span>, +x: Span) -> Bool:
  match ws:
    case Nil{}:
      False{}
    case w <> t:
      Bool.or(within(x, w), inside(t, x))

# x and y share a minute: each starts before the other ends.
def overlaps(x: Span, y: Span) -> Bool:
  match x y:
    case Span{a, b} Span{c, d}:
      Bool.and(U32.is_lt(a, d), U32.is_lt(c, b))

def free(bs: List<&2, Span>, +x: Span) -> Bool:
  match bs:
    case Nil{}:
      True{}
    case y <> t:
      Bool.and(Bool.not(overlaps(x, y)), free(t, x))

def ok(+from: U32, +len: U32, +ws: List<&2, Span>, +bs: List<&2, Span>, +x: Span) -> Bool:
  Bool.and(long(len, x), Bool.and(future(from, x), Bool.and(inside(ws, x), free(bs, x))))

# Candidates
# ----------

def steps(n: Nat, +len: U32, +a: U32) -> List<&2, Span>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Span{a, (a + len : U32)} <> steps(p, len, (a + len : U32))

def count.if(fits: Bool, +a: U32, +b: U32, +len: U32) -> Nat:
  match fits:
    case False{}:
      0n
    case True{}:
      U32.to_nat(((b - a : U32) / len : U32))

# The slots a window holds: len minutes each, back to back from its start.
def cut(+len: U32, w: Span) -> List<&2, Span>:
  match w:
    case Span{+a, +b}:
      steps(count.if(Bool.and(U32.is_lt(a, b), U32.is_lt(0, len)), a, b, len), len, a)

def cands(ws: List<&2, Span>, +len: U32) -> List<&2, Span>:
  match ws:
    case Nil{}:
      Nil{}
    case w <> t:
      List.append(&2, Span, cut(len, w), cands(t, len))

def keep(cs: List<&2, Span>, +from: U32, +len: U32, +ws: List<&2, Span>, +bs: List<&2, Span>) -> List<&2, Span>:
  match cs:
    case Nil{}:
      Nil{}
    case +x <> t:
      List.filter.put(Span, x, keep(t, from, len, ws, bs), ok(from, len, ws, bs, x))

# The open slots of len minutes, from `from` on, in the windows ws, around
# the busy spans bs.
def slots(+from: U32, +len: U32, +ws: List<&2, Span>, +bs: List<&2, Span>) -> List<&2, Span>:
  keep(cands(ws, len), from, len, ws, bs)

# What the laws say of a list of slots
# ------------------------------------

def all.long(xs: List<&2, Span>, +len: U32) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case x <> t:
      Bool.and(long(len, x), all.long(t, len))

def all.future(xs: List<&2, Span>, +from: U32) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case x <> t:
      Bool.and(future(from, x), all.future(t, from))

def all.inside(xs: List<&2, Span>, +ws: List<&2, Span>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case x <> t:
      Bool.and(inside(ws, x), all.inside(t, ws))

def all.free(xs: List<&2, Span>, +bs: List<&2, Span>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case x <> t:
      Bool.and(free(bs, x), all.free(t, bs))

def all.ok(xs: List<&2, Span>, +from: U32, +len: U32, +ws: List<&2, Span>, +bs: List<&2, Span>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case x <> t:
      Bool.and(ok(from, len, ws, bs, x), all.ok(t, from, len, ws, bs))

# Dates
# -----
#
# A date is "2026-11-18". Days count from 1970-01-01 (a Thursday), by the
# proleptic Gregorian calendar (Howard Hinnant's days_from_civil and
# civil_from_days).

def pad2(+n: U32) -> String:
  Bool.pick(String, U32.is_lt(n, 10), "0" ++ U32.show(n), U32.show(n))

def num(+s: String, +i: Nat, +n: Nat) -> U32:
  Maybe.default(&2, U32, U32.read(String.take(String.drop(s, i), n)), 0)

def days.go(+y: U32, +m: U32, +d: U32) -> U32:
  +era = (y / 400 : U32)
  +yoe = (y - (era * 400) : U32)
  +mp = ((m + 9) % 12 : U32)
  +doy = ((((153 * mp) + 2) / 5) + d - 1 : U32)
  +doe = ((yoe * 365) + (yoe / 4) - (yoe / 100) + doy : U32)
  ((era * 146097) + doe - 719468 : U32)

def days.of(+y: U32, +m: U32, +d: U32) -> U32:
  days.go(Bool.pick(U32, U32.is_le(m, 2), (y - 1 : U32), y), m, d)

def Date.days(+s: String) -> U32:
  days.of(num(s, 0n, 4n), num(s, 5n, 2n), num(s, 8n, 2n))

def date.show(+y: U32, +m: U32, +d: U32) -> String:
  U32.show(y) ++ "-" ++ pad2(m) ++ "-" ++ pad2(d)

def Date.of(+days: U32) -> String:
  +z = (days + 719468 : U32)
  +era = (z / 146097 : U32)
  +doe = (z - (era * 146097) : U32)
  +yoe = ((doe - (doe / 1460) + (doe / 36524) - (doe / 146096)) / 365 : U32)
  +doy = (doe - ((365 * yoe) + (yoe / 4) - (yoe / 100)) : U32)
  +mp = (((5 * doy) + 2) / 153 : U32)
  +d = (doy - ((((153 * mp) + 2) / 5)) + 1 : U32)
  +m = Bool.pick(U32, U32.is_lt(mp, 10), (mp + 3 : U32), (mp - 9 : U32))
  +y = (yoe + (era * 400) : U32)
  date.show(Bool.pick(U32, U32.is_le(m, 2), (y + 1 : U32), y), m, d)

# The date n days after s.
def Date.add(+s: String, +n: U32) -> String:
  Date.of((Date.days(s) + n : U32))

# 1 is Monday, 7 is Sunday (ISO 8601).
def Date.weekday(+s: String) -> U32:
  (((Date.days(s) + 3) % 7) + 1 : U32)

# A minute as UTC, "2026-11-18T15:00:00Z".
def Min.iso(+t: U32) -> String:
  +r = (t % 1440 : U32)
  Date.of((t / 1440 : U32)) ++ "T" ++ pad2((r / 60 : U32)) ++ ":" ++ pad2((r % 60 : U32)) ++ ":00Z"

# A second as UTC, "2026-11-18T15:00:07Z".
def Sec.iso(+t: U32) -> String:
  +m = (t / 60 : U32)
  +r = (m % 1440 : U32)
  Date.of((m / 1440 : U32)) ++ "T" ++ pad2((r / 60 : U32)) ++ ":" ++ pad2((r % 60 : U32)) ++ ":" ++ pad2((t % 60 : U32)) ++ "Z"
