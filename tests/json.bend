import Base
import ../Json.bend as J

def main() -> IO(Unit):
  do IO<Unit>:
    +src : String = "{\"kind\": \"calendar#events\", \"items\": [{\"id\": \"abc\", \"summary\": \"Cena \\\"familiar\\\" \\u00e9\\n\", \"n\": 12.5, \"ok\": true, \"no\": null, \"start\": {\"date\": \"2026-11-29\"}}, [], {}], \"nextSyncToken\": \"tok=\"}"
    +j : J.Json = J.Json.read(src)
    IO.print(J.Json.show(j))
    IO.print(J.Json.at(j, "nextSyncToken"))
    IO.print(J.Json.show(J.Json.get(Maybe.default(&2, J.Json, List.head(&2, J.Json, J.Json.items(J.Json.get(j, "items"))), J.JNull{}), "start")))
    IO.print(J.Json.show(J.Json.read(J.Json.show(j))))
