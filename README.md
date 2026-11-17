# horas

A calendar in [Bend](https://bend-lang.com): one copy per machine, joined
over ssh and with Google Calendar, and the open slots it publishes so
people can book a call.

```
horas add TITLE WHEN [--end WHEN] [--at PLACE] [--notes TEXT]
horas list | show ID | rm ID
horas edit ID [--title T] [--start WHEN] [--end WHEN] [--at P] [--notes N]
horas sync [PEER...] | export | import FILE
horas login [ACCOUNT]
horas slots [OPTION...]
horas publish [OPTION...]
```

WHEN is a day, `2026-11-29`, or a time there, `2026-11-29T19:00`, in
`$HORAS_TZ` (default `America/Mexico_City`). Each machine keeps its copy in
`$HORAS_DIR` (default `~/.local/share/horas`); `horas sync` joins it with
Google Calendar's copy and with the machines in `$HORAS_DIR/peers`, so each
ends with every edit either saw (for each event, the latest edit wins).

Build it with `nix build`; the build checks every proof and runs the tests.

## Open slots for a call

`horas slots` lists the times someone may book a call: 30-minute slots over
the next 14 days, Monday to Friday 09:00-17:00 in `$HORAS_TZ`, at least
4 hours from now, around every live event in this machine's copy. It
prints JSON:

```json
{"zone":"America/Mexico_City","generated":"2026-11-17T18:01:14Z",
 "slots":["2026-11-18T15:00:00Z","2026-11-18T15:30:00Z", ...]}
```

Only the slots' starts (in UTC), the zone and when the list was made: never
an event's title, notes, place or times. Busy means an event in horas's
copy: horas's Google sign-in sees only the calendar horas made, so an event
put straight into another Google calendar is not seen. An all-day event takes its whole
day. A repeating event counts as busy only at its first time (horas keeps no
other); `slots` warns about each one on stderr.

Options (the defaults in brackets):

| option | meaning |
|---|---|
| `--ahead DAYS` | how many days from today to offer [14] |
| `--hours HH:MM-HH:MM[,...]` | working hours, one or more windows [09:00-17:00] |
| `--days mon-fri` | working days: `mon-fri`, `mon,wed,fri`, `1-5` [mon-fri] |
| `--length MIN` | a slot's length [30] |
| `--notice MIN` | how soon the first slot may start [240] |
| `--out FILE` | write the JSON there instead of printing it |

Which slots are open is `Slots.bend`. `LAWS.bend` states that every slot it
returns lasts the length asked, starts at or after the notice, lies inside a
working window and shares no minute with a busy event; `PROOF.bend` proves
it (`bend PROOF.bend --verdict` prints ALL PROOFS CHECK). The proofs say
the list keeps only what passes the four checks; `tests/slots.bend` tests the
checks themselves, minute by minute against a count that does not use them,
and the calendar arithmetic against GNU `date` and against every day of
1970-2169 (`bend tests/slots.bend`).

## Publishing them on hhefesto.dev

```
horas publish
```

syncs (with Google and the peers; `--no-sync` skips it), writes the slots
into `~/src/hhefesto.com/public/slots.json` (`--site DIR` for another site)
and commits that one file there, on whatever branch is checked out. It takes
the same options as `slots`. It does not push: pushing the site's `master`
deploys it, so that is a separate step,

```
git -C ~/src/hhefesto.com push
```

The page shows the slots still in the future, in the visitor's own time and
in UTC-6. A visitor who picks one gets an email to write to
hhefesto@rdataa.com with the slot in its subject and body; the page says the
call is confirmed by reply. If the file is missing, empty or more than 7 days
old, the page offers the plain email link instead.

## Confirming a booking

When the email comes:

1. Put the call in the calendar, with the visitor's address in the notes:

   ```
   horas add "Free call: Ada Lovelace" 2026-11-18T09:30 --end 2026-11-18T10:00 --notes "ada@example.com"
   ```

2. `horas sync` puts it in Google Calendar (and on the other machines).
3. Reply to the email: that reply is the confirmation.
4. `horas publish`, then push the site, so the slot is no longer offered.

If two people ask for the same slot, the first to get a reply has it; offer
the other a time from the list again.
