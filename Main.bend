import Base
import ./Json.bend as J
import ./Cal.bend as C

# horas: the command line. One copy of the calendar per machine, in
# $HORAS_DIR/copy.json (default ~/.local/share/horas); `sync` joins it with
# other machines' copies over ssh, so each ends with every edit either saw.
#
#   horas add TITLE WHEN [--end WHEN] [--at PLACE] [--notes TEXT]
#   horas list
#   horas show ID
#   horas edit ID [--title T] [--start WHEN] [--end WHEN] [--at P] [--notes N]
#   horas rm ID
#   horas sync [PEER...]      (default: the lines of $HORAS_DIR/peers)
#   horas export              (the copy, as JSON: what a peer's sync reads)
#   horas import FILE         (joins a copy written by export)
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

def say.if(ok: Bool, +peer: String, +good: String, +err: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.print(peer ++ ": " ++ good)
    case False{}:
      IO.print_err(peer ++ ": " ++ String.trim(err))

def sync.pushed(+peer: String, +n: U32, r: Ran) -> IO(Unit):
  match r:
    case Ran{+c, o, +e}:
      say.if(U32.is_eq(c, 0), peer, "in sync, " ++ U32.show(n) ++ " records", e)

def sync.join(+e: Env, +peer: String, m: Maybe<&2, J.Json>) -> IO(Unit):
  match m:
    case None{}:
      IO.print_err(peer ++ ": its copy is not JSON; nothing was changed")
    case Some{j}:
      do IO<Unit>:
        +copy : List<&2, C.Rec> <- load(e)
        +both : List<&2, C.Rec> = C.join(copy, C.Copy.of.json(j))
        save(e, both)
        r : Ran <- run("ssh", ssh.args(peer, push.cmd(env.remote(e))), J.Json.show(C.Copy.json(both)))
        sync.pushed(peer, U32.from_nat(List.length(&2, C.Rec, both)), r)

def sync.pulled.if(ok: Bool, +e: Env, +peer: String, +out: String, +err: String) -> IO(Unit):
  match ok:
    case True{}:
      sync.join(e, peer, J.Json.parse(out))
    case False{}:
      IO.print_err(peer ++ ": " ++ String.trim(err))

def sync.pulled(+e: Env, +peer: String, r: Ran) -> IO(Unit):
  match r:
    case Ran{+c, +o, +x}:
      sync.pulled.if(U32.is_eq(c, 0), e, peer, o, x)

def sync.peer(+e: Env, +peer: String) -> IO(Unit):
  do IO<Unit>:
    r : Ran <- run("ssh", ssh.args(peer, env.remote(e) ++ " export"), "")
    sync.pulled(e, peer, r)

def sync.all(+e: Env, peers: List<&2, String>) -> IO(Unit):
  match peers:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case +p <> t:
      do IO<Unit>:
        sync.peer(e, p)
        sync.all(e, t)

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

def sync.peers(+e: Env, given: List<&2, String>, file: Maybe<&2, String>) -> IO(Unit):
  match given:
    case Nil{}:
      sync.all(e, lines.kept(String.lines(text.or(file, ""))))
    case +g:
      sync.all(e, g)

def cmd.sync(+e: Env, xs: List<String>) -> IO(Unit):
  do IO<Unit>:
    m : Maybe<&2, String> <- file.read(env.dir(e) ++ "/peers")
    sync.peers(e, args.list(xs), m)

# The command line
# ----------------

def usage() -> String:
  "usage: horas add TITLE WHEN [--end WHEN] [--at PLACE] [--notes TEXT]\n" ++
  "       horas list | show ID | rm ID\n" ++
  "       horas edit ID [--title T] [--start WHEN] [--end WHEN] [--at P] [--notes N]\n" ++
  "       horas sync [PEER...] | export | import FILE\n" ++
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
