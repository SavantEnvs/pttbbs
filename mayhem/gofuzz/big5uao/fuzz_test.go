package big5uaofuzz

import (
	"testing"
	"unicode/utf8"

	"pttbbs/big5uao"
)

// FuzzBig5UAO feeds raw bytes, as they come from BBS articles, mails and the
// terminal, through every public Big5-UAO decode path, and the encoder with
// the same bytes read as UTF-8. Decode writes only runes, ASCII and '?', so
// its output must be valid UTF-8.
func FuzzBig5UAO(f *testing.F) {
	for _, s := range []string{
		"Hello, World! 12345",
		"\xb4\xfa\xb8\xd5\xa4\xf4\xb2\x79",
		"\x1b[1;33m[\xa4\xbd\xa7\x69]\x1b[m \x1b[1;32mGossiping\x1b[m",
		"\xa4\x1b[1m\xa4",
		"測試水球，批踢踢實業坊",
	} {
		f.Add([]byte(s))
	}
	f.Fuzz(func(t *testing.T, b []byte) {
		if s := big5uao.Decode(b); !utf8.ValidString(s) {
			t.Fatalf("Decode(%q) = %q, not UTF-8", b, s)
		}
		_ = big5uao.DecodeSGR66(b)
		_, _ = big5uao.Big5UAO.NewDecoder().Bytes(b)
		enc := big5uao.Encode(string(b))
		_, _ = big5uao.Big5UAO.NewEncoder().Bytes(b)
		_ = big5uao.Decode(enc)
	})
}
