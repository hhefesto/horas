import Base
import ./Json.bend as J
import ./Cal.bend as C
import ./Http.bend as H

# horas: the command line. One copy of the calendar per machine, in
# $HORAS_DIR/copy.json (default ~/.local/share/horas); `sync` joins it with
# Google Calendar's copy and with other machines' copies over ssh, so each
# ends with every edit either saw.
#
#   horas add TITLE WHEN [--end WHEN] [--at PLACE] [--notes TEXT]
#   horas list
#   horas show ID
#   horas edit ID [--title T] [--start WHEN] [--end WHEN] [--at P] [--notes N]
#   horas rm ID
#   horas sync [PEER...]      (a PEER is an ssh host, or google; by default
#                             google once signed in, then the lines of
#                             $HORAS_DIR/peers; exits 1 if one is missed)
#   horas export              (the copy, as JSON: what a peer's sync reads)
#   horas import FILE         (joins a copy written by export)
#   horas login [ACCOUNT]     (signs this machine in to Google, once)
#
# WHEN is a day, 2026-11-29, or a time there, 2026-11-29T19:00 (or with a
# space for the T), in $HORAS_TZ (default America/Mexico_City). Without
# --end, an event lasts an hour, or the whole day. ID is any prefix of an
# event's id that names one event.

# Running programs, files, the environment
# ----------------------------------------

# What a program did: its exit status, stdout, stderr (127: it did not start).
type Ran is Data:
  Ran{+code: U32, +out: String, +err: String}

def ran.of(v: U32 & (String & String)) -> Ran:
  (code, oe) = v
  (out, err) = oe
  Ran{code, out, err}

def ran(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Ran:
  match r:
    case Done{v}:
      ran.of(v)
    case Fail{(code, msg)}:
      Ran{127, "", msg}

def run(prog: String, args: List<String>, input: String) -> IO(Ran):
  do IO<Ran>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(prog, args, input, 67108864, 120000)
    return ran(r)

def out.of(r: Ran) -> String:
  match r:
    case Ran{c, o, e}:
      String.trim(o)

def must.if(ok: Bool, what: String, +err: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "horas: " ++ what ++ " failed: " ++ err)

def must(what: String, r: Ran) -> IO(Unit):
  match r:
    case Ran{+c, o, +e}:
      must.if(U32.is_eq(c, 0), what, e)

def res.or(r: Result<&1, &1, U32 & String, String>, d: String) -> String:
  match r:
    case Done{v}:
      v
    case Fail{e}:
      d

def env.get(name: String, d: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    return res.or(r, d)

def file.text(r: Result<&1, &1, U32 & String, String>) -> Maybe<&2, String>:
  match r:
    case Done{s}:
      Some{s}
    case Fail{e}:
      None{}

def file.got(p: File & Result<&1, &1, U32 & String, String>) -> IO(Maybe<&2, String>):
  (f, r) = p
  do IO<Maybe<&2, String>>:
    File.close(f)
    return file.text(r)

def file.opened(r: Result<&1, &1, U32 & String, File>) -> IO(Maybe<&2, String>):
  match r:
    case Fail{e}:
      IO.pure(Maybe<&2, String>, None{})
    case Done{f}:
      do IO<Maybe<&2, String>>:
        p : File & Result<&1, &1, U32 & String, String> <- File.read(f, 67108864)
        file.got(p)

# A file's text, or None if it cannot be read (it does not exist yet).
def file.read(path: String) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    file.opened(r)

def file.wrote(p: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, r) = p
  do IO<Unit>:
    File.close(f)
    IO.try(Unit, IO.pure(Result<&1, &1, U32 & String, Unit>, r))

def file.write(path: String, data: String) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "w"))
    p : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, data)
    file.wrote(p)

def text.or(m: Maybe<&2, String>, d: String) -> String:
  match m:
    case None{}:
      d
    case Some{s}:
      String.trim(s)

def now() -> IO(String):
  do IO<String>:
    r : Ran <- run("date", ["-u", "+%Y-%m-%dT%H:%M:%S.%3NZ"], "")
    return out.of(r)

# Where this machine keeps its copy, who it is, its zone, and the command a
# peer runs horas by.
type Env is Data:
  Env{+dir: String, +who: String, +zone: String, +remote: String}

def env.dir(e: Env) -> String:
  match e:
    case Env{d, w, z, r}:
      d

def env.who(e: Env) -> String:
  match e:
    case Env{d, w, z, r}:
      w

def env.zone(e: Env) -> String:
  match e:
    case Env{d, w, z, r}:
      z

def env.remote(e: Env) -> String:
  match e:
    case Env{d, w, z, r}:
      r

def copy.path(+e: Env) -> String:
  env.dir(e) ++ "/copy.json"

# Times
# -----

def leap(+y: U32) -> Bool:
  Bool.or(Bool.and(U32.is_eq((y % 4 : U32), 0), U32.is_ne((y % 100 : U32), 0)), U32.is_eq((y % 400 : U32), 0))

def mdays(+y: U32, +m: U32) -> U32:
  Bool.pick(U32, U32.is_eq(m, 2), Bool.pick(U32, leap(y), 29, 28),
  Bool.pick(U32, Bool.or(Bool.or(U32.is_eq(m, 4), U32.is_eq(m, 6)), Bool.or(U32.is_eq(m, 9), U32.is_eq(m, 11))), 30, 31))

def num(+s: String, +i: Nat, +n: Nat) -> U32:
  Maybe.default(&2, U32, U32.read(String.take(String.drop(s, i), n)), 0)

def pad2(+n: U32) -> String:
  Bool.pick(String, U32.is_lt(n, 10), "0" ++ U32.show(n), U32.show(n))

def ymd(+y: U32, +m: U32, +d: U32) -> String:
  U32.show(y) ++ "-" ++ pad2(m) ++ "-" ++ pad2(d)

def date.next3(+y: U32, +m: U32, +d: U32) -> String:
  Bool.pick(String, U32.is_lt(d, mdays(y, m)), ymd(y, m, (d + 1 : U32)),
  Bool.pick(String, U32.is_lt(m, 12), ymd(y, (m + 1 : U32), 1), ymd((y + 1 : U32), 1, 1)))

# The day after a day.
def date.next(+s: String) -> String:
  date.next3(num(s, 0n, 4n), num(s, 5n, 2n), num(s, 8n, 2n))

def ch.is(+c: Char, +k: Char) -> Bool:
  U32.is_eq(Char.to_u32(c), Char.to_u32(k))

# A character fits a pattern character: d is a digit, T is T or a space.
def ch.fits(+c: Char, +k: Char) -> Bool:
  Bool.pick(Bool, ch.is(k, 'd'), Char.is_digit(c),
  Bool.pick(Bool, ch.is(k, 'T'), Bool.or(ch.is(c, 'T'), ch.is(c, ' ')), ch.is(c, k)))

def shape(s: String, p: String) -> Bool:
  match s p:
    case SNil{} SNil{}:
      True{}
    case SCon{+c, st} SCon{+k, pt}:
      Bool.and(ch.fits(c, k), shape(st, pt))
    case _ _:
      False{}

def at.of(+s: String, +zone: String, secs: String) -> C.When:
  C.At{String.take(s, 10n) ++ "T" ++ String.take(String.drop(s, 11n), 5n) ++ secs, zone}

def When.parse(+s: String, +zone: String) -> Maybe<&2, C.When>:
  Bool.pick(Maybe<&2, C.When>, shape(s, "dddd-dd-dd"), Some{C.Day{s}},
  Bool.pick(Maybe<&2, C.When>, shape(s, "dddd-dd-ddTdd:dd"), Some{at.of(s, zone, ":00")},
  Bool.pick(Maybe<&2, C.When>, shape(s, "dddd-dd-ddTdd:dd:dd"), Some{at.of(s, zone, String.drop(s, 16n))},
    None{})))

def hour.next(+t: String, +z: String) -> C.When:
  Bool.pick(C.When, U32.is_lt(num(t, 11n, 2n), 23),
    C.At{String.take(t, 11n) ++ pad2((num(t, 11n, 2n) + 1 : U32)) ++ String.drop(t, 13n), z},
    C.At{date.next(String.take(t, 10n)) ++ "T00" ++ String.drop(t, 13n), z})

# Where an event that starts at w ends when no end is given.
def When.after(w: C.When) -> C.When:
  match w:
    case C.NoTime{}:
      C.NoTime{}
    case C.Day{+d}:
      C.Day{date.next(d)}
    case C.At{+t, +z}:
      hour.next(t, z)

# Options
# -------

type Opts is Data:
  Opts{+title: Maybe<&2, String>, +start: Maybe<&2, String>, +end: Maybe<&2, String>,
       +place: Maybe<&2, String>, +notes: Maybe<&2, String>}

def opts.none() -> Opts:
  Opts{None{}, None{}, None{}, None{}, None{}}

def opts.title(o: Opts, +v: String) -> Opts:
  match o:
    case Opts{t, s, e, p, n}:
      Opts{Some{v}, s, e, p, n}

def opts.start(o: Opts, +v: String) -> Opts:
  match o:
    case Opts{t, s, e, p, n}:
      Opts{t, Some{v}, e, p, n}

def opts.end(o: Opts, +v: String) -> Opts:
  match o:
    case Opts{t, s, e, p, n}:
      Opts{t, s, Some{v}, p, n}

def opts.place(o: Opts, +v: String) -> Opts:
  match o:
    case Opts{t, s, e, p, n}:
      Opts{t, s, e, Some{v}, n}

def opts.notes(o: Opts, +v: String) -> Opts:
  match o:
    case Opts{t, s, e, p, n}:
      Opts{t, s, e, p, Some{v}}

def opts.go(xs: List<String>, o: Opts) -> Maybe<&2, Opts>:
  match xs:
    case Nil{}:
      Some{o}
    case "--title" <> +v <> t:
      opts.go(t, opts.title(o, v))
    case "--start" <> +v <> t:
      opts.go(t, opts.start(o, v))
    case "--end" <> +v <> t:
      opts.go(t, opts.end(o, v))
    case "--at" <> +v <> t:
      opts.go(t, opts.place(o, v))
    case "--notes" <> +v <> t:
      opts.go(t, opts.notes(o, v))
    case _:
      None{}

def when.or(m: Maybe<&2, String>, +zone: String, old: C.When) -> Maybe<&2, C.When>:
  match m:
    case None{}:
      Some{old}
    case Some{+s}:
      When.parse(s, zone)

# A start moved to or past the end takes the end along (Google refuses an
# event that ends before it starts).
def end.fit(+st: C.When, +en: C.When) -> C.When:
  Bool.pick(C.When, String.is_ge(C.When.key(st), C.When.key(en)), When.after(st), en)

def body.edit(b: C.Body, o: Opts, +zone: String) -> Maybe<&2, C.Body>:
  match b o:
    case C.Body{l, ti, no, pl, st, en, rr} Opts{t, s, e, p, n}:
      do Maybe<&2, C.Body>:
        +st2 : C.When <- when.or(s, zone, st)
        +en2 : C.When <- when.or(e, zone, en)
        return C.Body{l, Maybe.default(&2, String, t, ti), Maybe.default(&2, String, n, no),
                      Maybe.default(&2, String, p, pl), st2, end.fit(st2, en2), rr}

def body.kill(b: C.Body) -> C.Body:
  match b:
    case C.Body{l, ti, no, pl, st, en, rr}:
      C.Body{False{}, ti, no, pl, st, en, rr}

# A new event: the title and start given, all else from the options.
def body.new(+title: String, +start: String, o: Opts, +zone: String) -> Maybe<&2, C.Body>:
  do Maybe<&2, C.Body>:
    +st : C.When <- When.parse(start, zone)
    return C.Body{True{}, title, "", "", st, When.after(st), []}

def body.add(+title: String, +start: String, o: Maybe<&2, Opts>, +zone: String) -> Maybe<&2, C.Body>:
  do Maybe<&2, C.Body>:
    +os : Opts <- o
    b : C.Body <- body.new(title, start, os, zone)
    body.edit(b, os, zone)

# The copy
# --------

def copy.parsed(m: Maybe<&2, J.Json>, +what: String) -> IO(List<&2, C.Rec>):
  match m:
    case None{}:
      IO.die(List<&2, C.Rec>, 1, "horas: " ++ what ++ " is not JSON; nothing was changed")
    case Some{j}:
      IO.pure(List<&2, C.Rec>, C.Copy.of.json(j))

def copy.text(m: Maybe<&2, String>, +what: String, missing: List<&2, C.Rec>) -> IO(List<&2, C.Rec>):
  match m:
    case None{}:
      IO.pure(List<&2, C.Rec>, missing)
    case Some{s}:
      copy.parsed(J.Json.parse(s), what)

def load(+e: Env) -> IO(List<&2, C.Rec>):
  do IO<List<&2, C.Rec>>:
    m : Maybe<&2, String> <- file.read(copy.path(e))
    copy.text(m, copy.path(e), [])

# The new copy goes beside the old one, then over it, so a crash leaves one
# whole copy.
def save(+e: Env, xs: List<&2, C.Rec>) -> IO(Unit):
  do IO<Unit>:
    +p : String = copy.path(e)
    file.write(p ++ ".tmp", J.Json.show(C.Copy.json(xs)) ++ "\n")
    r : Ran <- run("mv", ["-f", p ++ ".tmp", p], "")
    must("mv", r)

def one(xs: List<&2, C.Rec>, +p: String) -> IO(C.Rec):
  match xs:
    case x <> Nil{}:
      IO.pure(C.Rec, x)
    case Nil{}:
      IO.die(C.Rec, 1, "horas: no event's id starts with " ++ p)
    case _:
      IO.die(C.Rec, 1, "horas: more than one event's id starts with " ++ p)

def pick(+copy: List<&2, C.Rec>, +p: String) -> IO(C.Rec):
  one(C.Copy.prefixed(copy, p), p)

# An edit here: the record, with the next stamp, joins the copy.
def put(+e: Env, +copy: List<&2, C.Rec>, +id: String, b: C.Body, +what: String) -> IO(Unit):
  do IO<Unit>:
    +t : String <- now()
    +s : C.Stamp = C.Stamp.next(t, env.who(e), C.Copy.last(copy, C.Stamp.zero()))
    save(e, C.join(copy, [C.Rec{id, s, b}]))
    IO.print(String.take(id, 8n) ++ "  " ++ what)

def body.or(m: Maybe<&2, C.Body>) -> IO(C.Body):
  match m:
    case None{}:
      IO.die(C.Body, 2, "horas: a WHEN is 2026-11-29 or 2026-11-29T19:00; an option is --title, --start, --end, --at or --notes, each with a value")
    case Some{b}:
      IO.pure(C.Body, b)

# Commands
# --------

def rand.u32(r: Result<&1, &1, U32 & String, U32>) -> U32:
  match r:
    case Done{v}:
      v
    case Fail{e}:
      0

def new.id() -> IO(String):
  do IO<String>:
    a : Result<&1, &1, U32 & String, U32> <- IO.random_u32()
    b : Result<&1, &1, U32 & String, U32> <- IO.random_u32()
    c : Result<&1, &1, U32 & String, U32> <- IO.random_u32()
    d : Result<&1, &1, U32 & String, U32> <- IO.random_u32()
    return C.Id.of([rand.u32(a), rand.u32(b), rand.u32(c), rand.u32(d)])

def cmd.add(+e: Env, +title: String, +start: String, rest: List<String>) -> IO(Unit):
  do IO<Unit>:
    +copy : List<&2, C.Rec> <- load(e)
    b : C.Body <- body.or(body.add(title, start, opts.go(rest, opts.none()), env.zone(e)))
    +id : String <- new.id()
    put(e, copy, id, b, "added")

def cmd.edit(+e: Env, +p: String, rest: List<String>) -> IO(Unit):
  do IO<Unit>:
    +copy : List<&2, C.Rec> <- load(e)
    +r : C.Rec <- pick(copy, p)
    b : C.Body <- body.or(Maybe.bind(&2, Opts, C.Body, opts.go(rest, opts.none()), o => body.edit(C.Rec.body(r), o, env.zone(e))))
    put(e, copy, C.Rec.id(r), b, "edited")

def cmd.rm(+e: Env, +p: String) -> IO(Unit):
  do IO<Unit>:
    +copy : List<&2, C.Rec> <- load(e)
    +r : C.Rec <- pick(copy, p)
    put(e, copy, C.Rec.id(r), body.kill(C.Rec.body(r)), "deleted")

def print.all(xs: List<&2, C.Rec>) -> IO(Unit):
  match xs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case x <> t:
      do IO<Unit>:
        IO.print(C.Rec.show(x))
        print.all(t)

def cmd.list(+e: Env) -> IO(Unit):
  do IO<Unit>:
    copy : List<&2, C.Rec> <- load(e)
    print.all(C.Copy.agenda(copy))

def cmd.show(+e: Env, +p: String) -> IO(Unit):
  do IO<Unit>:
    +copy : List<&2, C.Rec> <- load(e)
    r : C.Rec <- pick(copy, p)
    IO.print(C.Rec.detail(r))

def cmd.export(+e: Env) -> IO(Unit):
  do IO<Unit>:
    copy : List<&2, C.Rec> <- load(e)
    IO.print(J.Json.show(C.Copy.json(copy)))

def cmd.import(+e: Env, +path: String) -> IO(Unit):
  do IO<Unit>:
    +copy : List<&2, C.Rec> <- load(e)
    m : Maybe<&2, String> <- file.read(path)
    theirs : List<&2, C.Rec> <- copy.text(m, path, [])
    +both : List<&2, C.Rec> = C.join(copy, theirs)
    save(e, both)
    IO.print("joined " ++ path ++ ": " ++ U32.show(U32.from_nat(List.length(&2, C.Rec, both))) ++ " records")

# Peers
# -----

def ssh.args(+peer: String, cmd: String) -> List<String>:
  ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", peer, cmd]

# The peer joins what it is sent into its own copy (so its edits since it
# was read are kept): through a file, since a program in Bend reads a file
# in one piece.
def push.cmd(+remote: String) -> String:
  "f=$(mktemp) && cat > \"$f\" && " ++ remote ++ " import \"$f\" > /dev/null; r=$?; rm -f \"$f\"; exit $r"

# A failure is said on stderr and answered False, so that sync goes on to
# the other replicas and still exits non-zero.
def failed(+what: String) -> IO(Bool):
  do IO<Bool>:
    IO.print_err(what)
    return False{}

def say.if(ok: Bool, +peer: String, +good: String, +err: String) -> IO(Bool):
  match ok:
    case True{}:
      do IO<Bool>:
        IO.print(peer ++ ": " ++ good)
        return True{}
    case False{}:
      failed(peer ++ ": " ++ String.trim(err))

def sync.pushed(+peer: String, +n: U32, r: Ran) -> IO(Bool):
  match r:
    case Ran{+c, o, +e}:
      say.if(U32.is_eq(c, 0), peer, "in sync, " ++ U32.show(n) ++ " records", e)

def sync.join(+e: Env, +peer: String, m: Maybe<&2, J.Json>) -> IO(Bool):
  match m:
    case None{}:
      failed(peer ++ ": its copy is not JSON; nothing was changed")
    case Some{j}:
      do IO<Bool>:
        +copy : List<&2, C.Rec> <- load(e)
        +both : List<&2, C.Rec> = C.join(copy, C.Copy.of.json(j))
        save(e, both)
        r : Ran <- run("ssh", ssh.args(peer, push.cmd(env.remote(e))), J.Json.show(C.Copy.json(both)))
        sync.pushed(peer, U32.from_nat(List.length(&2, C.Rec, both)), r)

def sync.pulled.if(ok: Bool, +e: Env, +peer: String, +out: String, +err: String) -> IO(Bool):
  match ok:
    case True{}:
      sync.join(e, peer, J.Json.parse(out))
    case False{}:
      failed(peer ++ ": " ++ String.trim(err))

def sync.pulled(+e: Env, +peer: String, r: Ran) -> IO(Bool):
  match r:
    case Ran{+c, +o, +x}:
      sync.pulled.if(U32.is_eq(c, 0), e, peer, o, x)

def sync.peer(+e: Env, +peer: String) -> IO(Bool):
  do IO<Bool>:
    r : Ran <- run("ssh", ssh.args(peer, env.remote(e) ++ " export"), "")
    sync.pulled(e, peer, r)

def lines.kept(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      List.filter.put(String, String.trim(x), lines.kept(t),
        Bool.not(Bool.or(String.is_empty(String.trim(x)), String.starts_with(String.trim(x), "#"))))

def args.list(xs: List<String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      x <> args.list(t)

# Google
# ------
#
# A machine signs in to Google once, with `horas login`: the browser asks the
# account's owner, Google hands a code to horas on 127.0.0.1, and horas trades
# it (with the PKCE verifier only it knows) for a refresh token. That token
# and the id of the calendar horas made in the account are kept in
# $HORAS_DIR/google.json, in a directory only its owner can read. horas asks
# for one scope: to make its own calendars and manage the events on them;
# it cannot see the account's other calendars.

def google.scope() -> String:
  "https://www.googleapis.com/auth/calendar.app.created"

def google.port() -> U32:
  47811

def google.redirect() -> String:
  "http://127.0.0.1:" ++ U32.show(google.port())

def google.api() -> String:
  "https://www.googleapis.com/calendar/v3"

def google.path(+e: Env) -> String:
  env.dir(e) ++ "/google.json"

# The directory holds secrets from now on: only its owner may enter it.
def private(+e: Env) -> IO(Unit):
  do IO<Unit>:
    r : Ran <- run("chmod", ["700", env.dir(e)], "")
    must("chmod 700 " ++ env.dir(e), r)

# The OAuth client made in Google Cloud (a "Desktop app"), as downloaded.
def client.of(m: Maybe<&2, String>, +path: String) -> IO(J.Json):
  match m:
    case None{}:
      IO.die(J.Json, 1, "horas: " ++ path ++ " is missing: save there the JSON of a Desktop OAuth client from Google Cloud")
    case Some{s}:
      IO.pure(J.Json, J.Json.get(J.Json.read(s), "installed"))

def client.load(+e: Env) -> IO(J.Json):
  do IO<J.Json>:
    m : Maybe<&2, String> <- file.read(env.dir(e) ++ "/client.json")
    client.of(m, env.dir(e) ++ "/client.json")

# PKCE's challenge for a verifier: base64url of its SHA-256.
def s256.of(r: Ran) -> String:
  H.b64url(H.hex.bytes(String.take(out.of(r), 64n)))

def s256(+v: String) -> IO(String):
  do IO<String>:
    +r : Ran <- run("sha256sum", [], v)
    must("sha256sum", r)
    return s256.of(r)

def hint.of(xs: List<String>) -> List<&2, H.Param>:
  match xs:
    case +a <> Nil{}:
      [H.Param{"login_hint", a}]
    case _:
      Nil{}

def auth.url(+id: String, +challenge: String, +state: String, hint: List<&2, H.Param>) -> String:
  H.url("https://accounts.google.com/o/oauth2/v2/auth", List.append(&2, H.Param, [
    H.Param{"client_id", id}, H.Param{"redirect_uri", google.redirect()}, H.Param{"response_type", "code"},
    H.Param{"scope", google.scope()}, H.Param{"code_challenge", challenge},
    H.Param{"code_challenge_method", "S256"}, H.Param{"state", state},
    H.Param{"access_type", "offline"}, H.Param{"prompt", "consent"}], hint))

# The browser opens the page on its own (so its output does not hold horas).
def browser.open(+u: String) -> IO(Unit):
  do IO<Unit>:
    r : Ran <- run("sh", ["-c", "xdg-open \"$1\" >/dev/null 2>&1 </dev/null &", "sh", u], "")
    IO.pure(Unit, Unit{})

# The loopback server: one request per connection, answered and closed,
# until one brings Google's answer (or half an hour passes).
def recv.text(p: Poll<&1, &1, Result<&1, &1, U32 & String, Maybe<&1, String>>, Unit>) -> String:
  match p:
    case Ready{Done{Some{s}}}:
      s
    case _:
      ""

def sent.close(q: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>) -> IO(Unit):
  (s, r) = q
  Socket.close(s)

def accept.read(p: Socket & Poll<&1, &1, Result<&1, &1, U32 & String, Maybe<&1, String>>, Unit>, +state: String) -> IO(H.Got):
  (s, r) = p
  do IO<H.Got>:
    +g : H.Got = H.Got.of(recv.text(r), state)
    q : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send(s, H.Got.page(g))
    sent.close(q)
    return g

def accepted.go(l: Listener, a: Poll<&1, &1, Result<&1, &1, U32 & String, Socket>, Unit>, +state: String) -> IO(Listener & H.Got):
  match a:
    case Ready{Done{s}}:
      do IO<Listener & H.Got>:
        p : Socket & Poll<&1, &1, Result<&1, &1, U32 & String, Maybe<&1, String>>, Unit> <- TCP.try_recv(s, 65536, 3000)
        g : H.Got <- accept.read(p, state)
        return (l, g)
    case _:
      IO.pure(Listener & H.Got, (l, H.GotOther{}))

def accepted(p: Listener & Poll<&1, &1, Result<&1, &1, U32 & String, Socket>, Unit>, +state: String) -> IO(Listener & H.Got):
  (l, a) = p
  accepted.go(l, a, state)

def serve(fuel: Nat, q: Listener & H.Got, +state: String) -> IO(Listener & H.Got):
  match fuel:
    case 0n:
      IO.pure(Listener & H.Got, q)
    case 1n+f:
      (l, g) = q
      match g:
        case H.GotOther{}:
          do IO<Listener & H.Got>:
            p : Listener & Poll<&1, &1, Result<&1, &1, U32 & String, Socket>, Unit> <- TCP.try_accept(l, 1000)
            r : Listener & H.Got <- accepted(p, state)
            serve(f, r, state)
        case g2:
          IO.pure(Listener & H.Got, (l, g2))

# Google's web API, through curl: a form, or JSON with the access token in a
# header file (so the token is never in a command line).
def form.post(+u: String, +body: String) -> IO(Ran):
  run("curl", ["-sS", "--max-time", "60", "--fail-with-body", "-X", "POST",
    "-H", "Content-Type: application/x-www-form-urlencoded", "--data-binary", "@-", u], body)

def json.if(ok: Bool, +what: String, +out: String, +err: String) -> IO(J.Json):
  match ok:
    case True{}:
      IO.pure(J.Json, J.Json.read(out))
    case False{}:
      IO.die(J.Json, 1, "horas: " ++ what ++ " failed: " ++ String.trim(out ++ " " ++ err))

def json.of(+what: String, r: Ran) -> IO(J.Json):
  match r:
    case Ran{+c, +o, +x}:
      json.if(U32.is_eq(c, 0), what, o, x)

def bearer.path(+e: Env) -> String:
  env.dir(e) ++ "/bearer"

# A secret is written to a file made readable only by its owner before
# anything is in it, then moved over the old one.
def secret.write(+p: String, +data: String) -> IO(Unit):
  do IO<Unit>:
    c : Ran <- run("install", ["-m", "600", "/dev/null", p ++ ".tmp"], "")
    must("making " ++ p ++ ".tmp", c)
    file.write(p ++ ".tmp", data)
    r : Ran <- run("mv", ["-f", p ++ ".tmp", p], "")
    must("mv", r)

def bearer.save(+e: Env, +token: String) -> IO(Unit):
  secret.write(bearer.path(e), "Authorization: Bearer " ++ token ++ "\n")

def api.args(+e: Env, +method: String, +u: String, body: Bool) -> List<String>:
  match body:
    case True{}:
      ["-sS", "--max-time", "60", "--fail-with-body", "-X", method, "-H", "@" ++ bearer.path(e),
       "-H", "Content-Type: application/json", "--data-binary", "@-", u]
    case False{}:
      ["-sS", "--max-time", "60", "--fail-with-body", "-X", method, "-H", "@" ++ bearer.path(e), u]

def api(+e: Env, +method: String, +u: String, +body: String) -> IO(Ran):
  run("curl", api.args(e, method, u, Bool.not(String.is_empty(body))), body)

def token.trade(+cl: J.Json, +code: String, +verifier: String) -> IO(J.Json):
  do IO<J.Json>:
    r : Ran <- form.post("https://oauth2.googleapis.com/token", H.query([
      H.Param{"client_id", J.Json.at(cl, "client_id")}, H.Param{"client_secret", J.Json.at(cl, "client_secret")},
      H.Param{"code", code}, H.Param{"code_verifier", verifier},
      H.Param{"grant_type", "authorization_code"}, H.Param{"redirect_uri", google.redirect()}]))
    json.of("trading Google's code for a token", r)

def google.load(+e: Env) -> IO(J.Json):
  do IO<J.Json>:
    m : Maybe<&2, String> <- file.read(google.path(e))
    return J.Json.read(text.or(m, "{}"))

def google.save(+e: Env, +refresh: String, +cal: String) -> IO(Unit):
  secret.write(google.path(e), J.Json.show(J.JObj{J.JField{"refresh_token", J.JStr{refresh},
    J.JField{"calendar", J.JStr{cal}, J.JNil{}}}}) ++ "\n")

# horas's own calendar in the account: made once, then kept by its id.
def cal.make(+e: Env) -> IO(String):
  do IO<String>:
    r : Ran <- api(e, "POST", google.api() ++ "/calendars", J.Json.show(J.JObj{
      J.JField{"summary", J.JStr{"horas"},
      J.JField{"timeZone", J.JStr{env.zone(e)},
      J.JField{"description", J.JStr{"Kept by horas: every machine's copy of the calendar, joined."},
      J.JNil{}}}}}))
    j : J.Json <- json.of("making the horas calendar", r)
    return J.Json.at(j, "id")

def cal.or(none: Bool, +e: Env, +old: String) -> IO(String):
  match none:
    case True{}:
      cal.make(e)
    case False{}:
      IO.pure(String, old)

def login.tokens(+e: Env, +t: J.Json) -> IO(Unit):
  do IO<Unit>:
    must.if(J.Json.has(t, "refresh_token"), "signing in", "Google sent no refresh token")
    bearer.save(e, J.Json.at(t, "access_token"))
    +old : J.Json <- google.load(e)
    +cal : String <- cal.or(String.is_empty(J.Json.at(old, "calendar")), e, J.Json.at(old, "calendar"))
    google.save(e, J.Json.at(t, "refresh_token"), cal)
    IO.print("signed in to Google; horas's calendar there is " ++ cal)

def login.got(+e: Env, +cl: J.Json, +verifier: String, g: H.Got) -> IO(Unit):
  match g:
    case H.GotCode{code}:
      do IO<Unit>:
        +t : J.Json <- token.trade(cl, code, verifier)
        login.tokens(e, t)
    case H.GotError{x}:
      IO.die(Unit, 1, "horas: Google did not sign horas in: " ++ x)
    case H.GotOther{}:
      IO.die(Unit, 1, "horas: no answer from the browser in 30 minutes")

def login.done(q: Listener & H.Got, +e: Env, +cl: J.Json, +verifier: String) -> IO(Unit):
  (l, g) = q
  do IO<Unit>:
    Listener.close(l)
    login.got(e, cl, verifier, g)

def cmd.login(+e: Env, hint: List<String>) -> IO(Unit):
  do IO<Unit>:
    private(e)
    +cl : J.Json <- client.load(e)
    +a : String <- new.id()
    +b : String <- new.id()
    +state : String <- new.id()
    +verifier : String = a ++ b
    +challenge : String <- s256(verifier)
    l : Listener <- IO.try(Listener, TCP.listen("127.0.0.1", google.port()))
    +u : String = auth.url(J.Json.at(cl, "client_id"), challenge, state, hint.of(hint))
    IO.print_err("horas: opening Google's sign-in in the browser; if it does not open, visit\n" ++ u)
    browser.open(u)
    q : Listener & H.Got <- serve(1800n, (l, H.GotOther{}), state)
    login.done(q, e, cl, verifier)

# Syncing with Google
# -------------------
#
# Google's copy of horas's calendar is one more replica. Every event horas
# writes there carries, in its private extended properties, the stamp of the
# version written and the hash of its body. Read back, an event whose body
# still has that hash is that version. One whose body does not was edited in
# Google Calendar (on the web, on a phone): a new version, stamped with when
# Google says it changed. So an edit on either side carries over to the
# other, and of two edits to one event the later wins.

def events.url(+cal: String) -> String:
  google.api() ++ "/calendars/" ++ H.pct(cal) ++ "/events"

def token.refresh(+cl: J.Json, +refresh: String) -> IO(Ran):
  form.post("https://oauth2.googleapis.com/token", H.query([
    H.Param{"client_id", J.Json.at(cl, "client_id")}, H.Param{"client_secret", J.Json.at(cl, "client_secret")},
    H.Param{"refresh_token", refresh}, H.Param{"grant_type", "refresh_token"}]))

# An event as Google holds it: whether it is a version horas wrote (its hash
# still matches), that version's stamp (or, edited in Google, Google's time
# of the edit), and its body.
type GV is Data:
  GV{+id: String, +ok: Bool, +at: C.Stamp, +body: C.Body}

def gv.id(v: GV) -> String:
  match v:
    case GV{i, o, s, b}:
      i

def gv.if(ok: Bool, +id: String, s: C.Stamp, +b: C.Body, edit: C.Stamp) -> GV:
  match ok:
    case True{}:
      GV{id, True{}, s, b}
    case False{}:
      GV{id, False{}, edit, b}

def gv.stamped(m: Maybe<&2, C.Stamp>, +id: String, +hash: String, +b: C.Body, edit: C.Stamp) -> GV:
  match m:
    case None{}:
      GV{id, False{}, edit, b}
    case Some{s}:
      gv.if(String.eq(hash, C.Body.hash(b)), id, s, b, edit)

def gv.props(+zone: String, +j: J.Json, +p: J.Json) -> GV:
  gv.stamped(C.Stamp.read(J.Json.at(p, "horas")), J.Json.at(j, "id"), J.Json.at(p, "horas_hash"),
    C.Body.google(j, zone), C.Stamp{J.Json.at(j, "updated"), 0, "google"})

def gv.of(+zone: String, +j: J.Json) -> GV:
  gv.props(zone, j, J.Json.get(J.Json.get(j, "extendedProperties"), "private"))

def gvs.of(+zone: String, xs: List<&2, J.Json>) -> List<&2, GV>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      gv.of(zone, x) <> gvs.of(zone, t)

def gv.find(vs: List<&2, GV>, +id: String) -> Maybe<&2, GV>:
  match vs:
    case Nil{}:
      None{}
    case +v <> t:
      Bool.pick(Maybe<&2, GV>, String.eq(gv.id(v), id), Some{v}, gv.find(t, id))

# What Google's copy adds: every version horas wrote (the join keeps the
# later), and every event edited in Google whose body is not the one here
# (one that only Google ever had, and that is deleted there, is left out).
def gv.new(m: Maybe<&2, C.Rec>, +b: C.Body) -> Bool:
  match m:
    case None{}:
      C.Body.live(b)
    case Some{r}:
      Bool.not(C.Body.same(C.Rec.body(r), b))

def gv.rec.if(keep: Bool, +i: String, s: C.Stamp, b: C.Body) -> List<&2, C.Rec>:
  match keep:
    case True{}:
      [C.Rec{i, s, b}]
    case False{}:
      Nil{}

def gv.rec(v: GV, +copy: List<&2, C.Rec>) -> List<&2, C.Rec>:
  match v:
    case GV{+i, o, s, +b}:
      gv.rec.if(Bool.or(o, gv.new(C.Copy.find(copy, i), b)), i, s, b)

def gv.recs(vs: List<&2, GV>, +copy: List<&2, C.Rec>) -> List<&2, C.Rec>:
  match vs:
    case Nil{}:
      Nil{}
    case v <> t:
      List.append(&2, C.Rec, gv.rec(v, copy), gv.recs(t, copy))

# What horas writes to Google: the body, its stamp and its hash.
def obj.fields(j: J.Json) -> J.Json:
  match j:
    case J.JObj{fs}:
      fs
    case _:
      J.JNil{}

def ev.json(+id: String, s: C.Stamp, +b: C.Body) -> String:
  J.Json.show(J.JObj{J.JField{"id", J.JStr{id},
    J.JField{"extendedProperties", J.JObj{J.JField{"private", J.JObj{
      J.JField{"horas", J.JStr{C.Stamp.show(s)},
      J.JField{"horas_hash", J.JStr{C.Body.hash(b)}, J.JNil{}}}}, J.JNil{}}},
    obj.fields(C.Body.json(b))}}})

def rec.ev(r: C.Rec) -> String:
  match r:
    case C.Rec{i, s, b}:
      ev.json(i, s, b)

def cmp.is_eq(c: Cmp) -> Bool:
  match c:
    case EQ{}:
      True{}
    case _:
      False{}

def stamp.eq(a: C.Stamp, b: C.Stamp) -> Bool:
  cmp.is_eq(C.Stamp.order(a, b))

# Google keeps no event without a start.
def When.set(w: C.When) -> Bool:
  match w:
    case C.NoTime{}:
      False{}
    case _:
      True{}

# For each record here: Google has its version (skip), lacks the event
# (insert it, unless it is deleted), or has another version (patch it).
type Act is Data:
  Skip{}
  Insert{}
  Patch{}

def act.had(v: GV, +r: C.Rec) -> Act:
  match v:
    case GV{i, o, s, b}:
      Bool.pick(Act, Bool.or(Bool.and(o, stamp.eq(s, C.Rec.at(r))), Bool.not(When.set(C.Body.start(C.Rec.body(r))))),
        Skip{}, Patch{})

def act.of(m: Maybe<&2, GV>, +r: C.Rec) -> Act:
  match m:
    case None{}:
      Bool.pick(Act, Bool.and(C.Rec.live(r), When.set(C.Body.start(C.Rec.body(r)))), Insert{}, Skip{})
    case Some{v}:
      act.had(v, r)

# 0: nothing to write, 1: written, 2: Google refused it.
def wrote.if(ok: Bool, +id: String, +err: String) -> IO(U32):
  match ok:
    case True{}:
      IO.pure(U32, 1)
    case False{}:
      do IO<U32>:
        IO.print_err("google: " ++ String.take(id, 8n) ++ ": " ++ String.trim(err))
        return 2

def wrote(+id: String, r: Ran) -> IO(U32):
  match r:
    case Ran{+c, +o, +x}:
      wrote.if(U32.is_eq(c, 0), id, o ++ " " ++ x)

def act.run(a: Act, +e: Env, +cal: String, +r: C.Rec) -> IO(U32):
  match a:
    case Skip{}:
      IO.pure(U32, 0)
    case Insert{}:
      do IO<U32>:
        x : Ran <- api(e, "POST", events.url(cal), rec.ev(r))
        wrote(C.Rec.id(r), x)
    case Patch{}:
      do IO<U32>:
        x : Ran <- api(e, "PATCH", events.url(cal) ++ "/" ++ C.Rec.id(r), rec.ev(r))
        wrote(C.Rec.id(r), x)

type Tally is Data:
  Tally{+wrote: U32, +failed: U32}

def one.if(+k: U32, +v: U32) -> U32:
  Bool.pick(U32, U32.is_eq(k, v), 1, 0)

def tally.add(t: Tally, +k: U32) -> Tally:
  match t:
    case Tally{w, f}:
      Tally{(w + one.if(k, 1) : U32), (f + one.if(k, 2) : U32)}

def push.all(+e: Env, +cal: String, +vs: List<&2, GV>, rs: List<&2, C.Rec>, t: Tally) -> IO(Tally):
  match rs:
    case Nil{}:
      IO.pure(Tally, t)
    case +r <> rest:
      do IO<Tally>:
        k : U32 <- act.run(act.of(gv.find(vs, C.Rec.id(r)), r), e, cal, r)
        push.all(e, cal, vs, rest, tally.add(t, k))

# Reading Google's copy, a page (up to 2500 events) at a time, deleted
# events too.
type Pages is Data:
  PMore{+token: String, +items: List<&2, J.Json>}
  PDone{+items: List<&2, J.Json>}
  PFail{+why: String}

def page.url(+cal: String, +tok: String) -> String:
  H.url(events.url(cal), List.append(&2, H.Param, [H.Param{"showDeleted", "true"}, H.Param{"maxResults", "2500"}],
    Bool.pick(List<&2, H.Param>, String.is_empty(tok), Nil{}, [H.Param{"pageToken", tok}])))

def page.more(last: Bool, +tok: String, xs: List<&2, J.Json>) -> Pages:
  match last:
    case True{}:
      PDone{xs}
    case False{}:
      PMore{tok, xs}

def page.of(+j: J.Json, acc: List<&2, J.Json>) -> Pages:
  page.more(String.is_empty(J.Json.at(j, "nextPageToken")), J.Json.at(j, "nextPageToken"),
    List.append(&2, J.Json, acc, J.Json.items(J.Json.get(j, "items"))))

def page.if(ok: Bool, +o: String, +x: String, acc: List<&2, J.Json>) -> Pages:
  match ok:
    case True{}:
      page.of(J.Json.read(o), acc)
    case False{}:
      PFail{String.trim(o ++ " " ++ x)}

def page.step(r: Ran, acc: List<&2, J.Json>) -> Pages:
  match r:
    case Ran{+c, +o, +x}:
      page.if(U32.is_eq(c, 0), o, x, acc)

def pages(fuel: Nat, +e: Env, +cal: String, st: Pages) -> IO(Maybe<&2, List<&2, J.Json>>):
  match fuel:
    case 0n:
      IO.pure(Maybe<&2, List<&2, J.Json>>, None{})
    case 1n+f:
      match st:
        case PDone{xs}:
          IO.pure(Maybe<&2, List<&2, J.Json>>, Some{xs})
        case PFail{+why}:
          do IO<Maybe<&2, List<&2, J.Json>>>:
            IO.print_err("google: reading the calendar failed: " ++ why)
            return None{}
        case PMore{+tok, xs}:
          do IO<Maybe<&2, List<&2, J.Json>>>:
            r : Ran <- api(e, "GET", page.url(cal, tok), "")
            pages(f, e, cal, page.step(r, xs))

def google.said(+n: U32, t: Tally) -> IO(Bool):
  match t:
    case Tally{+w, +f}:
      say.if(U32.is_eq(f, 0), "google", "in sync, " ++ U32.show(n) ++ " records, " ++ U32.show(w) ++ " written",
        U32.show(f) ++ " events not written, " ++ U32.show(w) ++ " written")

# Google's changes join the copy here, then whatever Google lacks is written.
def google.join(+e: Env, +cal: String, +vs: List<&2, GV>) -> IO(Bool):
  do IO<Bool>:
    +copy : List<&2, C.Rec> <- load(e)
    +both : List<&2, C.Rec> = C.join(copy, C.Copy.of(gv.recs(vs, copy)))
    save(e, both)
    t : Tally <- push.all(e, cal, vs, both, Tally{0, 0})
    google.said(U32.from_nat(List.length(&2, C.Rec, both)), t)

def google.listed(+e: Env, +cal: String, ms: Maybe<&2, List<&2, J.Json>>) -> IO(Bool):
  match ms:
    case None{}:
      IO.pure(Bool, False{})
    case Some{xs}:
      google.join(e, cal, gvs.of(env.zone(e), xs))

def google.fresh(ok: Bool, +e: Env, +cal: String, +o: String, +x: String) -> IO(Bool):
  match ok:
    case False{}:
      failed("google: renewing the sign-in failed (run horas login again?): " ++ String.trim(o ++ " " ++ x))
    case True{}:
      do IO<Bool>:
        bearer.save(e, J.Json.at(J.Json.read(o), "access_token"))
        ms : Maybe<&2, List<&2, J.Json>> <- pages(1000n, e, cal, PMore{"", Nil{}})
        google.listed(e, cal, ms)

def google.refreshed(+e: Env, +cal: String, r: Ran) -> IO(Bool):
  match r:
    case Ran{+c, +o, +x}:
      google.fresh(U32.is_eq(c, 0), e, cal, o, x)

def google.with(+e: Env, +g: J.Json) -> IO(Bool):
  do IO<Bool>:
    +cl : J.Json <- client.load(e)
    r : Ran <- token.refresh(cl, J.Json.at(g, "refresh_token"))
    google.refreshed(e, J.Json.at(g, "calendar"), r)

def google.signed(+e: Env, m: Maybe<&2, String>) -> IO(Bool):
  match m:
    case None{}:
      failed("google: this machine is not signed in (horas login)")
    case Some{s}:
      google.with(e, J.Json.read(s))

def sync.google(+e: Env) -> IO(Bool):
  do IO<Bool>:
    m : Maybe<&2, String> <- file.read(google.path(e))
    google.signed(e, m)

# Sync: every replica named ("google" is Google's copy), or else Google's
# (once this machine is signed in) and the peers in $HORAS_DIR/peers.
def sync.one(is_google: Bool, +e: Env, +p: String) -> IO(Bool):
  match is_google:
    case True{}:
      sync.google(e)
    case False{}:
      sync.peer(e, p)

def sync.all(+e: Env, peers: List<&2, String>, ok: Bool) -> IO(Bool):
  match peers:
    case Nil{}:
      IO.pure(Bool, ok)
    case +p <> t:
      do IO<Bool>:
        k : Bool <- sync.one(String.eq(p, "google"), e, p)
        sync.all(e, t, Bool.and(ok, k))

def signed.in(m: Maybe<&2, String>) -> List<&2, String>:
  match m:
    case None{}:
      Nil{}
    case Some{s}:
      ["google"]

def sync.peers(+e: Env, given: List<&2, String>, file: Maybe<&2, String>, g: Maybe<&2, String>) -> IO(Bool):
  match given:
    case Nil{}:
      sync.all(e, List.append(&2, String, signed.in(g), lines.kept(String.lines(text.or(file, "")))), True{})
    case +p:
      sync.all(e, p, True{})

def sync.end(ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "horas: sync did not reach every replica")

def cmd.sync(+e: Env, xs: List<String>) -> IO(Unit):
  do IO<Unit>:
    m : Maybe<&2, String> <- file.read(env.dir(e) ++ "/peers")
    g : Maybe<&2, String> <- file.read(google.path(e))
    ok : Bool <- sync.peers(e, args.list(xs), m, g)
    sync.end(ok)

# The command line
# ----------------

def usage() -> String:
  "usage: horas add TITLE WHEN [--end WHEN] [--at PLACE] [--notes TEXT]\n" ++
  "       horas list | show ID | rm ID\n" ++
  "       horas edit ID [--title T] [--start WHEN] [--end WHEN] [--at P] [--notes N]\n" ++
  "       horas sync [PEER...] | export | import FILE\n" ++
  "       horas login [ACCOUNT]\n" ++
  "WHEN: 2026-11-29 or 2026-11-29T19:00"

def horas.args(+e: Env, xs: List<String>) -> IO(Unit):
  match xs:
    case "add" <> +title <> +start <> rest:
      cmd.add(e, title, start, rest)
    case "list" <> Nil{}:
      cmd.list(e)
    case "show" <> +p <> Nil{}:
      cmd.show(e, p)
    case "edit" <> +p <> rest:
      cmd.edit(e, p, rest)
    case "rm" <> +p <> Nil{}:
      cmd.rm(e, p)
    case "sync" <> peers:
      cmd.sync(e, peers)
    case "export" <> Nil{}:
      cmd.export(e)
    case "import" <> +path <> Nil{}:
      cmd.import(e, path)
    case "login" <> hint:
      cmd.login(e, hint)
    case _:
      IO.die(Unit, 2, usage())

def horas.main(+e: Env, xs: List<String>) -> IO(Unit):
  match xs:
    case _ <> rest:
      horas.args(e, rest)
    case Nil{}:
      IO.die(Unit, 2, usage())

def main() -> IO(Unit):
  do IO<Unit>:
    argv : List<String> <- IO.args()
    home : String <- env.get("HOME", "/tmp")
    +dir : String <- env.get("HORAS_DIR", home ++ "/.local/share/horas")
    host : Maybe<&2, String> <- file.read("/etc/hostname")
    who : String <- env.get("HORAS_WHO", text.or(host, "here"))
    zone : String <- env.get("HORAS_TZ", "America/Mexico_City")
    remote : String <- env.get("HORAS_REMOTE", "horas")
    r : Ran <- run("mkdir", ["-p", dir], "")
    must("mkdir " ++ dir, r)
    horas.main(Env{dir, who, zone, remote}, argv)
