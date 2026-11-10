import Base

# JSON as Google's Calendar API writes it, and as horas keeps its own files.
#
# Bend has no mutual recursion, so a list or an object is not a List inside
# the value but a chain of the same type: an array holds JCons cells ending in
# JNil, an object JField cells ending in JNil. Then one def walks any value.
# Reading is two passes that each go down their input once, so both end by
# structure: the lexer takes one character at a time (a state machine), the
# parser one token at a time (a stack of open arrays and objects).

type Json is Data:
  JNull{}
  JBool{+b: Bool}
  # A number, as written (horas never does arithmetic on one).
  JNum{+s: String}
  JStr{+s: String}
  JArr{+items: Json}
  JObj{+fields: Json}
  JCons{+head: Json, +tail: Json}
  JField{+key: String, +val: Json, +tail: Json}
  JNil{}

# Writing
# -------

def hex.digit(+v: U32) -> Char:
  Bool.pick(Char, U32.is_lt(v, 10), Char.from_u32((v + 48 : U32)), Char.from_u32((v + 87 : U32)))

def hex4(+v: U32) -> String:
  SCon{hex.digit(((v >> 12n) .&. 15 : U32)), SCon{hex.digit(((v >> 8n) .&. 15 : U32)),
    SCon{hex.digit(((v >> 4n) .&. 15 : U32)), SCon{hex.digit((v .&. 15 : U32)), SNil{}}}}}

def esc.code(+c: Char, +code: U32) -> String:
  Bool.pick(String, U32.is_eq(code, 34), "\\\"",
  Bool.pick(String, U32.is_eq(code, 92), "\\\\",
  Bool.pick(String, U32.is_eq(code, 10), "\\n",
  Bool.pick(String, U32.is_eq(code, 13), "\\r",
  Bool.pick(String, U32.is_eq(code, 9), "\\t",
  Bool.pick(String, U32.is_lt(code, 32), "\\u" ++ hex4(code),
    SCon{c, SNil{}}))))))

def esc(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, t}:
      esc.code(c, Char.to_u32(c)) ++ esc(t)

def Json.quote(s: String) -> String:
  "\"" ++ esc(s) ++ "\""

def show.sep(first: Bool) -> String:
  match first:
    case True{}:
      ""
    case False{}:
      ","

def show.go(j: Json, first: Bool) -> String:
  match j:
    case JNull{}:
      "null"
    case JBool{b}:
      Bool.pick(String, b, "true", "false")
    case JNum{s}:
      s
    case JStr{s}:
      Json.quote(s)
    case JArr{xs}:
      "[" ++ show.go(xs, True{}) ++ "]"
    case JObj{fs}:
      "{" ++ show.go(fs, True{}) ++ "}"
    case JCons{h, t}:
      show.sep(first) ++ show.go(h, True{}) ++ show.go(t, False{})
    case JField{k, v, t}:
      show.sep(first) ++ Json.quote(k) ++ ":" ++ show.go(v, True{}) ++ show.go(t, False{})
    case JNil{}:
      ""

def Json.show(j: Json) -> String:
  show.go(j, True{})

# Building
# --------

def Json.chain(xs: List<&2, Json>) -> Json:
  match xs:
    case Nil{}:
      JNil{}
    case h <> t:
      JCons{h, Json.chain(t)}

def Json.arr(xs: List<&2, Json>) -> Json:
  JArr{Json.chain(xs)}

def Json.strs(xs: List<&2, String>) -> Json:
  match xs:
    case Nil{}:
      JNil{}
    case h <> t:
      JCons{JStr{h}, Json.strs(t)}

# Reading values back
# -------------------

# The value under key, JNull{} if there is none.
def Json.get(j: Json, +key: String) -> Json:
  match j:
    case JObj{fs}:
      Json.get(fs, key)
    case JField{+k, v, t}:
      Bool.pick(Json, String.eq(k, key), v, Json.get(t, key))
    case _:
      JNull{}

def Json.str(j: Json) -> String:
  match j:
    case JStr{s}:
      s
    case JNum{s}:
      s
    case _:
      ""

def Json.at(j: Json, +key: String) -> String:
  Json.str(Json.get(j, key))

def Json.has(j: Json, +key: String) -> Bool:
  match j:
    case JObj{fs}:
      Json.has(fs, key)
    case JField{+k, v, t}:
      Bool.or(String.eq(k, key), Json.has(t, key))
    case _:
      False{}

# An array's items (or the cells of a chain).
def Json.items(j: Json) -> List<&2, Json>:
  match j:
    case JArr{xs}:
      Json.items(xs)
    case JCons{h, t}:
      h <> Json.items(t)
    case _:
      Nil{}

def Json.texts(j: Json) -> List<&2, String>:
  match j:
    case JArr{xs}:
      Json.texts(xs)
    case JCons{h, t}:
      Json.str(h) <> Json.texts(t)
    case _:
      Nil{}

# Lexing
# ------

type Tok is Data:
  # `{` when obj, `[` otherwise
  TOpen{+obj: Bool}
  TClose{}
  TColon{}
  TComma{}
  TStr{+s: String}
  # a number, true, false or null
  TAtom{+s: String}

# What a character is, between tokens.
type Cls is Data:
  KOpen{+obj: Bool}
  KClose{}
  KColon{}
  KComma{}
  KQuote{}
  KSpace{}
  KOther{}

def cls.code(+code: U32) -> Cls:
  Bool.pick(Cls, U32.is_eq(code, 123), KOpen{True{}},
  Bool.pick(Cls, U32.is_eq(code, 91), KOpen{False{}},
  Bool.pick(Cls, Bool.or(U32.is_eq(code, 125), U32.is_eq(code, 93)), KClose{},
  Bool.pick(Cls, U32.is_eq(code, 58), KColon{},
  Bool.pick(Cls, U32.is_eq(code, 44), KComma{},
  Bool.pick(Cls, U32.is_eq(code, 34), KQuote{},
  Bool.pick(Cls, U32.is_le(code, 32), KSpace{},
    KOther{})))))))

def cls(c: Char) -> Cls:
  cls.code(Char.to_u32(c))

# The lexer's state: between tokens, in a string (its characters so far,
# last first), just after a backslash, in a \u escape (digits left, value so
# far), or in an atom.
type Lx is Data:
  LOut{}
  LStr{+acc: List<&2, Char>}
  LEsc{+acc: List<&2, Char>}
  LHex{+acc: List<&2, Char>, +n: Nat, +v: U32}
  LAtom{+acc: List<&2, Char>}

def chars.str(acc: List<&2, Char>) -> String:
  String.from_list(List.reverse(&2, Char, acc))

def lx.out(k: Cls, +c: Char, out: List<&2, Tok>) -> Lx & List<&2, Tok>:
  match k:
    case KOpen{o}:
      (LOut{}, TOpen{o} <> out)
    case KClose{}:
      (LOut{}, TClose{} <> out)
    case KColon{}:
      (LOut{}, TColon{} <> out)
    case KComma{}:
      (LOut{}, TComma{} <> out)
    case KQuote{}:
      (LStr{Nil{}}, out)
    case KSpace{}:
      (LOut{}, out)
    case KOther{}:
      (LAtom{[c]}, out)

def lx.str(+acc: List<&2, Char>, +c: Char, +code: U32, +out: List<&2, Tok>) -> Lx & List<&2, Tok>:
  Bool.pick(Lx & List<&2, Tok>, U32.is_eq(code, 34), (LOut{}, TStr{chars.str(acc)} <> out),
  Bool.pick(Lx & List<&2, Tok>, U32.is_eq(code, 92), (LEsc{acc}, out),
    (LStr{c <> acc}, out)))

# The character an escape stands for (\n, \t, ...; \" \\ \/ stand for themselves).
def unesc(+c: Char, +code: U32) -> Char:
  Bool.pick(Char, U32.is_eq(code, 110), Char.from_u32(10),
  Bool.pick(Char, U32.is_eq(code, 116), Char.from_u32(9),
  Bool.pick(Char, U32.is_eq(code, 114), Char.from_u32(13),
  Bool.pick(Char, U32.is_eq(code, 98), Char.from_u32(8),
  Bool.pick(Char, U32.is_eq(code, 102), Char.from_u32(12),
    c)))))

def lx.esc(+acc: List<&2, Char>, +c: Char, +code: U32, +out: List<&2, Tok>) -> Lx & List<&2, Tok>:
  Bool.pick(Lx & List<&2, Tok>, U32.is_eq(code, 117), (LHex{acc, 4n, 0}, out),
    (LStr{unesc(c, code) <> acc}, out))

def hex.val(+code: U32) -> U32:
  Bool.pick(U32, U32.is_le(code, 57), (code - 48 : U32),
  Bool.pick(U32, U32.is_le(code, 70), (code - 55 : U32),
    (code - 87 : U32)))

def lx.hex.fin(acc: List<&2, Char>, n: Nat, +v: U32) -> Lx:
  match n:
    case 0n:
      LStr{Char.from_u32(v) <> acc}
    case 1n+p:
      LHex{acc, 1n+p, v}

def lx.hex(acc: List<&2, Char>, n: Nat, +v: U32, out: List<&2, Tok>) -> Lx & List<&2, Tok>:
  match n:
    case 0n:
      (LStr{acc}, out)
    case 1n+p:
      (lx.hex.fin(acc, p, v), out)

def lx.atom(acc: List<&2, Char>, k: Cls, +c: Char, out: List<&2, Tok>) -> Lx & List<&2, Tok>:
  match k:
    case KOther{}:
      (LAtom{c <> acc}, out)
    case KOpen{o}:
      lx.out(KOpen{o}, c, TAtom{chars.str(acc)} <> out)
    case KClose{}:
      lx.out(KClose{}, c, TAtom{chars.str(acc)} <> out)
    case KColon{}:
      lx.out(KColon{}, c, TAtom{chars.str(acc)} <> out)
    case KComma{}:
      lx.out(KComma{}, c, TAtom{chars.str(acc)} <> out)
    case KQuote{}:
      lx.out(KQuote{}, c, TAtom{chars.str(acc)} <> out)
    case KSpace{}:
      lx.out(KSpace{}, c, TAtom{chars.str(acc)} <> out)

def lx.next(st: Lx, +c: Char, out: List<&2, Tok>) -> Lx & List<&2, Tok>:
  match st:
    case LOut{}:
      lx.out(cls(c), c, out)
    case LStr{acc}:
      lx.str(acc, c, Char.to_u32(c), out)
    case LEsc{acc}:
      lx.esc(acc, c, Char.to_u32(c), out)
    case LHex{acc, n, +v}:
      lx.hex(acc, n, ((v << 4n) + hex.val(Char.to_u32(c)) : U32), out)
    case LAtom{acc}:
      lx.atom(acc, cls(c), c, out)

def lx.end.go(st: Lx, out: List<&2, Tok>) -> List<&2, Tok>:
  match st:
    case LAtom{acc}:
      TAtom{chars.str(acc)} <> out
    case _:
      out

def lx.end(p: Lx & List<&2, Tok>) -> List<&2, Tok>:
  (st, out) = p
  lx.end.go(st, out)

def lx.step(p: Lx & List<&2, Tok>, +c: Char) -> Lx & List<&2, Tok>:
  (st, out) = p
  lx.next(st, c, out)

# The tokens of s, last first.
def lex(s: String, p: Lx & List<&2, Tok>) -> List<&2, Tok>:
  match s:
    case SNil{}:
      lx.end(p)
    case SCon{+c, t}:
      lex(t, lx.step(p, c))

# Parsing
# -------

# An open array (its items so far, last first) or object (its fields so far,
# last first, and the key read for the next value, if any).
type Kv is Data:
  Kv{+k: String, +v: Json}

type Frame is Data:
  FArr{+xs: List<&2, Json>}
  FObj{+fs: List<&2, Kv>, +key: Maybe<&2, String>}

def chain.rev(xs: List<&2, Json>, acc: Json) -> Json:
  match xs:
    case Nil{}:
      acc
    case h <> t:
      chain.rev(t, JCons{h, acc})

def fields.rev(fs: List<&2, Kv>, acc: Json) -> Json:
  match fs:
    case Nil{}:
      acc
    case Kv{k, v} <> t:
      fields.rev(t, JField{k, v, acc})

def frame.close(f: Frame) -> Json:
  match f:
    case FArr{xs}:
      JArr{chain.rev(xs, JNil{})}
    case FObj{fs, k}:
      JObj{fields.rev(fs, JNil{})}

def frame.open(obj: Bool) -> Frame:
  match obj:
    case True{}:
      FObj{Nil{}, None{}}
    case False{}:
      FArr{Nil{}}

# A finished value goes into the frame it is in, or is the whole document.
def ps.put(v: Json, stack: List<&2, Frame>, done: Maybe<&2, Json>) -> List<&2, Frame> & Maybe<&2, Json>:
  match stack:
    case Nil{}:
      (Nil{}, Some{v})
    case FArr{xs} <> r:
      (FArr{v <> xs} <> r, done)
    case FObj{fs, Some{k}} <> r:
      (FObj{Kv{k, v} <> fs, None{}} <> r, done)
    case FObj{fs, None{}} <> r:
      (FObj{fs, None{}} <> r, done)

def ps.str(s: String, stack: List<&2, Frame>, done: Maybe<&2, Json>) -> List<&2, Frame> & Maybe<&2, Json>:
  match stack:
    case FObj{fs, None{}} <> r:
      (FObj{fs, Some{s}} <> r, done)
    case Nil{}:
      ps.put(JStr{s}, Nil{}, done)
    case FArr{xs} <> r:
      ps.put(JStr{s}, FArr{xs} <> r, done)
    case FObj{fs, Some{k}} <> r:
      ps.put(JStr{s}, FObj{fs, Some{k}} <> r, done)

def ps.close(stack: List<&2, Frame>, done: Maybe<&2, Json>) -> List<&2, Frame> & Maybe<&2, Json>:
  match stack:
    case Nil{}:
      (Nil{}, done)
    case f <> r:
      ps.put(frame.close(f), r, done)

def atom(+s: String) -> Json:
  Bool.pick(Json, String.eq(s, "true"), JBool{True{}},
  Bool.pick(Json, String.eq(s, "false"), JBool{False{}},
  Bool.pick(Json, String.eq(s, "null"), JNull{},
    JNum{s})))

def ps.step(t: Tok, stack: List<&2, Frame>, done: Maybe<&2, Json>) -> List<&2, Frame> & Maybe<&2, Json>:
  match t:
    case TOpen{o}:
      (frame.open(o) <> stack, done)
    case TClose{}:
      ps.close(stack, done)
    case TColon{}:
      (stack, done)
    case TComma{}:
      (stack, done)
    case TStr{s}:
      ps.str(s, stack, done)
    case TAtom{s}:
      ps.put(atom(s), stack, done)

def ps.next(t: Tok, p: List<&2, Frame> & Maybe<&2, Json>) -> List<&2, Frame> & Maybe<&2, Json>:
  (stack, done) = p
  ps.step(t, stack, done)

def ps.done(p: List<&2, Frame> & Maybe<&2, Json>) -> Maybe<&2, Json>:
  (stack, done) = p
  done

def ps.go(toks: List<&2, Tok>, p: List<&2, Frame> & Maybe<&2, Json>) -> Maybe<&2, Json>:
  match toks:
    case Nil{}:
      ps.done(p)
    case t <> rest:
      ps.go(rest, ps.next(t, p))

# The document s, if it is one. Lenient: it reads every well-formed document
# right, and does not reject all ill-formed ones.
def Json.parse(s: String) -> Maybe<&2, Json>:
  ps.go(List.reverse(&2, Tok, lex(s, (LOut{}, Nil{}))), (Nil{}, None{}))

def Json.read(s: String) -> Json:
  Maybe.default(&2, Json, Json.parse(s), JNull{})
