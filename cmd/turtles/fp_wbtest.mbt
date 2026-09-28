///|
test "fingerprint hex" {
  inspect(fingerprint_hex(0x0123456789abcdefUL), content="0123456789abcdef")
  inspect(fingerprint_hex(0xaf63dc4c8601ec8cUL), content="af63dc4c8601ec8c")
}
