import Base
import ../Slots.bend as S

# Tests of Slots.bend that the proofs cannot give: that the four checks mean
# what they say, minute by minute, and that the dates are right.
#
# The minute check below does not use S.overlaps, S.within or U32 subtraction:
# it walks every minute of a slot and asks of each whether a busy span holds
# it and whether the window does. Every slot S.slots returns must pass it,
# and the fixture's slots must be exactly the ones worked out by hand.
# `bend tests/slots.bend` prints "ok" or a FAIL line per test and exits 1 if
# any failed.

def holds(+m: U32, y: S.Span) -> Bool:
  match y:
    case S.Span{c, d}:
      Bool.and(U32.is_le(c, m), U32.is_lt(m, d))

def held(bs: List<&2, S.Span>, +m: U32) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case y <> t:
      Bool.or(holds(m, y), held(t, m))

# Every one of the n minutes from m on is in the window w, and in no busy span.
def walk(n: Nat, +m: U32, +w: S.Span, +bs: List<&2, S.Span>) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      Bool.and(Bool.and(holds(m, w), Bool.not(held(bs, m))), walk(p, (m + 1 : U32), w, bs))

def some.window(ws: List<&2, S.Span>, +n: Nat, +m: U32, +bs: List<&2, S.Span>) -> Bool:
  match ws:
    case Nil{}:
      False{}
    case +w <> t:
      Bool.or(walk(n, m, w, bs), some.window(t, n, m, bs))

# The end is the start plus len, counted one minute at a time.
def ends(n: Nat, +m: U32, +b: U32) -> Bool:
  match n:
    case 0n:
      U32.is_eq(m, b)
    case 1n+p:
      ends(p, (m + 1 : U32), b)

def slot.ok(+from: U32, +len: Nat, +ws: List<&2, S.Span>, +bs: List<&2, S.Span>, x: S.Span) -> Bool:
  match x:
    case S.Span{+a, +b}:
      Bool.and(Bool.and(ends(len, a, b), U32.is_le(from, a)), some.window(ws, len, a, bs))

def slots.ok(xs: List<&2, S.Span>, +from: U32, +len: Nat, +ws: List<&2, S.Span>, +bs: List<&2, S.Span>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case x <> t:
      Bool.and(slot.ok(from, len, ws, bs, x), slots.ok(t, from, len, ws, bs))

# No two slots share a minute, and they come in order.
def apart(xs: List<&2, S.Span>) -> Bool:
  match xs:
    case +x <> +y <> t:
      Bool.and(U32.is_le(S.Span.b(x), S.Span.a(y)), apart(y <> t))
    case _:
      True{}

def starts(xs: List<&2, S.Span>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      S.Span.a(x) <> starts(t)

def same(xs: List<&2, U32>, ys: List<&2, U32>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      True{}
    case +x <> xt +y <> yt:
      Bool.and(U32.is_eq(x, y), same(xt, yt))
    case _ _:
      False{}

def show(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}:
      ""
    case +x <> t:
      U32.show(x) ++ " " ++ show(t)

# Dates, against a calendar written another way (month lengths), and against
# GNU date for a few days.
def leap(+y: U32) -> Bool:
  Bool.or(Bool.and(U32.is_eq((y % 4 : U32), 0), U32.is_ne((y % 100 : U32), 0)), U32.is_eq((y % 400 : U32), 0))

def mdays(+y: U32, +m: U32) -> U32:
  Bool.pick(U32, U32.is_eq(m, 2), Bool.pick(U32, leap(y), 29, 28),
  Bool.pick(U32, Bool.or(Bool.or(U32.is_eq(m, 4), U32.is_eq(m, 6)), Bool.or(U32.is_eq(m, 9), U32.is_eq(m, 11))), 30, 31))

def next3(+y: U32, +m: U32, +d: U32) -> String:
  Bool.pick(String, U32.is_lt(d, mdays(y, m)), S.date.show(y, m, (d + 1 : U32)),
  Bool.pick(String, U32.is_lt(m, 12), S.date.show(y, (m + 1 : U32), 1), S.date.show((y + 1 : U32), 1, 1)))

def next(+s: String) -> String:
  next3(S.num(s, 0n, 4n), S.num(s, 5n, 2n), S.num(s, 8n, 2n))

# From day n on, k days: Date.of and Date.days invert each other, and the
# next day is the calendar's next day.
def dates.ok(k: Nat, +n: U32) -> Bool:
  match k:
    case 0n:
      True{}
    case 1n+p:
      +s : String = S.Date.of(n)
      Bool.and(Bool.and(U32.is_eq(S.Date.days(s), n), String.eq(S.Date.of((n + 1 : U32)), next(s))),
        dates.ok(p, (n + 1 : U32)))

def say(ok: Bool, +name: String, +got: String) -> IO(U32):
  match ok:
    case True{}:
      do IO<U32>:
        IO.print("ok   " ++ name)
        return 0
    case False{}:
      do IO<U32>:
        IO.print("FAIL " ++ name ++ ": " ++ got)
        return 1

def finish.go(ok: Bool, +bad: U32) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("all slot tests pass")
    case False{}:
      IO.die(Unit, 1, U32.show(bad) ++ " slot tests failed")

# The fixture: two working days 09:00-17:00 (day 0 from minute 0), a short
# window that holds one slot, an empty one, and busy spans that overlap,
# touch and hide inside slots.
def ws() -> List<&2, S.Span>:
  [S.Span{540, 1020}, S.Span{1980, 2460}, S.Span{3000, 3050}, S.Span{4000, 3900}]

def bs() -> List<&2, S.Span>:
  [S.Span{615, 645}, S.Span{700, 700}, S.Span{1000, 1100}, S.Span{1020, 1050},
   S.Span{2000, 2001}, S.Span{500, 540}, S.Span{3030, 3100}]

# Worked out by hand: day 0 loses 540 and 570 (before 600), 600 and 630
# (615-645), 690 (the empty span at 700 counts: a slot is not offered across
# an event's mark) and 990 (1000-1100); day 1 loses 1980 (2000-2001); 3000
# fits once; the window 4000-3900 holds nothing.
def expected() -> List<&2, U32>:
  [660, 720, 750, 780, 810, 840, 870, 900, 930, 960,
   2010, 2040, 2070, 2100, 2130, 2160, 2190, 2220, 2250, 2280, 2310, 2340, 2370, 2400, 2430,
   3000]

def main() -> IO(Unit):
  do IO<Unit>:
    +sl : List<&2, S.Span> = S.slots(600, 30, ws(), bs())
    a : U32 <- say(same(starts(sl), expected()), "the fixture's slots are the ones worked out by hand", show(starts(sl)))
    b : U32 <- say(slots.ok(sl, 600, 30n, ws(), bs()), "every slot passes the minute-by-minute check", show(starts(sl)))
    c : U32 <- say(apart(sl), "slots are in order and share no minute", show(starts(sl)))
    +all : List<&2, S.Span> = S.slots(0, 30, [S.Span{0, 1440}], Nil{})
    d : U32 <- say(Nat.is_eq(List.length(&2, S.Span, all), 48n), "a free day of 24 hours holds 48 slots", show(starts(all)))
    +none : List<&2, S.Span> = S.slots(0, 30, [S.Span{540, 1020}], [S.Span{0, 1440}])
    f : U32 <- say(List.is_empty(&2, S.Span, none), "a day that is all busy has no slot", show(starts(none)))
    g : U32 <- say(Bool.and(U32.is_eq(S.Date.days("1970-01-01"), 0), Bool.and(U32.is_eq(S.Date.days("2000-02-29"), 11016),
                   Bool.and(U32.is_eq(S.Date.days("2000-03-01"), 11017), Bool.and(U32.is_eq(S.Date.days("2026-11-17"), 20774),
                   U32.is_eq(S.Date.days("2100-03-01"), 47541))))), "days since 1970 agree with GNU date", "")
    h : U32 <- say(Bool.and(U32.is_eq(S.Date.weekday("2026-11-17"), 2), Bool.and(U32.is_eq(S.Date.weekday("1970-01-01"), 4),
                   U32.is_eq(S.Date.weekday("2100-03-01"), 1))), "weekdays agree with GNU date", "")
    i : U32 <- say(Bool.and(String.eq(S.Min.iso(29900000), "2026-11-06T21:20:00Z"), String.eq(S.Sec.iso(1795000007), "2026-11-18T11:06:47Z")),
                   "UTC times agree with GNU date", S.Min.iso(29900000) ++ " " ++ S.Sec.iso(1795000007))
    j : U32 <- say(dates.ok(73049n, 0), "every day of 1970-2169 round-trips and steps like the calendar", "")
    +bad : U32 = (a + b + c + d + f + g + h + i + j : U32)
    finish.go(U32.is_eq(bad, 0), bad)
