import Base
import ../Http.bend as H

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(H.pct("a b/c?d=é~_.-"))
    IO.print(H.pct.dec("4%2F0AbC-x_y%3D%3D+z"))
    IO.print(H.query([H.Param{"redirect_uri", "http://127.0.0.1:47811"}, H.Param{"scope", "https://www.googleapis.com/auth/calendar.app.created"}]))
    IO.print(H.b64url(H.hex.bytes("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")))
    IO.print(H.b64url(H.hex.bytes("666f6f62")))
    IO.print(H.Got.page(H.Got.of("GET /?state=abc&code=4%2F0AX&scope=x HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n", "abc")))
    IO.print(H.Got.page(H.Got.of("GET /favicon.ico HTTP/1.1\r\n\r\n", "abc")))
    IO.print(H.Got.page(H.Got.of("GET /?error=access_denied&state=abc HTTP/1.1\r\n\r\n", "abc")))
    IO.print(H.Got.page(H.Got.of("GET /?state=zzz&code=1 HTTP/1.1\r\n\r\n", "abc")))
