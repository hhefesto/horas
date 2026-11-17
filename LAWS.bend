# The claims of horas's open slots (Slots.bend), the times `horas slots`
# publishes for booking a call. PROOF.bend proves them; a law that turns out
# false is reported, not reworded.
#
# For any time `from` (now, plus the notice asked for), slot length `len`,
# working windows `ws` and busy spans `bs`, every slot S.slots returns
#
#   lasts len minutes,
#   starts at or after `from` (so none is in the past),
#   lies inside one of the working windows,
#   shares no minute with any busy span.
#
# S.all.long and the others are "every slot in the list passes the check"; the
# checks themselves (S.long, S.future, S.inside, S.free, S.overlaps) are the
# definitions in Slots.bend, and tests/slots.bend tests them minute by minute
# against an independent count, since U32 arithmetic does not compute in a
# proof.

import Base
import ./Slots.bend as S

law slots_last_len:
  for +from: U32
  for +len: U32
  for +ws: List<&2, S.Span>
  for +bs: List<&2, S.Span>
  {S.all.long(S.slots(from, len, ws, bs), len) == True{} : Bool}

law slots_in_future:
  for +from: U32
  for +len: U32
  for +ws: List<&2, S.Span>
  for +bs: List<&2, S.Span>
  {S.all.future(S.slots(from, len, ws, bs), from) == True{} : Bool}

law slots_in_hours:
  for +from: U32
  for +len: U32
  for +ws: List<&2, S.Span>
  for +bs: List<&2, S.Span>
  {S.all.inside(S.slots(from, len, ws, bs), ws) == True{} : Bool}

law slots_miss_busy:
  for +from: U32
  for +len: U32
  for +ws: List<&2, S.Span>
  for +bs: List<&2, S.Span>
  {S.all.free(S.slots(from, len, ws, bs), bs) == True{} : Bool}
