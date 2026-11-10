import Base
import ./Json.bend as J

# What signing in to Google needs from the web, written in Bend: URL
# encoding both ways, query strings, base64url, and reading the one request
# the browser sends back to horas's loopback address.

# A name and a value in a query string or a form.
type Param is Data:
  Param{+k: String, +v: String}

# Percent-encoding
# ----------------

# The characters a URL carries as they are (RFC 3986 "unreserved").
def pct.keep(+code: U32) -> Bool:
  Bool.or(Bool.or(Bool.and(U32.is_ge(code, 65), U32.is_le(code, 90)), Bool.and(U32.is_ge(code, 97), U32.is_le(code, 122))),
  Bool.or(Bool.and(U32.is_ge(code, 48), U32.is_le(code, 57)),
  Bool.or(Bool.or(U32.is_eq(code, 45), U32.is_eq(code, 46)), Bool.or(U32.is_eq(code, 95), U32.is_eq(code, 126)))))

# A code point's UTF-8 bytes.
def utf8(+c: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_lt(c, 128), [c],
  Bool.pick(List<&2, U32>, U32.is_lt(c, 2048), [(192 .|. (c >> 6n) : U32), (128 .|. (c .&. 63) : U32)],
  Bool.pick(List<&2, U32>, U32.is_lt(c, 65536),
    [(224 .|. (c >> 12n) : U32), (128 .|. ((c >> 6n) .&. 63) : U32), (128 .|. (c .&. 63) : U32)],
    [(240 .|. (c >> 18n) : U32), (128 .|. ((c >> 12n) .&. 63) : U32), (128 .|. ((c >> 6n) .&. 63) : U32), (128 .|. (c .&. 63) : U32)])))

def pct.byte(+b: U32) -> String:
  SCon{'%', SCon{J.hex.digit((b >> 4n : U32)), SCon{J.hex.digit((b .&. 15 : U32)), SNil{}}}}

def pct.bytes(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}:
      ""
    case +b <> t:
      pct.byte(b) ++ pct.bytes(t)

def pct.char(+c: Char, +code: U32) -> String:
  Bool.pick(String, pct.keep(code), SCon{c, SNil{}}, pct.bytes(utf8(code)))

def pct(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, t}:
      pct.char(c, Char.to_u32(c)) ++ pct(t)

# Decoding, one character at a time: in text, after a %, after %X. (What
# Google sends back is ASCII, so a %XX is one character.)
type Pd is Data:
  PdText{}
  PdOne{}
  PdTwo{+hi: U32}

def pd.step(st: Pd, +c: Char, +out: List<&2, Char>) -> Pd & List<&2, Char>:
  match st:
    case PdText{}:
      Bool.pick(Pd & List<&2, Char>, U32.is_eq(Char.to_u32(c), 37), (PdOne{}, out),
        (PdText{}, Bool.pick(Char, U32.is_eq(Char.to_u32(c), 43), ' ', c) <> out))
    case PdOne{}:
      (PdTwo{J.hex.val(Char.to_u32(c))}, out)
    case PdTwo{hi}:
      (PdText{}, Char.from_u32((((hi .&. 15) << 4n) .|. (J.hex.val(Char.to_u32(c)) .&. 15) : U32)) <> out)

def pd.next(p: Pd & List<&2, Char>, +c: Char) -> Pd & List<&2, Char>:
  (st, out) = p
  pd.step(st, c, out)

def pd.out(p: Pd & List<&2, Char>) -> List<&2, Char>:
  (st, out) = p
  out

def pd.go(s: String, p: Pd & List<&2, Char>) -> List<&2, Char>:
  match s:
    case SNil{}:
      pd.out(p)
    case SCon{+c, t}:
      pd.go(t, pd.next(p, c))

def pct.dec(s: String) -> String:
  J.chars.str(pd.go(s, (PdText{}, Nil{})))

# Query strings and forms
# -----------------------

def param.show(p: Param) -> String:
  match p:
    case Param{k, v}:
      pct(k) ++ "=" ++ pct(v)

def query.go(ps: List<&2, Param>, first: Bool) -> String:
  match ps:
    case Nil{}:
      ""
    case p <> t:
      Bool.pick(String, first, "", "&") ++ param.show(p) ++ query.go(t, False{})

# "a=1&b=2", each name and value encoded: a URL's query, or a form's body.
def query(ps: List<&2, Param>) -> String:
  query.go(ps, True{})

def url(+base: String, ps: List<&2, Param>) -> String:
  base ++ "?" ++ query(ps)

# The value of name in the pairs of a query ("a=1", "b=2"), decoded.
def query.get(ps: List<&2, String>, +name: String) -> Maybe<&2, String>:
  match ps:
    case Nil{}:
      None{}
    case +p <> t:
      Bool.pick(Maybe<&2, String>, String.starts_with(p, name ++ "="),
        Some{pct.dec(String.drop(p, Nat.add(String.length(name), 1n)))},
        query.get(t, name))

# Bytes
# -----

# "0aff..." as bytes (a trailing odd digit is dropped).
def hex.bytes(s: String) -> List<&2, U32>:
  match s:
    case SCon{+a, SCon{+b, t}}:
      (((J.hex.val(Char.to_u32(a)) .&. 15) << 4n) .|. (J.hex.val(Char.to_u32(b)) .&. 15) : U32) <> hex.bytes(t)
    case _:
      Nil{}

def b64.char(+v: U32) -> Char:
  Bool.pick(Char, U32.is_lt(v, 26), Char.from_u32((v + 65 : U32)),
  Bool.pick(Char, U32.is_lt(v, 52), Char.from_u32((v + 71 : U32)),
  Bool.pick(Char, U32.is_lt(v, 62), Char.from_u32((v - 4 : U32)),
  Bool.pick(Char, U32.is_eq(v, 62), '-', '_'))))

# Bytes in base64url without padding (RFC 4648 section 5), as PKCE wants.
def b64url(xs: List<&2, U32>) -> String:
  match xs:
    case +a <> +b <> +c <> t:
      SCon{b64.char((a >> 2n : U32)), SCon{b64.char((((a .&. 3) << 4n) .|. (b >> 4n) : U32)),
        SCon{b64.char((((b .&. 15) << 2n) .|. (c >> 6n) : U32)), SCon{b64.char((c .&. 63 : U32)), b64url(t)}}}}
    case +a <> +b <> Nil{}:
      SCon{b64.char((a >> 2n : U32)), SCon{b64.char((((a .&. 3) << 4n) .|. (b >> 4n) : U32)),
        SCon{b64.char(((b .&. 15) << 2n : U32)), SNil{}}}}
    case +a <> Nil{}:
      SCon{b64.char((a >> 2n : U32)), SCon{b64.char(((a .&. 3) << 4n : U32)), SNil{}}}
    case _:
      SNil{}

# The browser's answer
# --------------------

# The second word of a request's first line: "/?state=..&code=..".
def req.target.of(ws: List<&2, String>) -> String:
  match ws:
    case m <> +t <> rest:
      t
    case _:
      ""

def req.query.of(ps: List<&2, String>) -> String:
  match ps:
    case p <> +q <> rest:
      q
    case _:
      ""

def first.line(xs: List<&2, String>) -> String:
  match xs:
    case +x <> t:
      x
    case Nil{}:
      ""

# The pairs of the query in an HTTP request.
def req.params(+req: String) -> List<&2, String>:
  String.split(req.query.of(String.split(req.target.of(String.split(first.line(String.lines(req)), ' ')), '?')), '&')

# What the browser brought back: the code to trade for tokens, Google's
# refusal, or some other request (the browser also asks for /favicon.ico).
type Got is Data:
  GotCode{+code: String}
  GotError{+err: String}
  GotOther{}

def got.code(c: Maybe<&2, String>, s: Maybe<&2, String>, +state: String) -> Got:
  match c s:
    case Some{+code} Some{+st}:
      Bool.pick(Got, String.eq(st, state), GotCode{code}, GotError{"the answer is for another login (state differs)"})
    case _ _:
      GotOther{}

def got.err(e: Maybe<&2, String>, +ps: List<&2, String>, +state: String) -> Got:
  match e:
    case Some{x}:
      GotError{x}
    case None{}:
      got.code(query.get(ps, "code"), query.get(ps, "state"), state)

# The request's meaning, if state is the one this login sent.
def Got.of(+req: String, +state: String) -> Got:
  got.err(query.get(req.params(req), "error"), req.params(req), state)

def Got.done(g: Got) -> Bool:
  match g:
    case GotOther{}:
      False{}
    case _:
      True{}

def page(+status: String, +msg: String) -> String:
  "HTTP/1.1 " ++ status ++ "\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" ++
  "<!doctype html><meta charset=utf-8><title>horas</title>" ++
  "<p style=\"font:20px sans-serif;margin:3em\">" ++ msg ++ "</p>\n"

# The page the browser shows for each answer.
def Got.page(g: Got) -> String:
  match g:
    case GotCode{c}:
      page("200 OK", "Google answered horas. You can close this tab; the terminal says whether signing in worked.")
    case GotError{e}:
      page("200 OK", "horas was not signed in. The terminal says why.")
    case GotOther{}:
      page("404 Not Found", "")
