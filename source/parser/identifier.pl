:- module(identifier, [identifier/3]).

:- use_module(library(dcgs)).

:- use_module(unicode, [unicode_character/2,
                        between_unicode_range/3]).

identifier(identifier_node([FirstCharacter | RestCharacters])) -->
  identifier_first_character(FirstCharacter),
  identifier_rest_characters(RestCharacters).

identifier_first_character(Character) -->
  [Character],
  {
    between_unicode_range(0x0041, 0x005A, Character) % XID_Start # L&  [26] LATIN CAPITAL LETTER A..LATIN CAPITAL LETTER Z
    ; between_unicode_range(0x0061, 0x007A, Character) % XID_Start # L&  [26] LATIN SMALL LETTER A..LATIN SMALL LETTER Z
    ; unicode_character(0x00AA, Character) % XID_Start # Lo       FEMININE ORDINAL INDICATOR
    ; unicode_character(0x00B5, Character) % XID_Start # L&       MICRO SIGN
    ; unicode_character(0x00BA, Character) % XID_Start # Lo       MASCULINE ORDINAL INDICATOR
    ; between_unicode_range(0x00C0, 0x00D6, Character) % XID_Start # L&  [23] LATIN CAPITAL LETTER A WITH GRAVE..LATIN CAPITAL LETTER O WITH DIAERESIS
    ; between_unicode_range(0x00D8, 0x00F6, Character) % XID_Start # L&  [31] LATIN CAPITAL LETTER O WITH STROKE..LATIN SMALL LETTER O WITH DIAERESIS
    ; between_unicode_range(0x00F8, 0x01BA, Character) % XID_Start # L& [195] LATIN SMALL LETTER O WITH STROKE..LATIN SMALL LETTER EZH WITH TAIL
    ; unicode_character(0x01BB, Character) % XID_Start # Lo       LATIN LETTER TWO WITH STROKE
    ; between_unicode_range(0x01BC, 0x01BF, Character) % XID_Start # L&   [4] LATIN CAPITAL LETTER TONE FIVE..LATIN LETTER WYNN
    ; between_unicode_range(0x01C0, 0x01C3, Character) % XID_Start # Lo   [4] LATIN LETTER DENTAL CLICK..LATIN LETTER RETROFLEX CLICK
    ; between_unicode_range(0x01C4, 0x0293, Character) % XID_Start # L& [208] LATIN CAPITAL LETTER DZ WITH CARON..LATIN SMALL LETTER EZH WITH CURL
    ; unicode_character(0x0294, Character) % XID_Start # Lo       LATIN LETTER GLOTTAL STOP
    ; between_unicode_range(0x0295, 0x02AF, Character) % XID_Start # L&  [27] LATIN LETTER PHARYNGEAL VOICED FRICATIVE..LATIN SMALL LETTER TURNED H WITH FISHHOOK AND TAIL
    ; between_unicode_range(0x02B0, 0x02C1, Character) % XID_Start # Lm  [18] MODIFIER LETTER SMALL H..MODIFIER LETTER REVERSED GLOTTAL STOP
    ; between_unicode_range(0x02C6, 0x02D1, Character) % XID_Start # Lm  [12] MODIFIER LETTER CIRCUMFLEX ACCENT..MODIFIER LETTER HALF TRIANGULAR COLON
    ; between_unicode_range(0x02E0, 0x02E4, Character) % XID_Start # Lm   [5] MODIFIER LETTER SMALL GAMMA..MODIFIER LETTER SMALL REVERSED GLOTTAL STOP
    ; unicode_character(0x02EC, Character) % XID_Start # Lm       MODIFIER LETTER VOICING
    ; unicode_character(0x02EE, Character) % XID_Start # Lm       MODIFIER LETTER DOUBLE APOSTROPHE
    ; between_unicode_range(0x0370, 0x0373, Character) % XID_Start # L&   [4] GREEK CAPITAL LETTER HETA..GREEK SMALL LETTER ARCHAIC SAMPI
    ; unicode_character(0x0374, Character) % XID_Start # Lm       GREEK NUMERAL SIGN
    ; between_unicode_range(0x0376, 0x0377, Character) % XID_Start # L&   [2] GREEK CAPITAL LETTER PAMPHYLIAN DIGAMMA..GREEK SMALL LETTER PAMPHYLIAN DIGAMMA
    ; between_unicode_range(0x037B, 0x037D, Character) % XID_Start # L&   [3] GREEK SMALL REVERSED LUNATE SIGMA SYMBOL..GREEK SMALL REVERSED DOTTED LUNATE SIGMA SYMBOL
    ; unicode_character(0x037F, Character) % XID_Start # L&       GREEK CAPITAL LETTER YOT
    ; unicode_character(0x0386, Character) % XID_Start # L&       GREEK CAPITAL LETTER ALPHA WITH TONOS
    ; between_unicode_range(0x0388, 0x038A, Character) % XID_Start # L&   [3] GREEK CAPITAL LETTER EPSILON WITH TONOS..GREEK CAPITAL LETTER IOTA WITH TONOS
    ; unicode_character(0x038C, Character) % XID_Start # L&       GREEK CAPITAL LETTER OMICRON WITH TONOS
    ; between_unicode_range(0x038E, 0x03A1, Character) % XID_Start # L&  [20] GREEK CAPITAL LETTER UPSILON WITH TONOS..GREEK CAPITAL LETTER RHO
    ; between_unicode_range(0x03A3, 0x03F5, Character) % XID_Start # L&  [83] GREEK CAPITAL LETTER SIGMA..GREEK LUNATE EPSILON SYMBOL
    ; between_unicode_range(0x03F7, 0x0481, Character) % XID_Start # L& [139] GREEK CAPITAL LETTER SHO..CYRILLIC SMALL LETTER KOPPA
    ; between_unicode_range(0x048A, 0x052F, Character) % XID_Start # L& [166] CYRILLIC CAPITAL LETTER SHORT I WITH TAIL..CYRILLIC SMALL LETTER EL WITH DESCENDER
    ; between_unicode_range(0x0531, 0x0556, Character) % XID_Start # L&  [38] ARMENIAN CAPITAL LETTER AYB..ARMENIAN CAPITAL LETTER FEH
    ; unicode_character(0x0559, Character) % XID_Start # Lm       ARMENIAN MODIFIER LETTER LEFT HALF RING
    ; between_unicode_range(0x0560, 0x0588, Character) % XID_Start # L&  [41] ARMENIAN SMALL LETTER TURNED AYB..ARMENIAN SMALL LETTER YI WITH STROKE
    ; between_unicode_range(0x05D0, 0x05EA, Character) % XID_Start # Lo  [27] HEBREW LETTER ALEF..HEBREW LETTER TAV
    ; between_unicode_range(0x05EF, 0x05F2, Character) % XID_Start # Lo   [4] HEBREW YOD TRIANGLE..HEBREW LIGATURE YIDDISH DOUBLE YOD
    ; between_unicode_range(0x0620, 0x063F, Character) % XID_Start # Lo  [32] ARABIC LETTER KASHMIRI YEH..ARABIC LETTER FARSI YEH WITH THREE DOTS ABOVE
    ; unicode_character(0x0640, Character) % XID_Start # Lm       ARABIC TATWEEL
    ; between_unicode_range(0x0641, 0x064A, Character) % XID_Start # Lo  [10] ARABIC LETTER FEH..ARABIC LETTER YEH
    ; between_unicode_range(0x066E, 0x066F, Character) % XID_Start # Lo   [2] ARABIC LETTER DOTLESS BEH..ARABIC LETTER DOTLESS QAF
    ; between_unicode_range(0x0671, 0x06D3, Character) % XID_Start # Lo  [99] ARABIC LETTER ALEF WASLA..ARABIC LETTER YEH BARREE WITH HAMZA ABOVE
    ; unicode_character(0x06D5, Character) % XID_Start # Lo       ARABIC LETTER AE
    ; between_unicode_range(0x06E5, 0x06E6, Character) % XID_Start # Lm   [2] ARABIC SMALL WAW..ARABIC SMALL YEH
    ; between_unicode_range(0x06EE, 0x06EF, Character) % XID_Start # Lo   [2] ARABIC LETTER DAL WITH INVERTED V..ARABIC LETTER REH WITH INVERTED V
    ; between_unicode_range(0x06FA, 0x06FC, Character) % XID_Start # Lo   [3] ARABIC LETTER SHEEN WITH DOT BELOW..ARABIC LETTER GHAIN WITH DOT BELOW
    ; unicode_character(0x06FF, Character) % XID_Start # Lo       ARABIC LETTER HEH WITH INVERTED V
    ; unicode_character(0x0710, Character) % XID_Start # Lo       SYRIAC LETTER ALAPH
    ; between_unicode_range(0x0712, 0x072F, Character) % XID_Start # Lo  [30] SYRIAC LETTER BETH..SYRIAC LETTER PERSIAN DHALATH
    ; between_unicode_range(0x074D, 0x07A5, Character) % XID_Start # Lo  [89] SYRIAC LETTER SOGDIAN ZHAIN..THAANA LETTER WAAVU
    ; unicode_character(0x07B1, Character) % XID_Start # Lo       THAANA LETTER NAA
    ; between_unicode_range(0x07CA, 0x07EA, Character) % XID_Start # Lo  [33] NKO LETTER A..NKO LETTER JONA RA
    ; between_unicode_range(0x07F4, 0x07F5, Character) % XID_Start # Lm   [2] NKO HIGH TONE APOSTROPHE..NKO LOW TONE APOSTROPHE
    ; unicode_character(0x07FA, Character) % XID_Start # Lm       NKO LAJANYALAN
    ; between_unicode_range(0x0800, 0x0815, Character) % XID_Start # Lo  [22] SAMARITAN LETTER ALAF..SAMARITAN LETTER TAAF
    ; unicode_character(0x081A, Character) % XID_Start # Lm       SAMARITAN MODIFIER LETTER EPENTHETIC YUT
    ; unicode_character(0x0824, Character) % XID_Start # Lm       SAMARITAN MODIFIER LETTER SHORT A
    ; unicode_character(0x0828, Character) % XID_Start # Lm       SAMARITAN MODIFIER LETTER I
    ; between_unicode_range(0x0840, 0x0858, Character) % XID_Start # Lo  [25] MANDAIC LETTER HALQA..MANDAIC LETTER AIN
    ; between_unicode_range(0x0860, 0x086A, Character) % XID_Start # Lo  [11] SYRIAC LETTER MALAYALAM NGA..SYRIAC LETTER MALAYALAM SSA
    ; between_unicode_range(0x0870, 0x0887, Character) % XID_Start # Lo  [24] ARABIC LETTER ALEF WITH ATTACHED FATHA..ARABIC BASELINE ROUND DOT
    ; between_unicode_range(0x0889, 0x088E, Character) % XID_Start # Lo   [6] ARABIC LETTER NOON WITH INVERTED SMALL V..ARABIC VERTICAL TAIL
    ; between_unicode_range(0x08A0, 0x08C8, Character) % XID_Start # Lo  [41] ARABIC LETTER BEH WITH SMALL V BELOW..ARABIC LETTER GRAF
    ; unicode_character(0x08C9, Character) % XID_Start # Lm       ARABIC SMALL FARSI YEH
    ; between_unicode_range(0x0904, 0x0939, Character) % XID_Start # Lo  [54] DEVANAGARI LETTER SHORT A..DEVANAGARI LETTER HA
    ; unicode_character(0x093D, Character) % XID_Start # Lo       DEVANAGARI SIGN AVAGRAHA
    ; unicode_character(0x0950, Character) % XID_Start # Lo       DEVANAGARI OM
    ; between_unicode_range(0x0958, 0x0961, Character) % XID_Start # Lo  [10] DEVANAGARI LETTER QA..DEVANAGARI LETTER VOCALIC LL
    ; unicode_character(0x0971, Character) % XID_Start # Lm       DEVANAGARI SIGN HIGH SPACING DOT
    ; between_unicode_range(0x0972, 0x0980, Character) % XID_Start # Lo  [15] DEVANAGARI LETTER CANDRA A..BENGALI ANJI
    ; between_unicode_range(0x0985, 0x098C, Character) % XID_Start # Lo   [8] BENGALI LETTER A..BENGALI LETTER VOCALIC L
    ; between_unicode_range(0x098F, 0x0990, Character) % XID_Start # Lo   [2] BENGALI LETTER E..BENGALI LETTER AI
    ; between_unicode_range(0x0993, 0x09A8, Character) % XID_Start # Lo  [22] BENGALI LETTER O..BENGALI LETTER NA
    ; between_unicode_range(0x09AA, 0x09B0, Character) % XID_Start # Lo   [7] BENGALI LETTER PA..BENGALI LETTER RA
    ; unicode_character(0x09B2, Character) % XID_Start # Lo       BENGALI LETTER LA
    ; between_unicode_range(0x09B6, 0x09B9, Character) % XID_Start # Lo   [4] BENGALI LETTER SHA..BENGALI LETTER HA
    ; unicode_character(0x09BD, Character) % XID_Start # Lo       BENGALI SIGN AVAGRAHA
    ; unicode_character(0x09CE, Character) % XID_Start # Lo       BENGALI LETTER KHANDA TA
    ; between_unicode_range(0x09DC, 0x09DD, Character) % XID_Start # Lo   [2] BENGALI LETTER RRA..BENGALI LETTER RHA
    ; between_unicode_range(0x09DF, 0x09E1, Character) % XID_Start # Lo   [3] BENGALI LETTER YYA..BENGALI LETTER VOCALIC LL
    ; between_unicode_range(0x09F0, 0x09F1, Character) % XID_Start # Lo   [2] BENGALI LETTER RA WITH MIDDLE DIAGONAL..BENGALI LETTER RA WITH LOWER DIAGONAL
    ; unicode_character(0x09FC, Character) % XID_Start # Lo       BENGALI LETTER VEDIC ANUSVARA
    ; between_unicode_range(0x0A05, 0x0A0A, Character) % XID_Start # Lo   [6] GURMUKHI LETTER A..GURMUKHI LETTER UU
    ; between_unicode_range(0x0A0F, 0x0A10, Character) % XID_Start # Lo   [2] GURMUKHI LETTER EE..GURMUKHI LETTER AI
    ; between_unicode_range(0x0A13, 0x0A28, Character) % XID_Start # Lo  [22] GURMUKHI LETTER OO..GURMUKHI LETTER NA
    ; between_unicode_range(0x0A2A, 0x0A30, Character) % XID_Start # Lo   [7] GURMUKHI LETTER PA..GURMUKHI LETTER RA
    ; between_unicode_range(0x0A32, 0x0A33, Character) % XID_Start # Lo   [2] GURMUKHI LETTER LA..GURMUKHI LETTER LLA
    ; between_unicode_range(0x0A35, 0x0A36, Character) % XID_Start # Lo   [2] GURMUKHI LETTER VA..GURMUKHI LETTER SHA
    ; between_unicode_range(0x0A38, 0x0A39, Character) % XID_Start # Lo   [2] GURMUKHI LETTER SA..GURMUKHI LETTER HA
    ; between_unicode_range(0x0A59, 0x0A5C, Character) % XID_Start # Lo   [4] GURMUKHI LETTER KHHA..GURMUKHI LETTER RRA
    ; unicode_character(0x0A5E, Character) % XID_Start # Lo       GURMUKHI LETTER FA
    ; between_unicode_range(0x0A72, 0x0A74, Character) % XID_Start # Lo   [3] GURMUKHI IRI..GURMUKHI EK ONKAR
    ; between_unicode_range(0x0A85, 0x0A8D, Character) % XID_Start # Lo   [9] GUJARATI LETTER A..GUJARATI VOWEL CANDRA E
    ; between_unicode_range(0x0A8F, 0x0A91, Character) % XID_Start # Lo   [3] GUJARATI LETTER E..GUJARATI VOWEL CANDRA O
    ; between_unicode_range(0x0A93, 0x0AA8, Character) % XID_Start # Lo  [22] GUJARATI LETTER O..GUJARATI LETTER NA
    ; between_unicode_range(0x0AAA, 0x0AB0, Character) % XID_Start # Lo   [7] GUJARATI LETTER PA..GUJARATI LETTER RA
    ; between_unicode_range(0x0AB2, 0x0AB3, Character) % XID_Start # Lo   [2] GUJARATI LETTER LA..GUJARATI LETTER LLA
    ; between_unicode_range(0x0AB5, 0x0AB9, Character) % XID_Start # Lo   [5] GUJARATI LETTER VA..GUJARATI LETTER HA
    ; unicode_character(0x0ABD, Character) % XID_Start # Lo       GUJARATI SIGN AVAGRAHA
    ; unicode_character(0x0AD0, Character) % XID_Start # Lo       GUJARATI OM
    ; between_unicode_range(0x0AE0, 0x0AE1, Character) % XID_Start # Lo   [2] GUJARATI LETTER VOCALIC RR..GUJARATI LETTER VOCALIC LL
    ; unicode_character(0x0AF9, Character) % XID_Start # Lo       GUJARATI LETTER ZHA
    ; between_unicode_range(0x0B05, 0x0B0C, Character) % XID_Start # Lo   [8] ORIYA LETTER A..ORIYA LETTER VOCALIC L
    ; between_unicode_range(0x0B0F, 0x0B10, Character) % XID_Start # Lo   [2] ORIYA LETTER E..ORIYA LETTER AI
    ; between_unicode_range(0x0B13, 0x0B28, Character) % XID_Start # Lo  [22] ORIYA LETTER O..ORIYA LETTER NA
    ; between_unicode_range(0x0B2A, 0x0B30, Character) % XID_Start # Lo   [7] ORIYA LETTER PA..ORIYA LETTER RA
    ; between_unicode_range(0x0B32, 0x0B33, Character) % XID_Start # Lo   [2] ORIYA LETTER LA..ORIYA LETTER LLA
    ; between_unicode_range(0x0B35, 0x0B39, Character) % XID_Start # Lo   [5] ORIYA LETTER VA..ORIYA LETTER HA
    ; unicode_character(0x0B3D, Character) % XID_Start # Lo       ORIYA SIGN AVAGRAHA
    ; between_unicode_range(0x0B5C, 0x0B5D, Character) % XID_Start # Lo   [2] ORIYA LETTER RRA..ORIYA LETTER RHA
    ; between_unicode_range(0x0B5F, 0x0B61, Character) % XID_Start # Lo   [3] ORIYA LETTER YYA..ORIYA LETTER VOCALIC LL
    ; unicode_character(0x0B71, Character) % XID_Start # Lo       ORIYA LETTER WA
    ; unicode_character(0x0B83, Character) % XID_Start # Lo       TAMIL SIGN VISARGA
    ; between_unicode_range(0x0B85, 0x0B8A, Character) % XID_Start # Lo   [6] TAMIL LETTER A..TAMIL LETTER UU
    ; between_unicode_range(0x0B8E, 0x0B90, Character) % XID_Start # Lo   [3] TAMIL LETTER E..TAMIL LETTER AI
    ; between_unicode_range(0x0B92, 0x0B95, Character) % XID_Start # Lo   [4] TAMIL LETTER O..TAMIL LETTER KA
    ; between_unicode_range(0x0B99, 0x0B9A, Character) % XID_Start # Lo   [2] TAMIL LETTER NGA..TAMIL LETTER CA
    ; unicode_character(0x0B9C, Character) % XID_Start # Lo       TAMIL LETTER JA
    ; between_unicode_range(0x0B9E, 0x0B9F, Character) % XID_Start # Lo   [2] TAMIL LETTER NYA..TAMIL LETTER TTA
    ; between_unicode_range(0x0BA3, 0x0BA4, Character) % XID_Start # Lo   [2] TAMIL LETTER NNA..TAMIL LETTER TA
    ; between_unicode_range(0x0BA8, 0x0BAA, Character) % XID_Start # Lo   [3] TAMIL LETTER NA..TAMIL LETTER PA
    ; between_unicode_range(0x0BAE, 0x0BB9, Character) % XID_Start # Lo  [12] TAMIL LETTER MA..TAMIL LETTER HA
    ; unicode_character(0x0BD0, Character) % XID_Start # Lo       TAMIL OM
    ; between_unicode_range(0x0C05, 0x0C0C, Character) % XID_Start # Lo   [8] TELUGU LETTER A..TELUGU LETTER VOCALIC L
    ; between_unicode_range(0x0C0E, 0x0C10, Character) % XID_Start # Lo   [3] TELUGU LETTER E..TELUGU LETTER AI
    ; between_unicode_range(0x0C12, 0x0C28, Character) % XID_Start # Lo  [23] TELUGU LETTER O..TELUGU LETTER NA
    ; between_unicode_range(0x0C2A, 0x0C39, Character) % XID_Start # Lo  [16] TELUGU LETTER PA..TELUGU LETTER HA
    ; unicode_character(0x0C3D, Character) % XID_Start # Lo       TELUGU SIGN AVAGRAHA
    ; between_unicode_range(0x0C58, 0x0C5A, Character) % XID_Start # Lo   [3] TELUGU LETTER TSA..TELUGU LETTER RRRA
    ; unicode_character(0x0C5D, Character) % XID_Start # Lo       TELUGU LETTER NAKAARA POLLU
    ; between_unicode_range(0x0C60, 0x0C61, Character) % XID_Start # Lo   [2] TELUGU LETTER VOCALIC RR..TELUGU LETTER VOCALIC LL
    ; unicode_character(0x0C80, Character) % XID_Start # Lo       KANNADA SIGN SPACING CANDRABINDU
    ; between_unicode_range(0x0C85, 0x0C8C, Character) % XID_Start # Lo   [8] KANNADA LETTER A..KANNADA LETTER VOCALIC L
    ; between_unicode_range(0x0C8E, 0x0C90, Character) % XID_Start # Lo   [3] KANNADA LETTER E..KANNADA LETTER AI
    ; between_unicode_range(0x0C92, 0x0CA8, Character) % XID_Start # Lo  [23] KANNADA LETTER O..KANNADA LETTER NA
    ; between_unicode_range(0x0CAA, 0x0CB3, Character) % XID_Start # Lo  [10] KANNADA LETTER PA..KANNADA LETTER LLA
    ; between_unicode_range(0x0CB5, 0x0CB9, Character) % XID_Start # Lo   [5] KANNADA LETTER VA..KANNADA LETTER HA
    ; unicode_character(0x0CBD, Character) % XID_Start # Lo       KANNADA SIGN AVAGRAHA
    ; between_unicode_range(0x0CDD, 0x0CDE, Character) % XID_Start # Lo   [2] KANNADA LETTER NAKAARA POLLU..KANNADA LETTER FA
    ; between_unicode_range(0x0CE0, 0x0CE1, Character) % XID_Start # Lo   [2] KANNADA LETTER VOCALIC RR..KANNADA LETTER VOCALIC LL
    ; between_unicode_range(0x0CF1, 0x0CF2, Character) % XID_Start # Lo   [2] KANNADA SIGN JIHVAMULIYA..KANNADA SIGN UPADHMANIYA
    ; between_unicode_range(0x0D04, 0x0D0C, Character) % XID_Start # Lo   [9] MALAYALAM LETTER VEDIC ANUSVARA..MALAYALAM LETTER VOCALIC L
    ; between_unicode_range(0x0D0E, 0x0D10, Character) % XID_Start # Lo   [3] MALAYALAM LETTER E..MALAYALAM LETTER AI
    ; between_unicode_range(0x0D12, 0x0D3A, Character) % XID_Start # Lo  [41] MALAYALAM LETTER O..MALAYALAM LETTER TTTA
    ; unicode_character(0x0D3D, Character) % XID_Start # Lo       MALAYALAM SIGN AVAGRAHA
    ; unicode_character(0x0D4E, Character) % XID_Start # Lo       MALAYALAM LETTER DOT REPH
    ; between_unicode_range(0x0D54, 0x0D56, Character) % XID_Start # Lo   [3] MALAYALAM LETTER CHILLU M..MALAYALAM LETTER CHILLU LLL
    ; between_unicode_range(0x0D5F, 0x0D61, Character) % XID_Start # Lo   [3] MALAYALAM LETTER ARCHAIC II..MALAYALAM LETTER VOCALIC LL
    ; between_unicode_range(0x0D7A, 0x0D7F, Character) % XID_Start # Lo   [6] MALAYALAM LETTER CHILLU NN..MALAYALAM LETTER CHILLU K
    ; between_unicode_range(0x0D85, 0x0D96, Character) % XID_Start # Lo  [18] SINHALA LETTER AYANNA..SINHALA LETTER AUYANNA
    ; between_unicode_range(0x0D9A, 0x0DB1, Character) % XID_Start # Lo  [24] SINHALA LETTER ALPAPRAANA KAYANNA..SINHALA LETTER DANTAJA NAYANNA
    ; between_unicode_range(0x0DB3, 0x0DBB, Character) % XID_Start # Lo   [9] SINHALA LETTER SANYAKA DAYANNA..SINHALA LETTER RAYANNA
    ; unicode_character(0x0DBD, Character) % XID_Start # Lo       SINHALA LETTER DANTAJA LAYANNA
    ; between_unicode_range(0x0DC0, 0x0DC6, Character) % XID_Start # Lo   [7] SINHALA LETTER VAYANNA..SINHALA LETTER FAYANNA
    ; between_unicode_range(0x0E01, 0x0E30, Character) % XID_Start # Lo  [48] THAI CHARACTER KO KAI..THAI CHARACTER SARA A
    ; unicode_character(0x0E32, Character) % XID_Start # Lo       THAI CHARACTER SARA AA
    ; between_unicode_range(0x0E40, 0x0E45, Character) % XID_Start # Lo   [6] THAI CHARACTER SARA E..THAI CHARACTER LAKKHANGYAO
    ; unicode_character(0x0E46, Character) % XID_Start # Lm       THAI CHARACTER MAIYAMOK
    ; between_unicode_range(0x0E81, 0x0E82, Character) % XID_Start # Lo   [2] LAO LETTER KO..LAO LETTER KHO SUNG
    ; unicode_character(0x0E84, Character) % XID_Start # Lo       LAO LETTER KHO TAM
    ; between_unicode_range(0x0E86, 0x0E8A, Character) % XID_Start # Lo   [5] LAO LETTER PALI GHA..LAO LETTER SO TAM
    ; between_unicode_range(0x0E8C, 0x0EA3, Character) % XID_Start # Lo  [24] LAO LETTER PALI JHA..LAO LETTER LO LING
    ; unicode_character(0x0EA5, Character) % XID_Start # Lo       LAO LETTER LO LOOT
    ; between_unicode_range(0x0EA7, 0x0EB0, Character) % XID_Start # Lo  [10] LAO LETTER WO..LAO VOWEL SIGN A
    ; unicode_character(0x0EB2, Character) % XID_Start # Lo       LAO VOWEL SIGN AA
    ; unicode_character(0x0EBD, Character) % XID_Start # Lo       LAO SEMIVOWEL SIGN NYO
    ; between_unicode_range(0x0EC0, 0x0EC4, Character) % XID_Start # Lo   [5] LAO VOWEL SIGN E..LAO VOWEL SIGN AI
    ; unicode_character(0x0EC6, Character) % XID_Start # Lm       LAO KO LA
    ; between_unicode_range(0x0EDC, 0x0EDF, Character) % XID_Start # Lo   [4] LAO HO NO..LAO LETTER KHMU NYO
    ; unicode_character(0x0F00, Character) % XID_Start # Lo       TIBETAN SYLLABLE OM
    ; between_unicode_range(0x0F40, 0x0F47, Character) % XID_Start # Lo   [8] TIBETAN LETTER KA..TIBETAN LETTER JA
    ; between_unicode_range(0x0F49, 0x0F6C, Character) % XID_Start # Lo  [36] TIBETAN LETTER NYA..TIBETAN LETTER RRA
    ; between_unicode_range(0x0F88, 0x0F8C, Character) % XID_Start # Lo   [5] TIBETAN SIGN LCE TSA CAN..TIBETAN SIGN INVERTED MCHU CAN
    ; between_unicode_range(0x1000, 0x102A, Character) % XID_Start # Lo  [43] MYANMAR LETTER KA..MYANMAR LETTER AU
    ; unicode_character(0x103F, Character) % XID_Start # Lo       MYANMAR LETTER GREAT SA
    ; between_unicode_range(0x1050, 0x1055, Character) % XID_Start # Lo   [6] MYANMAR LETTER SHA..MYANMAR LETTER VOCALIC LL
    ; between_unicode_range(0x105A, 0x105D, Character) % XID_Start # Lo   [4] MYANMAR LETTER MON NGA..MYANMAR LETTER MON BBE
    ; unicode_character(0x1061, Character) % XID_Start # Lo       MYANMAR LETTER SGAW KAREN SHA
    ; between_unicode_range(0x1065, 0x1066, Character) % XID_Start # Lo   [2] MYANMAR LETTER WESTERN PWO KAREN THA..MYANMAR LETTER WESTERN PWO KAREN PWA
    ; between_unicode_range(0x106E, 0x1070, Character) % XID_Start # Lo   [3] MYANMAR LETTER EASTERN PWO KAREN NNA..MYANMAR LETTER EASTERN PWO KAREN GHWA
    ; between_unicode_range(0x1075, 0x1081, Character) % XID_Start # Lo  [13] MYANMAR LETTER SHAN KA..MYANMAR LETTER SHAN HA
    ; unicode_character(0x108E, Character) % XID_Start # Lo       MYANMAR LETTER RUMAI PALAUNG FA
    ; between_unicode_range(0x10A0, 0x10C5, Character) % XID_Start # L&  [38] GEORGIAN CAPITAL LETTER AN..GEORGIAN CAPITAL LETTER HOE
    ; unicode_character(0x10C7, Character) % XID_Start # L&       GEORGIAN CAPITAL LETTER YN
    ; unicode_character(0x10CD, Character) % XID_Start # L&       GEORGIAN CAPITAL LETTER AEN
    ; between_unicode_range(0x10D0, 0x10FA, Character) % XID_Start # L&  [43] GEORGIAN LETTER AN..GEORGIAN LETTER AIN
    ; unicode_character(0x10FC, Character) % XID_Start # Lm       MODIFIER LETTER GEORGIAN NAR
    ; between_unicode_range(0x10FD, 0x10FF, Character) % XID_Start # L&   [3] GEORGIAN LETTER AEN..GEORGIAN LETTER LABIAL SIGN
    ; between_unicode_range(0x1100, 0x1248, Character) % XID_Start # Lo [329] HANGUL CHOSEONG KIYEOK..ETHIOPIC SYLLABLE QWA
    ; between_unicode_range(0x124A, 0x124D, Character) % XID_Start # Lo   [4] ETHIOPIC SYLLABLE QWI..ETHIOPIC SYLLABLE QWE
    ; between_unicode_range(0x1250, 0x1256, Character) % XID_Start # Lo   [7] ETHIOPIC SYLLABLE QHA..ETHIOPIC SYLLABLE QHO
    ; unicode_character(0x1258, Character) % XID_Start # Lo       ETHIOPIC SYLLABLE QHWA
    ; between_unicode_range(0x125A, 0x125D, Character) % XID_Start # Lo   [4] ETHIOPIC SYLLABLE QHWI..ETHIOPIC SYLLABLE QHWE
    ; between_unicode_range(0x1260, 0x1288, Character) % XID_Start # Lo  [41] ETHIOPIC SYLLABLE BA..ETHIOPIC SYLLABLE XWA
    ; between_unicode_range(0x128A, 0x128D, Character) % XID_Start # Lo   [4] ETHIOPIC SYLLABLE XWI..ETHIOPIC SYLLABLE XWE
    ; between_unicode_range(0x1290, 0x12B0, Character) % XID_Start # Lo  [33] ETHIOPIC SYLLABLE NA..ETHIOPIC SYLLABLE KWA
    ; between_unicode_range(0x12B2, 0x12B5, Character) % XID_Start # Lo   [4] ETHIOPIC SYLLABLE KWI..ETHIOPIC SYLLABLE KWE
    ; between_unicode_range(0x12B8, 0x12BE, Character) % XID_Start # Lo   [7] ETHIOPIC SYLLABLE KXA..ETHIOPIC SYLLABLE KXO
    ; unicode_character(0x12C0, Character) % XID_Start # Lo       ETHIOPIC SYLLABLE KXWA
    ; between_unicode_range(0x12C2, 0x12C5, Character) % XID_Start # Lo   [4] ETHIOPIC SYLLABLE KXWI..ETHIOPIC SYLLABLE KXWE
    ; between_unicode_range(0x12C8, 0x12D6, Character) % XID_Start # Lo  [15] ETHIOPIC SYLLABLE WA..ETHIOPIC SYLLABLE PHARYNGEAL O
    ; between_unicode_range(0x12D8, 0x1310, Character) % XID_Start # Lo  [57] ETHIOPIC SYLLABLE ZA..ETHIOPIC SYLLABLE GWA
    ; between_unicode_range(0x1312, 0x1315, Character) % XID_Start # Lo   [4] ETHIOPIC SYLLABLE GWI..ETHIOPIC SYLLABLE GWE
    ; between_unicode_range(0x1318, 0x135A, Character) % XID_Start # Lo  [67] ETHIOPIC SYLLABLE GGA..ETHIOPIC SYLLABLE FYA
    ; between_unicode_range(0x1380, 0x138F, Character) % XID_Start # Lo  [16] ETHIOPIC SYLLABLE SEBATBEIT MWA..ETHIOPIC SYLLABLE PWE
    ; between_unicode_range(0x13A0, 0x13F5, Character) % XID_Start # L&  [86] CHEROKEE LETTER A..CHEROKEE LETTER MV
    ; between_unicode_range(0x13F8, 0x13FD, Character) % XID_Start # L&   [6] CHEROKEE SMALL LETTER YE..CHEROKEE SMALL LETTER MV
    ; between_unicode_range(0x1401, 0x166C, Character) % XID_Start # Lo [620] CANADIAN SYLLABICS E..CANADIAN SYLLABICS CARRIER TTSA
    ; between_unicode_range(0x166F, 0x167F, Character) % XID_Start # Lo  [17] CANADIAN SYLLABICS QAI..CANADIAN SYLLABICS BLACKFOOT W
    ; between_unicode_range(0x1681, 0x169A, Character) % XID_Start # Lo  [26] OGHAM LETTER BEITH..OGHAM LETTER PEITH
    ; between_unicode_range(0x16A0, 0x16EA, Character) % XID_Start # Lo  [75] RUNIC LETTER FEHU FEOH FE F..RUNIC LETTER X
    ; between_unicode_range(0x16EE, 0x16F0, Character) % XID_Start # Nl   [3] RUNIC ARLAUG SYMBOL..RUNIC BELGTHOR SYMBOL
    ; between_unicode_range(0x16F1, 0x16F8, Character) % XID_Start # Lo   [8] RUNIC LETTER K..RUNIC LETTER FRANKS CASKET AESC
    ; between_unicode_range(0x1700, 0x1711, Character) % XID_Start # Lo  [18] TAGALOG LETTER A..TAGALOG LETTER HA
    ; between_unicode_range(0x171F, 0x1731, Character) % XID_Start # Lo  [19] TAGALOG LETTER ARCHAIC RA..HANUNOO LETTER HA
    ; between_unicode_range(0x1740, 0x1751, Character) % XID_Start # Lo  [18] BUHID LETTER A..BUHID LETTER HA
    ; between_unicode_range(0x1760, 0x176C, Character) % XID_Start # Lo  [13] TAGBANWA LETTER A..TAGBANWA LETTER YA
    ; between_unicode_range(0x176E, 0x1770, Character) % XID_Start # Lo   [3] TAGBANWA LETTER LA..TAGBANWA LETTER SA
    ; between_unicode_range(0x1780, 0x17B3, Character) % XID_Start # Lo  [52] KHMER LETTER KA..KHMER INDEPENDENT VOWEL QAU
    ; unicode_character(0x17D7, Character) % XID_Start # Lm       KHMER SIGN LEK TOO
    ; unicode_character(0x17DC, Character) % XID_Start # Lo       KHMER SIGN AVAKRAHASANYA
    ; between_unicode_range(0x1820, 0x1842, Character) % XID_Start # Lo  [35] MONGOLIAN LETTER A..MONGOLIAN LETTER CHI
    ; unicode_character(0x1843, Character) % XID_Start # Lm       MONGOLIAN LETTER TODO LONG VOWEL SIGN
    ; between_unicode_range(0x1844, 0x1878, Character) % XID_Start # Lo  [53] MONGOLIAN LETTER TODO E..MONGOLIAN LETTER CHA WITH TWO DOTS
    ; between_unicode_range(0x1880, 0x1884, Character) % XID_Start # Lo   [5] MONGOLIAN LETTER ALI GALI ANUSVARA ONE..MONGOLIAN LETTER ALI GALI INVERTED UBADAMA
    ; between_unicode_range(0x1885, 0x1886, Character) % XID_Start # Mn   [2] MONGOLIAN LETTER ALI GALI BALUDA..MONGOLIAN LETTER ALI GALI THREE BALUDA
    ; between_unicode_range(0x1887, 0x18A8, Character) % XID_Start # Lo  [34] MONGOLIAN LETTER ALI GALI A..MONGOLIAN LETTER MANCHU ALI GALI BHA
    ; unicode_character(0x18AA, Character) % XID_Start # Lo       MONGOLIAN LETTER MANCHU ALI GALI LHA
    ; between_unicode_range(0x18B0, 0x18F5, Character) % XID_Start # Lo  [70] CANADIAN SYLLABICS OY..CANADIAN SYLLABICS CARRIER DENTAL S
    ; between_unicode_range(0x1900, 0x191E, Character) % XID_Start # Lo  [31] LIMBU VOWEL-CARRIER LETTER..LIMBU LETTER TRA
    ; between_unicode_range(0x1950, 0x196D, Character) % XID_Start # Lo  [30] TAI LE LETTER KA..TAI LE LETTER AI
    ; between_unicode_range(0x1970, 0x1974, Character) % XID_Start # Lo   [5] TAI LE LETTER TONE-2..TAI LE LETTER TONE-6
    ; between_unicode_range(0x1980, 0x19AB, Character) % XID_Start # Lo  [44] NEW TAI LUE LETTER HIGH QA..NEW TAI LUE LETTER LOW SUA
    ; between_unicode_range(0x19B0, 0x19C9, Character) % XID_Start # Lo  [26] NEW TAI LUE VOWEL SIGN VOWEL SHORTENER..NEW TAI LUE TONE MARK-2
    ; between_unicode_range(0x1A00, 0x1A16, Character) % XID_Start # Lo  [23] BUGINESE LETTER KA..BUGINESE LETTER HA
    ; between_unicode_range(0x1A20, 0x1A54, Character) % XID_Start # Lo  [53] TAI THAM LETTER HIGH KA..TAI THAM LETTER GREAT SA
    ; unicode_character(0x1AA7, Character) % XID_Start # Lm       TAI THAM SIGN MAI YAMOK
    ; between_unicode_range(0x1B05, 0x1B33, Character) % XID_Start # Lo  [47] BALINESE LETTER AKARA..BALINESE LETTER HA
    ; between_unicode_range(0x1B45, 0x1B4C, Character) % XID_Start # Lo   [8] BALINESE LETTER KAF SASAK..BALINESE LETTER ARCHAIC JNYA
    ; between_unicode_range(0x1B83, 0x1BA0, Character) % XID_Start # Lo  [30] SUNDANESE LETTER A..SUNDANESE LETTER HA
    ; between_unicode_range(0x1BAE, 0x1BAF, Character) % XID_Start # Lo   [2] SUNDANESE LETTER KHA..SUNDANESE LETTER SYA
    ; between_unicode_range(0x1BBA, 0x1BE5, Character) % XID_Start # Lo  [44] SUNDANESE AVAGRAHA..BATAK LETTER U
    ; between_unicode_range(0x1C00, 0x1C23, Character) % XID_Start # Lo  [36] LEPCHA LETTER KA..LEPCHA LETTER A
    ; between_unicode_range(0x1C4D, 0x1C4F, Character) % XID_Start # Lo   [3] LEPCHA LETTER TTA..LEPCHA LETTER DDA
    ; between_unicode_range(0x1C5A, 0x1C77, Character) % XID_Start # Lo  [30] OL CHIKI LETTER LA..OL CHIKI LETTER OH
    ; between_unicode_range(0x1C78, 0x1C7D, Character) % XID_Start # Lm   [6] OL CHIKI MU TTUDDAG..OL CHIKI AHAD
    ; between_unicode_range(0x1C80, 0x1C8A, Character) % XID_Start # L&  [11] CYRILLIC SMALL LETTER ROUNDED VE..CYRILLIC SMALL LETTER TJE
    ; between_unicode_range(0x1C90, 0x1CBA, Character) % XID_Start # L&  [43] GEORGIAN MTAVRULI CAPITAL LETTER AN..GEORGIAN MTAVRULI CAPITAL LETTER AIN
    ; between_unicode_range(0x1CBD, 0x1CBF, Character) % XID_Start # L&   [3] GEORGIAN MTAVRULI CAPITAL LETTER AEN..GEORGIAN MTAVRULI CAPITAL LETTER LABIAL SIGN
    ; between_unicode_range(0x1CE9, 0x1CEC, Character) % XID_Start # Lo   [4] VEDIC SIGN ANUSVARA ANTARGOMUKHA..VEDIC SIGN ANUSVARA VAMAGOMUKHA WITH TAIL
    ; between_unicode_range(0x1CEE, 0x1CF3, Character) % XID_Start # Lo   [6] VEDIC SIGN HEXIFORM LONG ANUSVARA..VEDIC SIGN ROTATED ARDHAVISARGA
    ; between_unicode_range(0x1CF5, 0x1CF6, Character) % XID_Start # Lo   [2] VEDIC SIGN JIHVAMULIYA..VEDIC SIGN UPADHMANIYA
    ; unicode_character(0x1CFA, Character) % XID_Start # Lo       VEDIC SIGN DOUBLE ANUSVARA ANTARGOMUKHA
    ; between_unicode_range(0x1D00, 0x1D2B, Character) % XID_Start # L&  [44] LATIN LETTER SMALL CAPITAL A..CYRILLIC LETTER SMALL CAPITAL EL
    ; between_unicode_range(0x1D2C, 0x1D6A, Character) % XID_Start # Lm  [63] MODIFIER LETTER CAPITAL A..GREEK SUBSCRIPT SMALL LETTER CHI
    ; between_unicode_range(0x1D6B, 0x1D77, Character) % XID_Start # L&  [13] LATIN SMALL LETTER UE..LATIN SMALL LETTER TURNED G
    ; unicode_character(0x1D78, Character) % XID_Start # Lm       MODIFIER LETTER CYRILLIC EN
    ; between_unicode_range(0x1D79, 0x1D9A, Character) % XID_Start # L&  [34] LATIN SMALL LETTER INSULAR G..LATIN SMALL LETTER EZH WITH RETROFLEX HOOK
    ; between_unicode_range(0x1D9B, 0x1DBF, Character) % XID_Start # Lm  [37] MODIFIER LETTER SMALL TURNED ALPHA..MODIFIER LETTER SMALL THETA
    ; between_unicode_range(0x1E00, 0x1F15, Character) % XID_Start # L& [278] LATIN CAPITAL LETTER A WITH RING BELOW..GREEK SMALL LETTER EPSILON WITH DASIA AND OXIA
    ; between_unicode_range(0x1F18, 0x1F1D, Character) % XID_Start # L&   [6] GREEK CAPITAL LETTER EPSILON WITH PSILI..GREEK CAPITAL LETTER EPSILON WITH DASIA AND OXIA
    ; between_unicode_range(0x1F20, 0x1F45, Character) % XID_Start # L&  [38] GREEK SMALL LETTER ETA WITH PSILI..GREEK SMALL LETTER OMICRON WITH DASIA AND OXIA
    ; between_unicode_range(0x1F48, 0x1F4D, Character) % XID_Start # L&   [6] GREEK CAPITAL LETTER OMICRON WITH PSILI..GREEK CAPITAL LETTER OMICRON WITH DASIA AND OXIA
    ; between_unicode_range(0x1F50, 0x1F57, Character) % XID_Start # L&   [8] GREEK SMALL LETTER UPSILON WITH PSILI..GREEK SMALL LETTER UPSILON WITH DASIA AND PERISPOMENI
    ; unicode_character(0x1F59, Character) % XID_Start # L&       GREEK CAPITAL LETTER UPSILON WITH DASIA
    ; unicode_character(0x1F5B, Character) % XID_Start # L&       GREEK CAPITAL LETTER UPSILON WITH DASIA AND VARIA
    ; unicode_character(0x1F5D, Character) % XID_Start # L&       GREEK CAPITAL LETTER UPSILON WITH DASIA AND OXIA
    ; between_unicode_range(0x1F5F, 0x1F7D, Character) % XID_Start # L&  [31] GREEK CAPITAL LETTER UPSILON WITH DASIA AND PERISPOMENI..GREEK SMALL LETTER OMEGA WITH OXIA
    ; between_unicode_range(0x1F80, 0x1FB4, Character) % XID_Start # L&  [53] GREEK SMALL LETTER ALPHA WITH PSILI AND YPOGEGRAMMENI..GREEK SMALL LETTER ALPHA WITH OXIA AND YPOGEGRAMMENI
    ; between_unicode_range(0x1FB6, 0x1FBC, Character) % XID_Start # L&   [7] GREEK SMALL LETTER ALPHA WITH PERISPOMENI..GREEK CAPITAL LETTER ALPHA WITH PROSGEGRAMMENI
    ; unicode_character(0x1FBE, Character) % XID_Start # L&       GREEK PROSGEGRAMMENI
    ; between_unicode_range(0x1FC2, 0x1FC4, Character) % XID_Start # L&   [3] GREEK SMALL LETTER ETA WITH VARIA AND YPOGEGRAMMENI..GREEK SMALL LETTER ETA WITH OXIA AND YPOGEGRAMMENI
    ; between_unicode_range(0x1FC6, 0x1FCC, Character) % XID_Start # L&   [7] GREEK SMALL LETTER ETA WITH PERISPOMENI..GREEK CAPITAL LETTER ETA WITH PROSGEGRAMMENI
    ; between_unicode_range(0x1FD0, 0x1FD3, Character) % XID_Start # L&   [4] GREEK SMALL LETTER IOTA WITH VRACHY..GREEK SMALL LETTER IOTA WITH DIALYTIKA AND OXIA
    ; between_unicode_range(0x1FD6, 0x1FDB, Character) % XID_Start # L&   [6] GREEK SMALL LETTER IOTA WITH PERISPOMENI..GREEK CAPITAL LETTER IOTA WITH OXIA
    ; between_unicode_range(0x1FE0, 0x1FEC, Character) % XID_Start # L&  [13] GREEK SMALL LETTER UPSILON WITH VRACHY..GREEK CAPITAL LETTER RHO WITH DASIA
    ; between_unicode_range(0x1FF2, 0x1FF4, Character) % XID_Start # L&   [3] GREEK SMALL LETTER OMEGA WITH VARIA AND YPOGEGRAMMENI..GREEK SMALL LETTER OMEGA WITH OXIA AND YPOGEGRAMMENI
    ; between_unicode_range(0x1FF6, 0x1FFC, Character) % XID_Start # L&   [7] GREEK SMALL LETTER OMEGA WITH PERISPOMENI..GREEK CAPITAL LETTER OMEGA WITH PROSGEGRAMMENI
    ; unicode_character(0x2071, Character) % XID_Start # Lm       SUPERSCRIPT LATIN SMALL LETTER I
    ; unicode_character(0x207F, Character) % XID_Start # Lm       SUPERSCRIPT LATIN SMALL LETTER N
    ; between_unicode_range(0x2090, 0x209C, Character) % XID_Start # Lm  [13] LATIN SUBSCRIPT SMALL LETTER A..LATIN SUBSCRIPT SMALL LETTER T
    ; unicode_character(0x2102, Character) % XID_Start # L&       DOUBLE-STRUCK CAPITAL C
    ; unicode_character(0x2107, Character) % XID_Start # L&       EULER CONSTANT
    ; between_unicode_range(0x210A, 0x2113, Character) % XID_Start # L&  [10] SCRIPT SMALL G..SCRIPT SMALL L
    ; unicode_character(0x2115, Character) % XID_Start # L&       DOUBLE-STRUCK CAPITAL N
    ; unicode_character(0x2118, Character) % XID_Start # Sm       SCRIPT CAPITAL P
    ; between_unicode_range(0x2119, 0x211D, Character) % XID_Start # L&   [5] DOUBLE-STRUCK CAPITAL P..DOUBLE-STRUCK CAPITAL R
    ; unicode_character(0x2124, Character) % XID_Start # L&       DOUBLE-STRUCK CAPITAL Z
    ; unicode_character(0x2126, Character) % XID_Start # L&       OHM SIGN
    ; unicode_character(0x2128, Character) % XID_Start # L&       BLACK-LETTER CAPITAL Z
    ; between_unicode_range(0x212A, 0x212D, Character) % XID_Start # L&   [4] KELVIN SIGN..BLACK-LETTER CAPITAL C
    ; unicode_character(0x212E, Character) % XID_Start # So       ESTIMATED SYMBOL
    ; between_unicode_range(0x212F, 0x2134, Character) % XID_Start # L&   [6] SCRIPT SMALL E..SCRIPT SMALL O
    ; between_unicode_range(0x2135, 0x2138, Character) % XID_Start # Lo   [4] ALEF SYMBOL..DALET SYMBOL
    ; unicode_character(0x2139, Character) % XID_Start # L&       INFORMATION SOURCE
    ; between_unicode_range(0x213C, 0x213F, Character) % XID_Start # L&   [4] DOUBLE-STRUCK SMALL PI..DOUBLE-STRUCK CAPITAL PI
    ; between_unicode_range(0x2145, 0x2149, Character) % XID_Start # L&   [5] DOUBLE-STRUCK ITALIC CAPITAL D..DOUBLE-STRUCK ITALIC SMALL J
    ; unicode_character(0x214E, Character) % XID_Start # L&       TURNED SMALL F
    ; between_unicode_range(0x2160, 0x2182, Character) % XID_Start # Nl  [35] ROMAN NUMERAL ONE..ROMAN NUMERAL TEN THOUSAND
    ; between_unicode_range(0x2183, 0x2184, Character) % XID_Start # L&   [2] ROMAN NUMERAL REVERSED ONE HUNDRED..LATIN SMALL LETTER REVERSED C
    ; between_unicode_range(0x2185, 0x2188, Character) % XID_Start # Nl   [4] ROMAN NUMERAL SIX LATE FORM..ROMAN NUMERAL ONE HUNDRED THOUSAND
    ; between_unicode_range(0x2C00, 0x2C7B, Character) % XID_Start # L& [124] GLAGOLITIC CAPITAL LETTER AZU..LATIN LETTER SMALL CAPITAL TURNED E
    ; between_unicode_range(0x2C7C, 0x2C7D, Character) % XID_Start # Lm   [2] LATIN SUBSCRIPT SMALL LETTER J..MODIFIER LETTER CAPITAL V
    ; between_unicode_range(0x2C7E, 0x2CE4, Character) % XID_Start # L& [103] LATIN CAPITAL LETTER S WITH SWASH TAIL..COPTIC SYMBOL KAI
    ; between_unicode_range(0x2CEB, 0x2CEE, Character) % XID_Start # L&   [4] COPTIC CAPITAL LETTER CRYPTOGRAMMIC SHEI..COPTIC SMALL LETTER CRYPTOGRAMMIC GANGIA
    ; between_unicode_range(0x2CF2, 0x2CF3, Character) % XID_Start # L&   [2] COPTIC CAPITAL LETTER BOHAIRIC KHEI..COPTIC SMALL LETTER BOHAIRIC KHEI
    ; between_unicode_range(0x2D00, 0x2D25, Character) % XID_Start # L&  [38] GEORGIAN SMALL LETTER AN..GEORGIAN SMALL LETTER HOE
    ; unicode_character(0x2D27, Character) % XID_Start # L&       GEORGIAN SMALL LETTER YN
    ; unicode_character(0x2D2D, Character) % XID_Start # L&       GEORGIAN SMALL LETTER AEN
    ; between_unicode_range(0x2D30, 0x2D67, Character) % XID_Start # Lo  [56] TIFINAGH LETTER YA..TIFINAGH LETTER YO
    ; unicode_character(0x2D6F, Character) % XID_Start # Lm       TIFINAGH MODIFIER LETTER LABIALIZATION MARK
    ; between_unicode_range(0x2D80, 0x2D96, Character) % XID_Start # Lo  [23] ETHIOPIC SYLLABLE LOA..ETHIOPIC SYLLABLE GGWE
    ; between_unicode_range(0x2DA0, 0x2DA6, Character) % XID_Start # Lo   [7] ETHIOPIC SYLLABLE SSA..ETHIOPIC SYLLABLE SSO
    ; between_unicode_range(0x2DA8, 0x2DAE, Character) % XID_Start # Lo   [7] ETHIOPIC SYLLABLE CCA..ETHIOPIC SYLLABLE CCO
    ; between_unicode_range(0x2DB0, 0x2DB6, Character) % XID_Start # Lo   [7] ETHIOPIC SYLLABLE ZZA..ETHIOPIC SYLLABLE ZZO
    ; between_unicode_range(0x2DB8, 0x2DBE, Character) % XID_Start # Lo   [7] ETHIOPIC SYLLABLE CCHA..ETHIOPIC SYLLABLE CCHO
    ; between_unicode_range(0x2DC0, 0x2DC6, Character) % XID_Start # Lo   [7] ETHIOPIC SYLLABLE QYA..ETHIOPIC SYLLABLE QYO
    ; between_unicode_range(0x2DC8, 0x2DCE, Character) % XID_Start # Lo   [7] ETHIOPIC SYLLABLE KYA..ETHIOPIC SYLLABLE KYO
    ; between_unicode_range(0x2DD0, 0x2DD6, Character) % XID_Start # Lo   [7] ETHIOPIC SYLLABLE XYA..ETHIOPIC SYLLABLE XYO
    ; between_unicode_range(0x2DD8, 0x2DDE, Character) % XID_Start # Lo   [7] ETHIOPIC SYLLABLE GYA..ETHIOPIC SYLLABLE GYO
    ; unicode_character(0x3005, Character) % XID_Start # Lm       IDEOGRAPHIC ITERATION MARK
    ; unicode_character(0x3006, Character) % XID_Start # Lo       IDEOGRAPHIC CLOSING MARK
    ; unicode_character(0x3007, Character) % XID_Start # Nl       IDEOGRAPHIC NUMBER ZERO
    ; between_unicode_range(0x3021, 0x3029, Character) % XID_Start # Nl   [9] HANGZHOU NUMERAL ONE..HANGZHOU NUMERAL NINE
    ; between_unicode_range(0x3031, 0x3035, Character) % XID_Start # Lm   [5] VERTICAL KANA REPEAT MARK..VERTICAL KANA REPEAT MARK LOWER HALF
    ; between_unicode_range(0x3038, 0x303A, Character) % XID_Start # Nl   [3] HANGZHOU NUMERAL TEN..HANGZHOU NUMERAL THIRTY
    ; unicode_character(0x303B, Character) % XID_Start # Lm       VERTICAL IDEOGRAPHIC ITERATION MARK
    ; unicode_character(0x303C, Character) % XID_Start # Lo       MASU MARK
    ; between_unicode_range(0x3041, 0x3096, Character) % XID_Start # Lo  [86] HIRAGANA LETTER SMALL A..HIRAGANA LETTER SMALL KE
    ; between_unicode_range(0x309D, 0x309E, Character) % XID_Start # Lm   [2] HIRAGANA ITERATION MARK..HIRAGANA VOICED ITERATION MARK
    ; unicode_character(0x309F, Character) % XID_Start # Lo       HIRAGANA DIGRAPH YORI
    ; between_unicode_range(0x30A1, 0x30FA, Character) % XID_Start # Lo  [90] KATAKANA LETTER SMALL A..KATAKANA LETTER VO
    ; between_unicode_range(0x30FC, 0x30FE, Character) % XID_Start # Lm   [3] KATAKANA-HIRAGANA PROLONGED SOUND MARK..KATAKANA VOICED ITERATION MARK
    ; unicode_character(0x30FF, Character) % XID_Start # Lo       KATAKANA DIGRAPH KOTO
    ; between_unicode_range(0x3105, 0x312F, Character) % XID_Start # Lo  [43] BOPOMOFO LETTER B..BOPOMOFO LETTER NN
    ; between_unicode_range(0x3131, 0x318E, Character) % XID_Start # Lo  [94] HANGUL LETTER KIYEOK..HANGUL LETTER ARAEAE
    ; between_unicode_range(0x31A0, 0x31BF, Character) % XID_Start # Lo  [32] BOPOMOFO LETTER BU..BOPOMOFO LETTER AH
    ; between_unicode_range(0x31F0, 0x31FF, Character) % XID_Start # Lo  [16] KATAKANA LETTER SMALL KU..KATAKANA LETTER SMALL RO
    ; between_unicode_range(0x3400, 0x4DBF, Character) % XID_Start # Lo [6592] CJK UNIFIED IDEOGRAPH-3400..CJK UNIFIED IDEOGRAPH-4DBF
    ; between_unicode_range(0x4E00, 0xA014, Character) % XID_Start # Lo [21013] CJK UNIFIED IDEOGRAPH-4E00..YI SYLLABLE E
    ; unicode_character(0xA015, Character) % XID_Start # Lm       YI SYLLABLE WU
    ; between_unicode_range(0xA016, 0xA48C, Character) % XID_Start # Lo [1143] YI SYLLABLE BIT..YI SYLLABLE YYR
    ; between_unicode_range(0xA4D0, 0xA4F7, Character) % XID_Start # Lo  [40] LISU LETTER BA..LISU LETTER OE
    ; between_unicode_range(0xA4F8, 0xA4FD, Character) % XID_Start # Lm   [6] LISU LETTER TONE MYA TI..LISU LETTER TONE MYA JEU
    ; between_unicode_range(0xA500, 0xA60B, Character) % XID_Start # Lo [268] VAI SYLLABLE EE..VAI SYLLABLE NG
    ; unicode_character(0xA60C, Character) % XID_Start # Lm       VAI SYLLABLE LENGTHENER
    ; between_unicode_range(0xA610, 0xA61F, Character) % XID_Start # Lo  [16] VAI SYLLABLE NDOLE FA..VAI SYMBOL JONG
    ; between_unicode_range(0xA62A, 0xA62B, Character) % XID_Start # Lo   [2] VAI SYLLABLE NDOLE MA..VAI SYLLABLE NDOLE DO
    ; between_unicode_range(0xA640, 0xA66D, Character) % XID_Start # L&  [46] CYRILLIC CAPITAL LETTER ZEMLYA..CYRILLIC SMALL LETTER DOUBLE MONOCULAR O
    ; unicode_character(0xA66E, Character) % XID_Start # Lo       CYRILLIC LETTER MULTIOCULAR O
    ; unicode_character(0xA67F, Character) % XID_Start # Lm       CYRILLIC PAYEROK
    ; between_unicode_range(0xA680, 0xA69B, Character) % XID_Start # L&  [28] CYRILLIC CAPITAL LETTER DWE..CYRILLIC SMALL LETTER CROSSED O
    ; between_unicode_range(0xA69C, 0xA69D, Character) % XID_Start # Lm   [2] MODIFIER LETTER CYRILLIC HARD SIGN..MODIFIER LETTER CYRILLIC SOFT SIGN
    ; between_unicode_range(0xA6A0, 0xA6E5, Character) % XID_Start # Lo  [70] BAMUM LETTER A..BAMUM LETTER KI
    ; between_unicode_range(0xA6E6, 0xA6EF, Character) % XID_Start # Nl  [10] BAMUM LETTER MO..BAMUM LETTER KOGHOM
    ; between_unicode_range(0xA717, 0xA71F, Character) % XID_Start # Lm   [9] MODIFIER LETTER DOT VERTICAL BAR..MODIFIER LETTER LOW INVERTED EXCLAMATION MARK
    ; between_unicode_range(0xA722, 0xA76F, Character) % XID_Start # L&  [78] LATIN CAPITAL LETTER EGYPTOLOGICAL ALEF..LATIN SMALL LETTER CON
    ; unicode_character(0xA770, Character) % XID_Start # Lm       MODIFIER LETTER US
    ; between_unicode_range(0xA771, 0xA787, Character) % XID_Start # L&  [23] LATIN SMALL LETTER DUM..LATIN SMALL LETTER INSULAR T
    ; unicode_character(0xA788, Character) % XID_Start # Lm       MODIFIER LETTER LOW CIRCUMFLEX ACCENT
    ; between_unicode_range(0xA78B, 0xA78E, Character) % XID_Start # L&   [4] LATIN CAPITAL LETTER SALTILLO..LATIN SMALL LETTER L WITH RETROFLEX HOOK AND BELT
    ; unicode_character(0xA78F, Character) % XID_Start # Lo       LATIN LETTER SINOLOGICAL DOT
    ; between_unicode_range(0xA790, 0xA7CD, Character) % XID_Start # L&  [62] LATIN CAPITAL LETTER N WITH DESCENDER..LATIN SMALL LETTER S WITH DIAGONAL STROKE
    ; between_unicode_range(0xA7D0, 0xA7D1, Character) % XID_Start # L&   [2] LATIN CAPITAL LETTER CLOSED INSULAR G..LATIN SMALL LETTER CLOSED INSULAR G
    ; unicode_character(0xA7D3, Character) % XID_Start # L&       LATIN SMALL LETTER DOUBLE THORN
    ; between_unicode_range(0xA7D5, 0xA7DC, Character) % XID_Start # L&   [8] LATIN SMALL LETTER DOUBLE WYNN..LATIN CAPITAL LETTER LAMBDA WITH STROKE
    ; between_unicode_range(0xA7F2, 0xA7F4, Character) % XID_Start # Lm   [3] MODIFIER LETTER CAPITAL C..MODIFIER LETTER CAPITAL Q
    ; between_unicode_range(0xA7F5, 0xA7F6, Character) % XID_Start # L&   [2] LATIN CAPITAL LETTER REVERSED HALF H..LATIN SMALL LETTER REVERSED HALF H
    ; unicode_character(0xA7F7, Character) % XID_Start # Lo       LATIN EPIGRAPHIC LETTER SIDEWAYS I
    ; between_unicode_range(0xA7F8, 0xA7F9, Character) % XID_Start # Lm   [2] MODIFIER LETTER CAPITAL H WITH STROKE..MODIFIER LETTER SMALL LIGATURE OE
    ; unicode_character(0xA7FA, Character) % XID_Start # L&       LATIN LETTER SMALL CAPITAL TURNED M
    ; between_unicode_range(0xA7FB, 0xA801, Character) % XID_Start # Lo   [7] LATIN EPIGRAPHIC LETTER REVERSED F..SYLOTI NAGRI LETTER I
    ; between_unicode_range(0xA803, 0xA805, Character) % XID_Start # Lo   [3] SYLOTI NAGRI LETTER U..SYLOTI NAGRI LETTER O
    ; between_unicode_range(0xA807, 0xA80A, Character) % XID_Start # Lo   [4] SYLOTI NAGRI LETTER KO..SYLOTI NAGRI LETTER GHO
    ; between_unicode_range(0xA80C, 0xA822, Character) % XID_Start # Lo  [23] SYLOTI NAGRI LETTER CO..SYLOTI NAGRI LETTER HO
    ; between_unicode_range(0xA840, 0xA873, Character) % XID_Start # Lo  [52] PHAGS-PA LETTER KA..PHAGS-PA LETTER CANDRABINDU
    ; between_unicode_range(0xA882, 0xA8B3, Character) % XID_Start # Lo  [50] SAURASHTRA LETTER A..SAURASHTRA LETTER LLA
    ; between_unicode_range(0xA8F2, 0xA8F7, Character) % XID_Start # Lo   [6] DEVANAGARI SIGN SPACING CANDRABINDU..DEVANAGARI SIGN CANDRABINDU AVAGRAHA
    ; unicode_character(0xA8FB, Character) % XID_Start # Lo       DEVANAGARI HEADSTROKE
    ; between_unicode_range(0xA8FD, 0xA8FE, Character) % XID_Start # Lo   [2] DEVANAGARI JAIN OM..DEVANAGARI LETTER AY
    ; between_unicode_range(0xA90A, 0xA925, Character) % XID_Start # Lo  [28] KAYAH LI LETTER KA..KAYAH LI LETTER OO
    ; between_unicode_range(0xA930, 0xA946, Character) % XID_Start # Lo  [23] REJANG LETTER KA..REJANG LETTER A
    ; between_unicode_range(0xA960, 0xA97C, Character) % XID_Start # Lo  [29] HANGUL CHOSEONG TIKEUT-MIEUM..HANGUL CHOSEONG SSANGYEORINHIEUH
    ; between_unicode_range(0xA984, 0xA9B2, Character) % XID_Start # Lo  [47] JAVANESE LETTER A..JAVANESE LETTER HA
    ; unicode_character(0xA9CF, Character) % XID_Start # Lm       JAVANESE PANGRANGKEP
    ; between_unicode_range(0xA9E0, 0xA9E4, Character) % XID_Start # Lo   [5] MYANMAR LETTER SHAN GHA..MYANMAR LETTER SHAN BHA
    ; unicode_character(0xA9E6, Character) % XID_Start # Lm       MYANMAR MODIFIER LETTER SHAN REDUPLICATION
    ; between_unicode_range(0xA9E7, 0xA9EF, Character) % XID_Start # Lo   [9] MYANMAR LETTER TAI LAING NYA..MYANMAR LETTER TAI LAING NNA
    ; between_unicode_range(0xA9FA, 0xA9FE, Character) % XID_Start # Lo   [5] MYANMAR LETTER TAI LAING LLA..MYANMAR LETTER TAI LAING BHA
    ; between_unicode_range(0xAA00, 0xAA28, Character) % XID_Start # Lo  [41] CHAM LETTER A..CHAM LETTER HA
    ; between_unicode_range(0xAA40, 0xAA42, Character) % XID_Start # Lo   [3] CHAM LETTER FINAL K..CHAM LETTER FINAL NG
    ; between_unicode_range(0xAA44, 0xAA4B, Character) % XID_Start # Lo   [8] CHAM LETTER FINAL CH..CHAM LETTER FINAL SS
    ; between_unicode_range(0xAA60, 0xAA6F, Character) % XID_Start # Lo  [16] MYANMAR LETTER KHAMTI GA..MYANMAR LETTER KHAMTI FA
    ; unicode_character(0xAA70, Character) % XID_Start # Lm       MYANMAR MODIFIER LETTER KHAMTI REDUPLICATION
    ; between_unicode_range(0xAA71, 0xAA76, Character) % XID_Start # Lo   [6] MYANMAR LETTER KHAMTI XA..MYANMAR LOGOGRAM KHAMTI HM
    ; unicode_character(0xAA7A, Character) % XID_Start # Lo       MYANMAR LETTER AITON RA
    ; between_unicode_range(0xAA7E, 0xAAAF, Character) % XID_Start # Lo  [50] MYANMAR LETTER SHWE PALAUNG CHA..TAI VIET LETTER HIGH O
    ; unicode_character(0xAAB1, Character) % XID_Start # Lo       TAI VIET VOWEL AA
    ; between_unicode_range(0xAAB5, 0xAAB6, Character) % XID_Start # Lo   [2] TAI VIET VOWEL E..TAI VIET VOWEL O
    ; between_unicode_range(0xAAB9, 0xAABD, Character) % XID_Start # Lo   [5] TAI VIET VOWEL UEA..TAI VIET VOWEL AN
    ; unicode_character(0xAAC0, Character) % XID_Start # Lo       TAI VIET TONE MAI NUENG
    ; unicode_character(0xAAC2, Character) % XID_Start # Lo       TAI VIET TONE MAI SONG
    ; between_unicode_range(0xAADB, 0xAADC, Character) % XID_Start # Lo   [2] TAI VIET SYMBOL KON..TAI VIET SYMBOL NUENG
    ; unicode_character(0xAADD, Character) % XID_Start # Lm       TAI VIET SYMBOL SAM
    ; between_unicode_range(0xAAE0, 0xAAEA, Character) % XID_Start # Lo  [11] MEETEI MAYEK LETTER E..MEETEI MAYEK LETTER SSA
    ; unicode_character(0xAAF2, Character) % XID_Start # Lo       MEETEI MAYEK ANJI
    ; between_unicode_range(0xAAF3, 0xAAF4, Character) % XID_Start # Lm   [2] MEETEI MAYEK SYLLABLE REPETITION MARK..MEETEI MAYEK WORD REPETITION MARK
    ; between_unicode_range(0xAB01, 0xAB06, Character) % XID_Start # Lo   [6] ETHIOPIC SYLLABLE TTHU..ETHIOPIC SYLLABLE TTHO
    ; between_unicode_range(0xAB09, 0xAB0E, Character) % XID_Start # Lo   [6] ETHIOPIC SYLLABLE DDHU..ETHIOPIC SYLLABLE DDHO
    ; between_unicode_range(0xAB11, 0xAB16, Character) % XID_Start # Lo   [6] ETHIOPIC SYLLABLE DZU..ETHIOPIC SYLLABLE DZO
    ; between_unicode_range(0xAB20, 0xAB26, Character) % XID_Start # Lo   [7] ETHIOPIC SYLLABLE CCHHA..ETHIOPIC SYLLABLE CCHHO
    ; between_unicode_range(0xAB28, 0xAB2E, Character) % XID_Start # Lo   [7] ETHIOPIC SYLLABLE BBA..ETHIOPIC SYLLABLE BBO
    ; between_unicode_range(0xAB30, 0xAB5A, Character) % XID_Start # L&  [43] LATIN SMALL LETTER BARRED ALPHA..LATIN SMALL LETTER Y WITH SHORT RIGHT LEG
    ; between_unicode_range(0xAB5C, 0xAB5F, Character) % XID_Start # Lm   [4] MODIFIER LETTER SMALL HENG..MODIFIER LETTER SMALL U WITH LEFT HOOK
    ; between_unicode_range(0xAB60, 0xAB68, Character) % XID_Start # L&   [9] LATIN SMALL LETTER SAKHA YAT..LATIN SMALL LETTER TURNED R WITH MIDDLE TILDE
    ; unicode_character(0xAB69, Character) % XID_Start # Lm       MODIFIER LETTER SMALL TURNED W
    ; between_unicode_range(0xAB70, 0xABBF, Character) % XID_Start # L&  [80] CHEROKEE SMALL LETTER A..CHEROKEE SMALL LETTER YA
    ; between_unicode_range(0xABC0, 0xABE2, Character) % XID_Start # Lo  [35] MEETEI MAYEK LETTER KOK..MEETEI MAYEK LETTER I LONSUM
    ; between_unicode_range(0xAC00, 0xD7A3, Character) % XID_Start # Lo [11172] HANGUL SYLLABLE GA..HANGUL SYLLABLE HIH
    ; between_unicode_range(0xD7B0, 0xD7C6, Character) % XID_Start # Lo  [23] HANGUL JUNGSEONG O-YEO..HANGUL JUNGSEONG ARAEA-E
    ; between_unicode_range(0xD7CB, 0xD7FB, Character) % XID_Start # Lo  [49] HANGUL JONGSEONG NIEUN-RIEUL..HANGUL JONGSEONG PHIEUPH-THIEUTH
    ; between_unicode_range(0xF900, 0xFA6D, Character) % XID_Start # Lo [366] CJK COMPATIBILITY IDEOGRAPH-F900..CJK COMPATIBILITY IDEOGRAPH-FA6D
    ; between_unicode_range(0xFA70, 0xFAD9, Character) % XID_Start # Lo [106] CJK COMPATIBILITY IDEOGRAPH-FA70..CJK COMPATIBILITY IDEOGRAPH-FAD9
    ; between_unicode_range(0xFB00, 0xFB06, Character) % XID_Start # L&   [7] LATIN SMALL LIGATURE FF..LATIN SMALL LIGATURE ST
    ; between_unicode_range(0xFB13, 0xFB17, Character) % XID_Start # L&   [5] ARMENIAN SMALL LIGATURE MEN NOW..ARMENIAN SMALL LIGATURE MEN XEH
    ; unicode_character(0xFB1D, Character) % XID_Start # Lo       HEBREW LETTER YOD WITH HIRIQ
    ; between_unicode_range(0xFB1F, 0xFB28, Character) % XID_Start # Lo  [10] HEBREW LIGATURE YIDDISH YOD YOD PATAH..HEBREW LETTER WIDE TAV
    ; between_unicode_range(0xFB2A, 0xFB36, Character) % XID_Start # Lo  [13] HEBREW LETTER SHIN WITH SHIN DOT..HEBREW LETTER ZAYIN WITH DAGESH
    ; between_unicode_range(0xFB38, 0xFB3C, Character) % XID_Start # Lo   [5] HEBREW LETTER TET WITH DAGESH..HEBREW LETTER LAMED WITH DAGESH
    ; unicode_character(0xFB3E, Character) % XID_Start # Lo       HEBREW LETTER MEM WITH DAGESH
    ; between_unicode_range(0xFB40, 0xFB41, Character) % XID_Start # Lo   [2] HEBREW LETTER NUN WITH DAGESH..HEBREW LETTER SAMEKH WITH DAGESH
    ; between_unicode_range(0xFB43, 0xFB44, Character) % XID_Start # Lo   [2] HEBREW LETTER FINAL PE WITH DAGESH..HEBREW LETTER PE WITH DAGESH
    ; between_unicode_range(0xFB46, 0xFBB1, Character) % XID_Start # Lo [108] HEBREW LETTER TSADI WITH DAGESH..ARABIC LETTER YEH BARREE WITH HAMZA ABOVE FINAL FORM
    ; between_unicode_range(0xFBD3, 0xFC5D, Character) % XID_Start # Lo [139] ARABIC LETTER NG ISOLATED FORM..ARABIC LIGATURE ALEF MAKSURA WITH SUPERSCRIPT ALEF ISOLATED FORM
    ; between_unicode_range(0xFC64, 0xFD3D, Character) % XID_Start # Lo [218] ARABIC LIGATURE YEH WITH HAMZA ABOVE WITH REH FINAL FORM..ARABIC LIGATURE ALEF WITH FATHATAN ISOLATED FORM
    ; between_unicode_range(0xFD50, 0xFD8F, Character) % XID_Start # Lo  [64] ARABIC LIGATURE TEH WITH JEEM WITH MEEM INITIAL FORM..ARABIC LIGATURE MEEM WITH KHAH WITH MEEM INITIAL FORM
    ; between_unicode_range(0xFD92, 0xFDC7, Character) % XID_Start # Lo  [54] ARABIC LIGATURE MEEM WITH JEEM WITH KHAH INITIAL FORM..ARABIC LIGATURE NOON WITH JEEM WITH YEH FINAL FORM
    ; between_unicode_range(0xFDF0, 0xFDF9, Character) % XID_Start # Lo  [10] ARABIC LIGATURE SALLA USED AS KORANIC STOP SIGN ISOLATED FORM..ARABIC LIGATURE SALLA ISOLATED FORM
    ; unicode_character(0xFE71, Character) % XID_Start # Lo       ARABIC TATWEEL WITH FATHATAN ABOVE
    ; unicode_character(0xFE73, Character) % XID_Start # Lo       ARABIC TAIL FRAGMENT
    ; unicode_character(0xFE77, Character) % XID_Start # Lo       ARABIC FATHA MEDIAL FORM
    ; unicode_character(0xFE79, Character) % XID_Start # Lo       ARABIC DAMMA MEDIAL FORM
    ; unicode_character(0xFE7B, Character) % XID_Start # Lo       ARABIC KASRA MEDIAL FORM
    ; unicode_character(0xFE7D, Character) % XID_Start # Lo       ARABIC SHADDA MEDIAL FORM
    ; between_unicode_range(0xFE7F, 0xFEFC, Character) % XID_Start # Lo [126] ARABIC SUKUN MEDIAL FORM..ARABIC LIGATURE LAM WITH ALEF FINAL FORM
    ; between_unicode_range(0xFF21, 0xFF3A, Character) % XID_Start # L&  [26] FULLWIDTH LATIN CAPITAL LETTER A..FULLWIDTH LATIN CAPITAL LETTER Z
    ; between_unicode_range(0xFF41, 0xFF5A, Character) % XID_Start # L&  [26] FULLWIDTH LATIN SMALL LETTER A..FULLWIDTH LATIN SMALL LETTER Z
    ; between_unicode_range(0xFF66, 0xFF6F, Character) % XID_Start # Lo  [10] HALFWIDTH KATAKANA LETTER WO..HALFWIDTH KATAKANA LETTER SMALL TU
    ; unicode_character(0xFF70, Character) % XID_Start # Lm       HALFWIDTH KATAKANA-HIRAGANA PROLONGED SOUND MARK
    ; between_unicode_range(0xFF71, 0xFF9D, Character) % XID_Start # Lo  [45] HALFWIDTH KATAKANA LETTER A..HALFWIDTH KATAKANA LETTER N
    ; between_unicode_range(0xFFA0, 0xFFBE, Character) % XID_Start # Lo  [31] HALFWIDTH HANGUL FILLER..HALFWIDTH HANGUL LETTER HIEUH
    ; between_unicode_range(0xFFC2, 0xFFC7, Character) % XID_Start # Lo   [6] HALFWIDTH HANGUL LETTER A..HALFWIDTH HANGUL LETTER E
    ; between_unicode_range(0xFFCA, 0xFFCF, Character) % XID_Start # Lo   [6] HALFWIDTH HANGUL LETTER YEO..HALFWIDTH HANGUL LETTER OE
    ; between_unicode_range(0xFFD2, 0xFFD7, Character) % XID_Start # Lo   [6] HALFWIDTH HANGUL LETTER YO..HALFWIDTH HANGUL LETTER YU
    ; between_unicode_range(0xFFDA, 0xFFDC, Character) % XID_Start # Lo   [3] HALFWIDTH HANGUL LETTER EU..HALFWIDTH HANGUL LETTER I
    ; between_unicode_range(0x10000, 0x1000B, Character) % XID_Start # Lo  [12] LINEAR B SYLLABLE B008 A..LINEAR B SYLLABLE B046 JE
    ; between_unicode_range(0x1000D, 0x10026, Character) % XID_Start # Lo  [26] LINEAR B SYLLABLE B036 JO..LINEAR B SYLLABLE B032 QO
    ; between_unicode_range(0x10028, 0x1003A, Character) % XID_Start # Lo  [19] LINEAR B SYLLABLE B060 RA..LINEAR B SYLLABLE B042 WO
    ; between_unicode_range(0x1003C, 0x1003D, Character) % XID_Start # Lo   [2] LINEAR B SYLLABLE B017 ZA..LINEAR B SYLLABLE B074 ZE
    ; between_unicode_range(0x1003F, 0x1004D, Character) % XID_Start # Lo  [15] LINEAR B SYLLABLE B020 ZO..LINEAR B SYLLABLE B091 TWO
    ; between_unicode_range(0x10050, 0x1005D, Character) % XID_Start # Lo  [14] LINEAR B SYMBOL B018..LINEAR B SYMBOL B089
    ; between_unicode_range(0x10080, 0x100FA, Character) % XID_Start # Lo [123] LINEAR B IDEOGRAM B100 MAN..LINEAR B IDEOGRAM VESSEL B305
    ; between_unicode_range(0x10140, 0x10174, Character) % XID_Start # Nl  [53] GREEK ACROPHONIC ATTIC ONE QUARTER..GREEK ACROPHONIC STRATIAN FIFTY MNAS
    ; between_unicode_range(0x10280, 0x1029C, Character) % XID_Start # Lo  [29] LYCIAN LETTER A..LYCIAN LETTER X
    ; between_unicode_range(0x102A0, 0x102D0, Character) % XID_Start # Lo  [49] CARIAN LETTER A..CARIAN LETTER UUU3
    ; between_unicode_range(0x10300, 0x1031F, Character) % XID_Start # Lo  [32] OLD ITALIC LETTER A..OLD ITALIC LETTER ESS
    ; between_unicode_range(0x1032D, 0x10340, Character) % XID_Start # Lo  [20] OLD ITALIC LETTER YE..GOTHIC LETTER PAIRTHRA
    ; unicode_character(0x10341, Character) % XID_Start # Nl       GOTHIC LETTER NINETY
    ; between_unicode_range(0x10342, 0x10349, Character) % XID_Start # Lo   [8] GOTHIC LETTER RAIDA..GOTHIC LETTER OTHAL
    ; unicode_character(0x1034A, Character) % XID_Start # Nl       GOTHIC LETTER NINE HUNDRED
    ; between_unicode_range(0x10350, 0x10375, Character) % XID_Start # Lo  [38] OLD PERMIC LETTER AN..OLD PERMIC LETTER IA
    ; between_unicode_range(0x10380, 0x1039D, Character) % XID_Start # Lo  [30] UGARITIC LETTER ALPA..UGARITIC LETTER SSU
    ; between_unicode_range(0x103A0, 0x103C3, Character) % XID_Start # Lo  [36] OLD PERSIAN SIGN A..OLD PERSIAN SIGN HA
    ; between_unicode_range(0x103C8, 0x103CF, Character) % XID_Start # Lo   [8] OLD PERSIAN SIGN AURAMAZDAA..OLD PERSIAN SIGN BUUMISH
    ; between_unicode_range(0x103D1, 0x103D5, Character) % XID_Start # Nl   [5] OLD PERSIAN NUMBER ONE..OLD PERSIAN NUMBER HUNDRED
    ; between_unicode_range(0x10400, 0x1044F, Character) % XID_Start # L&  [80] DESERET CAPITAL LETTER LONG I..DESERET SMALL LETTER EW
    ; between_unicode_range(0x10450, 0x1049D, Character) % XID_Start # Lo  [78] SHAVIAN LETTER PEEP..OSMANYA LETTER OO
    ; between_unicode_range(0x104B0, 0x104D3, Character) % XID_Start # L&  [36] OSAGE CAPITAL LETTER A..OSAGE CAPITAL LETTER ZHA
    ; between_unicode_range(0x104D8, 0x104FB, Character) % XID_Start # L&  [36] OSAGE SMALL LETTER A..OSAGE SMALL LETTER ZHA
    ; between_unicode_range(0x10500, 0x10527, Character) % XID_Start # Lo  [40] ELBASAN LETTER A..ELBASAN LETTER KHE
    ; between_unicode_range(0x10530, 0x10563, Character) % XID_Start # Lo  [52] CAUCASIAN ALBANIAN LETTER ALT..CAUCASIAN ALBANIAN LETTER KIW
    ; between_unicode_range(0x10570, 0x1057A, Character) % XID_Start # L&  [11] VITHKUQI CAPITAL LETTER A..VITHKUQI CAPITAL LETTER GA
    ; between_unicode_range(0x1057C, 0x1058A, Character) % XID_Start # L&  [15] VITHKUQI CAPITAL LETTER HA..VITHKUQI CAPITAL LETTER RE
    ; between_unicode_range(0x1058C, 0x10592, Character) % XID_Start # L&   [7] VITHKUQI CAPITAL LETTER SE..VITHKUQI CAPITAL LETTER XE
    ; between_unicode_range(0x10594, 0x10595, Character) % XID_Start # L&   [2] VITHKUQI CAPITAL LETTER Y..VITHKUQI CAPITAL LETTER ZE
    ; between_unicode_range(0x10597, 0x105A1, Character) % XID_Start # L&  [11] VITHKUQI SMALL LETTER A..VITHKUQI SMALL LETTER GA
    ; between_unicode_range(0x105A3, 0x105B1, Character) % XID_Start # L&  [15] VITHKUQI SMALL LETTER HA..VITHKUQI SMALL LETTER RE
    ; between_unicode_range(0x105B3, 0x105B9, Character) % XID_Start # L&   [7] VITHKUQI SMALL LETTER SE..VITHKUQI SMALL LETTER XE
    ; between_unicode_range(0x105BB, 0x105BC, Character) % XID_Start # L&   [2] VITHKUQI SMALL LETTER Y..VITHKUQI SMALL LETTER ZE
    ; between_unicode_range(0x105C0, 0x105F3, Character) % XID_Start # Lo  [52] TODHRI LETTER A..TODHRI LETTER OO
    ; between_unicode_range(0x10600, 0x10736, Character) % XID_Start # Lo [311] LINEAR A SIGN AB001..LINEAR A SIGN A664
    ; between_unicode_range(0x10740, 0x10755, Character) % XID_Start # Lo  [22] LINEAR A SIGN A701 A..LINEAR A SIGN A732 JE
    ; between_unicode_range(0x10760, 0x10767, Character) % XID_Start # Lo   [8] LINEAR A SIGN A800..LINEAR A SIGN A807
    ; between_unicode_range(0x10780, 0x10785, Character) % XID_Start # Lm   [6] MODIFIER LETTER SMALL CAPITAL AA..MODIFIER LETTER SMALL B WITH HOOK
    ; between_unicode_range(0x10787, 0x107B0, Character) % XID_Start # Lm  [42] MODIFIER LETTER SMALL DZ DIGRAPH..MODIFIER LETTER SMALL V WITH RIGHT HOOK
    ; between_unicode_range(0x107B2, 0x107BA, Character) % XID_Start # Lm   [9] MODIFIER LETTER SMALL CAPITAL Y..MODIFIER LETTER SMALL S WITH CURL
    ; between_unicode_range(0x10800, 0x10805, Character) % XID_Start # Lo   [6] CYPRIOT SYLLABLE A..CYPRIOT SYLLABLE JA
    ; unicode_character(0x10808, Character) % XID_Start # Lo       CYPRIOT SYLLABLE JO
    ; between_unicode_range(0x1080A, 0x10835, Character) % XID_Start # Lo  [44] CYPRIOT SYLLABLE KA..CYPRIOT SYLLABLE WO
    ; between_unicode_range(0x10837, 0x10838, Character) % XID_Start # Lo   [2] CYPRIOT SYLLABLE XA..CYPRIOT SYLLABLE XE
    ; unicode_character(0x1083C, Character) % XID_Start # Lo       CYPRIOT SYLLABLE ZA
    ; between_unicode_range(0x1083F, 0x10855, Character) % XID_Start # Lo  [23] CYPRIOT SYLLABLE ZO..IMPERIAL ARAMAIC LETTER TAW
    ; between_unicode_range(0x10860, 0x10876, Character) % XID_Start # Lo  [23] PALMYRENE LETTER ALEPH..PALMYRENE LETTER TAW
    ; between_unicode_range(0x10880, 0x1089E, Character) % XID_Start # Lo  [31] NABATAEAN LETTER FINAL ALEPH..NABATAEAN LETTER TAW
    ; between_unicode_range(0x108E0, 0x108F2, Character) % XID_Start # Lo  [19] HATRAN LETTER ALEPH..HATRAN LETTER QOPH
    ; between_unicode_range(0x108F4, 0x108F5, Character) % XID_Start # Lo   [2] HATRAN LETTER SHIN..HATRAN LETTER TAW
    ; between_unicode_range(0x10900, 0x10915, Character) % XID_Start # Lo  [22] PHOENICIAN LETTER ALF..PHOENICIAN LETTER TAU
    ; between_unicode_range(0x10920, 0x10939, Character) % XID_Start # Lo  [26] LYDIAN LETTER A..LYDIAN LETTER C
    ; between_unicode_range(0x10980, 0x109B7, Character) % XID_Start # Lo  [56] MEROITIC HIEROGLYPHIC LETTER A..MEROITIC CURSIVE LETTER DA
    ; between_unicode_range(0x109BE, 0x109BF, Character) % XID_Start # Lo   [2] MEROITIC CURSIVE LOGOGRAM RMT..MEROITIC CURSIVE LOGOGRAM IMN
    ; unicode_character(0x10A00, Character) % XID_Start # Lo       KHAROSHTHI LETTER A
    ; between_unicode_range(0x10A10, 0x10A13, Character) % XID_Start # Lo   [4] KHAROSHTHI LETTER KA..KHAROSHTHI LETTER GHA
    ; between_unicode_range(0x10A15, 0x10A17, Character) % XID_Start # Lo   [3] KHAROSHTHI LETTER CA..KHAROSHTHI LETTER JA
    ; between_unicode_range(0x10A19, 0x10A35, Character) % XID_Start # Lo  [29] KHAROSHTHI LETTER NYA..KHAROSHTHI LETTER VHA
    ; between_unicode_range(0x10A60, 0x10A7C, Character) % XID_Start # Lo  [29] OLD SOUTH ARABIAN LETTER HE..OLD SOUTH ARABIAN LETTER THETH
    ; between_unicode_range(0x10A80, 0x10A9C, Character) % XID_Start # Lo  [29] OLD NORTH ARABIAN LETTER HEH..OLD NORTH ARABIAN LETTER ZAH
    ; between_unicode_range(0x10AC0, 0x10AC7, Character) % XID_Start # Lo   [8] MANICHAEAN LETTER ALEPH..MANICHAEAN LETTER WAW
    ; between_unicode_range(0x10AC9, 0x10AE4, Character) % XID_Start # Lo  [28] MANICHAEAN LETTER ZAYIN..MANICHAEAN LETTER TAW
    ; between_unicode_range(0x10B00, 0x10B35, Character) % XID_Start # Lo  [54] AVESTAN LETTER A..AVESTAN LETTER HE
    ; between_unicode_range(0x10B40, 0x10B55, Character) % XID_Start # Lo  [22] INSCRIPTIONAL PARTHIAN LETTER ALEPH..INSCRIPTIONAL PARTHIAN LETTER TAW
    ; between_unicode_range(0x10B60, 0x10B72, Character) % XID_Start # Lo  [19] INSCRIPTIONAL PAHLAVI LETTER ALEPH..INSCRIPTIONAL PAHLAVI LETTER TAW
    ; between_unicode_range(0x10B80, 0x10B91, Character) % XID_Start # Lo  [18] PSALTER PAHLAVI LETTER ALEPH..PSALTER PAHLAVI LETTER TAW
    ; between_unicode_range(0x10C00, 0x10C48, Character) % XID_Start # Lo  [73] OLD TURKIC LETTER ORKHON A..OLD TURKIC LETTER ORKHON BASH
    ; between_unicode_range(0x10C80, 0x10CB2, Character) % XID_Start # L&  [51] OLD HUNGARIAN CAPITAL LETTER A..OLD HUNGARIAN CAPITAL LETTER US
    ; between_unicode_range(0x10CC0, 0x10CF2, Character) % XID_Start # L&  [51] OLD HUNGARIAN SMALL LETTER A..OLD HUNGARIAN SMALL LETTER US
    ; between_unicode_range(0x10D00, 0x10D23, Character) % XID_Start # Lo  [36] HANIFI ROHINGYA LETTER A..HANIFI ROHINGYA MARK NA KHONNA
    ; between_unicode_range(0x10D4A, 0x10D4D, Character) % XID_Start # Lo   [4] GARAY VOWEL SIGN A..GARAY VOWEL SIGN EE
    ; unicode_character(0x10D4E, Character) % XID_Start # Lm       GARAY VOWEL LENGTH MARK
    ; unicode_character(0x10D4F, Character) % XID_Start # Lo       GARAY SUKUN
    ; between_unicode_range(0x10D50, 0x10D65, Character) % XID_Start # L&  [22] GARAY CAPITAL LETTER A..GARAY CAPITAL LETTER OLD NA
    ; unicode_character(0x10D6F, Character) % XID_Start # Lm       GARAY REDUPLICATION MARK
    ; between_unicode_range(0x10D70, 0x10D85, Character) % XID_Start # L&  [22] GARAY SMALL LETTER A..GARAY SMALL LETTER OLD NA
    ; between_unicode_range(0x10E80, 0x10EA9, Character) % XID_Start # Lo  [42] YEZIDI LETTER ELIF..YEZIDI LETTER ET
    ; between_unicode_range(0x10EB0, 0x10EB1, Character) % XID_Start # Lo   [2] YEZIDI LETTER LAM WITH DOT ABOVE..YEZIDI LETTER YOT WITH CIRCUMFLEX ABOVE
    ; between_unicode_range(0x10EC2, 0x10EC4, Character) % XID_Start # Lo   [3] ARABIC LETTER DAL WITH TWO DOTS VERTICALLY BELOW..ARABIC LETTER KAF WITH TWO DOTS VERTICALLY BELOW
    ; between_unicode_range(0x10F00, 0x10F1C, Character) % XID_Start # Lo  [29] OLD SOGDIAN LETTER ALEPH..OLD SOGDIAN LETTER FINAL TAW WITH VERTICAL TAIL
    ; unicode_character(0x10F27, Character) % XID_Start # Lo       OLD SOGDIAN LIGATURE AYIN-DALETH
    ; between_unicode_range(0x10F30, 0x10F45, Character) % XID_Start # Lo  [22] SOGDIAN LETTER ALEPH..SOGDIAN INDEPENDENT SHIN
    ; between_unicode_range(0x10F70, 0x10F81, Character) % XID_Start # Lo  [18] OLD UYGHUR LETTER ALEPH..OLD UYGHUR LETTER LESH
    ; between_unicode_range(0x10FB0, 0x10FC4, Character) % XID_Start # Lo  [21] CHORASMIAN LETTER ALEPH..CHORASMIAN LETTER TAW
    ; between_unicode_range(0x10FE0, 0x10FF6, Character) % XID_Start # Lo  [23] ELYMAIC LETTER ALEPH..ELYMAIC LIGATURE ZAYIN-YODH
    ; between_unicode_range(0x11003, 0x11037, Character) % XID_Start # Lo  [53] BRAHMI SIGN JIHVAMULIYA..BRAHMI LETTER OLD TAMIL NNNA
    ; between_unicode_range(0x11071, 0x11072, Character) % XID_Start # Lo   [2] BRAHMI LETTER OLD TAMIL SHORT E..BRAHMI LETTER OLD TAMIL SHORT O
    ; unicode_character(0x11075, Character) % XID_Start # Lo       BRAHMI LETTER OLD TAMIL LLA
    ; between_unicode_range(0x11083, 0x110AF, Character) % XID_Start # Lo  [45] KAITHI LETTER A..KAITHI LETTER HA
    ; between_unicode_range(0x110D0, 0x110E8, Character) % XID_Start # Lo  [25] SORA SOMPENG LETTER SAH..SORA SOMPENG LETTER MAE
    ; between_unicode_range(0x11103, 0x11126, Character) % XID_Start # Lo  [36] CHAKMA LETTER AA..CHAKMA LETTER HAA
    ; unicode_character(0x11144, Character) % XID_Start # Lo       CHAKMA LETTER LHAA
    ; unicode_character(0x11147, Character) % XID_Start # Lo       CHAKMA LETTER VAA
    ; between_unicode_range(0x11150, 0x11172, Character) % XID_Start # Lo  [35] MAHAJANI LETTER A..MAHAJANI LETTER RRA
    ; unicode_character(0x11176, Character) % XID_Start # Lo       MAHAJANI LIGATURE SHRI
    ; between_unicode_range(0x11183, 0x111B2, Character) % XID_Start # Lo  [48] SHARADA LETTER A..SHARADA LETTER HA
    ; between_unicode_range(0x111C1, 0x111C4, Character) % XID_Start # Lo   [4] SHARADA SIGN AVAGRAHA..SHARADA OM
    ; unicode_character(0x111DA, Character) % XID_Start # Lo       SHARADA EKAM
    ; unicode_character(0x111DC, Character) % XID_Start # Lo       SHARADA HEADSTROKE
    ; between_unicode_range(0x11200, 0x11211, Character) % XID_Start # Lo  [18] KHOJKI LETTER A..KHOJKI LETTER JJA
    ; between_unicode_range(0x11213, 0x1122B, Character) % XID_Start # Lo  [25] KHOJKI LETTER NYA..KHOJKI LETTER LLA
    ; between_unicode_range(0x1123F, 0x11240, Character) % XID_Start # Lo   [2] KHOJKI LETTER QA..KHOJKI LETTER SHORT I
    ; between_unicode_range(0x11280, 0x11286, Character) % XID_Start # Lo   [7] MULTANI LETTER A..MULTANI LETTER GA
    ; unicode_character(0x11288, Character) % XID_Start # Lo       MULTANI LETTER GHA
    ; between_unicode_range(0x1128A, 0x1128D, Character) % XID_Start # Lo   [4] MULTANI LETTER CA..MULTANI LETTER JJA
    ; between_unicode_range(0x1128F, 0x1129D, Character) % XID_Start # Lo  [15] MULTANI LETTER NYA..MULTANI LETTER BA
    ; between_unicode_range(0x1129F, 0x112A8, Character) % XID_Start # Lo  [10] MULTANI LETTER BHA..MULTANI LETTER RHA
    ; between_unicode_range(0x112B0, 0x112DE, Character) % XID_Start # Lo  [47] KHUDAWADI LETTER A..KHUDAWADI LETTER HA
    ; between_unicode_range(0x11305, 0x1130C, Character) % XID_Start # Lo   [8] GRANTHA LETTER A..GRANTHA LETTER VOCALIC L
    ; between_unicode_range(0x1130F, 0x11310, Character) % XID_Start # Lo   [2] GRANTHA LETTER EE..GRANTHA LETTER AI
    ; between_unicode_range(0x11313, 0x11328, Character) % XID_Start # Lo  [22] GRANTHA LETTER OO..GRANTHA LETTER NA
    ; between_unicode_range(0x1132A, 0x11330, Character) % XID_Start # Lo   [7] GRANTHA LETTER PA..GRANTHA LETTER RA
    ; between_unicode_range(0x11332, 0x11333, Character) % XID_Start # Lo   [2] GRANTHA LETTER LA..GRANTHA LETTER LLA
    ; between_unicode_range(0x11335, 0x11339, Character) % XID_Start # Lo   [5] GRANTHA LETTER VA..GRANTHA LETTER HA
    ; unicode_character(0x1133D, Character) % XID_Start # Lo       GRANTHA SIGN AVAGRAHA
    ; unicode_character(0x11350, Character) % XID_Start # Lo       GRANTHA OM
    ; between_unicode_range(0x1135D, 0x11361, Character) % XID_Start # Lo   [5] GRANTHA SIGN PLUTA..GRANTHA LETTER VOCALIC LL
    ; between_unicode_range(0x11380, 0x11389, Character) % XID_Start # Lo  [10] TULU-TIGALARI LETTER A..TULU-TIGALARI LETTER VOCALIC LL
    ; unicode_character(0x1138B, Character) % XID_Start # Lo       TULU-TIGALARI LETTER EE
    ; unicode_character(0x1138E, Character) % XID_Start # Lo       TULU-TIGALARI LETTER AI
    ; between_unicode_range(0x11390, 0x113B5, Character) % XID_Start # Lo  [38] TULU-TIGALARI LETTER OO..TULU-TIGALARI LETTER LLLA
    ; unicode_character(0x113B7, Character) % XID_Start # Lo       TULU-TIGALARI SIGN AVAGRAHA
    ; unicode_character(0x113D1, Character) % XID_Start # Lo       TULU-TIGALARI REPHA
    ; unicode_character(0x113D3, Character) % XID_Start # Lo       TULU-TIGALARI SIGN PLUTA
    ; between_unicode_range(0x11400, 0x11434, Character) % XID_Start # Lo  [53] NEWA LETTER A..NEWA LETTER HA
    ; between_unicode_range(0x11447, 0x1144A, Character) % XID_Start # Lo   [4] NEWA SIGN AVAGRAHA..NEWA SIDDHI
    ; between_unicode_range(0x1145F, 0x11461, Character) % XID_Start # Lo   [3] NEWA LETTER VEDIC ANUSVARA..NEWA SIGN UPADHMANIYA
    ; between_unicode_range(0x11480, 0x114AF, Character) % XID_Start # Lo  [48] TIRHUTA ANJI..TIRHUTA LETTER HA
    ; between_unicode_range(0x114C4, 0x114C5, Character) % XID_Start # Lo   [2] TIRHUTA SIGN AVAGRAHA..TIRHUTA GVANG
    ; unicode_character(0x114C7, Character) % XID_Start # Lo       TIRHUTA OM
    ; between_unicode_range(0x11580, 0x115AE, Character) % XID_Start # Lo  [47] SIDDHAM LETTER A..SIDDHAM LETTER HA
    ; between_unicode_range(0x115D8, 0x115DB, Character) % XID_Start # Lo   [4] SIDDHAM LETTER THREE-CIRCLE ALTERNATE I..SIDDHAM LETTER ALTERNATE U
    ; between_unicode_range(0x11600, 0x1162F, Character) % XID_Start # Lo  [48] MODI LETTER A..MODI LETTER LLA
    ; unicode_character(0x11644, Character) % XID_Start # Lo       MODI SIGN HUVA
    ; between_unicode_range(0x11680, 0x116AA, Character) % XID_Start # Lo  [43] TAKRI LETTER A..TAKRI LETTER RRA
    ; unicode_character(0x116B8, Character) % XID_Start # Lo       TAKRI LETTER ARCHAIC KHA
    ; between_unicode_range(0x11700, 0x1171A, Character) % XID_Start # Lo  [27] AHOM LETTER KA..AHOM LETTER ALTERNATE BA
    ; between_unicode_range(0x11740, 0x11746, Character) % XID_Start # Lo   [7] AHOM LETTER CA..AHOM LETTER LLA
    ; between_unicode_range(0x11800, 0x1182B, Character) % XID_Start # Lo  [44] DOGRA LETTER A..DOGRA LETTER RRA
    ; between_unicode_range(0x118A0, 0x118DF, Character) % XID_Start # L&  [64] WARANG CITI CAPITAL LETTER NGAA..WARANG CITI SMALL LETTER VIYO
    ; between_unicode_range(0x118FF, 0x11906, Character) % XID_Start # Lo   [8] WARANG CITI OM..DIVES AKURU LETTER E
    ; unicode_character(0x11909, Character) % XID_Start # Lo       DIVES AKURU LETTER O
    ; between_unicode_range(0x1190C, 0x11913, Character) % XID_Start # Lo   [8] DIVES AKURU LETTER KA..DIVES AKURU LETTER JA
    ; between_unicode_range(0x11915, 0x11916, Character) % XID_Start # Lo   [2] DIVES AKURU LETTER NYA..DIVES AKURU LETTER TTA
    ; between_unicode_range(0x11918, 0x1192F, Character) % XID_Start # Lo  [24] DIVES AKURU LETTER DDA..DIVES AKURU LETTER ZA
    ; unicode_character(0x1193F, Character) % XID_Start # Lo       DIVES AKURU PREFIXED NASAL SIGN
    ; unicode_character(0x11941, Character) % XID_Start # Lo       DIVES AKURU INITIAL RA
    ; between_unicode_range(0x119A0, 0x119A7, Character) % XID_Start # Lo   [8] NANDINAGARI LETTER A..NANDINAGARI LETTER VOCALIC RR
    ; between_unicode_range(0x119AA, 0x119D0, Character) % XID_Start # Lo  [39] NANDINAGARI LETTER E..NANDINAGARI LETTER RRA
    ; unicode_character(0x119E1, Character) % XID_Start # Lo       NANDINAGARI SIGN AVAGRAHA
    ; unicode_character(0x119E3, Character) % XID_Start # Lo       NANDINAGARI HEADSTROKE
    ; unicode_character(0x11A00, Character) % XID_Start # Lo       ZANABAZAR SQUARE LETTER A
    ; between_unicode_range(0x11A0B, 0x11A32, Character) % XID_Start # Lo  [40] ZANABAZAR SQUARE LETTER KA..ZANABAZAR SQUARE LETTER KSSA
    ; unicode_character(0x11A3A, Character) % XID_Start # Lo       ZANABAZAR SQUARE CLUSTER-INITIAL LETTER RA
    ; unicode_character(0x11A50, Character) % XID_Start # Lo       SOYOMBO LETTER A
    ; between_unicode_range(0x11A5C, 0x11A89, Character) % XID_Start # Lo  [46] SOYOMBO LETTER KA..SOYOMBO CLUSTER-INITIAL LETTER SA
    ; unicode_character(0x11A9D, Character) % XID_Start # Lo       SOYOMBO MARK PLUTA
    ; between_unicode_range(0x11AB0, 0x11AF8, Character) % XID_Start # Lo  [73] CANADIAN SYLLABICS NATTILIK HI..PAU CIN HAU GLOTTAL STOP FINAL
    ; between_unicode_range(0x11BC0, 0x11BE0, Character) % XID_Start # Lo  [33] SUNUWAR LETTER DEVI..SUNUWAR LETTER KLOKO
    ; between_unicode_range(0x11C00, 0x11C08, Character) % XID_Start # Lo   [9] BHAIKSUKI LETTER A..BHAIKSUKI LETTER VOCALIC L
    ; between_unicode_range(0x11C0A, 0x11C2E, Character) % XID_Start # Lo  [37] BHAIKSUKI LETTER E..BHAIKSUKI LETTER HA
    ; unicode_character(0x11C40, Character) % XID_Start # Lo       BHAIKSUKI SIGN AVAGRAHA
    ; between_unicode_range(0x11C72, 0x11C8F, Character) % XID_Start # Lo  [30] MARCHEN LETTER KA..MARCHEN LETTER A
    ; between_unicode_range(0x11D00, 0x11D06, Character) % XID_Start # Lo   [7] MASARAM GONDI LETTER A..MASARAM GONDI LETTER E
    ; between_unicode_range(0x11D08, 0x11D09, Character) % XID_Start # Lo   [2] MASARAM GONDI LETTER AI..MASARAM GONDI LETTER O
    ; between_unicode_range(0x11D0B, 0x11D30, Character) % XID_Start # Lo  [38] MASARAM GONDI LETTER AU..MASARAM GONDI LETTER TRA
    ; unicode_character(0x11D46, Character) % XID_Start # Lo       MASARAM GONDI REPHA
    ; between_unicode_range(0x11D60, 0x11D65, Character) % XID_Start # Lo   [6] GUNJALA GONDI LETTER A..GUNJALA GONDI LETTER UU
    ; between_unicode_range(0x11D67, 0x11D68, Character) % XID_Start # Lo   [2] GUNJALA GONDI LETTER EE..GUNJALA GONDI LETTER AI
    ; between_unicode_range(0x11D6A, 0x11D89, Character) % XID_Start # Lo  [32] GUNJALA GONDI LETTER OO..GUNJALA GONDI LETTER SA
    ; unicode_character(0x11D98, Character) % XID_Start # Lo       GUNJALA GONDI OM
    ; between_unicode_range(0x11EE0, 0x11EF2, Character) % XID_Start # Lo  [19] MAKASAR LETTER KA..MAKASAR ANGKA
    ; unicode_character(0x11F02, Character) % XID_Start # Lo       KAWI SIGN REPHA
    ; between_unicode_range(0x11F04, 0x11F10, Character) % XID_Start # Lo  [13] KAWI LETTER A..KAWI LETTER O
    ; between_unicode_range(0x11F12, 0x11F33, Character) % XID_Start # Lo  [34] KAWI LETTER KA..KAWI LETTER JNYA
    ; unicode_character(0x11FB0, Character) % XID_Start # Lo       LISU LETTER YHA
    ; between_unicode_range(0x12000, 0x12399, Character) % XID_Start # Lo [922] CUNEIFORM SIGN A..CUNEIFORM SIGN U U
    ; between_unicode_range(0x12400, 0x1246E, Character) % XID_Start # Nl [111] CUNEIFORM NUMERIC SIGN TWO ASH..CUNEIFORM NUMERIC SIGN NINE U VARIANT FORM
    ; between_unicode_range(0x12480, 0x12543, Character) % XID_Start # Lo [196] CUNEIFORM SIGN AB TIMES NUN TENU..CUNEIFORM SIGN ZU5 TIMES THREE DISH TENU
    ; between_unicode_range(0x12F90, 0x12FF0, Character) % XID_Start # Lo  [97] CYPRO-MINOAN SIGN CM001..CYPRO-MINOAN SIGN CM114
    ; between_unicode_range(0x13000, 0x1342F, Character) % XID_Start # Lo [1072] EGYPTIAN HIEROGLYPH A001..EGYPTIAN HIEROGLYPH V011D
    ; between_unicode_range(0x13441, 0x13446, Character) % XID_Start # Lo   [6] EGYPTIAN HIEROGLYPH FULL BLANK..EGYPTIAN HIEROGLYPH WIDE LOST SIGN
    ; between_unicode_range(0x13460, 0x143FA, Character) % XID_Start # Lo [3995] EGYPTIAN HIEROGLYPH-13460..EGYPTIAN HIEROGLYPH-143FA
    ; between_unicode_range(0x14400, 0x14646, Character) % XID_Start # Lo [583] ANATOLIAN HIEROGLYPH A001..ANATOLIAN HIEROGLYPH A530
    ; between_unicode_range(0x16100, 0x1611D, Character) % XID_Start # Lo  [30] GURUNG KHEMA LETTER A..GURUNG KHEMA LETTER SA
    ; between_unicode_range(0x16800, 0x16A38, Character) % XID_Start # Lo [569] BAMUM LETTER PHASE-A NGKUE MFON..BAMUM LETTER PHASE-F VUEQ
    ; between_unicode_range(0x16A40, 0x16A5E, Character) % XID_Start # Lo  [31] MRO LETTER TA..MRO LETTER TEK
    ; between_unicode_range(0x16A70, 0x16ABE, Character) % XID_Start # Lo  [79] TANGSA LETTER OZ..TANGSA LETTER ZA
    ; between_unicode_range(0x16AD0, 0x16AED, Character) % XID_Start # Lo  [30] BASSA VAH LETTER ENNI..BASSA VAH LETTER I
    ; between_unicode_range(0x16B00, 0x16B2F, Character) % XID_Start # Lo  [48] PAHAWH HMONG VOWEL KEEB..PAHAWH HMONG CONSONANT CAU
    ; between_unicode_range(0x16B40, 0x16B43, Character) % XID_Start # Lm   [4] PAHAWH HMONG SIGN VOS SEEV..PAHAWH HMONG SIGN IB YAM
    ; between_unicode_range(0x16B63, 0x16B77, Character) % XID_Start # Lo  [21] PAHAWH HMONG SIGN VOS LUB..PAHAWH HMONG SIGN CIM NRES TOS
    ; between_unicode_range(0x16B7D, 0x16B8F, Character) % XID_Start # Lo  [19] PAHAWH HMONG CLAN SIGN TSHEEJ..PAHAWH HMONG CLAN SIGN VWJ
    ; between_unicode_range(0x16D40, 0x16D42, Character) % XID_Start # Lm   [3] KIRAT RAI SIGN ANUSVARA..KIRAT RAI SIGN VISARGA
    ; between_unicode_range(0x16D43, 0x16D6A, Character) % XID_Start # Lo  [40] KIRAT RAI LETTER A..KIRAT RAI VOWEL SIGN AU
    ; between_unicode_range(0x16D6B, 0x16D6C, Character) % XID_Start # Lm   [2] KIRAT RAI SIGN VIRAMA..KIRAT RAI SIGN SAAT
    ; between_unicode_range(0x16E40, 0x16E7F, Character) % XID_Start # L&  [64] MEDEFAIDRIN CAPITAL LETTER M..MEDEFAIDRIN SMALL LETTER Y
    ; between_unicode_range(0x16F00, 0x16F4A, Character) % XID_Start # Lo  [75] MIAO LETTER PA..MIAO LETTER RTE
    ; unicode_character(0x16F50, Character) % XID_Start # Lo       MIAO LETTER NASALIZATION
    ; between_unicode_range(0x16F93, 0x16F9F, Character) % XID_Start # Lm  [13] MIAO LETTER TONE-2..MIAO LETTER REFORMED TONE-8
    ; between_unicode_range(0x16FE0, 0x16FE1, Character) % XID_Start # Lm   [2] TANGUT ITERATION MARK..NUSHU ITERATION MARK
    ; unicode_character(0x16FE3, Character) % XID_Start # Lm       OLD CHINESE ITERATION MARK
    ; between_unicode_range(0x17000, 0x187F7, Character) % XID_Start # Lo [6136] TANGUT IDEOGRAPH-17000..TANGUT IDEOGRAPH-187F7
    ; between_unicode_range(0x18800, 0x18CD5, Character) % XID_Start # Lo [1238] TANGUT COMPONENT-001..KHITAN SMALL SCRIPT CHARACTER-18CD5
    ; between_unicode_range(0x18CFF, 0x18D08, Character) % XID_Start # Lo  [10] KHITAN SMALL SCRIPT CHARACTER-18CFF..TANGUT IDEOGRAPH-18D08
    ; between_unicode_range(0x1AFF0, 0x1AFF3, Character) % XID_Start # Lm   [4] KATAKANA LETTER MINNAN TONE-2..KATAKANA LETTER MINNAN TONE-5
    ; between_unicode_range(0x1AFF5, 0x1AFFB, Character) % XID_Start # Lm   [7] KATAKANA LETTER MINNAN TONE-7..KATAKANA LETTER MINNAN NASALIZED TONE-5
    ; between_unicode_range(0x1AFFD, 0x1AFFE, Character) % XID_Start # Lm   [2] KATAKANA LETTER MINNAN NASALIZED TONE-7..KATAKANA LETTER MINNAN NASALIZED TONE-8
    ; between_unicode_range(0x1B000, 0x1B122, Character) % XID_Start # Lo [291] KATAKANA LETTER ARCHAIC E..KATAKANA LETTER ARCHAIC WU
    ; unicode_character(0x1B132, Character) % XID_Start # Lo       HIRAGANA LETTER SMALL KO
    ; between_unicode_range(0x1B150, 0x1B152, Character) % XID_Start # Lo   [3] HIRAGANA LETTER SMALL WI..HIRAGANA LETTER SMALL WO
    ; unicode_character(0x1B155, Character) % XID_Start # Lo       KATAKANA LETTER SMALL KO
    ; between_unicode_range(0x1B164, 0x1B167, Character) % XID_Start # Lo   [4] KATAKANA LETTER SMALL WI..KATAKANA LETTER SMALL N
    ; between_unicode_range(0x1B170, 0x1B2FB, Character) % XID_Start # Lo [396] NUSHU CHARACTER-1B170..NUSHU CHARACTER-1B2FB
    ; between_unicode_range(0x1BC00, 0x1BC6A, Character) % XID_Start # Lo [107] DUPLOYAN LETTER H..DUPLOYAN LETTER VOCALIC M
    ; between_unicode_range(0x1BC70, 0x1BC7C, Character) % XID_Start # Lo  [13] DUPLOYAN AFFIX LEFT HORIZONTAL SECANT..DUPLOYAN AFFIX ATTACHED TANGENT HOOK
    ; between_unicode_range(0x1BC80, 0x1BC88, Character) % XID_Start # Lo   [9] DUPLOYAN AFFIX HIGH ACUTE..DUPLOYAN AFFIX HIGH VERTICAL
    ; between_unicode_range(0x1BC90, 0x1BC99, Character) % XID_Start # Lo  [10] DUPLOYAN AFFIX LOW ACUTE..DUPLOYAN AFFIX LOW ARROW
    ; between_unicode_range(0x1D400, 0x1D454, Character) % XID_Start # L&  [85] MATHEMATICAL BOLD CAPITAL A..MATHEMATICAL ITALIC SMALL G
    ; between_unicode_range(0x1D456, 0x1D49C, Character) % XID_Start # L&  [71] MATHEMATICAL ITALIC SMALL I..MATHEMATICAL SCRIPT CAPITAL A
    ; between_unicode_range(0x1D49E, 0x1D49F, Character) % XID_Start # L&   [2] MATHEMATICAL SCRIPT CAPITAL C..MATHEMATICAL SCRIPT CAPITAL D
    ; unicode_character(0x1D4A2, Character) % XID_Start # L&       MATHEMATICAL SCRIPT CAPITAL G
    ; between_unicode_range(0x1D4A5, 0x1D4A6, Character) % XID_Start # L&   [2] MATHEMATICAL SCRIPT CAPITAL J..MATHEMATICAL SCRIPT CAPITAL K
    ; between_unicode_range(0x1D4A9, 0x1D4AC, Character) % XID_Start # L&   [4] MATHEMATICAL SCRIPT CAPITAL N..MATHEMATICAL SCRIPT CAPITAL Q
    ; between_unicode_range(0x1D4AE, 0x1D4B9, Character) % XID_Start # L&  [12] MATHEMATICAL SCRIPT CAPITAL S..MATHEMATICAL SCRIPT SMALL D
    ; unicode_character(0x1D4BB, Character) % XID_Start # L&       MATHEMATICAL SCRIPT SMALL F
    ; between_unicode_range(0x1D4BD, 0x1D4C3, Character) % XID_Start # L&   [7] MATHEMATICAL SCRIPT SMALL H..MATHEMATICAL SCRIPT SMALL N
    ; between_unicode_range(0x1D4C5, 0x1D505, Character) % XID_Start # L&  [65] MATHEMATICAL SCRIPT SMALL P..MATHEMATICAL FRAKTUR CAPITAL B
    ; between_unicode_range(0x1D507, 0x1D50A, Character) % XID_Start # L&   [4] MATHEMATICAL FRAKTUR CAPITAL D..MATHEMATICAL FRAKTUR CAPITAL G
    ; between_unicode_range(0x1D50D, 0x1D514, Character) % XID_Start # L&   [8] MATHEMATICAL FRAKTUR CAPITAL J..MATHEMATICAL FRAKTUR CAPITAL Q
    ; between_unicode_range(0x1D516, 0x1D51C, Character) % XID_Start # L&   [7] MATHEMATICAL FRAKTUR CAPITAL S..MATHEMATICAL FRAKTUR CAPITAL Y
    ; between_unicode_range(0x1D51E, 0x1D539, Character) % XID_Start # L&  [28] MATHEMATICAL FRAKTUR SMALL A..MATHEMATICAL DOUBLE-STRUCK CAPITAL B
    ; between_unicode_range(0x1D53B, 0x1D53E, Character) % XID_Start # L&   [4] MATHEMATICAL DOUBLE-STRUCK CAPITAL D..MATHEMATICAL DOUBLE-STRUCK CAPITAL G
    ; between_unicode_range(0x1D540, 0x1D544, Character) % XID_Start # L&   [5] MATHEMATICAL DOUBLE-STRUCK CAPITAL I..MATHEMATICAL DOUBLE-STRUCK CAPITAL M
    ; unicode_character(0x1D546, Character) % XID_Start # L&       MATHEMATICAL DOUBLE-STRUCK CAPITAL O
    ; between_unicode_range(0x1D54A, 0x1D550, Character) % XID_Start # L&   [7] MATHEMATICAL DOUBLE-STRUCK CAPITAL S..MATHEMATICAL DOUBLE-STRUCK CAPITAL Y
    ; between_unicode_range(0x1D552, 0x1D6A5, Character) % XID_Start # L& [340] MATHEMATICAL DOUBLE-STRUCK SMALL A..MATHEMATICAL ITALIC SMALL DOTLESS J
    ; between_unicode_range(0x1D6A8, 0x1D6C0, Character) % XID_Start # L&  [25] MATHEMATICAL BOLD CAPITAL ALPHA..MATHEMATICAL BOLD CAPITAL OMEGA
    ; between_unicode_range(0x1D6C2, 0x1D6DA, Character) % XID_Start # L&  [25] MATHEMATICAL BOLD SMALL ALPHA..MATHEMATICAL BOLD SMALL OMEGA
    ; between_unicode_range(0x1D6DC, 0x1D6FA, Character) % XID_Start # L&  [31] MATHEMATICAL BOLD EPSILON SYMBOL..MATHEMATICAL ITALIC CAPITAL OMEGA
    ; between_unicode_range(0x1D6FC, 0x1D714, Character) % XID_Start # L&  [25] MATHEMATICAL ITALIC SMALL ALPHA..MATHEMATICAL ITALIC SMALL OMEGA
    ; between_unicode_range(0x1D716, 0x1D734, Character) % XID_Start # L&  [31] MATHEMATICAL ITALIC EPSILON SYMBOL..MATHEMATICAL BOLD ITALIC CAPITAL OMEGA
    ; between_unicode_range(0x1D736, 0x1D74E, Character) % XID_Start # L&  [25] MATHEMATICAL BOLD ITALIC SMALL ALPHA..MATHEMATICAL BOLD ITALIC SMALL OMEGA
    ; between_unicode_range(0x1D750, 0x1D76E, Character) % XID_Start # L&  [31] MATHEMATICAL BOLD ITALIC EPSILON SYMBOL..MATHEMATICAL SANS-SERIF BOLD CAPITAL OMEGA
    ; between_unicode_range(0x1D770, 0x1D788, Character) % XID_Start # L&  [25] MATHEMATICAL SANS-SERIF BOLD SMALL ALPHA..MATHEMATICAL SANS-SERIF BOLD SMALL OMEGA
    ; between_unicode_range(0x1D78A, 0x1D7A8, Character) % XID_Start # L&  [31] MATHEMATICAL SANS-SERIF BOLD EPSILON SYMBOL..MATHEMATICAL SANS-SERIF BOLD ITALIC CAPITAL OMEGA
    ; between_unicode_range(0x1D7AA, 0x1D7C2, Character) % XID_Start # L&  [25] MATHEMATICAL SANS-SERIF BOLD ITALIC SMALL ALPHA..MATHEMATICAL SANS-SERIF BOLD ITALIC SMALL OMEGA
    ; between_unicode_range(0x1D7C4, 0x1D7CB, Character) % XID_Start # L&   [8] MATHEMATICAL SANS-SERIF BOLD ITALIC EPSILON SYMBOL..MATHEMATICAL BOLD SMALL DIGAMMA
    ; between_unicode_range(0x1DF00, 0x1DF09, Character) % XID_Start # L&  [10] LATIN SMALL LETTER FENG DIGRAPH WITH TRILL..LATIN SMALL LETTER T WITH HOOK AND RETROFLEX HOOK
    ; unicode_character(0x1DF0A, Character) % XID_Start # Lo       LATIN LETTER RETROFLEX CLICK WITH RETROFLEX HOOK
    ; between_unicode_range(0x1DF0B, 0x1DF1E, Character) % XID_Start # L&  [20] LATIN SMALL LETTER ESH WITH DOUBLE BAR..LATIN SMALL LETTER S WITH CURL
    ; between_unicode_range(0x1DF25, 0x1DF2A, Character) % XID_Start # L&   [6] LATIN SMALL LETTER D WITH MID-HEIGHT LEFT HOOK..LATIN SMALL LETTER T WITH MID-HEIGHT LEFT HOOK
    ; between_unicode_range(0x1E030, 0x1E06D, Character) % XID_Start # Lm  [62] MODIFIER LETTER CYRILLIC SMALL A..MODIFIER LETTER CYRILLIC SMALL STRAIGHT U WITH STROKE
    ; between_unicode_range(0x1E100, 0x1E12C, Character) % XID_Start # Lo  [45] NYIAKENG PUACHUE HMONG LETTER MA..NYIAKENG PUACHUE HMONG LETTER W
    ; between_unicode_range(0x1E137, 0x1E13D, Character) % XID_Start # Lm   [7] NYIAKENG PUACHUE HMONG SIGN FOR PERSON..NYIAKENG PUACHUE HMONG SYLLABLE LENGTHENER
    ; unicode_character(0x1E14E, Character) % XID_Start # Lo       NYIAKENG PUACHUE HMONG LOGOGRAM NYAJ
    ; between_unicode_range(0x1E290, 0x1E2AD, Character) % XID_Start # Lo  [30] TOTO LETTER PA..TOTO LETTER A
    ; between_unicode_range(0x1E2C0, 0x1E2EB, Character) % XID_Start # Lo  [44] WANCHO LETTER AA..WANCHO LETTER YIH
    ; between_unicode_range(0x1E4D0, 0x1E4EA, Character) % XID_Start # Lo  [27] NAG MUNDARI LETTER O..NAG MUNDARI LETTER ELL
    ; unicode_character(0x1E4EB, Character) % XID_Start # Lm       NAG MUNDARI SIGN OJOD
    ; between_unicode_range(0x1E5D0, 0x1E5ED, Character) % XID_Start # Lo  [30] OL ONAL LETTER O..OL ONAL LETTER EG
    ; unicode_character(0x1E5F0, Character) % XID_Start # Lo       OL ONAL SIGN HODDOND
    ; between_unicode_range(0x1E7E0, 0x1E7E6, Character) % XID_Start # Lo   [7] ETHIOPIC SYLLABLE HHYA..ETHIOPIC SYLLABLE HHYO
    ; between_unicode_range(0x1E7E8, 0x1E7EB, Character) % XID_Start # Lo   [4] ETHIOPIC SYLLABLE GURAGE HHWA..ETHIOPIC SYLLABLE HHWE
    ; between_unicode_range(0x1E7ED, 0x1E7EE, Character) % XID_Start # Lo   [2] ETHIOPIC SYLLABLE GURAGE MWI..ETHIOPIC SYLLABLE GURAGE MWEE
    ; between_unicode_range(0x1E7F0, 0x1E7FE, Character) % XID_Start # Lo  [15] ETHIOPIC SYLLABLE GURAGE QWI..ETHIOPIC SYLLABLE GURAGE PWEE
    ; between_unicode_range(0x1E800, 0x1E8C4, Character) % XID_Start # Lo [197] MENDE KIKAKUI SYLLABLE M001 KI..MENDE KIKAKUI SYLLABLE M060 NYON
    ; between_unicode_range(0x1E900, 0x1E943, Character) % XID_Start # L&  [68] ADLAM CAPITAL LETTER ALIF..ADLAM SMALL LETTER SHA
    ; unicode_character(0x1E94B, Character) % XID_Start # Lm       ADLAM NASALIZATION MARK
    ; between_unicode_range(0x1EE00, 0x1EE03, Character) % XID_Start # Lo   [4] ARABIC MATHEMATICAL ALEF..ARABIC MATHEMATICAL DAL
    ; between_unicode_range(0x1EE05, 0x1EE1F, Character) % XID_Start # Lo  [27] ARABIC MATHEMATICAL WAW..ARABIC MATHEMATICAL DOTLESS QAF
    ; between_unicode_range(0x1EE21, 0x1EE22, Character) % XID_Start # Lo   [2] ARABIC MATHEMATICAL INITIAL BEH..ARABIC MATHEMATICAL INITIAL JEEM
    ; unicode_character(0x1EE24, Character) % XID_Start # Lo       ARABIC MATHEMATICAL INITIAL HEH
    ; unicode_character(0x1EE27, Character) % XID_Start # Lo       ARABIC MATHEMATICAL INITIAL HAH
    ; between_unicode_range(0x1EE29, 0x1EE32, Character) % XID_Start # Lo  [10] ARABIC MATHEMATICAL INITIAL YEH..ARABIC MATHEMATICAL INITIAL QAF
    ; between_unicode_range(0x1EE34, 0x1EE37, Character) % XID_Start # Lo   [4] ARABIC MATHEMATICAL INITIAL SHEEN..ARABIC MATHEMATICAL INITIAL KHAH
    ; unicode_character(0x1EE39, Character) % XID_Start # Lo       ARABIC MATHEMATICAL INITIAL DAD
    ; unicode_character(0x1EE3B, Character) % XID_Start # Lo       ARABIC MATHEMATICAL INITIAL GHAIN
    ; unicode_character(0x1EE42, Character) % XID_Start # Lo       ARABIC MATHEMATICAL TAILED JEEM
    ; unicode_character(0x1EE47, Character) % XID_Start # Lo       ARABIC MATHEMATICAL TAILED HAH
    ; unicode_character(0x1EE49, Character) % XID_Start # Lo       ARABIC MATHEMATICAL TAILED YEH
    ; unicode_character(0x1EE4B, Character) % XID_Start # Lo       ARABIC MATHEMATICAL TAILED LAM
    ; between_unicode_range(0x1EE4D, 0x1EE4F, Character) % XID_Start # Lo   [3] ARABIC MATHEMATICAL TAILED NOON..ARABIC MATHEMATICAL TAILED AIN
    ; between_unicode_range(0x1EE51, 0x1EE52, Character) % XID_Start # Lo   [2] ARABIC MATHEMATICAL TAILED SAD..ARABIC MATHEMATICAL TAILED QAF
    ; unicode_character(0x1EE54, Character) % XID_Start # Lo       ARABIC MATHEMATICAL TAILED SHEEN
    ; unicode_character(0x1EE57, Character) % XID_Start # Lo       ARABIC MATHEMATICAL TAILED KHAH
    ; unicode_character(0x1EE59, Character) % XID_Start # Lo       ARABIC MATHEMATICAL TAILED DAD
    ; unicode_character(0x1EE5B, Character) % XID_Start # Lo       ARABIC MATHEMATICAL TAILED GHAIN
    ; unicode_character(0x1EE5D, Character) % XID_Start # Lo       ARABIC MATHEMATICAL TAILED DOTLESS NOON
    ; unicode_character(0x1EE5F, Character) % XID_Start # Lo       ARABIC MATHEMATICAL TAILED DOTLESS QAF
    ; between_unicode_range(0x1EE61, 0x1EE62, Character) % XID_Start # Lo   [2] ARABIC MATHEMATICAL STRETCHED BEH..ARABIC MATHEMATICAL STRETCHED JEEM
    ; unicode_character(0x1EE64, Character) % XID_Start # Lo       ARABIC MATHEMATICAL STRETCHED HEH
    ; between_unicode_range(0x1EE67, 0x1EE6A, Character) % XID_Start # Lo   [4] ARABIC MATHEMATICAL STRETCHED HAH..ARABIC MATHEMATICAL STRETCHED KAF
    ; between_unicode_range(0x1EE6C, 0x1EE72, Character) % XID_Start # Lo   [7] ARABIC MATHEMATICAL STRETCHED MEEM..ARABIC MATHEMATICAL STRETCHED QAF
    ; between_unicode_range(0x1EE74, 0x1EE77, Character) % XID_Start # Lo   [4] ARABIC MATHEMATICAL STRETCHED SHEEN..ARABIC MATHEMATICAL STRETCHED KHAH
    ; between_unicode_range(0x1EE79, 0x1EE7C, Character) % XID_Start # Lo   [4] ARABIC MATHEMATICAL STRETCHED DAD..ARABIC MATHEMATICAL STRETCHED DOTLESS BEH
    ; unicode_character(0x1EE7E, Character) % XID_Start # Lo       ARABIC MATHEMATICAL STRETCHED DOTLESS FEH
    ; between_unicode_range(0x1EE80, 0x1EE89, Character) % XID_Start # Lo  [10] ARABIC MATHEMATICAL LOOPED ALEF..ARABIC MATHEMATICAL LOOPED YEH
    ; between_unicode_range(0x1EE8B, 0x1EE9B, Character) % XID_Start # Lo  [17] ARABIC MATHEMATICAL LOOPED LAM..ARABIC MATHEMATICAL LOOPED GHAIN
    ; between_unicode_range(0x1EEA1, 0x1EEA3, Character) % XID_Start # Lo   [3] ARABIC MATHEMATICAL DOUBLE-STRUCK BEH..ARABIC MATHEMATICAL DOUBLE-STRUCK DAL
    ; between_unicode_range(0x1EEA5, 0x1EEA9, Character) % XID_Start # Lo   [5] ARABIC MATHEMATICAL DOUBLE-STRUCK WAW..ARABIC MATHEMATICAL DOUBLE-STRUCK YEH
    ; between_unicode_range(0x1EEAB, 0x1EEBB, Character) % XID_Start # Lo  [17] ARABIC MATHEMATICAL DOUBLE-STRUCK LAM..ARABIC MATHEMATICAL DOUBLE-STRUCK GHAIN
    ; between_unicode_range(0x20000, 0x2A6DF, Character) % XID_Start # Lo [42720] CJK UNIFIED IDEOGRAPH-20000..CJK UNIFIED IDEOGRAPH-2A6DF
    ; between_unicode_range(0x2A700, 0x2B739, Character) % XID_Start # Lo [4154] CJK UNIFIED IDEOGRAPH-2A700..CJK UNIFIED IDEOGRAPH-2B739
    ; between_unicode_range(0x2B740, 0x2B81D, Character) % XID_Start # Lo [222] CJK UNIFIED IDEOGRAPH-2B740..CJK UNIFIED IDEOGRAPH-2B81D
    ; between_unicode_range(0x2B820, 0x2CEA1, Character) % XID_Start # Lo [5762] CJK UNIFIED IDEOGRAPH-2B820..CJK UNIFIED IDEOGRAPH-2CEA1
    ; between_unicode_range(0x2CEB0, 0x2EBE0, Character) % XID_Start # Lo [7473] CJK UNIFIED IDEOGRAPH-2CEB0..CJK UNIFIED IDEOGRAPH-2EBE0
    ; between_unicode_range(0x2EBF0, 0x2EE5D, Character) % XID_Start # Lo [622] CJK UNIFIED IDEOGRAPH-2EBF0..CJK UNIFIED IDEOGRAPH-2EE5D
    ; between_unicode_range(0x2F800, 0x2FA1D, Character) % XID_Start # Lo [542] CJK COMPATIBILITY IDEOGRAPH-2F800..CJK COMPATIBILITY IDEOGRAPH-2FA1D
    ; between_unicode_range(0x30000, 0x3134A, Character) % XID_Start # Lo [4939] CJK UNIFIED IDEOGRAPH-30000..CJK UNIFIED IDEOGRAPH-3134A
    ; between_unicode_range(0x31350, 0x323AF, Character) % XID_Start # Lo [4192] CJK UNIFIED IDEOGRAPH-31350..CJK UNIFIED IDEOGRAPH-323AF
  }.

identifier_rest_characters([ContinueCharacter | Characters]) -->
  identifier_continue_character(ContinueCharacter),
  identifier_rest_characters(Characters).
% The default clause has to be the last definition to enforce Prolog
% to report the largest available token as identifier first.
identifier_rest_characters([]) --> [].

identifier_continue_character(Character) -->
  [Character],
  {
    between_unicode_range(0x0030, 0x0039, Character) % XID_Continue # Nd  [10] DIGIT ZERO..DIGIT NINE
    ; between_unicode_range(0x0041, 0x005A, Character) % XID_Continue # L&  [26] LATIN CAPITAL LETTER A..LATIN CAPITAL LETTER Z
    ; unicode_character(0x005F, Character) % XID_Continue # Pc       LOW LINE
    ; between_unicode_range(0x0061, 0x007A, Character) % XID_Continue # L&  [26] LATIN SMALL LETTER A..LATIN SMALL LETTER Z
    ; unicode_character(0x00AA, Character) % XID_Continue # Lo       FEMININE ORDINAL INDICATOR
    ; unicode_character(0x00B5, Character) % XID_Continue # L&       MICRO SIGN
    ; unicode_character(0x00B7, Character) % XID_Continue # Po       MIDDLE DOT
    ; unicode_character(0x00BA, Character) % XID_Continue # Lo       MASCULINE ORDINAL INDICATOR
    ; between_unicode_range(0x00C0, 0x00D6, Character) % XID_Continue # L&  [23] LATIN CAPITAL LETTER A WITH GRAVE..LATIN CAPITAL LETTER O WITH DIAERESIS
    ; between_unicode_range(0x00D8, 0x00F6, Character) % XID_Continue # L&  [31] LATIN CAPITAL LETTER O WITH STROKE..LATIN SMALL LETTER O WITH DIAERESIS
    ; between_unicode_range(0x00F8, 0x01BA, Character) % XID_Continue # L& [195] LATIN SMALL LETTER O WITH STROKE..LATIN SMALL LETTER EZH WITH TAIL
    ; unicode_character(0x01BB, Character) % XID_Continue # Lo       LATIN LETTER TWO WITH STROKE
    ; between_unicode_range(0x01BC, 0x01BF, Character) % XID_Continue # L&   [4] LATIN CAPITAL LETTER TONE FIVE..LATIN LETTER WYNN
    ; between_unicode_range(0x01C0, 0x01C3, Character) % XID_Continue # Lo   [4] LATIN LETTER DENTAL CLICK..LATIN LETTER RETROFLEX CLICK
    ; between_unicode_range(0x01C4, 0x0293, Character) % XID_Continue # L& [208] LATIN CAPITAL LETTER DZ WITH CARON..LATIN SMALL LETTER EZH WITH CURL
    ; unicode_character(0x0294, Character) % XID_Continue # Lo       LATIN LETTER GLOTTAL STOP
    ; between_unicode_range(0x0295, 0x02AF, Character) % XID_Continue # L&  [27] LATIN LETTER PHARYNGEAL VOICED FRICATIVE..LATIN SMALL LETTER TURNED H WITH FISHHOOK AND TAIL
    ; between_unicode_range(0x02B0, 0x02C1, Character) % XID_Continue # Lm  [18] MODIFIER LETTER SMALL H..MODIFIER LETTER REVERSED GLOTTAL STOP
    ; between_unicode_range(0x02C6, 0x02D1, Character) % XID_Continue # Lm  [12] MODIFIER LETTER CIRCUMFLEX ACCENT..MODIFIER LETTER HALF TRIANGULAR COLON
    ; between_unicode_range(0x02E0, 0x02E4, Character) % XID_Continue # Lm   [5] MODIFIER LETTER SMALL GAMMA..MODIFIER LETTER SMALL REVERSED GLOTTAL STOP
    ; unicode_character(0x02EC, Character) % XID_Continue # Lm       MODIFIER LETTER VOICING
    ; unicode_character(0x02EE, Character) % XID_Continue # Lm       MODIFIER LETTER DOUBLE APOSTROPHE
    ; between_unicode_range(0x0300, 0x036F, Character) % XID_Continue # Mn [112] COMBINING GRAVE ACCENT..COMBINING LATIN SMALL LETTER X
    ; between_unicode_range(0x0370, 0x0373, Character) % XID_Continue # L&   [4] GREEK CAPITAL LETTER HETA..GREEK SMALL LETTER ARCHAIC SAMPI
    ; unicode_character(0x0374, Character) % XID_Continue # Lm       GREEK NUMERAL SIGN
    ; between_unicode_range(0x0376, 0x0377, Character) % XID_Continue # L&   [2] GREEK CAPITAL LETTER PAMPHYLIAN DIGAMMA..GREEK SMALL LETTER PAMPHYLIAN DIGAMMA
    ; between_unicode_range(0x037B, 0x037D, Character) % XID_Continue # L&   [3] GREEK SMALL REVERSED LUNATE SIGMA SYMBOL..GREEK SMALL REVERSED DOTTED LUNATE SIGMA SYMBOL
    ; unicode_character(0x037F, Character) % XID_Continue # L&       GREEK CAPITAL LETTER YOT
    ; unicode_character(0x0386, Character) % XID_Continue # L&       GREEK CAPITAL LETTER ALPHA WITH TONOS
    ; unicode_character(0x0387, Character) % XID_Continue # Po       GREEK ANO TELEIA
    ; between_unicode_range(0x0388, 0x038A, Character) % XID_Continue # L&   [3] GREEK CAPITAL LETTER EPSILON WITH TONOS..GREEK CAPITAL LETTER IOTA WITH TONOS
    ; unicode_character(0x038C, Character) % XID_Continue # L&       GREEK CAPITAL LETTER OMICRON WITH TONOS
    ; between_unicode_range(0x038E, 0x03A1, Character) % XID_Continue # L&  [20] GREEK CAPITAL LETTER UPSILON WITH TONOS..GREEK CAPITAL LETTER RHO
    ; between_unicode_range(0x03A3, 0x03F5, Character) % XID_Continue # L&  [83] GREEK CAPITAL LETTER SIGMA..GREEK LUNATE EPSILON SYMBOL
    ; between_unicode_range(0x03F7, 0x0481, Character) % XID_Continue # L& [139] GREEK CAPITAL LETTER SHO..CYRILLIC SMALL LETTER KOPPA
    ; between_unicode_range(0x0483, 0x0487, Character) % XID_Continue # Mn   [5] COMBINING CYRILLIC TITLO..COMBINING CYRILLIC POKRYTIE
    ; between_unicode_range(0x048A, 0x052F, Character) % XID_Continue # L& [166] CYRILLIC CAPITAL LETTER SHORT I WITH TAIL..CYRILLIC SMALL LETTER EL WITH DESCENDER
    ; between_unicode_range(0x0531, 0x0556, Character) % XID_Continue # L&  [38] ARMENIAN CAPITAL LETTER AYB..ARMENIAN CAPITAL LETTER FEH
    ; unicode_character(0x0559, Character) % XID_Continue # Lm       ARMENIAN MODIFIER LETTER LEFT HALF RING
    ; between_unicode_range(0x0560, 0x0588, Character) % XID_Continue # L&  [41] ARMENIAN SMALL LETTER TURNED AYB..ARMENIAN SMALL LETTER YI WITH STROKE
    ; between_unicode_range(0x0591, 0x05BD, Character) % XID_Continue # Mn  [45] HEBREW ACCENT ETNAHTA..HEBREW POINT METEG
    ; unicode_character(0x05BF, Character) % XID_Continue # Mn       HEBREW POINT RAFE
    ; between_unicode_range(0x05C1, 0x05C2, Character) % XID_Continue # Mn   [2] HEBREW POINT SHIN DOT..HEBREW POINT SIN DOT
    ; between_unicode_range(0x05C4, 0x05C5, Character) % XID_Continue # Mn   [2] HEBREW MARK UPPER DOT..HEBREW MARK LOWER DOT
    ; unicode_character(0x05C7, Character) % XID_Continue # Mn       HEBREW POINT QAMATS QATAN
    ; between_unicode_range(0x05D0, 0x05EA, Character) % XID_Continue # Lo  [27] HEBREW LETTER ALEF..HEBREW LETTER TAV
    ; between_unicode_range(0x05EF, 0x05F2, Character) % XID_Continue # Lo   [4] HEBREW YOD TRIANGLE..HEBREW LIGATURE YIDDISH DOUBLE YOD
    ; between_unicode_range(0x0610, 0x061A, Character) % XID_Continue # Mn  [11] ARABIC SIGN SALLALLAHOU ALAYHE WASSALLAM..ARABIC SMALL KASRA
    ; between_unicode_range(0x0620, 0x063F, Character) % XID_Continue # Lo  [32] ARABIC LETTER KASHMIRI YEH..ARABIC LETTER FARSI YEH WITH THREE DOTS ABOVE
    ; unicode_character(0x0640, Character) % XID_Continue # Lm       ARABIC TATWEEL
    ; between_unicode_range(0x0641, 0x064A, Character) % XID_Continue # Lo  [10] ARABIC LETTER FEH..ARABIC LETTER YEH
    ; between_unicode_range(0x064B, 0x065F, Character) % XID_Continue # Mn  [21] ARABIC FATHATAN..ARABIC WAVY HAMZA BELOW
    ; between_unicode_range(0x0660, 0x0669, Character) % XID_Continue # Nd  [10] ARABIC-INDIC DIGIT ZERO..ARABIC-INDIC DIGIT NINE
    ; between_unicode_range(0x066E, 0x066F, Character) % XID_Continue # Lo   [2] ARABIC LETTER DOTLESS BEH..ARABIC LETTER DOTLESS QAF
    ; unicode_character(0x0670, Character) % XID_Continue # Mn       ARABIC LETTER SUPERSCRIPT ALEF
    ; between_unicode_range(0x0671, 0x06D3, Character) % XID_Continue # Lo  [99] ARABIC LETTER ALEF WASLA..ARABIC LETTER YEH BARREE WITH HAMZA ABOVE
    ; unicode_character(0x06D5, Character) % XID_Continue # Lo       ARABIC LETTER AE
    ; between_unicode_range(0x06D6, 0x06DC, Character) % XID_Continue # Mn   [7] ARABIC SMALL HIGH LIGATURE SAD WITH LAM WITH ALEF MAKSURA..ARABIC SMALL HIGH SEEN
    ; between_unicode_range(0x06DF, 0x06E4, Character) % XID_Continue # Mn   [6] ARABIC SMALL HIGH ROUNDED ZERO..ARABIC SMALL HIGH MADDA
    ; between_unicode_range(0x06E5, 0x06E6, Character) % XID_Continue # Lm   [2] ARABIC SMALL WAW..ARABIC SMALL YEH
    ; between_unicode_range(0x06E7, 0x06E8, Character) % XID_Continue # Mn   [2] ARABIC SMALL HIGH YEH..ARABIC SMALL HIGH NOON
    ; between_unicode_range(0x06EA, 0x06ED, Character) % XID_Continue # Mn   [4] ARABIC EMPTY CENTRE LOW STOP..ARABIC SMALL LOW MEEM
    ; between_unicode_range(0x06EE, 0x06EF, Character) % XID_Continue # Lo   [2] ARABIC LETTER DAL WITH INVERTED V..ARABIC LETTER REH WITH INVERTED V
    ; between_unicode_range(0x06F0, 0x06F9, Character) % XID_Continue # Nd  [10] EXTENDED ARABIC-INDIC DIGIT ZERO..EXTENDED ARABIC-INDIC DIGIT NINE
    ; between_unicode_range(0x06FA, 0x06FC, Character) % XID_Continue # Lo   [3] ARABIC LETTER SHEEN WITH DOT BELOW..ARABIC LETTER GHAIN WITH DOT BELOW
    ; unicode_character(0x06FF, Character) % XID_Continue # Lo       ARABIC LETTER HEH WITH INVERTED V
    ; unicode_character(0x0710, Character) % XID_Continue # Lo       SYRIAC LETTER ALAPH
    ; unicode_character(0x0711, Character) % XID_Continue # Mn       SYRIAC LETTER SUPERSCRIPT ALAPH
    ; between_unicode_range(0x0712, 0x072F, Character) % XID_Continue # Lo  [30] SYRIAC LETTER BETH..SYRIAC LETTER PERSIAN DHALATH
    ; between_unicode_range(0x0730, 0x074A, Character) % XID_Continue # Mn  [27] SYRIAC PTHAHA ABOVE..SYRIAC BARREKH
    ; between_unicode_range(0x074D, 0x07A5, Character) % XID_Continue # Lo  [89] SYRIAC LETTER SOGDIAN ZHAIN..THAANA LETTER WAAVU
    ; between_unicode_range(0x07A6, 0x07B0, Character) % XID_Continue # Mn  [11] THAANA ABAFILI..THAANA SUKUN
    ; unicode_character(0x07B1, Character) % XID_Continue # Lo       THAANA LETTER NAA
    ; between_unicode_range(0x07C0, 0x07C9, Character) % XID_Continue # Nd  [10] NKO DIGIT ZERO..NKO DIGIT NINE
    ; between_unicode_range(0x07CA, 0x07EA, Character) % XID_Continue # Lo  [33] NKO LETTER A..NKO LETTER JONA RA
    ; between_unicode_range(0x07EB, 0x07F3, Character) % XID_Continue # Mn   [9] NKO COMBINING SHORT HIGH TONE..NKO COMBINING DOUBLE DOT ABOVE
    ; between_unicode_range(0x07F4, 0x07F5, Character) % XID_Continue # Lm   [2] NKO HIGH TONE APOSTROPHE..NKO LOW TONE APOSTROPHE
    ; unicode_character(0x07FA, Character) % XID_Continue # Lm       NKO LAJANYALAN
    ; unicode_character(0x07FD, Character) % XID_Continue # Mn       NKO DANTAYALAN
    ; between_unicode_range(0x0800, 0x0815, Character) % XID_Continue # Lo  [22] SAMARITAN LETTER ALAF..SAMARITAN LETTER TAAF
    ; between_unicode_range(0x0816, 0x0819, Character) % XID_Continue # Mn   [4] SAMARITAN MARK IN..SAMARITAN MARK DAGESH
    ; unicode_character(0x081A, Character) % XID_Continue # Lm       SAMARITAN MODIFIER LETTER EPENTHETIC YUT
    ; between_unicode_range(0x081B, 0x0823, Character) % XID_Continue # Mn   [9] SAMARITAN MARK EPENTHETIC YUT..SAMARITAN VOWEL SIGN A
    ; unicode_character(0x0824, Character) % XID_Continue # Lm       SAMARITAN MODIFIER LETTER SHORT A
    ; between_unicode_range(0x0825, 0x0827, Character) % XID_Continue # Mn   [3] SAMARITAN VOWEL SIGN SHORT A..SAMARITAN VOWEL SIGN U
    ; unicode_character(0x0828, Character) % XID_Continue # Lm       SAMARITAN MODIFIER LETTER I
    ; between_unicode_range(0x0829, 0x082D, Character) % XID_Continue # Mn   [5] SAMARITAN VOWEL SIGN LONG I..SAMARITAN MARK NEQUDAA
    ; between_unicode_range(0x0840, 0x0858, Character) % XID_Continue # Lo  [25] MANDAIC LETTER HALQA..MANDAIC LETTER AIN
    ; between_unicode_range(0x0859, 0x085B, Character) % XID_Continue # Mn   [3] MANDAIC AFFRICATION MARK..MANDAIC GEMINATION MARK
    ; between_unicode_range(0x0860, 0x086A, Character) % XID_Continue # Lo  [11] SYRIAC LETTER MALAYALAM NGA..SYRIAC LETTER MALAYALAM SSA
    ; between_unicode_range(0x0870, 0x0887, Character) % XID_Continue # Lo  [24] ARABIC LETTER ALEF WITH ATTACHED FATHA..ARABIC BASELINE ROUND DOT
    ; between_unicode_range(0x0889, 0x088E, Character) % XID_Continue # Lo   [6] ARABIC LETTER NOON WITH INVERTED SMALL V..ARABIC VERTICAL TAIL
    ; between_unicode_range(0x0897, 0x089F, Character) % XID_Continue # Mn   [9] ARABIC PEPET..ARABIC HALF MADDA OVER MADDA
    ; between_unicode_range(0x08A0, 0x08C8, Character) % XID_Continue # Lo  [41] ARABIC LETTER BEH WITH SMALL V BELOW..ARABIC LETTER GRAF
    ; unicode_character(0x08C9, Character) % XID_Continue # Lm       ARABIC SMALL FARSI YEH
    ; between_unicode_range(0x08CA, 0x08E1, Character) % XID_Continue # Mn  [24] ARABIC SMALL HIGH FARSI YEH..ARABIC SMALL HIGH SIGN SAFHA
    ; between_unicode_range(0x08E3, 0x0902, Character) % XID_Continue # Mn  [32] ARABIC TURNED DAMMA BELOW..DEVANAGARI SIGN ANUSVARA
    ; unicode_character(0x0903, Character) % XID_Continue # Mc       DEVANAGARI SIGN VISARGA
    ; between_unicode_range(0x0904, 0x0939, Character) % XID_Continue # Lo  [54] DEVANAGARI LETTER SHORT A..DEVANAGARI LETTER HA
    ; unicode_character(0x093A, Character) % XID_Continue # Mn       DEVANAGARI VOWEL SIGN OE
    ; unicode_character(0x093B, Character) % XID_Continue # Mc       DEVANAGARI VOWEL SIGN OOE
    ; unicode_character(0x093C, Character) % XID_Continue # Mn       DEVANAGARI SIGN NUKTA
    ; unicode_character(0x093D, Character) % XID_Continue # Lo       DEVANAGARI SIGN AVAGRAHA
    ; between_unicode_range(0x093E, 0x0940, Character) % XID_Continue # Mc   [3] DEVANAGARI VOWEL SIGN AA..DEVANAGARI VOWEL SIGN II
    ; between_unicode_range(0x0941, 0x0948, Character) % XID_Continue # Mn   [8] DEVANAGARI VOWEL SIGN U..DEVANAGARI VOWEL SIGN AI
    ; between_unicode_range(0x0949, 0x094C, Character) % XID_Continue # Mc   [4] DEVANAGARI VOWEL SIGN CANDRA O..DEVANAGARI VOWEL SIGN AU
    ; unicode_character(0x094D, Character) % XID_Continue # Mn       DEVANAGARI SIGN VIRAMA
    ; between_unicode_range(0x094E, 0x094F, Character) % XID_Continue # Mc   [2] DEVANAGARI VOWEL SIGN PRISHTHAMATRA E..DEVANAGARI VOWEL SIGN AW
    ; unicode_character(0x0950, Character) % XID_Continue # Lo       DEVANAGARI OM
    ; between_unicode_range(0x0951, 0x0957, Character) % XID_Continue # Mn   [7] DEVANAGARI STRESS SIGN UDATTA..DEVANAGARI VOWEL SIGN UUE
    ; between_unicode_range(0x0958, 0x0961, Character) % XID_Continue # Lo  [10] DEVANAGARI LETTER QA..DEVANAGARI LETTER VOCALIC LL
    ; between_unicode_range(0x0962, 0x0963, Character) % XID_Continue # Mn   [2] DEVANAGARI VOWEL SIGN VOCALIC L..DEVANAGARI VOWEL SIGN VOCALIC LL
    ; between_unicode_range(0x0966, 0x096F, Character) % XID_Continue # Nd  [10] DEVANAGARI DIGIT ZERO..DEVANAGARI DIGIT NINE
    ; unicode_character(0x0971, Character) % XID_Continue # Lm       DEVANAGARI SIGN HIGH SPACING DOT
    ; between_unicode_range(0x0972, 0x0980, Character) % XID_Continue # Lo  [15] DEVANAGARI LETTER CANDRA A..BENGALI ANJI
    ; unicode_character(0x0981, Character) % XID_Continue # Mn       BENGALI SIGN CANDRABINDU
    ; between_unicode_range(0x0982, 0x0983, Character) % XID_Continue # Mc   [2] BENGALI SIGN ANUSVARA..BENGALI SIGN VISARGA
    ; between_unicode_range(0x0985, 0x098C, Character) % XID_Continue # Lo   [8] BENGALI LETTER A..BENGALI LETTER VOCALIC L
    ; between_unicode_range(0x098F, 0x0990, Character) % XID_Continue # Lo   [2] BENGALI LETTER E..BENGALI LETTER AI
    ; between_unicode_range(0x0993, 0x09A8, Character) % XID_Continue # Lo  [22] BENGALI LETTER O..BENGALI LETTER NA
    ; between_unicode_range(0x09AA, 0x09B0, Character) % XID_Continue # Lo   [7] BENGALI LETTER PA..BENGALI LETTER RA
    ; unicode_character(0x09B2, Character) % XID_Continue # Lo       BENGALI LETTER LA
    ; between_unicode_range(0x09B6, 0x09B9, Character) % XID_Continue # Lo   [4] BENGALI LETTER SHA..BENGALI LETTER HA
    ; unicode_character(0x09BC, Character) % XID_Continue # Mn       BENGALI SIGN NUKTA
    ; unicode_character(0x09BD, Character) % XID_Continue # Lo       BENGALI SIGN AVAGRAHA
    ; between_unicode_range(0x09BE, 0x09C0, Character) % XID_Continue # Mc   [3] BENGALI VOWEL SIGN AA..BENGALI VOWEL SIGN II
    ; between_unicode_range(0x09C1, 0x09C4, Character) % XID_Continue # Mn   [4] BENGALI VOWEL SIGN U..BENGALI VOWEL SIGN VOCALIC RR
    ; between_unicode_range(0x09C7, 0x09C8, Character) % XID_Continue # Mc   [2] BENGALI VOWEL SIGN E..BENGALI VOWEL SIGN AI
    ; between_unicode_range(0x09CB, 0x09CC, Character) % XID_Continue # Mc   [2] BENGALI VOWEL SIGN O..BENGALI VOWEL SIGN AU
    ; unicode_character(0x09CD, Character) % XID_Continue # Mn       BENGALI SIGN VIRAMA
    ; unicode_character(0x09CE, Character) % XID_Continue # Lo       BENGALI LETTER KHANDA TA
    ; unicode_character(0x09D7, Character) % XID_Continue # Mc       BENGALI AU LENGTH MARK
    ; between_unicode_range(0x09DC, 0x09DD, Character) % XID_Continue # Lo   [2] BENGALI LETTER RRA..BENGALI LETTER RHA
    ; between_unicode_range(0x09DF, 0x09E1, Character) % XID_Continue # Lo   [3] BENGALI LETTER YYA..BENGALI LETTER VOCALIC LL
    ; between_unicode_range(0x09E2, 0x09E3, Character) % XID_Continue # Mn   [2] BENGALI VOWEL SIGN VOCALIC L..BENGALI VOWEL SIGN VOCALIC LL
    ; between_unicode_range(0x09E6, 0x09EF, Character) % XID_Continue # Nd  [10] BENGALI DIGIT ZERO..BENGALI DIGIT NINE
    ; between_unicode_range(0x09F0, 0x09F1, Character) % XID_Continue # Lo   [2] BENGALI LETTER RA WITH MIDDLE DIAGONAL..BENGALI LETTER RA WITH LOWER DIAGONAL
    ; unicode_character(0x09FC, Character) % XID_Continue # Lo       BENGALI LETTER VEDIC ANUSVARA
    ; unicode_character(0x09FE, Character) % XID_Continue # Mn       BENGALI SANDHI MARK
    ; between_unicode_range(0x0A01, 0x0A02, Character) % XID_Continue # Mn   [2] GURMUKHI SIGN ADAK BINDI..GURMUKHI SIGN BINDI
    ; unicode_character(0x0A03, Character) % XID_Continue # Mc       GURMUKHI SIGN VISARGA
    ; between_unicode_range(0x0A05, 0x0A0A, Character) % XID_Continue # Lo   [6] GURMUKHI LETTER A..GURMUKHI LETTER UU
    ; between_unicode_range(0x0A0F, 0x0A10, Character) % XID_Continue # Lo   [2] GURMUKHI LETTER EE..GURMUKHI LETTER AI
    ; between_unicode_range(0x0A13, 0x0A28, Character) % XID_Continue # Lo  [22] GURMUKHI LETTER OO..GURMUKHI LETTER NA
    ; between_unicode_range(0x0A2A, 0x0A30, Character) % XID_Continue # Lo   [7] GURMUKHI LETTER PA..GURMUKHI LETTER RA
    ; between_unicode_range(0x0A32, 0x0A33, Character) % XID_Continue # Lo   [2] GURMUKHI LETTER LA..GURMUKHI LETTER LLA
    ; between_unicode_range(0x0A35, 0x0A36, Character) % XID_Continue # Lo   [2] GURMUKHI LETTER VA..GURMUKHI LETTER SHA
    ; between_unicode_range(0x0A38, 0x0A39, Character) % XID_Continue # Lo   [2] GURMUKHI LETTER SA..GURMUKHI LETTER HA
    ; unicode_character(0x0A3C, Character) % XID_Continue # Mn       GURMUKHI SIGN NUKTA
    ; between_unicode_range(0x0A3E, 0x0A40, Character) % XID_Continue # Mc   [3] GURMUKHI VOWEL SIGN AA..GURMUKHI VOWEL SIGN II
    ; between_unicode_range(0x0A41, 0x0A42, Character) % XID_Continue # Mn   [2] GURMUKHI VOWEL SIGN U..GURMUKHI VOWEL SIGN UU
    ; between_unicode_range(0x0A47, 0x0A48, Character) % XID_Continue # Mn   [2] GURMUKHI VOWEL SIGN EE..GURMUKHI VOWEL SIGN AI
    ; between_unicode_range(0x0A4B, 0x0A4D, Character) % XID_Continue # Mn   [3] GURMUKHI VOWEL SIGN OO..GURMUKHI SIGN VIRAMA
    ; unicode_character(0x0A51, Character) % XID_Continue # Mn       GURMUKHI SIGN UDAAT
    ; between_unicode_range(0x0A59, 0x0A5C, Character) % XID_Continue # Lo   [4] GURMUKHI LETTER KHHA..GURMUKHI LETTER RRA
    ; unicode_character(0x0A5E, Character) % XID_Continue # Lo       GURMUKHI LETTER FA
    ; between_unicode_range(0x0A66, 0x0A6F, Character) % XID_Continue # Nd  [10] GURMUKHI DIGIT ZERO..GURMUKHI DIGIT NINE
    ; between_unicode_range(0x0A70, 0x0A71, Character) % XID_Continue # Mn   [2] GURMUKHI TIPPI..GURMUKHI ADDAK
    ; between_unicode_range(0x0A72, 0x0A74, Character) % XID_Continue # Lo   [3] GURMUKHI IRI..GURMUKHI EK ONKAR
    ; unicode_character(0x0A75, Character) % XID_Continue # Mn       GURMUKHI SIGN YAKASH
    ; between_unicode_range(0x0A81, 0x0A82, Character) % XID_Continue # Mn   [2] GUJARATI SIGN CANDRABINDU..GUJARATI SIGN ANUSVARA
    ; unicode_character(0x0A83, Character) % XID_Continue # Mc       GUJARATI SIGN VISARGA
    ; between_unicode_range(0x0A85, 0x0A8D, Character) % XID_Continue # Lo   [9] GUJARATI LETTER A..GUJARATI VOWEL CANDRA E
    ; between_unicode_range(0x0A8F, 0x0A91, Character) % XID_Continue # Lo   [3] GUJARATI LETTER E..GUJARATI VOWEL CANDRA O
    ; between_unicode_range(0x0A93, 0x0AA8, Character) % XID_Continue # Lo  [22] GUJARATI LETTER O..GUJARATI LETTER NA
    ; between_unicode_range(0x0AAA, 0x0AB0, Character) % XID_Continue # Lo   [7] GUJARATI LETTER PA..GUJARATI LETTER RA
    ; between_unicode_range(0x0AB2, 0x0AB3, Character) % XID_Continue # Lo   [2] GUJARATI LETTER LA..GUJARATI LETTER LLA
    ; between_unicode_range(0x0AB5, 0x0AB9, Character) % XID_Continue # Lo   [5] GUJARATI LETTER VA..GUJARATI LETTER HA
    ; unicode_character(0x0ABC, Character) % XID_Continue # Mn       GUJARATI SIGN NUKTA
    ; unicode_character(0x0ABD, Character) % XID_Continue # Lo       GUJARATI SIGN AVAGRAHA
    ; between_unicode_range(0x0ABE, 0x0AC0, Character) % XID_Continue # Mc   [3] GUJARATI VOWEL SIGN AA..GUJARATI VOWEL SIGN II
    ; between_unicode_range(0x0AC1, 0x0AC5, Character) % XID_Continue # Mn   [5] GUJARATI VOWEL SIGN U..GUJARATI VOWEL SIGN CANDRA E
    ; between_unicode_range(0x0AC7, 0x0AC8, Character) % XID_Continue # Mn   [2] GUJARATI VOWEL SIGN E..GUJARATI VOWEL SIGN AI
    ; unicode_character(0x0AC9, Character) % XID_Continue # Mc       GUJARATI VOWEL SIGN CANDRA O
    ; between_unicode_range(0x0ACB, 0x0ACC, Character) % XID_Continue # Mc   [2] GUJARATI VOWEL SIGN O..GUJARATI VOWEL SIGN AU
    ; unicode_character(0x0ACD, Character) % XID_Continue # Mn       GUJARATI SIGN VIRAMA
    ; unicode_character(0x0AD0, Character) % XID_Continue # Lo       GUJARATI OM
    ; between_unicode_range(0x0AE0, 0x0AE1, Character) % XID_Continue # Lo   [2] GUJARATI LETTER VOCALIC RR..GUJARATI LETTER VOCALIC LL
    ; between_unicode_range(0x0AE2, 0x0AE3, Character) % XID_Continue # Mn   [2] GUJARATI VOWEL SIGN VOCALIC L..GUJARATI VOWEL SIGN VOCALIC LL
    ; between_unicode_range(0x0AE6, 0x0AEF, Character) % XID_Continue # Nd  [10] GUJARATI DIGIT ZERO..GUJARATI DIGIT NINE
    ; unicode_character(0x0AF9, Character) % XID_Continue # Lo       GUJARATI LETTER ZHA
    ; between_unicode_range(0x0AFA, 0x0AFF, Character) % XID_Continue # Mn   [6] GUJARATI SIGN SUKUN..GUJARATI SIGN TWO-CIRCLE NUKTA ABOVE
    ; unicode_character(0x0B01, Character) % XID_Continue # Mn       ORIYA SIGN CANDRABINDU
    ; between_unicode_range(0x0B02, 0x0B03, Character) % XID_Continue # Mc   [2] ORIYA SIGN ANUSVARA..ORIYA SIGN VISARGA
    ; between_unicode_range(0x0B05, 0x0B0C, Character) % XID_Continue # Lo   [8] ORIYA LETTER A..ORIYA LETTER VOCALIC L
    ; between_unicode_range(0x0B0F, 0x0B10, Character) % XID_Continue # Lo   [2] ORIYA LETTER E..ORIYA LETTER AI
    ; between_unicode_range(0x0B13, 0x0B28, Character) % XID_Continue # Lo  [22] ORIYA LETTER O..ORIYA LETTER NA
    ; between_unicode_range(0x0B2A, 0x0B30, Character) % XID_Continue # Lo   [7] ORIYA LETTER PA..ORIYA LETTER RA
    ; between_unicode_range(0x0B32, 0x0B33, Character) % XID_Continue # Lo   [2] ORIYA LETTER LA..ORIYA LETTER LLA
    ; between_unicode_range(0x0B35, 0x0B39, Character) % XID_Continue # Lo   [5] ORIYA LETTER VA..ORIYA LETTER HA
    ; unicode_character(0x0B3C, Character) % XID_Continue # Mn       ORIYA SIGN NUKTA
    ; unicode_character(0x0B3D, Character) % XID_Continue # Lo       ORIYA SIGN AVAGRAHA
    ; unicode_character(0x0B3E, Character) % XID_Continue # Mc       ORIYA VOWEL SIGN AA
    ; unicode_character(0x0B3F, Character) % XID_Continue # Mn       ORIYA VOWEL SIGN I
    ; unicode_character(0x0B40, Character) % XID_Continue # Mc       ORIYA VOWEL SIGN II
    ; between_unicode_range(0x0B41, 0x0B44, Character) % XID_Continue # Mn   [4] ORIYA VOWEL SIGN U..ORIYA VOWEL SIGN VOCALIC RR
    ; between_unicode_range(0x0B47, 0x0B48, Character) % XID_Continue # Mc   [2] ORIYA VOWEL SIGN E..ORIYA VOWEL SIGN AI
    ; between_unicode_range(0x0B4B, 0x0B4C, Character) % XID_Continue # Mc   [2] ORIYA VOWEL SIGN O..ORIYA VOWEL SIGN AU
    ; unicode_character(0x0B4D, Character) % XID_Continue # Mn       ORIYA SIGN VIRAMA
    ; between_unicode_range(0x0B55, 0x0B56, Character) % XID_Continue # Mn   [2] ORIYA SIGN OVERLINE..ORIYA AI LENGTH MARK
    ; unicode_character(0x0B57, Character) % XID_Continue # Mc       ORIYA AU LENGTH MARK
    ; between_unicode_range(0x0B5C, 0x0B5D, Character) % XID_Continue # Lo   [2] ORIYA LETTER RRA..ORIYA LETTER RHA
    ; between_unicode_range(0x0B5F, 0x0B61, Character) % XID_Continue # Lo   [3] ORIYA LETTER YYA..ORIYA LETTER VOCALIC LL
    ; between_unicode_range(0x0B62, 0x0B63, Character) % XID_Continue # Mn   [2] ORIYA VOWEL SIGN VOCALIC L..ORIYA VOWEL SIGN VOCALIC LL
    ; between_unicode_range(0x0B66, 0x0B6F, Character) % XID_Continue # Nd  [10] ORIYA DIGIT ZERO..ORIYA DIGIT NINE
    ; unicode_character(0x0B71, Character) % XID_Continue # Lo       ORIYA LETTER WA
    ; unicode_character(0x0B82, Character) % XID_Continue # Mn       TAMIL SIGN ANUSVARA
    ; unicode_character(0x0B83, Character) % XID_Continue # Lo       TAMIL SIGN VISARGA
    ; between_unicode_range(0x0B85, 0x0B8A, Character) % XID_Continue # Lo   [6] TAMIL LETTER A..TAMIL LETTER UU
    ; between_unicode_range(0x0B8E, 0x0B90, Character) % XID_Continue # Lo   [3] TAMIL LETTER E..TAMIL LETTER AI
    ; between_unicode_range(0x0B92, 0x0B95, Character) % XID_Continue # Lo   [4] TAMIL LETTER O..TAMIL LETTER KA
    ; between_unicode_range(0x0B99, 0x0B9A, Character) % XID_Continue # Lo   [2] TAMIL LETTER NGA..TAMIL LETTER CA
    ; unicode_character(0x0B9C, Character) % XID_Continue # Lo       TAMIL LETTER JA
    ; between_unicode_range(0x0B9E, 0x0B9F, Character) % XID_Continue # Lo   [2] TAMIL LETTER NYA..TAMIL LETTER TTA
    ; between_unicode_range(0x0BA3, 0x0BA4, Character) % XID_Continue # Lo   [2] TAMIL LETTER NNA..TAMIL LETTER TA
    ; between_unicode_range(0x0BA8, 0x0BAA, Character) % XID_Continue # Lo   [3] TAMIL LETTER NA..TAMIL LETTER PA
    ; between_unicode_range(0x0BAE, 0x0BB9, Character) % XID_Continue # Lo  [12] TAMIL LETTER MA..TAMIL LETTER HA
    ; between_unicode_range(0x0BBE, 0x0BBF, Character) % XID_Continue # Mc   [2] TAMIL VOWEL SIGN AA..TAMIL VOWEL SIGN I
    ; unicode_character(0x0BC0, Character) % XID_Continue # Mn       TAMIL VOWEL SIGN II
    ; between_unicode_range(0x0BC1, 0x0BC2, Character) % XID_Continue # Mc   [2] TAMIL VOWEL SIGN U..TAMIL VOWEL SIGN UU
    ; between_unicode_range(0x0BC6, 0x0BC8, Character) % XID_Continue # Mc   [3] TAMIL VOWEL SIGN E..TAMIL VOWEL SIGN AI
    ; between_unicode_range(0x0BCA, 0x0BCC, Character) % XID_Continue # Mc   [3] TAMIL VOWEL SIGN O..TAMIL VOWEL SIGN AU
    ; unicode_character(0x0BCD, Character) % XID_Continue # Mn       TAMIL SIGN VIRAMA
    ; unicode_character(0x0BD0, Character) % XID_Continue # Lo       TAMIL OM
    ; unicode_character(0x0BD7, Character) % XID_Continue # Mc       TAMIL AU LENGTH MARK
    ; between_unicode_range(0x0BE6, 0x0BEF, Character) % XID_Continue # Nd  [10] TAMIL DIGIT ZERO..TAMIL DIGIT NINE
    ; unicode_character(0x0C00, Character) % XID_Continue # Mn       TELUGU SIGN COMBINING CANDRABINDU ABOVE
    ; between_unicode_range(0x0C01, 0x0C03, Character) % XID_Continue # Mc   [3] TELUGU SIGN CANDRABINDU..TELUGU SIGN VISARGA
    ; unicode_character(0x0C04, Character) % XID_Continue # Mn       TELUGU SIGN COMBINING ANUSVARA ABOVE
    ; between_unicode_range(0x0C05, 0x0C0C, Character) % XID_Continue # Lo   [8] TELUGU LETTER A..TELUGU LETTER VOCALIC L
    ; between_unicode_range(0x0C0E, 0x0C10, Character) % XID_Continue # Lo   [3] TELUGU LETTER E..TELUGU LETTER AI
    ; between_unicode_range(0x0C12, 0x0C28, Character) % XID_Continue # Lo  [23] TELUGU LETTER O..TELUGU LETTER NA
    ; between_unicode_range(0x0C2A, 0x0C39, Character) % XID_Continue # Lo  [16] TELUGU LETTER PA..TELUGU LETTER HA
    ; unicode_character(0x0C3C, Character) % XID_Continue # Mn       TELUGU SIGN NUKTA
    ; unicode_character(0x0C3D, Character) % XID_Continue # Lo       TELUGU SIGN AVAGRAHA
    ; between_unicode_range(0x0C3E, 0x0C40, Character) % XID_Continue # Mn   [3] TELUGU VOWEL SIGN AA..TELUGU VOWEL SIGN II
    ; between_unicode_range(0x0C41, 0x0C44, Character) % XID_Continue # Mc   [4] TELUGU VOWEL SIGN U..TELUGU VOWEL SIGN VOCALIC RR
    ; between_unicode_range(0x0C46, 0x0C48, Character) % XID_Continue # Mn   [3] TELUGU VOWEL SIGN E..TELUGU VOWEL SIGN AI
    ; between_unicode_range(0x0C4A, 0x0C4D, Character) % XID_Continue # Mn   [4] TELUGU VOWEL SIGN O..TELUGU SIGN VIRAMA
    ; between_unicode_range(0x0C55, 0x0C56, Character) % XID_Continue # Mn   [2] TELUGU LENGTH MARK..TELUGU AI LENGTH MARK
    ; between_unicode_range(0x0C58, 0x0C5A, Character) % XID_Continue # Lo   [3] TELUGU LETTER TSA..TELUGU LETTER RRRA
    ; unicode_character(0x0C5D, Character) % XID_Continue # Lo       TELUGU LETTER NAKAARA POLLU
    ; between_unicode_range(0x0C60, 0x0C61, Character) % XID_Continue # Lo   [2] TELUGU LETTER VOCALIC RR..TELUGU LETTER VOCALIC LL
    ; between_unicode_range(0x0C62, 0x0C63, Character) % XID_Continue # Mn   [2] TELUGU VOWEL SIGN VOCALIC L..TELUGU VOWEL SIGN VOCALIC LL
    ; between_unicode_range(0x0C66, 0x0C6F, Character) % XID_Continue # Nd  [10] TELUGU DIGIT ZERO..TELUGU DIGIT NINE
    ; unicode_character(0x0C80, Character) % XID_Continue # Lo       KANNADA SIGN SPACING CANDRABINDU
    ; unicode_character(0x0C81, Character) % XID_Continue # Mn       KANNADA SIGN CANDRABINDU
    ; between_unicode_range(0x0C82, 0x0C83, Character) % XID_Continue # Mc   [2] KANNADA SIGN ANUSVARA..KANNADA SIGN VISARGA
    ; between_unicode_range(0x0C85, 0x0C8C, Character) % XID_Continue # Lo   [8] KANNADA LETTER A..KANNADA LETTER VOCALIC L
    ; between_unicode_range(0x0C8E, 0x0C90, Character) % XID_Continue # Lo   [3] KANNADA LETTER E..KANNADA LETTER AI
    ; between_unicode_range(0x0C92, 0x0CA8, Character) % XID_Continue # Lo  [23] KANNADA LETTER O..KANNADA LETTER NA
    ; between_unicode_range(0x0CAA, 0x0CB3, Character) % XID_Continue # Lo  [10] KANNADA LETTER PA..KANNADA LETTER LLA
    ; between_unicode_range(0x0CB5, 0x0CB9, Character) % XID_Continue # Lo   [5] KANNADA LETTER VA..KANNADA LETTER HA
    ; unicode_character(0x0CBC, Character) % XID_Continue # Mn       KANNADA SIGN NUKTA
    ; unicode_character(0x0CBD, Character) % XID_Continue # Lo       KANNADA SIGN AVAGRAHA
    ; unicode_character(0x0CBE, Character) % XID_Continue # Mc       KANNADA VOWEL SIGN AA
    ; unicode_character(0x0CBF, Character) % XID_Continue # Mn       KANNADA VOWEL SIGN I
    ; between_unicode_range(0x0CC0, 0x0CC4, Character) % XID_Continue # Mc   [5] KANNADA VOWEL SIGN II..KANNADA VOWEL SIGN VOCALIC RR
    ; unicode_character(0x0CC6, Character) % XID_Continue # Mn       KANNADA VOWEL SIGN E
    ; between_unicode_range(0x0CC7, 0x0CC8, Character) % XID_Continue # Mc   [2] KANNADA VOWEL SIGN EE..KANNADA VOWEL SIGN AI
    ; between_unicode_range(0x0CCA, 0x0CCB, Character) % XID_Continue # Mc   [2] KANNADA VOWEL SIGN O..KANNADA VOWEL SIGN OO
    ; between_unicode_range(0x0CCC, 0x0CCD, Character) % XID_Continue # Mn   [2] KANNADA VOWEL SIGN AU..KANNADA SIGN VIRAMA
    ; between_unicode_range(0x0CD5, 0x0CD6, Character) % XID_Continue # Mc   [2] KANNADA LENGTH MARK..KANNADA AI LENGTH MARK
    ; between_unicode_range(0x0CDD, 0x0CDE, Character) % XID_Continue # Lo   [2] KANNADA LETTER NAKAARA POLLU..KANNADA LETTER FA
    ; between_unicode_range(0x0CE0, 0x0CE1, Character) % XID_Continue # Lo   [2] KANNADA LETTER VOCALIC RR..KANNADA LETTER VOCALIC LL
    ; between_unicode_range(0x0CE2, 0x0CE3, Character) % XID_Continue # Mn   [2] KANNADA VOWEL SIGN VOCALIC L..KANNADA VOWEL SIGN VOCALIC LL
    ; between_unicode_range(0x0CE6, 0x0CEF, Character) % XID_Continue # Nd  [10] KANNADA DIGIT ZERO..KANNADA DIGIT NINE
    ; between_unicode_range(0x0CF1, 0x0CF2, Character) % XID_Continue # Lo   [2] KANNADA SIGN JIHVAMULIYA..KANNADA SIGN UPADHMANIYA
    ; unicode_character(0x0CF3, Character) % XID_Continue # Mc       KANNADA SIGN COMBINING ANUSVARA ABOVE RIGHT
    ; between_unicode_range(0x0D00, 0x0D01, Character) % XID_Continue # Mn   [2] MALAYALAM SIGN COMBINING ANUSVARA ABOVE..MALAYALAM SIGN CANDRABINDU
    ; between_unicode_range(0x0D02, 0x0D03, Character) % XID_Continue # Mc   [2] MALAYALAM SIGN ANUSVARA..MALAYALAM SIGN VISARGA
    ; between_unicode_range(0x0D04, 0x0D0C, Character) % XID_Continue # Lo   [9] MALAYALAM LETTER VEDIC ANUSVARA..MALAYALAM LETTER VOCALIC L
    ; between_unicode_range(0x0D0E, 0x0D10, Character) % XID_Continue # Lo   [3] MALAYALAM LETTER E..MALAYALAM LETTER AI
    ; between_unicode_range(0x0D12, 0x0D3A, Character) % XID_Continue # Lo  [41] MALAYALAM LETTER O..MALAYALAM LETTER TTTA
    ; between_unicode_range(0x0D3B, 0x0D3C, Character) % XID_Continue # Mn   [2] MALAYALAM SIGN VERTICAL BAR VIRAMA..MALAYALAM SIGN CIRCULAR VIRAMA
    ; unicode_character(0x0D3D, Character) % XID_Continue # Lo       MALAYALAM SIGN AVAGRAHA
    ; between_unicode_range(0x0D3E, 0x0D40, Character) % XID_Continue # Mc   [3] MALAYALAM VOWEL SIGN AA..MALAYALAM VOWEL SIGN II
    ; between_unicode_range(0x0D41, 0x0D44, Character) % XID_Continue # Mn   [4] MALAYALAM VOWEL SIGN U..MALAYALAM VOWEL SIGN VOCALIC RR
    ; between_unicode_range(0x0D46, 0x0D48, Character) % XID_Continue # Mc   [3] MALAYALAM VOWEL SIGN E..MALAYALAM VOWEL SIGN AI
    ; between_unicode_range(0x0D4A, 0x0D4C, Character) % XID_Continue # Mc   [3] MALAYALAM VOWEL SIGN O..MALAYALAM VOWEL SIGN AU
    ; unicode_character(0x0D4D, Character) % XID_Continue # Mn       MALAYALAM SIGN VIRAMA
    ; unicode_character(0x0D4E, Character) % XID_Continue # Lo       MALAYALAM LETTER DOT REPH
    ; between_unicode_range(0x0D54, 0x0D56, Character) % XID_Continue # Lo   [3] MALAYALAM LETTER CHILLU M..MALAYALAM LETTER CHILLU LLL
    ; unicode_character(0x0D57, Character) % XID_Continue # Mc       MALAYALAM AU LENGTH MARK
    ; between_unicode_range(0x0D5F, 0x0D61, Character) % XID_Continue # Lo   [3] MALAYALAM LETTER ARCHAIC II..MALAYALAM LETTER VOCALIC LL
    ; between_unicode_range(0x0D62, 0x0D63, Character) % XID_Continue # Mn   [2] MALAYALAM VOWEL SIGN VOCALIC L..MALAYALAM VOWEL SIGN VOCALIC LL
    ; between_unicode_range(0x0D66, 0x0D6F, Character) % XID_Continue # Nd  [10] MALAYALAM DIGIT ZERO..MALAYALAM DIGIT NINE
    ; between_unicode_range(0x0D7A, 0x0D7F, Character) % XID_Continue # Lo   [6] MALAYALAM LETTER CHILLU NN..MALAYALAM LETTER CHILLU K
    ; unicode_character(0x0D81, Character) % XID_Continue # Mn       SINHALA SIGN CANDRABINDU
    ; between_unicode_range(0x0D82, 0x0D83, Character) % XID_Continue # Mc   [2] SINHALA SIGN ANUSVARAYA..SINHALA SIGN VISARGAYA
    ; between_unicode_range(0x0D85, 0x0D96, Character) % XID_Continue # Lo  [18] SINHALA LETTER AYANNA..SINHALA LETTER AUYANNA
    ; between_unicode_range(0x0D9A, 0x0DB1, Character) % XID_Continue # Lo  [24] SINHALA LETTER ALPAPRAANA KAYANNA..SINHALA LETTER DANTAJA NAYANNA
    ; between_unicode_range(0x0DB3, 0x0DBB, Character) % XID_Continue # Lo   [9] SINHALA LETTER SANYAKA DAYANNA..SINHALA LETTER RAYANNA
    ; unicode_character(0x0DBD, Character) % XID_Continue # Lo       SINHALA LETTER DANTAJA LAYANNA
    ; between_unicode_range(0x0DC0, 0x0DC6, Character) % XID_Continue # Lo   [7] SINHALA LETTER VAYANNA..SINHALA LETTER FAYANNA
    ; unicode_character(0x0DCA, Character) % XID_Continue # Mn       SINHALA SIGN AL-LAKUNA
    ; between_unicode_range(0x0DCF, 0x0DD1, Character) % XID_Continue # Mc   [3] SINHALA VOWEL SIGN AELA-PILLA..SINHALA VOWEL SIGN DIGA AEDA-PILLA
    ; between_unicode_range(0x0DD2, 0x0DD4, Character) % XID_Continue # Mn   [3] SINHALA VOWEL SIGN KETTI IS-PILLA..SINHALA VOWEL SIGN KETTI PAA-PILLA
    ; unicode_character(0x0DD6, Character) % XID_Continue # Mn       SINHALA VOWEL SIGN DIGA PAA-PILLA
    ; between_unicode_range(0x0DD8, 0x0DDF, Character) % XID_Continue # Mc   [8] SINHALA VOWEL SIGN GAETTA-PILLA..SINHALA VOWEL SIGN GAYANUKITTA
    ; between_unicode_range(0x0DE6, 0x0DEF, Character) % XID_Continue # Nd  [10] SINHALA LITH DIGIT ZERO..SINHALA LITH DIGIT NINE
    ; between_unicode_range(0x0DF2, 0x0DF3, Character) % XID_Continue # Mc   [2] SINHALA VOWEL SIGN DIGA GAETTA-PILLA..SINHALA VOWEL SIGN DIGA GAYANUKITTA
    ; between_unicode_range(0x0E01, 0x0E30, Character) % XID_Continue # Lo  [48] THAI CHARACTER KO KAI..THAI CHARACTER SARA A
    ; unicode_character(0x0E31, Character) % XID_Continue # Mn       THAI CHARACTER MAI HAN-AKAT
    ; between_unicode_range(0x0E32, 0x0E33, Character) % XID_Continue # Lo   [2] THAI CHARACTER SARA AA..THAI CHARACTER SARA AM
    ; between_unicode_range(0x0E34, 0x0E3A, Character) % XID_Continue # Mn   [7] THAI CHARACTER SARA I..THAI CHARACTER PHINTHU
    ; between_unicode_range(0x0E40, 0x0E45, Character) % XID_Continue # Lo   [6] THAI CHARACTER SARA E..THAI CHARACTER LAKKHANGYAO
    ; unicode_character(0x0E46, Character) % XID_Continue # Lm       THAI CHARACTER MAIYAMOK
    ; between_unicode_range(0x0E47, 0x0E4E, Character) % XID_Continue # Mn   [8] THAI CHARACTER MAITAIKHU..THAI CHARACTER YAMAKKAN
    ; between_unicode_range(0x0E50, 0x0E59, Character) % XID_Continue # Nd  [10] THAI DIGIT ZERO..THAI DIGIT NINE
    ; between_unicode_range(0x0E81, 0x0E82, Character) % XID_Continue # Lo   [2] LAO LETTER KO..LAO LETTER KHO SUNG
    ; unicode_character(0x0E84, Character) % XID_Continue # Lo       LAO LETTER KHO TAM
    ; between_unicode_range(0x0E86, 0x0E8A, Character) % XID_Continue # Lo   [5] LAO LETTER PALI GHA..LAO LETTER SO TAM
    ; between_unicode_range(0x0E8C, 0x0EA3, Character) % XID_Continue # Lo  [24] LAO LETTER PALI JHA..LAO LETTER LO LING
    ; unicode_character(0x0EA5, Character) % XID_Continue # Lo       LAO LETTER LO LOOT
    ; between_unicode_range(0x0EA7, 0x0EB0, Character) % XID_Continue # Lo  [10] LAO LETTER WO..LAO VOWEL SIGN A
    ; unicode_character(0x0EB1, Character) % XID_Continue # Mn       LAO VOWEL SIGN MAI KAN
    ; between_unicode_range(0x0EB2, 0x0EB3, Character) % XID_Continue # Lo   [2] LAO VOWEL SIGN AA..LAO VOWEL SIGN AM
    ; between_unicode_range(0x0EB4, 0x0EBC, Character) % XID_Continue # Mn   [9] LAO VOWEL SIGN I..LAO SEMIVOWEL SIGN LO
    ; unicode_character(0x0EBD, Character) % XID_Continue # Lo       LAO SEMIVOWEL SIGN NYO
    ; between_unicode_range(0x0EC0, 0x0EC4, Character) % XID_Continue # Lo   [5] LAO VOWEL SIGN E..LAO VOWEL SIGN AI
    ; unicode_character(0x0EC6, Character) % XID_Continue # Lm       LAO KO LA
    ; between_unicode_range(0x0EC8, 0x0ECE, Character) % XID_Continue # Mn   [7] LAO TONE MAI EK..LAO YAMAKKAN
    ; between_unicode_range(0x0ED0, 0x0ED9, Character) % XID_Continue # Nd  [10] LAO DIGIT ZERO..LAO DIGIT NINE
    ; between_unicode_range(0x0EDC, 0x0EDF, Character) % XID_Continue # Lo   [4] LAO HO NO..LAO LETTER KHMU NYO
    ; unicode_character(0x0F00, Character) % XID_Continue # Lo       TIBETAN SYLLABLE OM
    ; between_unicode_range(0x0F18, 0x0F19, Character) % XID_Continue # Mn   [2] TIBETAN ASTROLOGICAL SIGN -KHYUD PA..TIBETAN ASTROLOGICAL SIGN SDONG TSHUGS
    ; between_unicode_range(0x0F20, 0x0F29, Character) % XID_Continue # Nd  [10] TIBETAN DIGIT ZERO..TIBETAN DIGIT NINE
    ; unicode_character(0x0F35, Character) % XID_Continue # Mn       TIBETAN MARK NGAS BZUNG NYI ZLA
    ; unicode_character(0x0F37, Character) % XID_Continue # Mn       TIBETAN MARK NGAS BZUNG SGOR RTAGS
    ; unicode_character(0x0F39, Character) % XID_Continue # Mn       TIBETAN MARK TSA -PHRU
    ; between_unicode_range(0x0F3E, 0x0F3F, Character) % XID_Continue # Mc   [2] TIBETAN SIGN YAR TSHES..TIBETAN SIGN MAR TSHES
    ; between_unicode_range(0x0F40, 0x0F47, Character) % XID_Continue # Lo   [8] TIBETAN LETTER KA..TIBETAN LETTER JA
    ; between_unicode_range(0x0F49, 0x0F6C, Character) % XID_Continue # Lo  [36] TIBETAN LETTER NYA..TIBETAN LETTER RRA
    ; between_unicode_range(0x0F71, 0x0F7E, Character) % XID_Continue # Mn  [14] TIBETAN VOWEL SIGN AA..TIBETAN SIGN RJES SU NGA RO
    ; unicode_character(0x0F7F, Character) % XID_Continue # Mc       TIBETAN SIGN RNAM BCAD
    ; between_unicode_range(0x0F80, 0x0F84, Character) % XID_Continue # Mn   [5] TIBETAN VOWEL SIGN REVERSED I..TIBETAN MARK HALANTA
    ; between_unicode_range(0x0F86, 0x0F87, Character) % XID_Continue # Mn   [2] TIBETAN SIGN LCI RTAGS..TIBETAN SIGN YANG RTAGS
    ; between_unicode_range(0x0F88, 0x0F8C, Character) % XID_Continue # Lo   [5] TIBETAN SIGN LCE TSA CAN..TIBETAN SIGN INVERTED MCHU CAN
    ; between_unicode_range(0x0F8D, 0x0F97, Character) % XID_Continue # Mn  [11] TIBETAN SUBJOINED SIGN LCE TSA CAN..TIBETAN SUBJOINED LETTER JA
    ; between_unicode_range(0x0F99, 0x0FBC, Character) % XID_Continue # Mn  [36] TIBETAN SUBJOINED LETTER NYA..TIBETAN SUBJOINED LETTER FIXED-FORM RA
    ; unicode_character(0x0FC6, Character) % XID_Continue # Mn       TIBETAN SYMBOL PADMA GDAN
    ; between_unicode_range(0x1000, 0x102A, Character) % XID_Continue # Lo  [43] MYANMAR LETTER KA..MYANMAR LETTER AU
    ; between_unicode_range(0x102B, 0x102C, Character) % XID_Continue # Mc   [2] MYANMAR VOWEL SIGN TALL AA..MYANMAR VOWEL SIGN AA
    ; between_unicode_range(0x102D, 0x1030, Character) % XID_Continue # Mn   [4] MYANMAR VOWEL SIGN I..MYANMAR VOWEL SIGN UU
    ; unicode_character(0x1031, Character) % XID_Continue # Mc       MYANMAR VOWEL SIGN E
    ; between_unicode_range(0x1032, 0x1037, Character) % XID_Continue # Mn   [6] MYANMAR VOWEL SIGN AI..MYANMAR SIGN DOT BELOW
    ; unicode_character(0x1038, Character) % XID_Continue # Mc       MYANMAR SIGN VISARGA
    ; between_unicode_range(0x1039, 0x103A, Character) % XID_Continue # Mn   [2] MYANMAR SIGN VIRAMA..MYANMAR SIGN ASAT
    ; between_unicode_range(0x103B, 0x103C, Character) % XID_Continue # Mc   [2] MYANMAR CONSONANT SIGN MEDIAL YA..MYANMAR CONSONANT SIGN MEDIAL RA
    ; between_unicode_range(0x103D, 0x103E, Character) % XID_Continue # Mn   [2] MYANMAR CONSONANT SIGN MEDIAL WA..MYANMAR CONSONANT SIGN MEDIAL HA
    ; unicode_character(0x103F, Character) % XID_Continue # Lo       MYANMAR LETTER GREAT SA
    ; between_unicode_range(0x1040, 0x1049, Character) % XID_Continue # Nd  [10] MYANMAR DIGIT ZERO..MYANMAR DIGIT NINE
    ; between_unicode_range(0x1050, 0x1055, Character) % XID_Continue # Lo   [6] MYANMAR LETTER SHA..MYANMAR LETTER VOCALIC LL
    ; between_unicode_range(0x1056, 0x1057, Character) % XID_Continue # Mc   [2] MYANMAR VOWEL SIGN VOCALIC R..MYANMAR VOWEL SIGN VOCALIC RR
    ; between_unicode_range(0x1058, 0x1059, Character) % XID_Continue # Mn   [2] MYANMAR VOWEL SIGN VOCALIC L..MYANMAR VOWEL SIGN VOCALIC LL
    ; between_unicode_range(0x105A, 0x105D, Character) % XID_Continue # Lo   [4] MYANMAR LETTER MON NGA..MYANMAR LETTER MON BBE
    ; between_unicode_range(0x105E, 0x1060, Character) % XID_Continue # Mn   [3] MYANMAR CONSONANT SIGN MON MEDIAL NA..MYANMAR CONSONANT SIGN MON MEDIAL LA
    ; unicode_character(0x1061, Character) % XID_Continue # Lo       MYANMAR LETTER SGAW KAREN SHA
    ; between_unicode_range(0x1062, 0x1064, Character) % XID_Continue # Mc   [3] MYANMAR VOWEL SIGN SGAW KAREN EU..MYANMAR TONE MARK SGAW KAREN KE PHO
    ; between_unicode_range(0x1065, 0x1066, Character) % XID_Continue # Lo   [2] MYANMAR LETTER WESTERN PWO KAREN THA..MYANMAR LETTER WESTERN PWO KAREN PWA
    ; between_unicode_range(0x1067, 0x106D, Character) % XID_Continue # Mc   [7] MYANMAR VOWEL SIGN WESTERN PWO KAREN EU..MYANMAR SIGN WESTERN PWO KAREN TONE-5
    ; between_unicode_range(0x106E, 0x1070, Character) % XID_Continue # Lo   [3] MYANMAR LETTER EASTERN PWO KAREN NNA..MYANMAR LETTER EASTERN PWO KAREN GHWA
    ; between_unicode_range(0x1071, 0x1074, Character) % XID_Continue # Mn   [4] MYANMAR VOWEL SIGN GEBA KAREN I..MYANMAR VOWEL SIGN KAYAH EE
    ; between_unicode_range(0x1075, 0x1081, Character) % XID_Continue # Lo  [13] MYANMAR LETTER SHAN KA..MYANMAR LETTER SHAN HA
    ; unicode_character(0x1082, Character) % XID_Continue # Mn       MYANMAR CONSONANT SIGN SHAN MEDIAL WA
    ; between_unicode_range(0x1083, 0x1084, Character) % XID_Continue # Mc   [2] MYANMAR VOWEL SIGN SHAN AA..MYANMAR VOWEL SIGN SHAN E
    ; between_unicode_range(0x1085, 0x1086, Character) % XID_Continue # Mn   [2] MYANMAR VOWEL SIGN SHAN E ABOVE..MYANMAR VOWEL SIGN SHAN FINAL Y
    ; between_unicode_range(0x1087, 0x108C, Character) % XID_Continue # Mc   [6] MYANMAR SIGN SHAN TONE-2..MYANMAR SIGN SHAN COUNCIL TONE-3
    ; unicode_character(0x108D, Character) % XID_Continue # Mn       MYANMAR SIGN SHAN COUNCIL EMPHATIC TONE
    ; unicode_character(0x108E, Character) % XID_Continue # Lo       MYANMAR LETTER RUMAI PALAUNG FA
    ; unicode_character(0x108F, Character) % XID_Continue # Mc       MYANMAR SIGN RUMAI PALAUNG TONE-5
    ; between_unicode_range(0x1090, 0x1099, Character) % XID_Continue # Nd  [10] MYANMAR SHAN DIGIT ZERO..MYANMAR SHAN DIGIT NINE
    ; between_unicode_range(0x109A, 0x109C, Character) % XID_Continue # Mc   [3] MYANMAR SIGN KHAMTI TONE-1..MYANMAR VOWEL SIGN AITON A
    ; unicode_character(0x109D, Character) % XID_Continue # Mn       MYANMAR VOWEL SIGN AITON AI
    ; between_unicode_range(0x10A0, 0x10C5, Character) % XID_Continue # L&  [38] GEORGIAN CAPITAL LETTER AN..GEORGIAN CAPITAL LETTER HOE
    ; unicode_character(0x10C7, Character) % XID_Continue # L&       GEORGIAN CAPITAL LETTER YN
    ; unicode_character(0x10CD, Character) % XID_Continue # L&       GEORGIAN CAPITAL LETTER AEN
    ; between_unicode_range(0x10D0, 0x10FA, Character) % XID_Continue # L&  [43] GEORGIAN LETTER AN..GEORGIAN LETTER AIN
    ; unicode_character(0x10FC, Character) % XID_Continue # Lm       MODIFIER LETTER GEORGIAN NAR
    ; between_unicode_range(0x10FD, 0x10FF, Character) % XID_Continue # L&   [3] GEORGIAN LETTER AEN..GEORGIAN LETTER LABIAL SIGN
    ; between_unicode_range(0x1100, 0x1248, Character) % XID_Continue # Lo [329] HANGUL CHOSEONG KIYEOK..ETHIOPIC SYLLABLE QWA
    ; between_unicode_range(0x124A, 0x124D, Character) % XID_Continue # Lo   [4] ETHIOPIC SYLLABLE QWI..ETHIOPIC SYLLABLE QWE
    ; between_unicode_range(0x1250, 0x1256, Character) % XID_Continue # Lo   [7] ETHIOPIC SYLLABLE QHA..ETHIOPIC SYLLABLE QHO
    ; unicode_character(0x1258, Character) % XID_Continue # Lo       ETHIOPIC SYLLABLE QHWA
    ; between_unicode_range(0x125A, 0x125D, Character) % XID_Continue # Lo   [4] ETHIOPIC SYLLABLE QHWI..ETHIOPIC SYLLABLE QHWE
    ; between_unicode_range(0x1260, 0x1288, Character) % XID_Continue # Lo  [41] ETHIOPIC SYLLABLE BA..ETHIOPIC SYLLABLE XWA
    ; between_unicode_range(0x128A, 0x128D, Character) % XID_Continue # Lo   [4] ETHIOPIC SYLLABLE XWI..ETHIOPIC SYLLABLE XWE
    ; between_unicode_range(0x1290, 0x12B0, Character) % XID_Continue # Lo  [33] ETHIOPIC SYLLABLE NA..ETHIOPIC SYLLABLE KWA
    ; between_unicode_range(0x12B2, 0x12B5, Character) % XID_Continue # Lo   [4] ETHIOPIC SYLLABLE KWI..ETHIOPIC SYLLABLE KWE
    ; between_unicode_range(0x12B8, 0x12BE, Character) % XID_Continue # Lo   [7] ETHIOPIC SYLLABLE KXA..ETHIOPIC SYLLABLE KXO
    ; unicode_character(0x12C0, Character) % XID_Continue # Lo       ETHIOPIC SYLLABLE KXWA
    ; between_unicode_range(0x12C2, 0x12C5, Character) % XID_Continue # Lo   [4] ETHIOPIC SYLLABLE KXWI..ETHIOPIC SYLLABLE KXWE
    ; between_unicode_range(0x12C8, 0x12D6, Character) % XID_Continue # Lo  [15] ETHIOPIC SYLLABLE WA..ETHIOPIC SYLLABLE PHARYNGEAL O
    ; between_unicode_range(0x12D8, 0x1310, Character) % XID_Continue # Lo  [57] ETHIOPIC SYLLABLE ZA..ETHIOPIC SYLLABLE GWA
    ; between_unicode_range(0x1312, 0x1315, Character) % XID_Continue # Lo   [4] ETHIOPIC SYLLABLE GWI..ETHIOPIC SYLLABLE GWE
    ; between_unicode_range(0x1318, 0x135A, Character) % XID_Continue # Lo  [67] ETHIOPIC SYLLABLE GGA..ETHIOPIC SYLLABLE FYA
    ; between_unicode_range(0x135D, 0x135F, Character) % XID_Continue # Mn   [3] ETHIOPIC COMBINING GEMINATION AND VOWEL LENGTH MARK..ETHIOPIC COMBINING GEMINATION MARK
    ; between_unicode_range(0x1369, 0x1371, Character) % XID_Continue # No   [9] ETHIOPIC DIGIT ONE..ETHIOPIC DIGIT NINE
    ; between_unicode_range(0x1380, 0x138F, Character) % XID_Continue # Lo  [16] ETHIOPIC SYLLABLE SEBATBEIT MWA..ETHIOPIC SYLLABLE PWE
    ; between_unicode_range(0x13A0, 0x13F5, Character) % XID_Continue # L&  [86] CHEROKEE LETTER A..CHEROKEE LETTER MV
    ; between_unicode_range(0x13F8, 0x13FD, Character) % XID_Continue # L&   [6] CHEROKEE SMALL LETTER YE..CHEROKEE SMALL LETTER MV
    ; between_unicode_range(0x1401, 0x166C, Character) % XID_Continue # Lo [620] CANADIAN SYLLABICS E..CANADIAN SYLLABICS CARRIER TTSA
    ; between_unicode_range(0x166F, 0x167F, Character) % XID_Continue # Lo  [17] CANADIAN SYLLABICS QAI..CANADIAN SYLLABICS BLACKFOOT W
    ; between_unicode_range(0x1681, 0x169A, Character) % XID_Continue # Lo  [26] OGHAM LETTER BEITH..OGHAM LETTER PEITH
    ; between_unicode_range(0x16A0, 0x16EA, Character) % XID_Continue # Lo  [75] RUNIC LETTER FEHU FEOH FE F..RUNIC LETTER X
    ; between_unicode_range(0x16EE, 0x16F0, Character) % XID_Continue # Nl   [3] RUNIC ARLAUG SYMBOL..RUNIC BELGTHOR SYMBOL
    ; between_unicode_range(0x16F1, 0x16F8, Character) % XID_Continue # Lo   [8] RUNIC LETTER K..RUNIC LETTER FRANKS CASKET AESC
    ; between_unicode_range(0x1700, 0x1711, Character) % XID_Continue # Lo  [18] TAGALOG LETTER A..TAGALOG LETTER HA
    ; between_unicode_range(0x1712, 0x1714, Character) % XID_Continue # Mn   [3] TAGALOG VOWEL SIGN I..TAGALOG SIGN VIRAMA
    ; unicode_character(0x1715, Character) % XID_Continue # Mc       TAGALOG SIGN PAMUDPOD
    ; between_unicode_range(0x171F, 0x1731, Character) % XID_Continue # Lo  [19] TAGALOG LETTER ARCHAIC RA..HANUNOO LETTER HA
    ; between_unicode_range(0x1732, 0x1733, Character) % XID_Continue # Mn   [2] HANUNOO VOWEL SIGN I..HANUNOO VOWEL SIGN U
    ; unicode_character(0x1734, Character) % XID_Continue # Mc       HANUNOO SIGN PAMUDPOD
    ; between_unicode_range(0x1740, 0x1751, Character) % XID_Continue # Lo  [18] BUHID LETTER A..BUHID LETTER HA
    ; between_unicode_range(0x1752, 0x1753, Character) % XID_Continue # Mn   [2] BUHID VOWEL SIGN I..BUHID VOWEL SIGN U
    ; between_unicode_range(0x1760, 0x176C, Character) % XID_Continue # Lo  [13] TAGBANWA LETTER A..TAGBANWA LETTER YA
    ; between_unicode_range(0x176E, 0x1770, Character) % XID_Continue # Lo   [3] TAGBANWA LETTER LA..TAGBANWA LETTER SA
    ; between_unicode_range(0x1772, 0x1773, Character) % XID_Continue # Mn   [2] TAGBANWA VOWEL SIGN I..TAGBANWA VOWEL SIGN U
    ; between_unicode_range(0x1780, 0x17B3, Character) % XID_Continue # Lo  [52] KHMER LETTER KA..KHMER INDEPENDENT VOWEL QAU
    ; between_unicode_range(0x17B4, 0x17B5, Character) % XID_Continue # Mn   [2] KHMER VOWEL INHERENT AQ..KHMER VOWEL INHERENT AA
    ; unicode_character(0x17B6, Character) % XID_Continue # Mc       KHMER VOWEL SIGN AA
    ; between_unicode_range(0x17B7, 0x17BD, Character) % XID_Continue # Mn   [7] KHMER VOWEL SIGN I..KHMER VOWEL SIGN UA
    ; between_unicode_range(0x17BE, 0x17C5, Character) % XID_Continue # Mc   [8] KHMER VOWEL SIGN OE..KHMER VOWEL SIGN AU
    ; unicode_character(0x17C6, Character) % XID_Continue # Mn       KHMER SIGN NIKAHIT
    ; between_unicode_range(0x17C7, 0x17C8, Character) % XID_Continue # Mc   [2] KHMER SIGN REAHMUK..KHMER SIGN YUUKALEAPINTU
    ; between_unicode_range(0x17C9, 0x17D3, Character) % XID_Continue # Mn  [11] KHMER SIGN MUUSIKATOAN..KHMER SIGN BATHAMASAT
    ; unicode_character(0x17D7, Character) % XID_Continue # Lm       KHMER SIGN LEK TOO
    ; unicode_character(0x17DC, Character) % XID_Continue # Lo       KHMER SIGN AVAKRAHASANYA
    ; unicode_character(0x17DD, Character) % XID_Continue # Mn       KHMER SIGN ATTHACAN
    ; between_unicode_range(0x17E0, 0x17E9, Character) % XID_Continue # Nd  [10] KHMER DIGIT ZERO..KHMER DIGIT NINE
    ; between_unicode_range(0x180B, 0x180D, Character) % XID_Continue # Mn   [3] MONGOLIAN FREE VARIATION SELECTOR ONE..MONGOLIAN FREE VARIATION SELECTOR THREE
    ; unicode_character(0x180F, Character) % XID_Continue # Mn       MONGOLIAN FREE VARIATION SELECTOR FOUR
    ; between_unicode_range(0x1810, 0x1819, Character) % XID_Continue # Nd  [10] MONGOLIAN DIGIT ZERO..MONGOLIAN DIGIT NINE
    ; between_unicode_range(0x1820, 0x1842, Character) % XID_Continue # Lo  [35] MONGOLIAN LETTER A..MONGOLIAN LETTER CHI
    ; unicode_character(0x1843, Character) % XID_Continue # Lm       MONGOLIAN LETTER TODO LONG VOWEL SIGN
    ; between_unicode_range(0x1844, 0x1878, Character) % XID_Continue # Lo  [53] MONGOLIAN LETTER TODO E..MONGOLIAN LETTER CHA WITH TWO DOTS
    ; between_unicode_range(0x1880, 0x1884, Character) % XID_Continue # Lo   [5] MONGOLIAN LETTER ALI GALI ANUSVARA ONE..MONGOLIAN LETTER ALI GALI INVERTED UBADAMA
    ; between_unicode_range(0x1885, 0x1886, Character) % XID_Continue # Mn   [2] MONGOLIAN LETTER ALI GALI BALUDA..MONGOLIAN LETTER ALI GALI THREE BALUDA
    ; between_unicode_range(0x1887, 0x18A8, Character) % XID_Continue # Lo  [34] MONGOLIAN LETTER ALI GALI A..MONGOLIAN LETTER MANCHU ALI GALI BHA
    ; unicode_character(0x18A9, Character) % XID_Continue # Mn       MONGOLIAN LETTER ALI GALI DAGALGA
    ; unicode_character(0x18AA, Character) % XID_Continue # Lo       MONGOLIAN LETTER MANCHU ALI GALI LHA
    ; between_unicode_range(0x18B0, 0x18F5, Character) % XID_Continue # Lo  [70] CANADIAN SYLLABICS OY..CANADIAN SYLLABICS CARRIER DENTAL S
    ; between_unicode_range(0x1900, 0x191E, Character) % XID_Continue # Lo  [31] LIMBU VOWEL-CARRIER LETTER..LIMBU LETTER TRA
    ; between_unicode_range(0x1920, 0x1922, Character) % XID_Continue # Mn   [3] LIMBU VOWEL SIGN A..LIMBU VOWEL SIGN U
    ; between_unicode_range(0x1923, 0x1926, Character) % XID_Continue # Mc   [4] LIMBU VOWEL SIGN EE..LIMBU VOWEL SIGN AU
    ; between_unicode_range(0x1927, 0x1928, Character) % XID_Continue # Mn   [2] LIMBU VOWEL SIGN E..LIMBU VOWEL SIGN O
    ; between_unicode_range(0x1929, 0x192B, Character) % XID_Continue # Mc   [3] LIMBU SUBJOINED LETTER YA..LIMBU SUBJOINED LETTER WA
    ; between_unicode_range(0x1930, 0x1931, Character) % XID_Continue # Mc   [2] LIMBU SMALL LETTER KA..LIMBU SMALL LETTER NGA
    ; unicode_character(0x1932, Character) % XID_Continue # Mn       LIMBU SMALL LETTER ANUSVARA
    ; between_unicode_range(0x1933, 0x1938, Character) % XID_Continue # Mc   [6] LIMBU SMALL LETTER TA..LIMBU SMALL LETTER LA
    ; between_unicode_range(0x1939, 0x193B, Character) % XID_Continue # Mn   [3] LIMBU SIGN MUKPHRENG..LIMBU SIGN SA-I
    ; between_unicode_range(0x1946, 0x194F, Character) % XID_Continue # Nd  [10] LIMBU DIGIT ZERO..LIMBU DIGIT NINE
    ; between_unicode_range(0x1950, 0x196D, Character) % XID_Continue # Lo  [30] TAI LE LETTER KA..TAI LE LETTER AI
    ; between_unicode_range(0x1970, 0x1974, Character) % XID_Continue # Lo   [5] TAI LE LETTER TONE-2..TAI LE LETTER TONE-6
    ; between_unicode_range(0x1980, 0x19AB, Character) % XID_Continue # Lo  [44] NEW TAI LUE LETTER HIGH QA..NEW TAI LUE LETTER LOW SUA
    ; between_unicode_range(0x19B0, 0x19C9, Character) % XID_Continue # Lo  [26] NEW TAI LUE VOWEL SIGN VOWEL SHORTENER..NEW TAI LUE TONE MARK-2
    ; between_unicode_range(0x19D0, 0x19D9, Character) % XID_Continue # Nd  [10] NEW TAI LUE DIGIT ZERO..NEW TAI LUE DIGIT NINE
    ; unicode_character(0x19DA, Character) % XID_Continue # No       NEW TAI LUE THAM DIGIT ONE
    ; between_unicode_range(0x1A00, 0x1A16, Character) % XID_Continue # Lo  [23] BUGINESE LETTER KA..BUGINESE LETTER HA
    ; between_unicode_range(0x1A17, 0x1A18, Character) % XID_Continue # Mn   [2] BUGINESE VOWEL SIGN I..BUGINESE VOWEL SIGN U
    ; between_unicode_range(0x1A19, 0x1A1A, Character) % XID_Continue # Mc   [2] BUGINESE VOWEL SIGN E..BUGINESE VOWEL SIGN O
    ; unicode_character(0x1A1B, Character) % XID_Continue # Mn       BUGINESE VOWEL SIGN AE
    ; between_unicode_range(0x1A20, 0x1A54, Character) % XID_Continue # Lo  [53] TAI THAM LETTER HIGH KA..TAI THAM LETTER GREAT SA
    ; unicode_character(0x1A55, Character) % XID_Continue # Mc       TAI THAM CONSONANT SIGN MEDIAL RA
    ; unicode_character(0x1A56, Character) % XID_Continue # Mn       TAI THAM CONSONANT SIGN MEDIAL LA
    ; unicode_character(0x1A57, Character) % XID_Continue # Mc       TAI THAM CONSONANT SIGN LA TANG LAI
    ; between_unicode_range(0x1A58, 0x1A5E, Character) % XID_Continue # Mn   [7] TAI THAM SIGN MAI KANG LAI..TAI THAM CONSONANT SIGN SA
    ; unicode_character(0x1A60, Character) % XID_Continue # Mn       TAI THAM SIGN SAKOT
    ; unicode_character(0x1A61, Character) % XID_Continue # Mc       TAI THAM VOWEL SIGN A
    ; unicode_character(0x1A62, Character) % XID_Continue # Mn       TAI THAM VOWEL SIGN MAI SAT
    ; between_unicode_range(0x1A63, 0x1A64, Character) % XID_Continue # Mc   [2] TAI THAM VOWEL SIGN AA..TAI THAM VOWEL SIGN TALL AA
    ; between_unicode_range(0x1A65, 0x1A6C, Character) % XID_Continue # Mn   [8] TAI THAM VOWEL SIGN I..TAI THAM VOWEL SIGN OA BELOW
    ; between_unicode_range(0x1A6D, 0x1A72, Character) % XID_Continue # Mc   [6] TAI THAM VOWEL SIGN OY..TAI THAM VOWEL SIGN THAM AI
    ; between_unicode_range(0x1A73, 0x1A7C, Character) % XID_Continue # Mn  [10] TAI THAM VOWEL SIGN OA ABOVE..TAI THAM SIGN KHUEN-LUE KARAN
    ; unicode_character(0x1A7F, Character) % XID_Continue # Mn       TAI THAM COMBINING CRYPTOGRAMMIC DOT
    ; between_unicode_range(0x1A80, 0x1A89, Character) % XID_Continue # Nd  [10] TAI THAM HORA DIGIT ZERO..TAI THAM HORA DIGIT NINE
    ; between_unicode_range(0x1A90, 0x1A99, Character) % XID_Continue # Nd  [10] TAI THAM THAM DIGIT ZERO..TAI THAM THAM DIGIT NINE
    ; unicode_character(0x1AA7, Character) % XID_Continue # Lm       TAI THAM SIGN MAI YAMOK
    ; between_unicode_range(0x1AB0, 0x1ABD, Character) % XID_Continue # Mn  [14] COMBINING DOUBLED CIRCUMFLEX ACCENT..COMBINING PARENTHESES BELOW
    ; between_unicode_range(0x1ABF, 0x1ACE, Character) % XID_Continue # Mn  [16] COMBINING LATIN SMALL LETTER W BELOW..COMBINING LATIN SMALL LETTER INSULAR T
    ; between_unicode_range(0x1B00, 0x1B03, Character) % XID_Continue # Mn   [4] BALINESE SIGN ULU RICEM..BALINESE SIGN SURANG
    ; unicode_character(0x1B04, Character) % XID_Continue # Mc       BALINESE SIGN BISAH
    ; between_unicode_range(0x1B05, 0x1B33, Character) % XID_Continue # Lo  [47] BALINESE LETTER AKARA..BALINESE LETTER HA
    ; unicode_character(0x1B34, Character) % XID_Continue # Mn       BALINESE SIGN REREKAN
    ; unicode_character(0x1B35, Character) % XID_Continue # Mc       BALINESE VOWEL SIGN TEDUNG
    ; between_unicode_range(0x1B36, 0x1B3A, Character) % XID_Continue # Mn   [5] BALINESE VOWEL SIGN ULU..BALINESE VOWEL SIGN RA REPA
    ; unicode_character(0x1B3B, Character) % XID_Continue # Mc       BALINESE VOWEL SIGN RA REPA TEDUNG
    ; unicode_character(0x1B3C, Character) % XID_Continue # Mn       BALINESE VOWEL SIGN LA LENGA
    ; between_unicode_range(0x1B3D, 0x1B41, Character) % XID_Continue # Mc   [5] BALINESE VOWEL SIGN LA LENGA TEDUNG..BALINESE VOWEL SIGN TALING REPA TEDUNG
    ; unicode_character(0x1B42, Character) % XID_Continue # Mn       BALINESE VOWEL SIGN PEPET
    ; between_unicode_range(0x1B43, 0x1B44, Character) % XID_Continue # Mc   [2] BALINESE VOWEL SIGN PEPET TEDUNG..BALINESE ADEG ADEG
    ; between_unicode_range(0x1B45, 0x1B4C, Character) % XID_Continue # Lo   [8] BALINESE LETTER KAF SASAK..BALINESE LETTER ARCHAIC JNYA
    ; between_unicode_range(0x1B50, 0x1B59, Character) % XID_Continue # Nd  [10] BALINESE DIGIT ZERO..BALINESE DIGIT NINE
    ; between_unicode_range(0x1B6B, 0x1B73, Character) % XID_Continue # Mn   [9] BALINESE MUSICAL SYMBOL COMBINING TEGEH..BALINESE MUSICAL SYMBOL COMBINING GONG
    ; between_unicode_range(0x1B80, 0x1B81, Character) % XID_Continue # Mn   [2] SUNDANESE SIGN PANYECEK..SUNDANESE SIGN PANGLAYAR
    ; unicode_character(0x1B82, Character) % XID_Continue # Mc       SUNDANESE SIGN PANGWISAD
    ; between_unicode_range(0x1B83, 0x1BA0, Character) % XID_Continue # Lo  [30] SUNDANESE LETTER A..SUNDANESE LETTER HA
    ; unicode_character(0x1BA1, Character) % XID_Continue # Mc       SUNDANESE CONSONANT SIGN PAMINGKAL
    ; between_unicode_range(0x1BA2, 0x1BA5, Character) % XID_Continue # Mn   [4] SUNDANESE CONSONANT SIGN PANYAKRA..SUNDANESE VOWEL SIGN PANYUKU
    ; between_unicode_range(0x1BA6, 0x1BA7, Character) % XID_Continue # Mc   [2] SUNDANESE VOWEL SIGN PANAELAENG..SUNDANESE VOWEL SIGN PANOLONG
    ; between_unicode_range(0x1BA8, 0x1BA9, Character) % XID_Continue # Mn   [2] SUNDANESE VOWEL SIGN PAMEPET..SUNDANESE VOWEL SIGN PANEULEUNG
    ; unicode_character(0x1BAA, Character) % XID_Continue # Mc       SUNDANESE SIGN PAMAAEH
    ; between_unicode_range(0x1BAB, 0x1BAD, Character) % XID_Continue # Mn   [3] SUNDANESE SIGN VIRAMA..SUNDANESE CONSONANT SIGN PASANGAN WA
    ; between_unicode_range(0x1BAE, 0x1BAF, Character) % XID_Continue # Lo   [2] SUNDANESE LETTER KHA..SUNDANESE LETTER SYA
    ; between_unicode_range(0x1BB0, 0x1BB9, Character) % XID_Continue # Nd  [10] SUNDANESE DIGIT ZERO..SUNDANESE DIGIT NINE
    ; between_unicode_range(0x1BBA, 0x1BE5, Character) % XID_Continue # Lo  [44] SUNDANESE AVAGRAHA..BATAK LETTER U
    ; unicode_character(0x1BE6, Character) % XID_Continue # Mn       BATAK SIGN TOMPI
    ; unicode_character(0x1BE7, Character) % XID_Continue # Mc       BATAK VOWEL SIGN E
    ; between_unicode_range(0x1BE8, 0x1BE9, Character) % XID_Continue # Mn   [2] BATAK VOWEL SIGN PAKPAK E..BATAK VOWEL SIGN EE
    ; between_unicode_range(0x1BEA, 0x1BEC, Character) % XID_Continue # Mc   [3] BATAK VOWEL SIGN I..BATAK VOWEL SIGN O
    ; unicode_character(0x1BED, Character) % XID_Continue # Mn       BATAK VOWEL SIGN KARO O
    ; unicode_character(0x1BEE, Character) % XID_Continue # Mc       BATAK VOWEL SIGN U
    ; between_unicode_range(0x1BEF, 0x1BF1, Character) % XID_Continue # Mn   [3] BATAK VOWEL SIGN U FOR SIMALUNGUN SA..BATAK CONSONANT SIGN H
    ; between_unicode_range(0x1BF2, 0x1BF3, Character) % XID_Continue # Mc   [2] BATAK PANGOLAT..BATAK PANONGONAN
    ; between_unicode_range(0x1C00, 0x1C23, Character) % XID_Continue # Lo  [36] LEPCHA LETTER KA..LEPCHA LETTER A
    ; between_unicode_range(0x1C24, 0x1C2B, Character) % XID_Continue # Mc   [8] LEPCHA SUBJOINED LETTER YA..LEPCHA VOWEL SIGN UU
    ; between_unicode_range(0x1C2C, 0x1C33, Character) % XID_Continue # Mn   [8] LEPCHA VOWEL SIGN E..LEPCHA CONSONANT SIGN T
    ; between_unicode_range(0x1C34, 0x1C35, Character) % XID_Continue # Mc   [2] LEPCHA CONSONANT SIGN NYIN-DO..LEPCHA CONSONANT SIGN KANG
    ; between_unicode_range(0x1C36, 0x1C37, Character) % XID_Continue # Mn   [2] LEPCHA SIGN RAN..LEPCHA SIGN NUKTA
    ; between_unicode_range(0x1C40, 0x1C49, Character) % XID_Continue # Nd  [10] LEPCHA DIGIT ZERO..LEPCHA DIGIT NINE
    ; between_unicode_range(0x1C4D, 0x1C4F, Character) % XID_Continue # Lo   [3] LEPCHA LETTER TTA..LEPCHA LETTER DDA
    ; between_unicode_range(0x1C50, 0x1C59, Character) % XID_Continue # Nd  [10] OL CHIKI DIGIT ZERO..OL CHIKI DIGIT NINE
    ; between_unicode_range(0x1C5A, 0x1C77, Character) % XID_Continue # Lo  [30] OL CHIKI LETTER LA..OL CHIKI LETTER OH
    ; between_unicode_range(0x1C78, 0x1C7D, Character) % XID_Continue # Lm   [6] OL CHIKI MU TTUDDAG..OL CHIKI AHAD
    ; between_unicode_range(0x1C80, 0x1C8A, Character) % XID_Continue # L&  [11] CYRILLIC SMALL LETTER ROUNDED VE..CYRILLIC SMALL LETTER TJE
    ; between_unicode_range(0x1C90, 0x1CBA, Character) % XID_Continue # L&  [43] GEORGIAN MTAVRULI CAPITAL LETTER AN..GEORGIAN MTAVRULI CAPITAL LETTER AIN
    ; between_unicode_range(0x1CBD, 0x1CBF, Character) % XID_Continue # L&   [3] GEORGIAN MTAVRULI CAPITAL LETTER AEN..GEORGIAN MTAVRULI CAPITAL LETTER LABIAL SIGN
    ; between_unicode_range(0x1CD0, 0x1CD2, Character) % XID_Continue # Mn   [3] VEDIC TONE KARSHANA..VEDIC TONE PRENKHA
    ; between_unicode_range(0x1CD4, 0x1CE0, Character) % XID_Continue # Mn  [13] VEDIC SIGN YAJURVEDIC MIDLINE SVARITA..VEDIC TONE RIGVEDIC KASHMIRI INDEPENDENT SVARITA
    ; unicode_character(0x1CE1, Character) % XID_Continue # Mc       VEDIC TONE ATHARVAVEDIC INDEPENDENT SVARITA
    ; between_unicode_range(0x1CE2, 0x1CE8, Character) % XID_Continue # Mn   [7] VEDIC SIGN VISARGA SVARITA..VEDIC SIGN VISARGA ANUDATTA WITH TAIL
    ; between_unicode_range(0x1CE9, 0x1CEC, Character) % XID_Continue # Lo   [4] VEDIC SIGN ANUSVARA ANTARGOMUKHA..VEDIC SIGN ANUSVARA VAMAGOMUKHA WITH TAIL
    ; unicode_character(0x1CED, Character) % XID_Continue # Mn       VEDIC SIGN TIRYAK
    ; between_unicode_range(0x1CEE, 0x1CF3, Character) % XID_Continue # Lo   [6] VEDIC SIGN HEXIFORM LONG ANUSVARA..VEDIC SIGN ROTATED ARDHAVISARGA
    ; unicode_character(0x1CF4, Character) % XID_Continue # Mn       VEDIC TONE CANDRA ABOVE
    ; between_unicode_range(0x1CF5, 0x1CF6, Character) % XID_Continue # Lo   [2] VEDIC SIGN JIHVAMULIYA..VEDIC SIGN UPADHMANIYA
    ; unicode_character(0x1CF7, Character) % XID_Continue # Mc       VEDIC SIGN ATIKRAMA
    ; between_unicode_range(0x1CF8, 0x1CF9, Character) % XID_Continue # Mn   [2] VEDIC TONE RING ABOVE..VEDIC TONE DOUBLE RING ABOVE
    ; unicode_character(0x1CFA, Character) % XID_Continue # Lo       VEDIC SIGN DOUBLE ANUSVARA ANTARGOMUKHA
    ; between_unicode_range(0x1D00, 0x1D2B, Character) % XID_Continue # L&  [44] LATIN LETTER SMALL CAPITAL A..CYRILLIC LETTER SMALL CAPITAL EL
    ; between_unicode_range(0x1D2C, 0x1D6A, Character) % XID_Continue # Lm  [63] MODIFIER LETTER CAPITAL A..GREEK SUBSCRIPT SMALL LETTER CHI
    ; between_unicode_range(0x1D6B, 0x1D77, Character) % XID_Continue # L&  [13] LATIN SMALL LETTER UE..LATIN SMALL LETTER TURNED G
    ; unicode_character(0x1D78, Character) % XID_Continue # Lm       MODIFIER LETTER CYRILLIC EN
    ; between_unicode_range(0x1D79, 0x1D9A, Character) % XID_Continue # L&  [34] LATIN SMALL LETTER INSULAR G..LATIN SMALL LETTER EZH WITH RETROFLEX HOOK
    ; between_unicode_range(0x1D9B, 0x1DBF, Character) % XID_Continue # Lm  [37] MODIFIER LETTER SMALL TURNED ALPHA..MODIFIER LETTER SMALL THETA
    ; between_unicode_range(0x1DC0, 0x1DFF, Character) % XID_Continue # Mn  [64] COMBINING DOTTED GRAVE ACCENT..COMBINING RIGHT ARROWHEAD AND DOWN ARROWHEAD BELOW
    ; between_unicode_range(0x1E00, 0x1F15, Character) % XID_Continue # L& [278] LATIN CAPITAL LETTER A WITH RING BELOW..GREEK SMALL LETTER EPSILON WITH DASIA AND OXIA
    ; between_unicode_range(0x1F18, 0x1F1D, Character) % XID_Continue # L&   [6] GREEK CAPITAL LETTER EPSILON WITH PSILI..GREEK CAPITAL LETTER EPSILON WITH DASIA AND OXIA
    ; between_unicode_range(0x1F20, 0x1F45, Character) % XID_Continue # L&  [38] GREEK SMALL LETTER ETA WITH PSILI..GREEK SMALL LETTER OMICRON WITH DASIA AND OXIA
    ; between_unicode_range(0x1F48, 0x1F4D, Character) % XID_Continue # L&   [6] GREEK CAPITAL LETTER OMICRON WITH PSILI..GREEK CAPITAL LETTER OMICRON WITH DASIA AND OXIA
    ; between_unicode_range(0x1F50, 0x1F57, Character) % XID_Continue # L&   [8] GREEK SMALL LETTER UPSILON WITH PSILI..GREEK SMALL LETTER UPSILON WITH DASIA AND PERISPOMENI
    ; unicode_character(0x1F59, Character) % XID_Continue # L&       GREEK CAPITAL LETTER UPSILON WITH DASIA
    ; unicode_character(0x1F5B, Character) % XID_Continue # L&       GREEK CAPITAL LETTER UPSILON WITH DASIA AND VARIA
    ; unicode_character(0x1F5D, Character) % XID_Continue # L&       GREEK CAPITAL LETTER UPSILON WITH DASIA AND OXIA
    ; between_unicode_range(0x1F5F, 0x1F7D, Character) % XID_Continue # L&  [31] GREEK CAPITAL LETTER UPSILON WITH DASIA AND PERISPOMENI..GREEK SMALL LETTER OMEGA WITH OXIA
    ; between_unicode_range(0x1F80, 0x1FB4, Character) % XID_Continue # L&  [53] GREEK SMALL LETTER ALPHA WITH PSILI AND YPOGEGRAMMENI..GREEK SMALL LETTER ALPHA WITH OXIA AND YPOGEGRAMMENI
    ; between_unicode_range(0x1FB6, 0x1FBC, Character) % XID_Continue # L&   [7] GREEK SMALL LETTER ALPHA WITH PERISPOMENI..GREEK CAPITAL LETTER ALPHA WITH PROSGEGRAMMENI
    ; unicode_character(0x1FBE, Character) % XID_Continue # L&       GREEK PROSGEGRAMMENI
    ; between_unicode_range(0x1FC2, 0x1FC4, Character) % XID_Continue # L&   [3] GREEK SMALL LETTER ETA WITH VARIA AND YPOGEGRAMMENI..GREEK SMALL LETTER ETA WITH OXIA AND YPOGEGRAMMENI
    ; between_unicode_range(0x1FC6, 0x1FCC, Character) % XID_Continue # L&   [7] GREEK SMALL LETTER ETA WITH PERISPOMENI..GREEK CAPITAL LETTER ETA WITH PROSGEGRAMMENI
    ; between_unicode_range(0x1FD0, 0x1FD3, Character) % XID_Continue # L&   [4] GREEK SMALL LETTER IOTA WITH VRACHY..GREEK SMALL LETTER IOTA WITH DIALYTIKA AND OXIA
    ; between_unicode_range(0x1FD6, 0x1FDB, Character) % XID_Continue # L&   [6] GREEK SMALL LETTER IOTA WITH PERISPOMENI..GREEK CAPITAL LETTER IOTA WITH OXIA
    ; between_unicode_range(0x1FE0, 0x1FEC, Character) % XID_Continue # L&  [13] GREEK SMALL LETTER UPSILON WITH VRACHY..GREEK CAPITAL LETTER RHO WITH DASIA
    ; between_unicode_range(0x1FF2, 0x1FF4, Character) % XID_Continue # L&   [3] GREEK SMALL LETTER OMEGA WITH VARIA AND YPOGEGRAMMENI..GREEK SMALL LETTER OMEGA WITH OXIA AND YPOGEGRAMMENI
    ; between_unicode_range(0x1FF6, 0x1FFC, Character) % XID_Continue # L&   [7] GREEK SMALL LETTER OMEGA WITH PERISPOMENI..GREEK CAPITAL LETTER OMEGA WITH PROSGEGRAMMENI
    ; between_unicode_range(0x200C, 0x200D, Character) % XID_Continue # Cf   [2] ZERO WIDTH NON-JOINER..ZERO WIDTH JOINER
    ; between_unicode_range(0x203F, 0x2040, Character) % XID_Continue # Pc   [2] UNDERTIE..CHARACTER TIE
    ; unicode_character(0x2054, Character) % XID_Continue # Pc       INVERTED UNDERTIE
    ; unicode_character(0x2071, Character) % XID_Continue # Lm       SUPERSCRIPT LATIN SMALL LETTER I
    ; unicode_character(0x207F, Character) % XID_Continue # Lm       SUPERSCRIPT LATIN SMALL LETTER N
    ; between_unicode_range(0x2090, 0x209C, Character) % XID_Continue # Lm  [13] LATIN SUBSCRIPT SMALL LETTER A..LATIN SUBSCRIPT SMALL LETTER T
    ; between_unicode_range(0x20D0, 0x20DC, Character) % XID_Continue # Mn  [13] COMBINING LEFT HARPOON ABOVE..COMBINING FOUR DOTS ABOVE
    ; unicode_character(0x20E1, Character) % XID_Continue # Mn       COMBINING LEFT RIGHT ARROW ABOVE
    ; between_unicode_range(0x20E5, 0x20F0, Character) % XID_Continue # Mn  [12] COMBINING REVERSE SOLIDUS OVERLAY..COMBINING ASTERISK ABOVE
    ; unicode_character(0x2102, Character) % XID_Continue # L&       DOUBLE-STRUCK CAPITAL C
    ; unicode_character(0x2107, Character) % XID_Continue # L&       EULER CONSTANT
    ; between_unicode_range(0x210A, 0x2113, Character) % XID_Continue # L&  [10] SCRIPT SMALL G..SCRIPT SMALL L
    ; unicode_character(0x2115, Character) % XID_Continue # L&       DOUBLE-STRUCK CAPITAL N
    ; unicode_character(0x2118, Character) % XID_Continue # Sm       SCRIPT CAPITAL P
    ; between_unicode_range(0x2119, 0x211D, Character) % XID_Continue # L&   [5] DOUBLE-STRUCK CAPITAL P..DOUBLE-STRUCK CAPITAL R
    ; unicode_character(0x2124, Character) % XID_Continue # L&       DOUBLE-STRUCK CAPITAL Z
    ; unicode_character(0x2126, Character) % XID_Continue # L&       OHM SIGN
    ; unicode_character(0x2128, Character) % XID_Continue # L&       BLACK-LETTER CAPITAL Z
    ; between_unicode_range(0x212A, 0x212D, Character) % XID_Continue # L&   [4] KELVIN SIGN..BLACK-LETTER CAPITAL C
    ; unicode_character(0x212E, Character) % XID_Continue # So       ESTIMATED SYMBOL
    ; between_unicode_range(0x212F, 0x2134, Character) % XID_Continue # L&   [6] SCRIPT SMALL E..SCRIPT SMALL O
    ; between_unicode_range(0x2135, 0x2138, Character) % XID_Continue # Lo   [4] ALEF SYMBOL..DALET SYMBOL
    ; unicode_character(0x2139, Character) % XID_Continue # L&       INFORMATION SOURCE
    ; between_unicode_range(0x213C, 0x213F, Character) % XID_Continue # L&   [4] DOUBLE-STRUCK SMALL PI..DOUBLE-STRUCK CAPITAL PI
    ; between_unicode_range(0x2145, 0x2149, Character) % XID_Continue # L&   [5] DOUBLE-STRUCK ITALIC CAPITAL D..DOUBLE-STRUCK ITALIC SMALL J
    ; unicode_character(0x214E, Character) % XID_Continue # L&       TURNED SMALL F
    ; between_unicode_range(0x2160, 0x2182, Character) % XID_Continue # Nl  [35] ROMAN NUMERAL ONE..ROMAN NUMERAL TEN THOUSAND
    ; between_unicode_range(0x2183, 0x2184, Character) % XID_Continue # L&   [2] ROMAN NUMERAL REVERSED ONE HUNDRED..LATIN SMALL LETTER REVERSED C
    ; between_unicode_range(0x2185, 0x2188, Character) % XID_Continue # Nl   [4] ROMAN NUMERAL SIX LATE FORM..ROMAN NUMERAL ONE HUNDRED THOUSAND
    ; between_unicode_range(0x2C00, 0x2C7B, Character) % XID_Continue # L& [124] GLAGOLITIC CAPITAL LETTER AZU..LATIN LETTER SMALL CAPITAL TURNED E
    ; between_unicode_range(0x2C7C, 0x2C7D, Character) % XID_Continue # Lm   [2] LATIN SUBSCRIPT SMALL LETTER J..MODIFIER LETTER CAPITAL V
    ; between_unicode_range(0x2C7E, 0x2CE4, Character) % XID_Continue # L& [103] LATIN CAPITAL LETTER S WITH SWASH TAIL..COPTIC SYMBOL KAI
    ; between_unicode_range(0x2CEB, 0x2CEE, Character) % XID_Continue # L&   [4] COPTIC CAPITAL LETTER CRYPTOGRAMMIC SHEI..COPTIC SMALL LETTER CRYPTOGRAMMIC GANGIA
    ; between_unicode_range(0x2CEF, 0x2CF1, Character) % XID_Continue # Mn   [3] COPTIC COMBINING NI ABOVE..COPTIC COMBINING SPIRITUS LENIS
    ; between_unicode_range(0x2CF2, 0x2CF3, Character) % XID_Continue # L&   [2] COPTIC CAPITAL LETTER BOHAIRIC KHEI..COPTIC SMALL LETTER BOHAIRIC KHEI
    ; between_unicode_range(0x2D00, 0x2D25, Character) % XID_Continue # L&  [38] GEORGIAN SMALL LETTER AN..GEORGIAN SMALL LETTER HOE
    ; unicode_character(0x2D27, Character) % XID_Continue # L&       GEORGIAN SMALL LETTER YN
    ; unicode_character(0x2D2D, Character) % XID_Continue # L&       GEORGIAN SMALL LETTER AEN
    ; between_unicode_range(0x2D30, 0x2D67, Character) % XID_Continue # Lo  [56] TIFINAGH LETTER YA..TIFINAGH LETTER YO
    ; unicode_character(0x2D6F, Character) % XID_Continue # Lm       TIFINAGH MODIFIER LETTER LABIALIZATION MARK
    ; unicode_character(0x2D7F, Character) % XID_Continue # Mn       TIFINAGH CONSONANT JOINER
    ; between_unicode_range(0x2D80, 0x2D96, Character) % XID_Continue # Lo  [23] ETHIOPIC SYLLABLE LOA..ETHIOPIC SYLLABLE GGWE
    ; between_unicode_range(0x2DA0, 0x2DA6, Character) % XID_Continue # Lo   [7] ETHIOPIC SYLLABLE SSA..ETHIOPIC SYLLABLE SSO
    ; between_unicode_range(0x2DA8, 0x2DAE, Character) % XID_Continue # Lo   [7] ETHIOPIC SYLLABLE CCA..ETHIOPIC SYLLABLE CCO
    ; between_unicode_range(0x2DB0, 0x2DB6, Character) % XID_Continue # Lo   [7] ETHIOPIC SYLLABLE ZZA..ETHIOPIC SYLLABLE ZZO
    ; between_unicode_range(0x2DB8, 0x2DBE, Character) % XID_Continue # Lo   [7] ETHIOPIC SYLLABLE CCHA..ETHIOPIC SYLLABLE CCHO
    ; between_unicode_range(0x2DC0, 0x2DC6, Character) % XID_Continue # Lo   [7] ETHIOPIC SYLLABLE QYA..ETHIOPIC SYLLABLE QYO
    ; between_unicode_range(0x2DC8, 0x2DCE, Character) % XID_Continue # Lo   [7] ETHIOPIC SYLLABLE KYA..ETHIOPIC SYLLABLE KYO
    ; between_unicode_range(0x2DD0, 0x2DD6, Character) % XID_Continue # Lo   [7] ETHIOPIC SYLLABLE XYA..ETHIOPIC SYLLABLE XYO
    ; between_unicode_range(0x2DD8, 0x2DDE, Character) % XID_Continue # Lo   [7] ETHIOPIC SYLLABLE GYA..ETHIOPIC SYLLABLE GYO
    ; between_unicode_range(0x2DE0, 0x2DFF, Character) % XID_Continue # Mn  [32] COMBINING CYRILLIC LETTER BE..COMBINING CYRILLIC LETTER IOTIFIED BIG YUS
    ; unicode_character(0x3005, Character) % XID_Continue # Lm       IDEOGRAPHIC ITERATION MARK
    ; unicode_character(0x3006, Character) % XID_Continue # Lo       IDEOGRAPHIC CLOSING MARK
    ; unicode_character(0x3007, Character) % XID_Continue # Nl       IDEOGRAPHIC NUMBER ZERO
    ; between_unicode_range(0x3021, 0x3029, Character) % XID_Continue # Nl   [9] HANGZHOU NUMERAL ONE..HANGZHOU NUMERAL NINE
    ; between_unicode_range(0x302A, 0x302D, Character) % XID_Continue # Mn   [4] IDEOGRAPHIC LEVEL TONE MARK..IDEOGRAPHIC ENTERING TONE MARK
    ; between_unicode_range(0x302E, 0x302F, Character) % XID_Continue # Mc   [2] HANGUL SINGLE DOT TONE MARK..HANGUL DOUBLE DOT TONE MARK
    ; between_unicode_range(0x3031, 0x3035, Character) % XID_Continue # Lm   [5] VERTICAL KANA REPEAT MARK..VERTICAL KANA REPEAT MARK LOWER HALF
    ; between_unicode_range(0x3038, 0x303A, Character) % XID_Continue # Nl   [3] HANGZHOU NUMERAL TEN..HANGZHOU NUMERAL THIRTY
    ; unicode_character(0x303B, Character) % XID_Continue # Lm       VERTICAL IDEOGRAPHIC ITERATION MARK
    ; unicode_character(0x303C, Character) % XID_Continue # Lo       MASU MARK
    ; between_unicode_range(0x3041, 0x3096, Character) % XID_Continue # Lo  [86] HIRAGANA LETTER SMALL A..HIRAGANA LETTER SMALL KE
    ; between_unicode_range(0x3099, 0x309A, Character) % XID_Continue # Mn   [2] COMBINING KATAKANA-HIRAGANA VOICED SOUND MARK..COMBINING KATAKANA-HIRAGANA SEMI-VOICED SOUND MARK
    ; between_unicode_range(0x309D, 0x309E, Character) % XID_Continue # Lm   [2] HIRAGANA ITERATION MARK..HIRAGANA VOICED ITERATION MARK
    ; unicode_character(0x309F, Character) % XID_Continue # Lo       HIRAGANA DIGRAPH YORI
    ; between_unicode_range(0x30A1, 0x30FA, Character) % XID_Continue # Lo  [90] KATAKANA LETTER SMALL A..KATAKANA LETTER VO
    ; unicode_character(0x30FB, Character) % XID_Continue # Po       KATAKANA MIDDLE DOT
    ; between_unicode_range(0x30FC, 0x30FE, Character) % XID_Continue # Lm   [3] KATAKANA-HIRAGANA PROLONGED SOUND MARK..KATAKANA VOICED ITERATION MARK
    ; unicode_character(0x30FF, Character) % XID_Continue # Lo       KATAKANA DIGRAPH KOTO
    ; between_unicode_range(0x3105, 0x312F, Character) % XID_Continue # Lo  [43] BOPOMOFO LETTER B..BOPOMOFO LETTER NN
    ; between_unicode_range(0x3131, 0x318E, Character) % XID_Continue # Lo  [94] HANGUL LETTER KIYEOK..HANGUL LETTER ARAEAE
    ; between_unicode_range(0x31A0, 0x31BF, Character) % XID_Continue # Lo  [32] BOPOMOFO LETTER BU..BOPOMOFO LETTER AH
    ; between_unicode_range(0x31F0, 0x31FF, Character) % XID_Continue # Lo  [16] KATAKANA LETTER SMALL KU..KATAKANA LETTER SMALL RO
    ; between_unicode_range(0x3400, 0x4DBF, Character) % XID_Continue # Lo [6592] CJK UNIFIED IDEOGRAPH-3400..CJK UNIFIED IDEOGRAPH-4DBF
    ; between_unicode_range(0x4E00, 0xA014, Character) % XID_Continue # Lo [21013] CJK UNIFIED IDEOGRAPH-4E00..YI SYLLABLE E
    ; unicode_character(0xA015, Character) % XID_Continue # Lm       YI SYLLABLE WU
    ; between_unicode_range(0xA016, 0xA48C, Character) % XID_Continue # Lo [1143] YI SYLLABLE BIT..YI SYLLABLE YYR
    ; between_unicode_range(0xA4D0, 0xA4F7, Character) % XID_Continue # Lo  [40] LISU LETTER BA..LISU LETTER OE
    ; between_unicode_range(0xA4F8, 0xA4FD, Character) % XID_Continue # Lm   [6] LISU LETTER TONE MYA TI..LISU LETTER TONE MYA JEU
    ; between_unicode_range(0xA500, 0xA60B, Character) % XID_Continue # Lo [268] VAI SYLLABLE EE..VAI SYLLABLE NG
    ; unicode_character(0xA60C, Character) % XID_Continue # Lm       VAI SYLLABLE LENGTHENER
    ; between_unicode_range(0xA610, 0xA61F, Character) % XID_Continue # Lo  [16] VAI SYLLABLE NDOLE FA..VAI SYMBOL JONG
    ; between_unicode_range(0xA620, 0xA629, Character) % XID_Continue # Nd  [10] VAI DIGIT ZERO..VAI DIGIT NINE
    ; between_unicode_range(0xA62A, 0xA62B, Character) % XID_Continue # Lo   [2] VAI SYLLABLE NDOLE MA..VAI SYLLABLE NDOLE DO
    ; between_unicode_range(0xA640, 0xA66D, Character) % XID_Continue # L&  [46] CYRILLIC CAPITAL LETTER ZEMLYA..CYRILLIC SMALL LETTER DOUBLE MONOCULAR O
    ; unicode_character(0xA66E, Character) % XID_Continue # Lo       CYRILLIC LETTER MULTIOCULAR O
    ; unicode_character(0xA66F, Character) % XID_Continue # Mn       COMBINING CYRILLIC VZMET
    ; between_unicode_range(0xA674, 0xA67D, Character) % XID_Continue # Mn  [10] COMBINING CYRILLIC LETTER UKRAINIAN IE..COMBINING CYRILLIC PAYEROK
    ; unicode_character(0xA67F, Character) % XID_Continue # Lm       CYRILLIC PAYEROK
    ; between_unicode_range(0xA680, 0xA69B, Character) % XID_Continue # L&  [28] CYRILLIC CAPITAL LETTER DWE..CYRILLIC SMALL LETTER CROSSED O
    ; between_unicode_range(0xA69C, 0xA69D, Character) % XID_Continue # Lm   [2] MODIFIER LETTER CYRILLIC HARD SIGN..MODIFIER LETTER CYRILLIC SOFT SIGN
    ; between_unicode_range(0xA69E, 0xA69F, Character) % XID_Continue # Mn   [2] COMBINING CYRILLIC LETTER EF..COMBINING CYRILLIC LETTER IOTIFIED E
    ; between_unicode_range(0xA6A0, 0xA6E5, Character) % XID_Continue # Lo  [70] BAMUM LETTER A..BAMUM LETTER KI
    ; between_unicode_range(0xA6E6, 0xA6EF, Character) % XID_Continue # Nl  [10] BAMUM LETTER MO..BAMUM LETTER KOGHOM
    ; between_unicode_range(0xA6F0, 0xA6F1, Character) % XID_Continue # Mn   [2] BAMUM COMBINING MARK KOQNDON..BAMUM COMBINING MARK TUKWENTIS
    ; between_unicode_range(0xA717, 0xA71F, Character) % XID_Continue # Lm   [9] MODIFIER LETTER DOT VERTICAL BAR..MODIFIER LETTER LOW INVERTED EXCLAMATION MARK
    ; between_unicode_range(0xA722, 0xA76F, Character) % XID_Continue # L&  [78] LATIN CAPITAL LETTER EGYPTOLOGICAL ALEF..LATIN SMALL LETTER CON
    ; unicode_character(0xA770, Character) % XID_Continue # Lm       MODIFIER LETTER US
    ; between_unicode_range(0xA771, 0xA787, Character) % XID_Continue # L&  [23] LATIN SMALL LETTER DUM..LATIN SMALL LETTER INSULAR T
    ; unicode_character(0xA788, Character) % XID_Continue # Lm       MODIFIER LETTER LOW CIRCUMFLEX ACCENT
    ; between_unicode_range(0xA78B, 0xA78E, Character) % XID_Continue # L&   [4] LATIN CAPITAL LETTER SALTILLO..LATIN SMALL LETTER L WITH RETROFLEX HOOK AND BELT
    ; unicode_character(0xA78F, Character) % XID_Continue # Lo       LATIN LETTER SINOLOGICAL DOT
    ; between_unicode_range(0xA790, 0xA7CD, Character) % XID_Continue # L&  [62] LATIN CAPITAL LETTER N WITH DESCENDER..LATIN SMALL LETTER S WITH DIAGONAL STROKE
    ; between_unicode_range(0xA7D0, 0xA7D1, Character) % XID_Continue # L&   [2] LATIN CAPITAL LETTER CLOSED INSULAR G..LATIN SMALL LETTER CLOSED INSULAR G
    ; unicode_character(0xA7D3, Character) % XID_Continue # L&       LATIN SMALL LETTER DOUBLE THORN
    ; between_unicode_range(0xA7D5, 0xA7DC, Character) % XID_Continue # L&   [8] LATIN SMALL LETTER DOUBLE WYNN..LATIN CAPITAL LETTER LAMBDA WITH STROKE
    ; between_unicode_range(0xA7F2, 0xA7F4, Character) % XID_Continue # Lm   [3] MODIFIER LETTER CAPITAL C..MODIFIER LETTER CAPITAL Q
    ; between_unicode_range(0xA7F5, 0xA7F6, Character) % XID_Continue # L&   [2] LATIN CAPITAL LETTER REVERSED HALF H..LATIN SMALL LETTER REVERSED HALF H
    ; unicode_character(0xA7F7, Character) % XID_Continue # Lo       LATIN EPIGRAPHIC LETTER SIDEWAYS I
    ; between_unicode_range(0xA7F8, 0xA7F9, Character) % XID_Continue # Lm   [2] MODIFIER LETTER CAPITAL H WITH STROKE..MODIFIER LETTER SMALL LIGATURE OE
    ; unicode_character(0xA7FA, Character) % XID_Continue # L&       LATIN LETTER SMALL CAPITAL TURNED M
    ; between_unicode_range(0xA7FB, 0xA801, Character) % XID_Continue # Lo   [7] LATIN EPIGRAPHIC LETTER REVERSED F..SYLOTI NAGRI LETTER I
    ; unicode_character(0xA802, Character) % XID_Continue # Mn       SYLOTI NAGRI SIGN DVISVARA
    ; between_unicode_range(0xA803, 0xA805, Character) % XID_Continue # Lo   [3] SYLOTI NAGRI LETTER U..SYLOTI NAGRI LETTER O
    ; unicode_character(0xA806, Character) % XID_Continue # Mn       SYLOTI NAGRI SIGN HASANTA
    ; between_unicode_range(0xA807, 0xA80A, Character) % XID_Continue # Lo   [4] SYLOTI NAGRI LETTER KO..SYLOTI NAGRI LETTER GHO
    ; unicode_character(0xA80B, Character) % XID_Continue # Mn       SYLOTI NAGRI SIGN ANUSVARA
    ; between_unicode_range(0xA80C, 0xA822, Character) % XID_Continue # Lo  [23] SYLOTI NAGRI LETTER CO..SYLOTI NAGRI LETTER HO
    ; between_unicode_range(0xA823, 0xA824, Character) % XID_Continue # Mc   [2] SYLOTI NAGRI VOWEL SIGN A..SYLOTI NAGRI VOWEL SIGN I
    ; between_unicode_range(0xA825, 0xA826, Character) % XID_Continue # Mn   [2] SYLOTI NAGRI VOWEL SIGN U..SYLOTI NAGRI VOWEL SIGN E
    ; unicode_character(0xA827, Character) % XID_Continue # Mc       SYLOTI NAGRI VOWEL SIGN OO
    ; unicode_character(0xA82C, Character) % XID_Continue # Mn       SYLOTI NAGRI SIGN ALTERNATE HASANTA
    ; between_unicode_range(0xA840, 0xA873, Character) % XID_Continue # Lo  [52] PHAGS-PA LETTER KA..PHAGS-PA LETTER CANDRABINDU
    ; between_unicode_range(0xA880, 0xA881, Character) % XID_Continue # Mc   [2] SAURASHTRA SIGN ANUSVARA..SAURASHTRA SIGN VISARGA
    ; between_unicode_range(0xA882, 0xA8B3, Character) % XID_Continue # Lo  [50] SAURASHTRA LETTER A..SAURASHTRA LETTER LLA
    ; between_unicode_range(0xA8B4, 0xA8C3, Character) % XID_Continue # Mc  [16] SAURASHTRA CONSONANT SIGN HAARU..SAURASHTRA VOWEL SIGN AU
    ; between_unicode_range(0xA8C4, 0xA8C5, Character) % XID_Continue # Mn   [2] SAURASHTRA SIGN VIRAMA..SAURASHTRA SIGN CANDRABINDU
    ; between_unicode_range(0xA8D0, 0xA8D9, Character) % XID_Continue # Nd  [10] SAURASHTRA DIGIT ZERO..SAURASHTRA DIGIT NINE
    ; between_unicode_range(0xA8E0, 0xA8F1, Character) % XID_Continue # Mn  [18] COMBINING DEVANAGARI DIGIT ZERO..COMBINING DEVANAGARI SIGN AVAGRAHA
    ; between_unicode_range(0xA8F2, 0xA8F7, Character) % XID_Continue # Lo   [6] DEVANAGARI SIGN SPACING CANDRABINDU..DEVANAGARI SIGN CANDRABINDU AVAGRAHA
    ; unicode_character(0xA8FB, Character) % XID_Continue # Lo       DEVANAGARI HEADSTROKE
    ; between_unicode_range(0xA8FD, 0xA8FE, Character) % XID_Continue # Lo   [2] DEVANAGARI JAIN OM..DEVANAGARI LETTER AY
    ; unicode_character(0xA8FF, Character) % XID_Continue # Mn       DEVANAGARI VOWEL SIGN AY
    ; between_unicode_range(0xA900, 0xA909, Character) % XID_Continue # Nd  [10] KAYAH LI DIGIT ZERO..KAYAH LI DIGIT NINE
    ; between_unicode_range(0xA90A, 0xA925, Character) % XID_Continue # Lo  [28] KAYAH LI LETTER KA..KAYAH LI LETTER OO
    ; between_unicode_range(0xA926, 0xA92D, Character) % XID_Continue # Mn   [8] KAYAH LI VOWEL UE..KAYAH LI TONE CALYA PLOPHU
    ; between_unicode_range(0xA930, 0xA946, Character) % XID_Continue # Lo  [23] REJANG LETTER KA..REJANG LETTER A
    ; between_unicode_range(0xA947, 0xA951, Character) % XID_Continue # Mn  [11] REJANG VOWEL SIGN I..REJANG CONSONANT SIGN R
    ; between_unicode_range(0xA952, 0xA953, Character) % XID_Continue # Mc   [2] REJANG CONSONANT SIGN H..REJANG VIRAMA
    ; between_unicode_range(0xA960, 0xA97C, Character) % XID_Continue # Lo  [29] HANGUL CHOSEONG TIKEUT-MIEUM..HANGUL CHOSEONG SSANGYEORINHIEUH
    ; between_unicode_range(0xA980, 0xA982, Character) % XID_Continue # Mn   [3] JAVANESE SIGN PANYANGGA..JAVANESE SIGN LAYAR
    ; unicode_character(0xA983, Character) % XID_Continue # Mc       JAVANESE SIGN WIGNYAN
    ; between_unicode_range(0xA984, 0xA9B2, Character) % XID_Continue # Lo  [47] JAVANESE LETTER A..JAVANESE LETTER HA
    ; unicode_character(0xA9B3, Character) % XID_Continue # Mn       JAVANESE SIGN CECAK TELU
    ; between_unicode_range(0xA9B4, 0xA9B5, Character) % XID_Continue # Mc   [2] JAVANESE VOWEL SIGN TARUNG..JAVANESE VOWEL SIGN TOLONG
    ; between_unicode_range(0xA9B6, 0xA9B9, Character) % XID_Continue # Mn   [4] JAVANESE VOWEL SIGN WULU..JAVANESE VOWEL SIGN SUKU MENDUT
    ; between_unicode_range(0xA9BA, 0xA9BB, Character) % XID_Continue # Mc   [2] JAVANESE VOWEL SIGN TALING..JAVANESE VOWEL SIGN DIRGA MURE
    ; between_unicode_range(0xA9BC, 0xA9BD, Character) % XID_Continue # Mn   [2] JAVANESE VOWEL SIGN PEPET..JAVANESE CONSONANT SIGN KERET
    ; between_unicode_range(0xA9BE, 0xA9C0, Character) % XID_Continue # Mc   [3] JAVANESE CONSONANT SIGN PENGKAL..JAVANESE PANGKON
    ; unicode_character(0xA9CF, Character) % XID_Continue # Lm       JAVANESE PANGRANGKEP
    ; between_unicode_range(0xA9D0, 0xA9D9, Character) % XID_Continue # Nd  [10] JAVANESE DIGIT ZERO..JAVANESE DIGIT NINE
    ; between_unicode_range(0xA9E0, 0xA9E4, Character) % XID_Continue # Lo   [5] MYANMAR LETTER SHAN GHA..MYANMAR LETTER SHAN BHA
    ; unicode_character(0xA9E5, Character) % XID_Continue # Mn       MYANMAR SIGN SHAN SAW
    ; unicode_character(0xA9E6, Character) % XID_Continue # Lm       MYANMAR MODIFIER LETTER SHAN REDUPLICATION
    ; between_unicode_range(0xA9E7, 0xA9EF, Character) % XID_Continue # Lo   [9] MYANMAR LETTER TAI LAING NYA..MYANMAR LETTER TAI LAING NNA
    ; between_unicode_range(0xA9F0, 0xA9F9, Character) % XID_Continue # Nd  [10] MYANMAR TAI LAING DIGIT ZERO..MYANMAR TAI LAING DIGIT NINE
    ; between_unicode_range(0xA9FA, 0xA9FE, Character) % XID_Continue # Lo   [5] MYANMAR LETTER TAI LAING LLA..MYANMAR LETTER TAI LAING BHA
    ; between_unicode_range(0xAA00, 0xAA28, Character) % XID_Continue # Lo  [41] CHAM LETTER A..CHAM LETTER HA
    ; between_unicode_range(0xAA29, 0xAA2E, Character) % XID_Continue # Mn   [6] CHAM VOWEL SIGN AA..CHAM VOWEL SIGN OE
    ; between_unicode_range(0xAA2F, 0xAA30, Character) % XID_Continue # Mc   [2] CHAM VOWEL SIGN O..CHAM VOWEL SIGN AI
    ; between_unicode_range(0xAA31, 0xAA32, Character) % XID_Continue # Mn   [2] CHAM VOWEL SIGN AU..CHAM VOWEL SIGN UE
    ; between_unicode_range(0xAA33, 0xAA34, Character) % XID_Continue # Mc   [2] CHAM CONSONANT SIGN YA..CHAM CONSONANT SIGN RA
    ; between_unicode_range(0xAA35, 0xAA36, Character) % XID_Continue # Mn   [2] CHAM CONSONANT SIGN LA..CHAM CONSONANT SIGN WA
    ; between_unicode_range(0xAA40, 0xAA42, Character) % XID_Continue # Lo   [3] CHAM LETTER FINAL K..CHAM LETTER FINAL NG
    ; unicode_character(0xAA43, Character) % XID_Continue # Mn       CHAM CONSONANT SIGN FINAL NG
    ; between_unicode_range(0xAA44, 0xAA4B, Character) % XID_Continue # Lo   [8] CHAM LETTER FINAL CH..CHAM LETTER FINAL SS
    ; unicode_character(0xAA4C, Character) % XID_Continue # Mn       CHAM CONSONANT SIGN FINAL M
    ; unicode_character(0xAA4D, Character) % XID_Continue # Mc       CHAM CONSONANT SIGN FINAL H
    ; between_unicode_range(0xAA50, 0xAA59, Character) % XID_Continue # Nd  [10] CHAM DIGIT ZERO..CHAM DIGIT NINE
    ; between_unicode_range(0xAA60, 0xAA6F, Character) % XID_Continue # Lo  [16] MYANMAR LETTER KHAMTI GA..MYANMAR LETTER KHAMTI FA
    ; unicode_character(0xAA70, Character) % XID_Continue # Lm       MYANMAR MODIFIER LETTER KHAMTI REDUPLICATION
    ; between_unicode_range(0xAA71, 0xAA76, Character) % XID_Continue # Lo   [6] MYANMAR LETTER KHAMTI XA..MYANMAR LOGOGRAM KHAMTI HM
    ; unicode_character(0xAA7A, Character) % XID_Continue # Lo       MYANMAR LETTER AITON RA
    ; unicode_character(0xAA7B, Character) % XID_Continue # Mc       MYANMAR SIGN PAO KAREN TONE
    ; unicode_character(0xAA7C, Character) % XID_Continue # Mn       MYANMAR SIGN TAI LAING TONE-2
    ; unicode_character(0xAA7D, Character) % XID_Continue # Mc       MYANMAR SIGN TAI LAING TONE-5
    ; between_unicode_range(0xAA7E, 0xAAAF, Character) % XID_Continue # Lo  [50] MYANMAR LETTER SHWE PALAUNG CHA..TAI VIET LETTER HIGH O
    ; unicode_character(0xAAB0, Character) % XID_Continue # Mn       TAI VIET MAI KANG
    ; unicode_character(0xAAB1, Character) % XID_Continue # Lo       TAI VIET VOWEL AA
    ; between_unicode_range(0xAAB2, 0xAAB4, Character) % XID_Continue # Mn   [3] TAI VIET VOWEL I..TAI VIET VOWEL U
    ; between_unicode_range(0xAAB5, 0xAAB6, Character) % XID_Continue # Lo   [2] TAI VIET VOWEL E..TAI VIET VOWEL O
    ; between_unicode_range(0xAAB7, 0xAAB8, Character) % XID_Continue # Mn   [2] TAI VIET MAI KHIT..TAI VIET VOWEL IA
    ; between_unicode_range(0xAAB9, 0xAABD, Character) % XID_Continue # Lo   [5] TAI VIET VOWEL UEA..TAI VIET VOWEL AN
    ; between_unicode_range(0xAABE, 0xAABF, Character) % XID_Continue # Mn   [2] TAI VIET VOWEL AM..TAI VIET TONE MAI EK
    ; unicode_character(0xAAC0, Character) % XID_Continue # Lo       TAI VIET TONE MAI NUENG
    ; unicode_character(0xAAC1, Character) % XID_Continue # Mn       TAI VIET TONE MAI THO
    ; unicode_character(0xAAC2, Character) % XID_Continue # Lo       TAI VIET TONE MAI SONG
    ; between_unicode_range(0xAADB, 0xAADC, Character) % XID_Continue # Lo   [2] TAI VIET SYMBOL KON..TAI VIET SYMBOL NUENG
    ; unicode_character(0xAADD, Character) % XID_Continue # Lm       TAI VIET SYMBOL SAM
    ; between_unicode_range(0xAAE0, 0xAAEA, Character) % XID_Continue # Lo  [11] MEETEI MAYEK LETTER E..MEETEI MAYEK LETTER SSA
    ; unicode_character(0xAAEB, Character) % XID_Continue # Mc       MEETEI MAYEK VOWEL SIGN II
    ; between_unicode_range(0xAAEC, 0xAAED, Character) % XID_Continue # Mn   [2] MEETEI MAYEK VOWEL SIGN UU..MEETEI MAYEK VOWEL SIGN AAI
    ; between_unicode_range(0xAAEE, 0xAAEF, Character) % XID_Continue # Mc   [2] MEETEI MAYEK VOWEL SIGN AU..MEETEI MAYEK VOWEL SIGN AAU
    ; unicode_character(0xAAF2, Character) % XID_Continue # Lo       MEETEI MAYEK ANJI
    ; between_unicode_range(0xAAF3, 0xAAF4, Character) % XID_Continue # Lm   [2] MEETEI MAYEK SYLLABLE REPETITION MARK..MEETEI MAYEK WORD REPETITION MARK
    ; unicode_character(0xAAF5, Character) % XID_Continue # Mc       MEETEI MAYEK VOWEL SIGN VISARGA
    ; unicode_character(0xAAF6, Character) % XID_Continue # Mn       MEETEI MAYEK VIRAMA
    ; between_unicode_range(0xAB01, 0xAB06, Character) % XID_Continue # Lo   [6] ETHIOPIC SYLLABLE TTHU..ETHIOPIC SYLLABLE TTHO
    ; between_unicode_range(0xAB09, 0xAB0E, Character) % XID_Continue # Lo   [6] ETHIOPIC SYLLABLE DDHU..ETHIOPIC SYLLABLE DDHO
    ; between_unicode_range(0xAB11, 0xAB16, Character) % XID_Continue # Lo   [6] ETHIOPIC SYLLABLE DZU..ETHIOPIC SYLLABLE DZO
    ; between_unicode_range(0xAB20, 0xAB26, Character) % XID_Continue # Lo   [7] ETHIOPIC SYLLABLE CCHHA..ETHIOPIC SYLLABLE CCHHO
    ; between_unicode_range(0xAB28, 0xAB2E, Character) % XID_Continue # Lo   [7] ETHIOPIC SYLLABLE BBA..ETHIOPIC SYLLABLE BBO
    ; between_unicode_range(0xAB30, 0xAB5A, Character) % XID_Continue # L&  [43] LATIN SMALL LETTER BARRED ALPHA..LATIN SMALL LETTER Y WITH SHORT RIGHT LEG
    ; between_unicode_range(0xAB5C, 0xAB5F, Character) % XID_Continue # Lm   [4] MODIFIER LETTER SMALL HENG..MODIFIER LETTER SMALL U WITH LEFT HOOK
    ; between_unicode_range(0xAB60, 0xAB68, Character) % XID_Continue # L&   [9] LATIN SMALL LETTER SAKHA YAT..LATIN SMALL LETTER TURNED R WITH MIDDLE TILDE
    ; unicode_character(0xAB69, Character) % XID_Continue # Lm       MODIFIER LETTER SMALL TURNED W
    ; between_unicode_range(0xAB70, 0xABBF, Character) % XID_Continue # L&  [80] CHEROKEE SMALL LETTER A..CHEROKEE SMALL LETTER YA
    ; between_unicode_range(0xABC0, 0xABE2, Character) % XID_Continue # Lo  [35] MEETEI MAYEK LETTER KOK..MEETEI MAYEK LETTER I LONSUM
    ; between_unicode_range(0xABE3, 0xABE4, Character) % XID_Continue # Mc   [2] MEETEI MAYEK VOWEL SIGN ONAP..MEETEI MAYEK VOWEL SIGN INAP
    ; unicode_character(0xABE5, Character) % XID_Continue # Mn       MEETEI MAYEK VOWEL SIGN ANAP
    ; between_unicode_range(0xABE6, 0xABE7, Character) % XID_Continue # Mc   [2] MEETEI MAYEK VOWEL SIGN YENAP..MEETEI MAYEK VOWEL SIGN SOUNAP
    ; unicode_character(0xABE8, Character) % XID_Continue # Mn       MEETEI MAYEK VOWEL SIGN UNAP
    ; between_unicode_range(0xABE9, 0xABEA, Character) % XID_Continue # Mc   [2] MEETEI MAYEK VOWEL SIGN CHEINAP..MEETEI MAYEK VOWEL SIGN NUNG
    ; unicode_character(0xABEC, Character) % XID_Continue # Mc       MEETEI MAYEK LUM IYEK
    ; unicode_character(0xABED, Character) % XID_Continue # Mn       MEETEI MAYEK APUN IYEK
    ; between_unicode_range(0xABF0, 0xABF9, Character) % XID_Continue # Nd  [10] MEETEI MAYEK DIGIT ZERO..MEETEI MAYEK DIGIT NINE
    ; between_unicode_range(0xAC00, 0xD7A3, Character) % XID_Continue # Lo [11172] HANGUL SYLLABLE GA..HANGUL SYLLABLE HIH
    ; between_unicode_range(0xD7B0, 0xD7C6, Character) % XID_Continue # Lo  [23] HANGUL JUNGSEONG O-YEO..HANGUL JUNGSEONG ARAEA-E
    ; between_unicode_range(0xD7CB, 0xD7FB, Character) % XID_Continue # Lo  [49] HANGUL JONGSEONG NIEUN-RIEUL..HANGUL JONGSEONG PHIEUPH-THIEUTH
    ; between_unicode_range(0xF900, 0xFA6D, Character) % XID_Continue # Lo [366] CJK COMPATIBILITY IDEOGRAPH-F900..CJK COMPATIBILITY IDEOGRAPH-FA6D
    ; between_unicode_range(0xFA70, 0xFAD9, Character) % XID_Continue # Lo [106] CJK COMPATIBILITY IDEOGRAPH-FA70..CJK COMPATIBILITY IDEOGRAPH-FAD9
    ; between_unicode_range(0xFB00, 0xFB06, Character) % XID_Continue # L&   [7] LATIN SMALL LIGATURE FF..LATIN SMALL LIGATURE ST
    ; between_unicode_range(0xFB13, 0xFB17, Character) % XID_Continue # L&   [5] ARMENIAN SMALL LIGATURE MEN NOW..ARMENIAN SMALL LIGATURE MEN XEH
    ; unicode_character(0xFB1D, Character) % XID_Continue # Lo       HEBREW LETTER YOD WITH HIRIQ
    ; unicode_character(0xFB1E, Character) % XID_Continue # Mn       HEBREW POINT JUDEO-SPANISH VARIKA
    ; between_unicode_range(0xFB1F, 0xFB28, Character) % XID_Continue # Lo  [10] HEBREW LIGATURE YIDDISH YOD YOD PATAH..HEBREW LETTER WIDE TAV
    ; between_unicode_range(0xFB2A, 0xFB36, Character) % XID_Continue # Lo  [13] HEBREW LETTER SHIN WITH SHIN DOT..HEBREW LETTER ZAYIN WITH DAGESH
    ; between_unicode_range(0xFB38, 0xFB3C, Character) % XID_Continue # Lo   [5] HEBREW LETTER TET WITH DAGESH..HEBREW LETTER LAMED WITH DAGESH
    ; unicode_character(0xFB3E, Character) % XID_Continue # Lo       HEBREW LETTER MEM WITH DAGESH
    ; between_unicode_range(0xFB40, 0xFB41, Character) % XID_Continue # Lo   [2] HEBREW LETTER NUN WITH DAGESH..HEBREW LETTER SAMEKH WITH DAGESH
    ; between_unicode_range(0xFB43, 0xFB44, Character) % XID_Continue # Lo   [2] HEBREW LETTER FINAL PE WITH DAGESH..HEBREW LETTER PE WITH DAGESH
    ; between_unicode_range(0xFB46, 0xFBB1, Character) % XID_Continue # Lo [108] HEBREW LETTER TSADI WITH DAGESH..ARABIC LETTER YEH BARREE WITH HAMZA ABOVE FINAL FORM
    ; between_unicode_range(0xFBD3, 0xFC5D, Character) % XID_Continue # Lo [139] ARABIC LETTER NG ISOLATED FORM..ARABIC LIGATURE ALEF MAKSURA WITH SUPERSCRIPT ALEF ISOLATED FORM
    ; between_unicode_range(0xFC64, 0xFD3D, Character) % XID_Continue # Lo [218] ARABIC LIGATURE YEH WITH HAMZA ABOVE WITH REH FINAL FORM..ARABIC LIGATURE ALEF WITH FATHATAN ISOLATED FORM
    ; between_unicode_range(0xFD50, 0xFD8F, Character) % XID_Continue # Lo  [64] ARABIC LIGATURE TEH WITH JEEM WITH MEEM INITIAL FORM..ARABIC LIGATURE MEEM WITH KHAH WITH MEEM INITIAL FORM
    ; between_unicode_range(0xFD92, 0xFDC7, Character) % XID_Continue # Lo  [54] ARABIC LIGATURE MEEM WITH JEEM WITH KHAH INITIAL FORM..ARABIC LIGATURE NOON WITH JEEM WITH YEH FINAL FORM
    ; between_unicode_range(0xFDF0, 0xFDF9, Character) % XID_Continue # Lo  [10] ARABIC LIGATURE SALLA USED AS KORANIC STOP SIGN ISOLATED FORM..ARABIC LIGATURE SALLA ISOLATED FORM
    ; between_unicode_range(0xFE00, 0xFE0F, Character) % XID_Continue # Mn  [16] VARIATION SELECTOR-1..VARIATION SELECTOR-16
    ; between_unicode_range(0xFE20, 0xFE2F, Character) % XID_Continue # Mn  [16] COMBINING LIGATURE LEFT HALF..COMBINING CYRILLIC TITLO RIGHT HALF
    ; between_unicode_range(0xFE33, 0xFE34, Character) % XID_Continue # Pc   [2] PRESENTATION FORM FOR VERTICAL LOW LINE..PRESENTATION FORM FOR VERTICAL WAVY LOW LINE
    ; between_unicode_range(0xFE4D, 0xFE4F, Character) % XID_Continue # Pc   [3] DASHED LOW LINE..WAVY LOW LINE
    ; unicode_character(0xFE71, Character) % XID_Continue # Lo       ARABIC TATWEEL WITH FATHATAN ABOVE
    ; unicode_character(0xFE73, Character) % XID_Continue # Lo       ARABIC TAIL FRAGMENT
    ; unicode_character(0xFE77, Character) % XID_Continue # Lo       ARABIC FATHA MEDIAL FORM
    ; unicode_character(0xFE79, Character) % XID_Continue # Lo       ARABIC DAMMA MEDIAL FORM
    ; unicode_character(0xFE7B, Character) % XID_Continue # Lo       ARABIC KASRA MEDIAL FORM
    ; unicode_character(0xFE7D, Character) % XID_Continue # Lo       ARABIC SHADDA MEDIAL FORM
    ; between_unicode_range(0xFE7F, 0xFEFC, Character) % XID_Continue # Lo [126] ARABIC SUKUN MEDIAL FORM..ARABIC LIGATURE LAM WITH ALEF FINAL FORM
    ; between_unicode_range(0xFF10, 0xFF19, Character) % XID_Continue # Nd  [10] FULLWIDTH DIGIT ZERO..FULLWIDTH DIGIT NINE
    ; between_unicode_range(0xFF21, 0xFF3A, Character) % XID_Continue # L&  [26] FULLWIDTH LATIN CAPITAL LETTER A..FULLWIDTH LATIN CAPITAL LETTER Z
    ; unicode_character(0xFF3F, Character) % XID_Continue # Pc       FULLWIDTH LOW LINE
    ; between_unicode_range(0xFF41, 0xFF5A, Character) % XID_Continue # L&  [26] FULLWIDTH LATIN SMALL LETTER A..FULLWIDTH LATIN SMALL LETTER Z
    ; unicode_character(0xFF65, Character) % XID_Continue # Po       HALFWIDTH KATAKANA MIDDLE DOT
    ; between_unicode_range(0xFF66, 0xFF6F, Character) % XID_Continue # Lo  [10] HALFWIDTH KATAKANA LETTER WO..HALFWIDTH KATAKANA LETTER SMALL TU
    ; unicode_character(0xFF70, Character) % XID_Continue # Lm       HALFWIDTH KATAKANA-HIRAGANA PROLONGED SOUND MARK
    ; between_unicode_range(0xFF71, 0xFF9D, Character) % XID_Continue # Lo  [45] HALFWIDTH KATAKANA LETTER A..HALFWIDTH KATAKANA LETTER N
    ; between_unicode_range(0xFF9E, 0xFF9F, Character) % XID_Continue # Lm   [2] HALFWIDTH KATAKANA VOICED SOUND MARK..HALFWIDTH KATAKANA SEMI-VOICED SOUND MARK
    ; between_unicode_range(0xFFA0, 0xFFBE, Character) % XID_Continue # Lo  [31] HALFWIDTH HANGUL FILLER..HALFWIDTH HANGUL LETTER HIEUH
    ; between_unicode_range(0xFFC2, 0xFFC7, Character) % XID_Continue # Lo   [6] HALFWIDTH HANGUL LETTER A..HALFWIDTH HANGUL LETTER E
    ; between_unicode_range(0xFFCA, 0xFFCF, Character) % XID_Continue # Lo   [6] HALFWIDTH HANGUL LETTER YEO..HALFWIDTH HANGUL LETTER OE
    ; between_unicode_range(0xFFD2, 0xFFD7, Character) % XID_Continue # Lo   [6] HALFWIDTH HANGUL LETTER YO..HALFWIDTH HANGUL LETTER YU
    ; between_unicode_range(0xFFDA, 0xFFDC, Character) % XID_Continue # Lo   [3] HALFWIDTH HANGUL LETTER EU..HALFWIDTH HANGUL LETTER I
    ; between_unicode_range(0x10000, 0x1000B, Character) % XID_Continue # Lo  [12] LINEAR B SYLLABLE B008 A..LINEAR B SYLLABLE B046 JE
    ; between_unicode_range(0x1000D, 0x10026, Character) % XID_Continue # Lo  [26] LINEAR B SYLLABLE B036 JO..LINEAR B SYLLABLE B032 QO
    ; between_unicode_range(0x10028, 0x1003A, Character) % XID_Continue # Lo  [19] LINEAR B SYLLABLE B060 RA..LINEAR B SYLLABLE B042 WO
    ; between_unicode_range(0x1003C, 0x1003D, Character) % XID_Continue # Lo   [2] LINEAR B SYLLABLE B017 ZA..LINEAR B SYLLABLE B074 ZE
    ; between_unicode_range(0x1003F, 0x1004D, Character) % XID_Continue # Lo  [15] LINEAR B SYLLABLE B020 ZO..LINEAR B SYLLABLE B091 TWO
    ; between_unicode_range(0x10050, 0x1005D, Character) % XID_Continue # Lo  [14] LINEAR B SYMBOL B018..LINEAR B SYMBOL B089
    ; between_unicode_range(0x10080, 0x100FA, Character) % XID_Continue # Lo [123] LINEAR B IDEOGRAM B100 MAN..LINEAR B IDEOGRAM VESSEL B305
    ; between_unicode_range(0x10140, 0x10174, Character) % XID_Continue # Nl  [53] GREEK ACROPHONIC ATTIC ONE QUARTER..GREEK ACROPHONIC STRATIAN FIFTY MNAS
    ; unicode_character(0x101FD, Character) % XID_Continue # Mn       PHAISTOS DISC SIGN COMBINING OBLIQUE STROKE
    ; between_unicode_range(0x10280, 0x1029C, Character) % XID_Continue # Lo  [29] LYCIAN LETTER A..LYCIAN LETTER X
    ; between_unicode_range(0x102A0, 0x102D0, Character) % XID_Continue # Lo  [49] CARIAN LETTER A..CARIAN LETTER UUU3
    ; unicode_character(0x102E0, Character) % XID_Continue # Mn       COPTIC EPACT THOUSANDS MARK
    ; between_unicode_range(0x10300, 0x1031F, Character) % XID_Continue # Lo  [32] OLD ITALIC LETTER A..OLD ITALIC LETTER ESS
    ; between_unicode_range(0x1032D, 0x10340, Character) % XID_Continue # Lo  [20] OLD ITALIC LETTER YE..GOTHIC LETTER PAIRTHRA
    ; unicode_character(0x10341, Character) % XID_Continue # Nl       GOTHIC LETTER NINETY
    ; between_unicode_range(0x10342, 0x10349, Character) % XID_Continue # Lo   [8] GOTHIC LETTER RAIDA..GOTHIC LETTER OTHAL
    ; unicode_character(0x1034A, Character) % XID_Continue # Nl       GOTHIC LETTER NINE HUNDRED
    ; between_unicode_range(0x10350, 0x10375, Character) % XID_Continue # Lo  [38] OLD PERMIC LETTER AN..OLD PERMIC LETTER IA
    ; between_unicode_range(0x10376, 0x1037A, Character) % XID_Continue # Mn   [5] COMBINING OLD PERMIC LETTER AN..COMBINING OLD PERMIC LETTER SII
    ; between_unicode_range(0x10380, 0x1039D, Character) % XID_Continue # Lo  [30] UGARITIC LETTER ALPA..UGARITIC LETTER SSU
    ; between_unicode_range(0x103A0, 0x103C3, Character) % XID_Continue # Lo  [36] OLD PERSIAN SIGN A..OLD PERSIAN SIGN HA
    ; between_unicode_range(0x103C8, 0x103CF, Character) % XID_Continue # Lo   [8] OLD PERSIAN SIGN AURAMAZDAA..OLD PERSIAN SIGN BUUMISH
    ; between_unicode_range(0x103D1, 0x103D5, Character) % XID_Continue # Nl   [5] OLD PERSIAN NUMBER ONE..OLD PERSIAN NUMBER HUNDRED
    ; between_unicode_range(0x10400, 0x1044F, Character) % XID_Continue # L&  [80] DESERET CAPITAL LETTER LONG I..DESERET SMALL LETTER EW
    ; between_unicode_range(0x10450, 0x1049D, Character) % XID_Continue # Lo  [78] SHAVIAN LETTER PEEP..OSMANYA LETTER OO
    ; between_unicode_range(0x104A0, 0x104A9, Character) % XID_Continue # Nd  [10] OSMANYA DIGIT ZERO..OSMANYA DIGIT NINE
    ; between_unicode_range(0x104B0, 0x104D3, Character) % XID_Continue # L&  [36] OSAGE CAPITAL LETTER A..OSAGE CAPITAL LETTER ZHA
    ; between_unicode_range(0x104D8, 0x104FB, Character) % XID_Continue # L&  [36] OSAGE SMALL LETTER A..OSAGE SMALL LETTER ZHA
    ; between_unicode_range(0x10500, 0x10527, Character) % XID_Continue # Lo  [40] ELBASAN LETTER A..ELBASAN LETTER KHE
    ; between_unicode_range(0x10530, 0x10563, Character) % XID_Continue # Lo  [52] CAUCASIAN ALBANIAN LETTER ALT..CAUCASIAN ALBANIAN LETTER KIW
    ; between_unicode_range(0x10570, 0x1057A, Character) % XID_Continue # L&  [11] VITHKUQI CAPITAL LETTER A..VITHKUQI CAPITAL LETTER GA
    ; between_unicode_range(0x1057C, 0x1058A, Character) % XID_Continue # L&  [15] VITHKUQI CAPITAL LETTER HA..VITHKUQI CAPITAL LETTER RE
    ; between_unicode_range(0x1058C, 0x10592, Character) % XID_Continue # L&   [7] VITHKUQI CAPITAL LETTER SE..VITHKUQI CAPITAL LETTER XE
    ; between_unicode_range(0x10594, 0x10595, Character) % XID_Continue # L&   [2] VITHKUQI CAPITAL LETTER Y..VITHKUQI CAPITAL LETTER ZE
    ; between_unicode_range(0x10597, 0x105A1, Character) % XID_Continue # L&  [11] VITHKUQI SMALL LETTER A..VITHKUQI SMALL LETTER GA
    ; between_unicode_range(0x105A3, 0x105B1, Character) % XID_Continue # L&  [15] VITHKUQI SMALL LETTER HA..VITHKUQI SMALL LETTER RE
    ; between_unicode_range(0x105B3, 0x105B9, Character) % XID_Continue # L&   [7] VITHKUQI SMALL LETTER SE..VITHKUQI SMALL LETTER XE
    ; between_unicode_range(0x105BB, 0x105BC, Character) % XID_Continue # L&   [2] VITHKUQI SMALL LETTER Y..VITHKUQI SMALL LETTER ZE
    ; between_unicode_range(0x105C0, 0x105F3, Character) % XID_Continue # Lo  [52] TODHRI LETTER A..TODHRI LETTER OO
    ; between_unicode_range(0x10600, 0x10736, Character) % XID_Continue # Lo [311] LINEAR A SIGN AB001..LINEAR A SIGN A664
    ; between_unicode_range(0x10740, 0x10755, Character) % XID_Continue # Lo  [22] LINEAR A SIGN A701 A..LINEAR A SIGN A732 JE
    ; between_unicode_range(0x10760, 0x10767, Character) % XID_Continue # Lo   [8] LINEAR A SIGN A800..LINEAR A SIGN A807
    ; between_unicode_range(0x10780, 0x10785, Character) % XID_Continue # Lm   [6] MODIFIER LETTER SMALL CAPITAL AA..MODIFIER LETTER SMALL B WITH HOOK
    ; between_unicode_range(0x10787, 0x107B0, Character) % XID_Continue # Lm  [42] MODIFIER LETTER SMALL DZ DIGRAPH..MODIFIER LETTER SMALL V WITH RIGHT HOOK
    ; between_unicode_range(0x107B2, 0x107BA, Character) % XID_Continue # Lm   [9] MODIFIER LETTER SMALL CAPITAL Y..MODIFIER LETTER SMALL S WITH CURL
    ; between_unicode_range(0x10800, 0x10805, Character) % XID_Continue # Lo   [6] CYPRIOT SYLLABLE A..CYPRIOT SYLLABLE JA
    ; unicode_character(0x10808, Character) % XID_Continue # Lo       CYPRIOT SYLLABLE JO
    ; between_unicode_range(0x1080A, 0x10835, Character) % XID_Continue # Lo  [44] CYPRIOT SYLLABLE KA..CYPRIOT SYLLABLE WO
    ; between_unicode_range(0x10837, 0x10838, Character) % XID_Continue # Lo   [2] CYPRIOT SYLLABLE XA..CYPRIOT SYLLABLE XE
    ; unicode_character(0x1083C, Character) % XID_Continue # Lo       CYPRIOT SYLLABLE ZA
    ; between_unicode_range(0x1083F, 0x10855, Character) % XID_Continue # Lo  [23] CYPRIOT SYLLABLE ZO..IMPERIAL ARAMAIC LETTER TAW
    ; between_unicode_range(0x10860, 0x10876, Character) % XID_Continue # Lo  [23] PALMYRENE LETTER ALEPH..PALMYRENE LETTER TAW
    ; between_unicode_range(0x10880, 0x1089E, Character) % XID_Continue # Lo  [31] NABATAEAN LETTER FINAL ALEPH..NABATAEAN LETTER TAW
    ; between_unicode_range(0x108E0, 0x108F2, Character) % XID_Continue # Lo  [19] HATRAN LETTER ALEPH..HATRAN LETTER QOPH
    ; between_unicode_range(0x108F4, 0x108F5, Character) % XID_Continue # Lo   [2] HATRAN LETTER SHIN..HATRAN LETTER TAW
    ; between_unicode_range(0x10900, 0x10915, Character) % XID_Continue # Lo  [22] PHOENICIAN LETTER ALF..PHOENICIAN LETTER TAU
    ; between_unicode_range(0x10920, 0x10939, Character) % XID_Continue # Lo  [26] LYDIAN LETTER A..LYDIAN LETTER C
    ; between_unicode_range(0x10980, 0x109B7, Character) % XID_Continue # Lo  [56] MEROITIC HIEROGLYPHIC LETTER A..MEROITIC CURSIVE LETTER DA
    ; between_unicode_range(0x109BE, 0x109BF, Character) % XID_Continue # Lo   [2] MEROITIC CURSIVE LOGOGRAM RMT..MEROITIC CURSIVE LOGOGRAM IMN
    ; unicode_character(0x10A00, Character) % XID_Continue # Lo       KHAROSHTHI LETTER A
    ; between_unicode_range(0x10A01, 0x10A03, Character) % XID_Continue # Mn   [3] KHAROSHTHI VOWEL SIGN I..KHAROSHTHI VOWEL SIGN VOCALIC R
    ; between_unicode_range(0x10A05, 0x10A06, Character) % XID_Continue # Mn   [2] KHAROSHTHI VOWEL SIGN E..KHAROSHTHI VOWEL SIGN O
    ; between_unicode_range(0x10A0C, 0x10A0F, Character) % XID_Continue # Mn   [4] KHAROSHTHI VOWEL LENGTH MARK..KHAROSHTHI SIGN VISARGA
    ; between_unicode_range(0x10A10, 0x10A13, Character) % XID_Continue # Lo   [4] KHAROSHTHI LETTER KA..KHAROSHTHI LETTER GHA
    ; between_unicode_range(0x10A15, 0x10A17, Character) % XID_Continue # Lo   [3] KHAROSHTHI LETTER CA..KHAROSHTHI LETTER JA
    ; between_unicode_range(0x10A19, 0x10A35, Character) % XID_Continue # Lo  [29] KHAROSHTHI LETTER NYA..KHAROSHTHI LETTER VHA
    ; between_unicode_range(0x10A38, 0x10A3A, Character) % XID_Continue # Mn   [3] KHAROSHTHI SIGN BAR ABOVE..KHAROSHTHI SIGN DOT BELOW
    ; unicode_character(0x10A3F, Character) % XID_Continue # Mn       KHAROSHTHI VIRAMA
    ; between_unicode_range(0x10A60, 0x10A7C, Character) % XID_Continue # Lo  [29] OLD SOUTH ARABIAN LETTER HE..OLD SOUTH ARABIAN LETTER THETH
    ; between_unicode_range(0x10A80, 0x10A9C, Character) % XID_Continue # Lo  [29] OLD NORTH ARABIAN LETTER HEH..OLD NORTH ARABIAN LETTER ZAH
    ; between_unicode_range(0x10AC0, 0x10AC7, Character) % XID_Continue # Lo   [8] MANICHAEAN LETTER ALEPH..MANICHAEAN LETTER WAW
    ; between_unicode_range(0x10AC9, 0x10AE4, Character) % XID_Continue # Lo  [28] MANICHAEAN LETTER ZAYIN..MANICHAEAN LETTER TAW
    ; between_unicode_range(0x10AE5, 0x10AE6, Character) % XID_Continue # Mn   [2] MANICHAEAN ABBREVIATION MARK ABOVE..MANICHAEAN ABBREVIATION MARK BELOW
    ; between_unicode_range(0x10B00, 0x10B35, Character) % XID_Continue # Lo  [54] AVESTAN LETTER A..AVESTAN LETTER HE
    ; between_unicode_range(0x10B40, 0x10B55, Character) % XID_Continue # Lo  [22] INSCRIPTIONAL PARTHIAN LETTER ALEPH..INSCRIPTIONAL PARTHIAN LETTER TAW
    ; between_unicode_range(0x10B60, 0x10B72, Character) % XID_Continue # Lo  [19] INSCRIPTIONAL PAHLAVI LETTER ALEPH..INSCRIPTIONAL PAHLAVI LETTER TAW
    ; between_unicode_range(0x10B80, 0x10B91, Character) % XID_Continue # Lo  [18] PSALTER PAHLAVI LETTER ALEPH..PSALTER PAHLAVI LETTER TAW
    ; between_unicode_range(0x10C00, 0x10C48, Character) % XID_Continue # Lo  [73] OLD TURKIC LETTER ORKHON A..OLD TURKIC LETTER ORKHON BASH
    ; between_unicode_range(0x10C80, 0x10CB2, Character) % XID_Continue # L&  [51] OLD HUNGARIAN CAPITAL LETTER A..OLD HUNGARIAN CAPITAL LETTER US
    ; between_unicode_range(0x10CC0, 0x10CF2, Character) % XID_Continue # L&  [51] OLD HUNGARIAN SMALL LETTER A..OLD HUNGARIAN SMALL LETTER US
    ; between_unicode_range(0x10D00, 0x10D23, Character) % XID_Continue # Lo  [36] HANIFI ROHINGYA LETTER A..HANIFI ROHINGYA MARK NA KHONNA
    ; between_unicode_range(0x10D24, 0x10D27, Character) % XID_Continue # Mn   [4] HANIFI ROHINGYA SIGN HARBAHAY..HANIFI ROHINGYA SIGN TASSI
    ; between_unicode_range(0x10D30, 0x10D39, Character) % XID_Continue # Nd  [10] HANIFI ROHINGYA DIGIT ZERO..HANIFI ROHINGYA DIGIT NINE
    ; between_unicode_range(0x10D40, 0x10D49, Character) % XID_Continue # Nd  [10] GARAY DIGIT ZERO..GARAY DIGIT NINE
    ; between_unicode_range(0x10D4A, 0x10D4D, Character) % XID_Continue # Lo   [4] GARAY VOWEL SIGN A..GARAY VOWEL SIGN EE
    ; unicode_character(0x10D4E, Character) % XID_Continue # Lm       GARAY VOWEL LENGTH MARK
    ; unicode_character(0x10D4F, Character) % XID_Continue # Lo       GARAY SUKUN
    ; between_unicode_range(0x10D50, 0x10D65, Character) % XID_Continue # L&  [22] GARAY CAPITAL LETTER A..GARAY CAPITAL LETTER OLD NA
    ; between_unicode_range(0x10D69, 0x10D6D, Character) % XID_Continue # Mn   [5] GARAY VOWEL SIGN E..GARAY CONSONANT NASALIZATION MARK
    ; unicode_character(0x10D6F, Character) % XID_Continue # Lm       GARAY REDUPLICATION MARK
    ; between_unicode_range(0x10D70, 0x10D85, Character) % XID_Continue # L&  [22] GARAY SMALL LETTER A..GARAY SMALL LETTER OLD NA
    ; between_unicode_range(0x10E80, 0x10EA9, Character) % XID_Continue # Lo  [42] YEZIDI LETTER ELIF..YEZIDI LETTER ET
    ; between_unicode_range(0x10EAB, 0x10EAC, Character) % XID_Continue # Mn   [2] YEZIDI COMBINING HAMZA MARK..YEZIDI COMBINING MADDA MARK
    ; between_unicode_range(0x10EB0, 0x10EB1, Character) % XID_Continue # Lo   [2] YEZIDI LETTER LAM WITH DOT ABOVE..YEZIDI LETTER YOT WITH CIRCUMFLEX ABOVE
    ; between_unicode_range(0x10EC2, 0x10EC4, Character) % XID_Continue # Lo   [3] ARABIC LETTER DAL WITH TWO DOTS VERTICALLY BELOW..ARABIC LETTER KAF WITH TWO DOTS VERTICALLY BELOW
    ; between_unicode_range(0x10EFC, 0x10EFF, Character) % XID_Continue # Mn   [4] ARABIC COMBINING ALEF OVERLAY..ARABIC SMALL LOW WORD MADDA
    ; between_unicode_range(0x10F00, 0x10F1C, Character) % XID_Continue # Lo  [29] OLD SOGDIAN LETTER ALEPH..OLD SOGDIAN LETTER FINAL TAW WITH VERTICAL TAIL
    ; unicode_character(0x10F27, Character) % XID_Continue # Lo       OLD SOGDIAN LIGATURE AYIN-DALETH
    ; between_unicode_range(0x10F30, 0x10F45, Character) % XID_Continue # Lo  [22] SOGDIAN LETTER ALEPH..SOGDIAN INDEPENDENT SHIN
    ; between_unicode_range(0x10F46, 0x10F50, Character) % XID_Continue # Mn  [11] SOGDIAN COMBINING DOT BELOW..SOGDIAN COMBINING STROKE BELOW
    ; between_unicode_range(0x10F70, 0x10F81, Character) % XID_Continue # Lo  [18] OLD UYGHUR LETTER ALEPH..OLD UYGHUR LETTER LESH
    ; between_unicode_range(0x10F82, 0x10F85, Character) % XID_Continue # Mn   [4] OLD UYGHUR COMBINING DOT ABOVE..OLD UYGHUR COMBINING TWO DOTS BELOW
    ; between_unicode_range(0x10FB0, 0x10FC4, Character) % XID_Continue # Lo  [21] CHORASMIAN LETTER ALEPH..CHORASMIAN LETTER TAW
    ; between_unicode_range(0x10FE0, 0x10FF6, Character) % XID_Continue # Lo  [23] ELYMAIC LETTER ALEPH..ELYMAIC LIGATURE ZAYIN-YODH
    ; unicode_character(0x11000, Character) % XID_Continue # Mc       BRAHMI SIGN CANDRABINDU
    ; unicode_character(0x11001, Character) % XID_Continue # Mn       BRAHMI SIGN ANUSVARA
    ; unicode_character(0x11002, Character) % XID_Continue # Mc       BRAHMI SIGN VISARGA
    ; between_unicode_range(0x11003, 0x11037, Character) % XID_Continue # Lo  [53] BRAHMI SIGN JIHVAMULIYA..BRAHMI LETTER OLD TAMIL NNNA
    ; between_unicode_range(0x11038, 0x11046, Character) % XID_Continue # Mn  [15] BRAHMI VOWEL SIGN AA..BRAHMI VIRAMA
    ; between_unicode_range(0x11066, 0x1106F, Character) % XID_Continue # Nd  [10] BRAHMI DIGIT ZERO..BRAHMI DIGIT NINE
    ; unicode_character(0x11070, Character) % XID_Continue # Mn       BRAHMI SIGN OLD TAMIL VIRAMA
    ; between_unicode_range(0x11071, 0x11072, Character) % XID_Continue # Lo   [2] BRAHMI LETTER OLD TAMIL SHORT E..BRAHMI LETTER OLD TAMIL SHORT O
    ; between_unicode_range(0x11073, 0x11074, Character) % XID_Continue # Mn   [2] BRAHMI VOWEL SIGN OLD TAMIL SHORT E..BRAHMI VOWEL SIGN OLD TAMIL SHORT O
    ; unicode_character(0x11075, Character) % XID_Continue # Lo       BRAHMI LETTER OLD TAMIL LLA
    ; between_unicode_range(0x1107F, 0x11081, Character) % XID_Continue # Mn   [3] BRAHMI NUMBER JOINER..KAITHI SIGN ANUSVARA
    ; unicode_character(0x11082, Character) % XID_Continue # Mc       KAITHI SIGN VISARGA
    ; between_unicode_range(0x11083, 0x110AF, Character) % XID_Continue # Lo  [45] KAITHI LETTER A..KAITHI LETTER HA
    ; between_unicode_range(0x110B0, 0x110B2, Character) % XID_Continue # Mc   [3] KAITHI VOWEL SIGN AA..KAITHI VOWEL SIGN II
    ; between_unicode_range(0x110B3, 0x110B6, Character) % XID_Continue # Mn   [4] KAITHI VOWEL SIGN U..KAITHI VOWEL SIGN AI
    ; between_unicode_range(0x110B7, 0x110B8, Character) % XID_Continue # Mc   [2] KAITHI VOWEL SIGN O..KAITHI VOWEL SIGN AU
    ; between_unicode_range(0x110B9, 0x110BA, Character) % XID_Continue # Mn   [2] KAITHI SIGN VIRAMA..KAITHI SIGN NUKTA
    ; unicode_character(0x110C2, Character) % XID_Continue # Mn       KAITHI VOWEL SIGN VOCALIC R
    ; between_unicode_range(0x110D0, 0x110E8, Character) % XID_Continue # Lo  [25] SORA SOMPENG LETTER SAH..SORA SOMPENG LETTER MAE
    ; between_unicode_range(0x110F0, 0x110F9, Character) % XID_Continue # Nd  [10] SORA SOMPENG DIGIT ZERO..SORA SOMPENG DIGIT NINE
    ; between_unicode_range(0x11100, 0x11102, Character) % XID_Continue # Mn   [3] CHAKMA SIGN CANDRABINDU..CHAKMA SIGN VISARGA
    ; between_unicode_range(0x11103, 0x11126, Character) % XID_Continue # Lo  [36] CHAKMA LETTER AA..CHAKMA LETTER HAA
    ; between_unicode_range(0x11127, 0x1112B, Character) % XID_Continue # Mn   [5] CHAKMA VOWEL SIGN A..CHAKMA VOWEL SIGN UU
    ; unicode_character(0x1112C, Character) % XID_Continue # Mc       CHAKMA VOWEL SIGN E
    ; between_unicode_range(0x1112D, 0x11134, Character) % XID_Continue # Mn   [8] CHAKMA VOWEL SIGN AI..CHAKMA MAAYYAA
    ; between_unicode_range(0x11136, 0x1113F, Character) % XID_Continue # Nd  [10] CHAKMA DIGIT ZERO..CHAKMA DIGIT NINE
    ; unicode_character(0x11144, Character) % XID_Continue # Lo       CHAKMA LETTER LHAA
    ; between_unicode_range(0x11145, 0x11146, Character) % XID_Continue # Mc   [2] CHAKMA VOWEL SIGN AA..CHAKMA VOWEL SIGN EI
    ; unicode_character(0x11147, Character) % XID_Continue # Lo       CHAKMA LETTER VAA
    ; between_unicode_range(0x11150, 0x11172, Character) % XID_Continue # Lo  [35] MAHAJANI LETTER A..MAHAJANI LETTER RRA
    ; unicode_character(0x11173, Character) % XID_Continue # Mn       MAHAJANI SIGN NUKTA
    ; unicode_character(0x11176, Character) % XID_Continue # Lo       MAHAJANI LIGATURE SHRI
    ; between_unicode_range(0x11180, 0x11181, Character) % XID_Continue # Mn   [2] SHARADA SIGN CANDRABINDU..SHARADA SIGN ANUSVARA
    ; unicode_character(0x11182, Character) % XID_Continue # Mc       SHARADA SIGN VISARGA
    ; between_unicode_range(0x11183, 0x111B2, Character) % XID_Continue # Lo  [48] SHARADA LETTER A..SHARADA LETTER HA
    ; between_unicode_range(0x111B3, 0x111B5, Character) % XID_Continue # Mc   [3] SHARADA VOWEL SIGN AA..SHARADA VOWEL SIGN II
    ; between_unicode_range(0x111B6, 0x111BE, Character) % XID_Continue # Mn   [9] SHARADA VOWEL SIGN U..SHARADA VOWEL SIGN O
    ; between_unicode_range(0x111BF, 0x111C0, Character) % XID_Continue # Mc   [2] SHARADA VOWEL SIGN AU..SHARADA SIGN VIRAMA
    ; between_unicode_range(0x111C1, 0x111C4, Character) % XID_Continue # Lo   [4] SHARADA SIGN AVAGRAHA..SHARADA OM
    ; between_unicode_range(0x111C9, 0x111CC, Character) % XID_Continue # Mn   [4] SHARADA SANDHI MARK..SHARADA EXTRA SHORT VOWEL MARK
    ; unicode_character(0x111CE, Character) % XID_Continue # Mc       SHARADA VOWEL SIGN PRISHTHAMATRA E
    ; unicode_character(0x111CF, Character) % XID_Continue # Mn       SHARADA SIGN INVERTED CANDRABINDU
    ; between_unicode_range(0x111D0, 0x111D9, Character) % XID_Continue # Nd  [10] SHARADA DIGIT ZERO..SHARADA DIGIT NINE
    ; unicode_character(0x111DA, Character) % XID_Continue # Lo       SHARADA EKAM
    ; unicode_character(0x111DC, Character) % XID_Continue # Lo       SHARADA HEADSTROKE
    ; between_unicode_range(0x11200, 0x11211, Character) % XID_Continue # Lo  [18] KHOJKI LETTER A..KHOJKI LETTER JJA
    ; between_unicode_range(0x11213, 0x1122B, Character) % XID_Continue # Lo  [25] KHOJKI LETTER NYA..KHOJKI LETTER LLA
    ; between_unicode_range(0x1122C, 0x1122E, Character) % XID_Continue # Mc   [3] KHOJKI VOWEL SIGN AA..KHOJKI VOWEL SIGN II
    ; between_unicode_range(0x1122F, 0x11231, Character) % XID_Continue # Mn   [3] KHOJKI VOWEL SIGN U..KHOJKI VOWEL SIGN AI
    ; between_unicode_range(0x11232, 0x11233, Character) % XID_Continue # Mc   [2] KHOJKI VOWEL SIGN O..KHOJKI VOWEL SIGN AU
    ; unicode_character(0x11234, Character) % XID_Continue # Mn       KHOJKI SIGN ANUSVARA
    ; unicode_character(0x11235, Character) % XID_Continue # Mc       KHOJKI SIGN VIRAMA
    ; between_unicode_range(0x11236, 0x11237, Character) % XID_Continue # Mn   [2] KHOJKI SIGN NUKTA..KHOJKI SIGN SHADDA
    ; unicode_character(0x1123E, Character) % XID_Continue # Mn       KHOJKI SIGN SUKUN
    ; between_unicode_range(0x1123F, 0x11240, Character) % XID_Continue # Lo   [2] KHOJKI LETTER QA..KHOJKI LETTER SHORT I
    ; unicode_character(0x11241, Character) % XID_Continue # Mn       KHOJKI VOWEL SIGN VOCALIC R
    ; between_unicode_range(0x11280, 0x11286, Character) % XID_Continue # Lo   [7] MULTANI LETTER A..MULTANI LETTER GA
    ; unicode_character(0x11288, Character) % XID_Continue # Lo       MULTANI LETTER GHA
    ; between_unicode_range(0x1128A, 0x1128D, Character) % XID_Continue # Lo   [4] MULTANI LETTER CA..MULTANI LETTER JJA
    ; between_unicode_range(0x1128F, 0x1129D, Character) % XID_Continue # Lo  [15] MULTANI LETTER NYA..MULTANI LETTER BA
    ; between_unicode_range(0x1129F, 0x112A8, Character) % XID_Continue # Lo  [10] MULTANI LETTER BHA..MULTANI LETTER RHA
    ; between_unicode_range(0x112B0, 0x112DE, Character) % XID_Continue # Lo  [47] KHUDAWADI LETTER A..KHUDAWADI LETTER HA
    ; unicode_character(0x112DF, Character) % XID_Continue # Mn       KHUDAWADI SIGN ANUSVARA
    ; between_unicode_range(0x112E0, 0x112E2, Character) % XID_Continue # Mc   [3] KHUDAWADI VOWEL SIGN AA..KHUDAWADI VOWEL SIGN II
    ; between_unicode_range(0x112E3, 0x112EA, Character) % XID_Continue # Mn   [8] KHUDAWADI VOWEL SIGN U..KHUDAWADI SIGN VIRAMA
    ; between_unicode_range(0x112F0, 0x112F9, Character) % XID_Continue # Nd  [10] KHUDAWADI DIGIT ZERO..KHUDAWADI DIGIT NINE
    ; between_unicode_range(0x11300, 0x11301, Character) % XID_Continue # Mn   [2] GRANTHA SIGN COMBINING ANUSVARA ABOVE..GRANTHA SIGN CANDRABINDU
    ; between_unicode_range(0x11302, 0x11303, Character) % XID_Continue # Mc   [2] GRANTHA SIGN ANUSVARA..GRANTHA SIGN VISARGA
    ; between_unicode_range(0x11305, 0x1130C, Character) % XID_Continue # Lo   [8] GRANTHA LETTER A..GRANTHA LETTER VOCALIC L
    ; between_unicode_range(0x1130F, 0x11310, Character) % XID_Continue # Lo   [2] GRANTHA LETTER EE..GRANTHA LETTER AI
    ; between_unicode_range(0x11313, 0x11328, Character) % XID_Continue # Lo  [22] GRANTHA LETTER OO..GRANTHA LETTER NA
    ; between_unicode_range(0x1132A, 0x11330, Character) % XID_Continue # Lo   [7] GRANTHA LETTER PA..GRANTHA LETTER RA
    ; between_unicode_range(0x11332, 0x11333, Character) % XID_Continue # Lo   [2] GRANTHA LETTER LA..GRANTHA LETTER LLA
    ; between_unicode_range(0x11335, 0x11339, Character) % XID_Continue # Lo   [5] GRANTHA LETTER VA..GRANTHA LETTER HA
    ; between_unicode_range(0x1133B, 0x1133C, Character) % XID_Continue # Mn   [2] COMBINING BINDU BELOW..GRANTHA SIGN NUKTA
    ; unicode_character(0x1133D, Character) % XID_Continue # Lo       GRANTHA SIGN AVAGRAHA
    ; between_unicode_range(0x1133E, 0x1133F, Character) % XID_Continue # Mc   [2] GRANTHA VOWEL SIGN AA..GRANTHA VOWEL SIGN I
    ; unicode_character(0x11340, Character) % XID_Continue # Mn       GRANTHA VOWEL SIGN II
    ; between_unicode_range(0x11341, 0x11344, Character) % XID_Continue # Mc   [4] GRANTHA VOWEL SIGN U..GRANTHA VOWEL SIGN VOCALIC RR
    ; between_unicode_range(0x11347, 0x11348, Character) % XID_Continue # Mc   [2] GRANTHA VOWEL SIGN EE..GRANTHA VOWEL SIGN AI
    ; between_unicode_range(0x1134B, 0x1134D, Character) % XID_Continue # Mc   [3] GRANTHA VOWEL SIGN OO..GRANTHA SIGN VIRAMA
    ; unicode_character(0x11350, Character) % XID_Continue # Lo       GRANTHA OM
    ; unicode_character(0x11357, Character) % XID_Continue # Mc       GRANTHA AU LENGTH MARK
    ; between_unicode_range(0x1135D, 0x11361, Character) % XID_Continue # Lo   [5] GRANTHA SIGN PLUTA..GRANTHA LETTER VOCALIC LL
    ; between_unicode_range(0x11362, 0x11363, Character) % XID_Continue # Mc   [2] GRANTHA VOWEL SIGN VOCALIC L..GRANTHA VOWEL SIGN VOCALIC LL
    ; between_unicode_range(0x11366, 0x1136C, Character) % XID_Continue # Mn   [7] COMBINING GRANTHA DIGIT ZERO..COMBINING GRANTHA DIGIT SIX
    ; between_unicode_range(0x11370, 0x11374, Character) % XID_Continue # Mn   [5] COMBINING GRANTHA LETTER A..COMBINING GRANTHA LETTER PA
    ; between_unicode_range(0x11380, 0x11389, Character) % XID_Continue # Lo  [10] TULU-TIGALARI LETTER A..TULU-TIGALARI LETTER VOCALIC LL
    ; unicode_character(0x1138B, Character) % XID_Continue # Lo       TULU-TIGALARI LETTER EE
    ; unicode_character(0x1138E, Character) % XID_Continue # Lo       TULU-TIGALARI LETTER AI
    ; between_unicode_range(0x11390, 0x113B5, Character) % XID_Continue # Lo  [38] TULU-TIGALARI LETTER OO..TULU-TIGALARI LETTER LLLA
    ; unicode_character(0x113B7, Character) % XID_Continue # Lo       TULU-TIGALARI SIGN AVAGRAHA
    ; between_unicode_range(0x113B8, 0x113BA, Character) % XID_Continue # Mc   [3] TULU-TIGALARI VOWEL SIGN AA..TULU-TIGALARI VOWEL SIGN II
    ; between_unicode_range(0x113BB, 0x113C0, Character) % XID_Continue # Mn   [6] TULU-TIGALARI VOWEL SIGN U..TULU-TIGALARI VOWEL SIGN VOCALIC LL
    ; unicode_character(0x113C2, Character) % XID_Continue # Mc       TULU-TIGALARI VOWEL SIGN EE
    ; unicode_character(0x113C5, Character) % XID_Continue # Mc       TULU-TIGALARI VOWEL SIGN AI
    ; between_unicode_range(0x113C7, 0x113CA, Character) % XID_Continue # Mc   [4] TULU-TIGALARI VOWEL SIGN OO..TULU-TIGALARI SIGN CANDRA ANUNASIKA
    ; between_unicode_range(0x113CC, 0x113CD, Character) % XID_Continue # Mc   [2] TULU-TIGALARI SIGN ANUSVARA..TULU-TIGALARI SIGN VISARGA
    ; unicode_character(0x113CE, Character) % XID_Continue # Mn       TULU-TIGALARI SIGN VIRAMA
    ; unicode_character(0x113CF, Character) % XID_Continue # Mc       TULU-TIGALARI SIGN LOOPED VIRAMA
    ; unicode_character(0x113D0, Character) % XID_Continue # Mn       TULU-TIGALARI CONJOINER
    ; unicode_character(0x113D1, Character) % XID_Continue # Lo       TULU-TIGALARI REPHA
    ; unicode_character(0x113D2, Character) % XID_Continue # Mn       TULU-TIGALARI GEMINATION MARK
    ; unicode_character(0x113D3, Character) % XID_Continue # Lo       TULU-TIGALARI SIGN PLUTA
    ; between_unicode_range(0x113E1, 0x113E2, Character) % XID_Continue # Mn   [2] TULU-TIGALARI VEDIC TONE SVARITA..TULU-TIGALARI VEDIC TONE ANUDATTA
    ; between_unicode_range(0x11400, 0x11434, Character) % XID_Continue # Lo  [53] NEWA LETTER A..NEWA LETTER HA
    ; between_unicode_range(0x11435, 0x11437, Character) % XID_Continue # Mc   [3] NEWA VOWEL SIGN AA..NEWA VOWEL SIGN II
    ; between_unicode_range(0x11438, 0x1143F, Character) % XID_Continue # Mn   [8] NEWA VOWEL SIGN U..NEWA VOWEL SIGN AI
    ; between_unicode_range(0x11440, 0x11441, Character) % XID_Continue # Mc   [2] NEWA VOWEL SIGN O..NEWA VOWEL SIGN AU
    ; between_unicode_range(0x11442, 0x11444, Character) % XID_Continue # Mn   [3] NEWA SIGN VIRAMA..NEWA SIGN ANUSVARA
    ; unicode_character(0x11445, Character) % XID_Continue # Mc       NEWA SIGN VISARGA
    ; unicode_character(0x11446, Character) % XID_Continue # Mn       NEWA SIGN NUKTA
    ; between_unicode_range(0x11447, 0x1144A, Character) % XID_Continue # Lo   [4] NEWA SIGN AVAGRAHA..NEWA SIDDHI
    ; between_unicode_range(0x11450, 0x11459, Character) % XID_Continue # Nd  [10] NEWA DIGIT ZERO..NEWA DIGIT NINE
    ; unicode_character(0x1145E, Character) % XID_Continue # Mn       NEWA SANDHI MARK
    ; between_unicode_range(0x1145F, 0x11461, Character) % XID_Continue # Lo   [3] NEWA LETTER VEDIC ANUSVARA..NEWA SIGN UPADHMANIYA
    ; between_unicode_range(0x11480, 0x114AF, Character) % XID_Continue # Lo  [48] TIRHUTA ANJI..TIRHUTA LETTER HA
    ; between_unicode_range(0x114B0, 0x114B2, Character) % XID_Continue # Mc   [3] TIRHUTA VOWEL SIGN AA..TIRHUTA VOWEL SIGN II
    ; between_unicode_range(0x114B3, 0x114B8, Character) % XID_Continue # Mn   [6] TIRHUTA VOWEL SIGN U..TIRHUTA VOWEL SIGN VOCALIC LL
    ; unicode_character(0x114B9, Character) % XID_Continue # Mc       TIRHUTA VOWEL SIGN E
    ; unicode_character(0x114BA, Character) % XID_Continue # Mn       TIRHUTA VOWEL SIGN SHORT E
    ; between_unicode_range(0x114BB, 0x114BE, Character) % XID_Continue # Mc   [4] TIRHUTA VOWEL SIGN AI..TIRHUTA VOWEL SIGN AU
    ; between_unicode_range(0x114BF, 0x114C0, Character) % XID_Continue # Mn   [2] TIRHUTA SIGN CANDRABINDU..TIRHUTA SIGN ANUSVARA
    ; unicode_character(0x114C1, Character) % XID_Continue # Mc       TIRHUTA SIGN VISARGA
    ; between_unicode_range(0x114C2, 0x114C3, Character) % XID_Continue # Mn   [2] TIRHUTA SIGN VIRAMA..TIRHUTA SIGN NUKTA
    ; between_unicode_range(0x114C4, 0x114C5, Character) % XID_Continue # Lo   [2] TIRHUTA SIGN AVAGRAHA..TIRHUTA GVANG
    ; unicode_character(0x114C7, Character) % XID_Continue # Lo       TIRHUTA OM
    ; between_unicode_range(0x114D0, 0x114D9, Character) % XID_Continue # Nd  [10] TIRHUTA DIGIT ZERO..TIRHUTA DIGIT NINE
    ; between_unicode_range(0x11580, 0x115AE, Character) % XID_Continue # Lo  [47] SIDDHAM LETTER A..SIDDHAM LETTER HA
    ; between_unicode_range(0x115AF, 0x115B1, Character) % XID_Continue # Mc   [3] SIDDHAM VOWEL SIGN AA..SIDDHAM VOWEL SIGN II
    ; between_unicode_range(0x115B2, 0x115B5, Character) % XID_Continue # Mn   [4] SIDDHAM VOWEL SIGN U..SIDDHAM VOWEL SIGN VOCALIC RR
    ; between_unicode_range(0x115B8, 0x115BB, Character) % XID_Continue # Mc   [4] SIDDHAM VOWEL SIGN E..SIDDHAM VOWEL SIGN AU
    ; between_unicode_range(0x115BC, 0x115BD, Character) % XID_Continue # Mn   [2] SIDDHAM SIGN CANDRABINDU..SIDDHAM SIGN ANUSVARA
    ; unicode_character(0x115BE, Character) % XID_Continue # Mc       SIDDHAM SIGN VISARGA
    ; between_unicode_range(0x115BF, 0x115C0, Character) % XID_Continue # Mn   [2] SIDDHAM SIGN VIRAMA..SIDDHAM SIGN NUKTA
    ; between_unicode_range(0x115D8, 0x115DB, Character) % XID_Continue # Lo   [4] SIDDHAM LETTER THREE-CIRCLE ALTERNATE I..SIDDHAM LETTER ALTERNATE U
    ; between_unicode_range(0x115DC, 0x115DD, Character) % XID_Continue # Mn   [2] SIDDHAM VOWEL SIGN ALTERNATE U..SIDDHAM VOWEL SIGN ALTERNATE UU
    ; between_unicode_range(0x11600, 0x1162F, Character) % XID_Continue # Lo  [48] MODI LETTER A..MODI LETTER LLA
    ; between_unicode_range(0x11630, 0x11632, Character) % XID_Continue # Mc   [3] MODI VOWEL SIGN AA..MODI VOWEL SIGN II
    ; between_unicode_range(0x11633, 0x1163A, Character) % XID_Continue # Mn   [8] MODI VOWEL SIGN U..MODI VOWEL SIGN AI
    ; between_unicode_range(0x1163B, 0x1163C, Character) % XID_Continue # Mc   [2] MODI VOWEL SIGN O..MODI VOWEL SIGN AU
    ; unicode_character(0x1163D, Character) % XID_Continue # Mn       MODI SIGN ANUSVARA
    ; unicode_character(0x1163E, Character) % XID_Continue # Mc       MODI SIGN VISARGA
    ; between_unicode_range(0x1163F, 0x11640, Character) % XID_Continue # Mn   [2] MODI SIGN VIRAMA..MODI SIGN ARDHACANDRA
    ; unicode_character(0x11644, Character) % XID_Continue # Lo       MODI SIGN HUVA
    ; between_unicode_range(0x11650, 0x11659, Character) % XID_Continue # Nd  [10] MODI DIGIT ZERO..MODI DIGIT NINE
    ; between_unicode_range(0x11680, 0x116AA, Character) % XID_Continue # Lo  [43] TAKRI LETTER A..TAKRI LETTER RRA
    ; unicode_character(0x116AB, Character) % XID_Continue # Mn       TAKRI SIGN ANUSVARA
    ; unicode_character(0x116AC, Character) % XID_Continue # Mc       TAKRI SIGN VISARGA
    ; unicode_character(0x116AD, Character) % XID_Continue # Mn       TAKRI VOWEL SIGN AA
    ; between_unicode_range(0x116AE, 0x116AF, Character) % XID_Continue # Mc   [2] TAKRI VOWEL SIGN I..TAKRI VOWEL SIGN II
    ; between_unicode_range(0x116B0, 0x116B5, Character) % XID_Continue # Mn   [6] TAKRI VOWEL SIGN U..TAKRI VOWEL SIGN AU
    ; unicode_character(0x116B6, Character) % XID_Continue # Mc       TAKRI SIGN VIRAMA
    ; unicode_character(0x116B7, Character) % XID_Continue # Mn       TAKRI SIGN NUKTA
    ; unicode_character(0x116B8, Character) % XID_Continue # Lo       TAKRI LETTER ARCHAIC KHA
    ; between_unicode_range(0x116C0, 0x116C9, Character) % XID_Continue # Nd  [10] TAKRI DIGIT ZERO..TAKRI DIGIT NINE
    ; between_unicode_range(0x116D0, 0x116E3, Character) % XID_Continue # Nd  [20] MYANMAR PAO DIGIT ZERO..MYANMAR EASTERN PWO KAREN DIGIT NINE
    ; between_unicode_range(0x11700, 0x1171A, Character) % XID_Continue # Lo  [27] AHOM LETTER KA..AHOM LETTER ALTERNATE BA
    ; unicode_character(0x1171D, Character) % XID_Continue # Mn       AHOM CONSONANT SIGN MEDIAL LA
    ; unicode_character(0x1171E, Character) % XID_Continue # Mc       AHOM CONSONANT SIGN MEDIAL RA
    ; unicode_character(0x1171F, Character) % XID_Continue # Mn       AHOM CONSONANT SIGN MEDIAL LIGATING RA
    ; between_unicode_range(0x11720, 0x11721, Character) % XID_Continue # Mc   [2] AHOM VOWEL SIGN A..AHOM VOWEL SIGN AA
    ; between_unicode_range(0x11722, 0x11725, Character) % XID_Continue # Mn   [4] AHOM VOWEL SIGN I..AHOM VOWEL SIGN UU
    ; unicode_character(0x11726, Character) % XID_Continue # Mc       AHOM VOWEL SIGN E
    ; between_unicode_range(0x11727, 0x1172B, Character) % XID_Continue # Mn   [5] AHOM VOWEL SIGN AW..AHOM SIGN KILLER
    ; between_unicode_range(0x11730, 0x11739, Character) % XID_Continue # Nd  [10] AHOM DIGIT ZERO..AHOM DIGIT NINE
    ; between_unicode_range(0x11740, 0x11746, Character) % XID_Continue # Lo   [7] AHOM LETTER CA..AHOM LETTER LLA
    ; between_unicode_range(0x11800, 0x1182B, Character) % XID_Continue # Lo  [44] DOGRA LETTER A..DOGRA LETTER RRA
    ; between_unicode_range(0x1182C, 0x1182E, Character) % XID_Continue # Mc   [3] DOGRA VOWEL SIGN AA..DOGRA VOWEL SIGN II
    ; between_unicode_range(0x1182F, 0x11837, Character) % XID_Continue # Mn   [9] DOGRA VOWEL SIGN U..DOGRA SIGN ANUSVARA
    ; unicode_character(0x11838, Character) % XID_Continue # Mc       DOGRA SIGN VISARGA
    ; between_unicode_range(0x11839, 0x1183A, Character) % XID_Continue # Mn   [2] DOGRA SIGN VIRAMA..DOGRA SIGN NUKTA
    ; between_unicode_range(0x118A0, 0x118DF, Character) % XID_Continue # L&  [64] WARANG CITI CAPITAL LETTER NGAA..WARANG CITI SMALL LETTER VIYO
    ; between_unicode_range(0x118E0, 0x118E9, Character) % XID_Continue # Nd  [10] WARANG CITI DIGIT ZERO..WARANG CITI DIGIT NINE
    ; between_unicode_range(0x118FF, 0x11906, Character) % XID_Continue # Lo   [8] WARANG CITI OM..DIVES AKURU LETTER E
    ; unicode_character(0x11909, Character) % XID_Continue # Lo       DIVES AKURU LETTER O
    ; between_unicode_range(0x1190C, 0x11913, Character) % XID_Continue # Lo   [8] DIVES AKURU LETTER KA..DIVES AKURU LETTER JA
    ; between_unicode_range(0x11915, 0x11916, Character) % XID_Continue # Lo   [2] DIVES AKURU LETTER NYA..DIVES AKURU LETTER TTA
    ; between_unicode_range(0x11918, 0x1192F, Character) % XID_Continue # Lo  [24] DIVES AKURU LETTER DDA..DIVES AKURU LETTER ZA
    ; between_unicode_range(0x11930, 0x11935, Character) % XID_Continue # Mc   [6] DIVES AKURU VOWEL SIGN AA..DIVES AKURU VOWEL SIGN E
    ; between_unicode_range(0x11937, 0x11938, Character) % XID_Continue # Mc   [2] DIVES AKURU VOWEL SIGN AI..DIVES AKURU VOWEL SIGN O
    ; between_unicode_range(0x1193B, 0x1193C, Character) % XID_Continue # Mn   [2] DIVES AKURU SIGN ANUSVARA..DIVES AKURU SIGN CANDRABINDU
    ; unicode_character(0x1193D, Character) % XID_Continue # Mc       DIVES AKURU SIGN HALANTA
    ; unicode_character(0x1193E, Character) % XID_Continue # Mn       DIVES AKURU VIRAMA
    ; unicode_character(0x1193F, Character) % XID_Continue # Lo       DIVES AKURU PREFIXED NASAL SIGN
    ; unicode_character(0x11940, Character) % XID_Continue # Mc       DIVES AKURU MEDIAL YA
    ; unicode_character(0x11941, Character) % XID_Continue # Lo       DIVES AKURU INITIAL RA
    ; unicode_character(0x11942, Character) % XID_Continue # Mc       DIVES AKURU MEDIAL RA
    ; unicode_character(0x11943, Character) % XID_Continue # Mn       DIVES AKURU SIGN NUKTA
    ; between_unicode_range(0x11950, 0x11959, Character) % XID_Continue # Nd  [10] DIVES AKURU DIGIT ZERO..DIVES AKURU DIGIT NINE
    ; between_unicode_range(0x119A0, 0x119A7, Character) % XID_Continue # Lo   [8] NANDINAGARI LETTER A..NANDINAGARI LETTER VOCALIC RR
    ; between_unicode_range(0x119AA, 0x119D0, Character) % XID_Continue # Lo  [39] NANDINAGARI LETTER E..NANDINAGARI LETTER RRA
    ; between_unicode_range(0x119D1, 0x119D3, Character) % XID_Continue # Mc   [3] NANDINAGARI VOWEL SIGN AA..NANDINAGARI VOWEL SIGN II
    ; between_unicode_range(0x119D4, 0x119D7, Character) % XID_Continue # Mn   [4] NANDINAGARI VOWEL SIGN U..NANDINAGARI VOWEL SIGN VOCALIC RR
    ; between_unicode_range(0x119DA, 0x119DB, Character) % XID_Continue # Mn   [2] NANDINAGARI VOWEL SIGN E..NANDINAGARI VOWEL SIGN AI
    ; between_unicode_range(0x119DC, 0x119DF, Character) % XID_Continue # Mc   [4] NANDINAGARI VOWEL SIGN O..NANDINAGARI SIGN VISARGA
    ; unicode_character(0x119E0, Character) % XID_Continue # Mn       NANDINAGARI SIGN VIRAMA
    ; unicode_character(0x119E1, Character) % XID_Continue # Lo       NANDINAGARI SIGN AVAGRAHA
    ; unicode_character(0x119E3, Character) % XID_Continue # Lo       NANDINAGARI HEADSTROKE
    ; unicode_character(0x119E4, Character) % XID_Continue # Mc       NANDINAGARI VOWEL SIGN PRISHTHAMATRA E
    ; unicode_character(0x11A00, Character) % XID_Continue # Lo       ZANABAZAR SQUARE LETTER A
    ; between_unicode_range(0x11A01, 0x11A0A, Character) % XID_Continue # Mn  [10] ZANABAZAR SQUARE VOWEL SIGN I..ZANABAZAR SQUARE VOWEL LENGTH MARK
    ; between_unicode_range(0x11A0B, 0x11A32, Character) % XID_Continue # Lo  [40] ZANABAZAR SQUARE LETTER KA..ZANABAZAR SQUARE LETTER KSSA
    ; between_unicode_range(0x11A33, 0x11A38, Character) % XID_Continue # Mn   [6] ZANABAZAR SQUARE FINAL CONSONANT MARK..ZANABAZAR SQUARE SIGN ANUSVARA
    ; unicode_character(0x11A39, Character) % XID_Continue # Mc       ZANABAZAR SQUARE SIGN VISARGA
    ; unicode_character(0x11A3A, Character) % XID_Continue # Lo       ZANABAZAR SQUARE CLUSTER-INITIAL LETTER RA
    ; between_unicode_range(0x11A3B, 0x11A3E, Character) % XID_Continue # Mn   [4] ZANABAZAR SQUARE CLUSTER-FINAL LETTER YA..ZANABAZAR SQUARE CLUSTER-FINAL LETTER VA
    ; unicode_character(0x11A47, Character) % XID_Continue # Mn       ZANABAZAR SQUARE SUBJOINER
    ; unicode_character(0x11A50, Character) % XID_Continue # Lo       SOYOMBO LETTER A
    ; between_unicode_range(0x11A51, 0x11A56, Character) % XID_Continue # Mn   [6] SOYOMBO VOWEL SIGN I..SOYOMBO VOWEL SIGN OE
    ; between_unicode_range(0x11A57, 0x11A58, Character) % XID_Continue # Mc   [2] SOYOMBO VOWEL SIGN AI..SOYOMBO VOWEL SIGN AU
    ; between_unicode_range(0x11A59, 0x11A5B, Character) % XID_Continue # Mn   [3] SOYOMBO VOWEL SIGN VOCALIC R..SOYOMBO VOWEL LENGTH MARK
    ; between_unicode_range(0x11A5C, 0x11A89, Character) % XID_Continue # Lo  [46] SOYOMBO LETTER KA..SOYOMBO CLUSTER-INITIAL LETTER SA
    ; between_unicode_range(0x11A8A, 0x11A96, Character) % XID_Continue # Mn  [13] SOYOMBO FINAL CONSONANT SIGN G..SOYOMBO SIGN ANUSVARA
    ; unicode_character(0x11A97, Character) % XID_Continue # Mc       SOYOMBO SIGN VISARGA
    ; between_unicode_range(0x11A98, 0x11A99, Character) % XID_Continue # Mn   [2] SOYOMBO GEMINATION MARK..SOYOMBO SUBJOINER
    ; unicode_character(0x11A9D, Character) % XID_Continue # Lo       SOYOMBO MARK PLUTA
    ; between_unicode_range(0x11AB0, 0x11AF8, Character) % XID_Continue # Lo  [73] CANADIAN SYLLABICS NATTILIK HI..PAU CIN HAU GLOTTAL STOP FINAL
    ; between_unicode_range(0x11BC0, 0x11BE0, Character) % XID_Continue # Lo  [33] SUNUWAR LETTER DEVI..SUNUWAR LETTER KLOKO
    ; between_unicode_range(0x11BF0, 0x11BF9, Character) % XID_Continue # Nd  [10] SUNUWAR DIGIT ZERO..SUNUWAR DIGIT NINE
    ; between_unicode_range(0x11C00, 0x11C08, Character) % XID_Continue # Lo   [9] BHAIKSUKI LETTER A..BHAIKSUKI LETTER VOCALIC L
    ; between_unicode_range(0x11C0A, 0x11C2E, Character) % XID_Continue # Lo  [37] BHAIKSUKI LETTER E..BHAIKSUKI LETTER HA
    ; unicode_character(0x11C2F, Character) % XID_Continue # Mc       BHAIKSUKI VOWEL SIGN AA
    ; between_unicode_range(0x11C30, 0x11C36, Character) % XID_Continue # Mn   [7] BHAIKSUKI VOWEL SIGN I..BHAIKSUKI VOWEL SIGN VOCALIC L
    ; between_unicode_range(0x11C38, 0x11C3D, Character) % XID_Continue # Mn   [6] BHAIKSUKI VOWEL SIGN E..BHAIKSUKI SIGN ANUSVARA
    ; unicode_character(0x11C3E, Character) % XID_Continue # Mc       BHAIKSUKI SIGN VISARGA
    ; unicode_character(0x11C3F, Character) % XID_Continue # Mn       BHAIKSUKI SIGN VIRAMA
    ; unicode_character(0x11C40, Character) % XID_Continue # Lo       BHAIKSUKI SIGN AVAGRAHA
    ; between_unicode_range(0x11C50, 0x11C59, Character) % XID_Continue # Nd  [10] BHAIKSUKI DIGIT ZERO..BHAIKSUKI DIGIT NINE
    ; between_unicode_range(0x11C72, 0x11C8F, Character) % XID_Continue # Lo  [30] MARCHEN LETTER KA..MARCHEN LETTER A
    ; between_unicode_range(0x11C92, 0x11CA7, Character) % XID_Continue # Mn  [22] MARCHEN SUBJOINED LETTER KA..MARCHEN SUBJOINED LETTER ZA
    ; unicode_character(0x11CA9, Character) % XID_Continue # Mc       MARCHEN SUBJOINED LETTER YA
    ; between_unicode_range(0x11CAA, 0x11CB0, Character) % XID_Continue # Mn   [7] MARCHEN SUBJOINED LETTER RA..MARCHEN VOWEL SIGN AA
    ; unicode_character(0x11CB1, Character) % XID_Continue # Mc       MARCHEN VOWEL SIGN I
    ; between_unicode_range(0x11CB2, 0x11CB3, Character) % XID_Continue # Mn   [2] MARCHEN VOWEL SIGN U..MARCHEN VOWEL SIGN E
    ; unicode_character(0x11CB4, Character) % XID_Continue # Mc       MARCHEN VOWEL SIGN O
    ; between_unicode_range(0x11CB5, 0x11CB6, Character) % XID_Continue # Mn   [2] MARCHEN SIGN ANUSVARA..MARCHEN SIGN CANDRABINDU
    ; between_unicode_range(0x11D00, 0x11D06, Character) % XID_Continue # Lo   [7] MASARAM GONDI LETTER A..MASARAM GONDI LETTER E
    ; between_unicode_range(0x11D08, 0x11D09, Character) % XID_Continue # Lo   [2] MASARAM GONDI LETTER AI..MASARAM GONDI LETTER O
    ; between_unicode_range(0x11D0B, 0x11D30, Character) % XID_Continue # Lo  [38] MASARAM GONDI LETTER AU..MASARAM GONDI LETTER TRA
    ; between_unicode_range(0x11D31, 0x11D36, Character) % XID_Continue # Mn   [6] MASARAM GONDI VOWEL SIGN AA..MASARAM GONDI VOWEL SIGN VOCALIC R
    ; unicode_character(0x11D3A, Character) % XID_Continue # Mn       MASARAM GONDI VOWEL SIGN E
    ; between_unicode_range(0x11D3C, 0x11D3D, Character) % XID_Continue # Mn   [2] MASARAM GONDI VOWEL SIGN AI..MASARAM GONDI VOWEL SIGN O
    ; between_unicode_range(0x11D3F, 0x11D45, Character) % XID_Continue # Mn   [7] MASARAM GONDI VOWEL SIGN AU..MASARAM GONDI VIRAMA
    ; unicode_character(0x11D46, Character) % XID_Continue # Lo       MASARAM GONDI REPHA
    ; unicode_character(0x11D47, Character) % XID_Continue # Mn       MASARAM GONDI RA-KARA
    ; between_unicode_range(0x11D50, 0x11D59, Character) % XID_Continue # Nd  [10] MASARAM GONDI DIGIT ZERO..MASARAM GONDI DIGIT NINE
    ; between_unicode_range(0x11D60, 0x11D65, Character) % XID_Continue # Lo   [6] GUNJALA GONDI LETTER A..GUNJALA GONDI LETTER UU
    ; between_unicode_range(0x11D67, 0x11D68, Character) % XID_Continue # Lo   [2] GUNJALA GONDI LETTER EE..GUNJALA GONDI LETTER AI
    ; between_unicode_range(0x11D6A, 0x11D89, Character) % XID_Continue # Lo  [32] GUNJALA GONDI LETTER OO..GUNJALA GONDI LETTER SA
    ; between_unicode_range(0x11D8A, 0x11D8E, Character) % XID_Continue # Mc   [5] GUNJALA GONDI VOWEL SIGN AA..GUNJALA GONDI VOWEL SIGN UU
    ; between_unicode_range(0x11D90, 0x11D91, Character) % XID_Continue # Mn   [2] GUNJALA GONDI VOWEL SIGN EE..GUNJALA GONDI VOWEL SIGN AI
    ; between_unicode_range(0x11D93, 0x11D94, Character) % XID_Continue # Mc   [2] GUNJALA GONDI VOWEL SIGN OO..GUNJALA GONDI VOWEL SIGN AU
    ; unicode_character(0x11D95, Character) % XID_Continue # Mn       GUNJALA GONDI SIGN ANUSVARA
    ; unicode_character(0x11D96, Character) % XID_Continue # Mc       GUNJALA GONDI SIGN VISARGA
    ; unicode_character(0x11D97, Character) % XID_Continue # Mn       GUNJALA GONDI VIRAMA
    ; unicode_character(0x11D98, Character) % XID_Continue # Lo       GUNJALA GONDI OM
    ; between_unicode_range(0x11DA0, 0x11DA9, Character) % XID_Continue # Nd  [10] GUNJALA GONDI DIGIT ZERO..GUNJALA GONDI DIGIT NINE
    ; between_unicode_range(0x11EE0, 0x11EF2, Character) % XID_Continue # Lo  [19] MAKASAR LETTER KA..MAKASAR ANGKA
    ; between_unicode_range(0x11EF3, 0x11EF4, Character) % XID_Continue # Mn   [2] MAKASAR VOWEL SIGN I..MAKASAR VOWEL SIGN U
    ; between_unicode_range(0x11EF5, 0x11EF6, Character) % XID_Continue # Mc   [2] MAKASAR VOWEL SIGN E..MAKASAR VOWEL SIGN O
    ; between_unicode_range(0x11F00, 0x11F01, Character) % XID_Continue # Mn   [2] KAWI SIGN CANDRABINDU..KAWI SIGN ANUSVARA
    ; unicode_character(0x11F02, Character) % XID_Continue # Lo       KAWI SIGN REPHA
    ; unicode_character(0x11F03, Character) % XID_Continue # Mc       KAWI SIGN VISARGA
    ; between_unicode_range(0x11F04, 0x11F10, Character) % XID_Continue # Lo  [13] KAWI LETTER A..KAWI LETTER O
    ; between_unicode_range(0x11F12, 0x11F33, Character) % XID_Continue # Lo  [34] KAWI LETTER KA..KAWI LETTER JNYA
    ; between_unicode_range(0x11F34, 0x11F35, Character) % XID_Continue # Mc   [2] KAWI VOWEL SIGN AA..KAWI VOWEL SIGN ALTERNATE AA
    ; between_unicode_range(0x11F36, 0x11F3A, Character) % XID_Continue # Mn   [5] KAWI VOWEL SIGN I..KAWI VOWEL SIGN VOCALIC R
    ; between_unicode_range(0x11F3E, 0x11F3F, Character) % XID_Continue # Mc   [2] KAWI VOWEL SIGN E..KAWI VOWEL SIGN AI
    ; unicode_character(0x11F40, Character) % XID_Continue # Mn       KAWI VOWEL SIGN EU
    ; unicode_character(0x11F41, Character) % XID_Continue # Mc       KAWI SIGN KILLER
    ; unicode_character(0x11F42, Character) % XID_Continue # Mn       KAWI CONJOINER
    ; between_unicode_range(0x11F50, 0x11F59, Character) % XID_Continue # Nd  [10] KAWI DIGIT ZERO..KAWI DIGIT NINE
    ; unicode_character(0x11F5A, Character) % XID_Continue # Mn       KAWI SIGN NUKTA
    ; unicode_character(0x11FB0, Character) % XID_Continue # Lo       LISU LETTER YHA
    ; between_unicode_range(0x12000, 0x12399, Character) % XID_Continue # Lo [922] CUNEIFORM SIGN A..CUNEIFORM SIGN U U
    ; between_unicode_range(0x12400, 0x1246E, Character) % XID_Continue # Nl [111] CUNEIFORM NUMERIC SIGN TWO ASH..CUNEIFORM NUMERIC SIGN NINE U VARIANT FORM
    ; between_unicode_range(0x12480, 0x12543, Character) % XID_Continue # Lo [196] CUNEIFORM SIGN AB TIMES NUN TENU..CUNEIFORM SIGN ZU5 TIMES THREE DISH TENU
    ; between_unicode_range(0x12F90, 0x12FF0, Character) % XID_Continue # Lo  [97] CYPRO-MINOAN SIGN CM001..CYPRO-MINOAN SIGN CM114
    ; between_unicode_range(0x13000, 0x1342F, Character) % XID_Continue # Lo [1072] EGYPTIAN HIEROGLYPH A001..EGYPTIAN HIEROGLYPH V011D
    ; unicode_character(0x13440, Character) % XID_Continue # Mn       EGYPTIAN HIEROGLYPH MIRROR HORIZONTALLY
    ; between_unicode_range(0x13441, 0x13446, Character) % XID_Continue # Lo   [6] EGYPTIAN HIEROGLYPH FULL BLANK..EGYPTIAN HIEROGLYPH WIDE LOST SIGN
    ; between_unicode_range(0x13447, 0x13455, Character) % XID_Continue # Mn  [15] EGYPTIAN HIEROGLYPH MODIFIER DAMAGED AT TOP START..EGYPTIAN HIEROGLYPH MODIFIER DAMAGED
    ; between_unicode_range(0x13460, 0x143FA, Character) % XID_Continue # Lo [3995] EGYPTIAN HIEROGLYPH-13460..EGYPTIAN HIEROGLYPH-143FA
    ; between_unicode_range(0x14400, 0x14646, Character) % XID_Continue # Lo [583] ANATOLIAN HIEROGLYPH A001..ANATOLIAN HIEROGLYPH A530
    ; between_unicode_range(0x16100, 0x1611D, Character) % XID_Continue # Lo  [30] GURUNG KHEMA LETTER A..GURUNG KHEMA LETTER SA
    ; between_unicode_range(0x1611E, 0x16129, Character) % XID_Continue # Mn  [12] GURUNG KHEMA VOWEL SIGN AA..GURUNG KHEMA VOWEL LENGTH MARK
    ; between_unicode_range(0x1612A, 0x1612C, Character) % XID_Continue # Mc   [3] GURUNG KHEMA CONSONANT SIGN MEDIAL YA..GURUNG KHEMA CONSONANT SIGN MEDIAL HA
    ; between_unicode_range(0x1612D, 0x1612F, Character) % XID_Continue # Mn   [3] GURUNG KHEMA SIGN ANUSVARA..GURUNG KHEMA SIGN THOLHOMA
    ; between_unicode_range(0x16130, 0x16139, Character) % XID_Continue # Nd  [10] GURUNG KHEMA DIGIT ZERO..GURUNG KHEMA DIGIT NINE
    ; between_unicode_range(0x16800, 0x16A38, Character) % XID_Continue # Lo [569] BAMUM LETTER PHASE-A NGKUE MFON..BAMUM LETTER PHASE-F VUEQ
    ; between_unicode_range(0x16A40, 0x16A5E, Character) % XID_Continue # Lo  [31] MRO LETTER TA..MRO LETTER TEK
    ; between_unicode_range(0x16A60, 0x16A69, Character) % XID_Continue # Nd  [10] MRO DIGIT ZERO..MRO DIGIT NINE
    ; between_unicode_range(0x16A70, 0x16ABE, Character) % XID_Continue # Lo  [79] TANGSA LETTER OZ..TANGSA LETTER ZA
    ; between_unicode_range(0x16AC0, 0x16AC9, Character) % XID_Continue # Nd  [10] TANGSA DIGIT ZERO..TANGSA DIGIT NINE
    ; between_unicode_range(0x16AD0, 0x16AED, Character) % XID_Continue # Lo  [30] BASSA VAH LETTER ENNI..BASSA VAH LETTER I
    ; between_unicode_range(0x16AF0, 0x16AF4, Character) % XID_Continue # Mn   [5] BASSA VAH COMBINING HIGH TONE..BASSA VAH COMBINING HIGH-LOW TONE
    ; between_unicode_range(0x16B00, 0x16B2F, Character) % XID_Continue # Lo  [48] PAHAWH HMONG VOWEL KEEB..PAHAWH HMONG CONSONANT CAU
    ; between_unicode_range(0x16B30, 0x16B36, Character) % XID_Continue # Mn   [7] PAHAWH HMONG MARK CIM TUB..PAHAWH HMONG MARK CIM TAUM
    ; between_unicode_range(0x16B40, 0x16B43, Character) % XID_Continue # Lm   [4] PAHAWH HMONG SIGN VOS SEEV..PAHAWH HMONG SIGN IB YAM
    ; between_unicode_range(0x16B50, 0x16B59, Character) % XID_Continue # Nd  [10] PAHAWH HMONG DIGIT ZERO..PAHAWH HMONG DIGIT NINE
    ; between_unicode_range(0x16B63, 0x16B77, Character) % XID_Continue # Lo  [21] PAHAWH HMONG SIGN VOS LUB..PAHAWH HMONG SIGN CIM NRES TOS
    ; between_unicode_range(0x16B7D, 0x16B8F, Character) % XID_Continue # Lo  [19] PAHAWH HMONG CLAN SIGN TSHEEJ..PAHAWH HMONG CLAN SIGN VWJ
    ; between_unicode_range(0x16D40, 0x16D42, Character) % XID_Continue # Lm   [3] KIRAT RAI SIGN ANUSVARA..KIRAT RAI SIGN VISARGA
    ; between_unicode_range(0x16D43, 0x16D6A, Character) % XID_Continue # Lo  [40] KIRAT RAI LETTER A..KIRAT RAI VOWEL SIGN AU
    ; between_unicode_range(0x16D6B, 0x16D6C, Character) % XID_Continue # Lm   [2] KIRAT RAI SIGN VIRAMA..KIRAT RAI SIGN SAAT
    ; between_unicode_range(0x16D70, 0x16D79, Character) % XID_Continue # Nd  [10] KIRAT RAI DIGIT ZERO..KIRAT RAI DIGIT NINE
    ; between_unicode_range(0x16E40, 0x16E7F, Character) % XID_Continue # L&  [64] MEDEFAIDRIN CAPITAL LETTER M..MEDEFAIDRIN SMALL LETTER Y
    ; between_unicode_range(0x16F00, 0x16F4A, Character) % XID_Continue # Lo  [75] MIAO LETTER PA..MIAO LETTER RTE
    ; unicode_character(0x16F4F, Character) % XID_Continue # Mn       MIAO SIGN CONSONANT MODIFIER BAR
    ; unicode_character(0x16F50, Character) % XID_Continue # Lo       MIAO LETTER NASALIZATION
    ; between_unicode_range(0x16F51, 0x16F87, Character) % XID_Continue # Mc  [55] MIAO SIGN ASPIRATION..MIAO VOWEL SIGN UI
    ; between_unicode_range(0x16F8F, 0x16F92, Character) % XID_Continue # Mn   [4] MIAO TONE RIGHT..MIAO TONE BELOW
    ; between_unicode_range(0x16F93, 0x16F9F, Character) % XID_Continue # Lm  [13] MIAO LETTER TONE-2..MIAO LETTER REFORMED TONE-8
    ; between_unicode_range(0x16FE0, 0x16FE1, Character) % XID_Continue # Lm   [2] TANGUT ITERATION MARK..NUSHU ITERATION MARK
    ; unicode_character(0x16FE3, Character) % XID_Continue # Lm       OLD CHINESE ITERATION MARK
    ; unicode_character(0x16FE4, Character) % XID_Continue # Mn       KHITAN SMALL SCRIPT FILLER
    ; between_unicode_range(0x16FF0, 0x16FF1, Character) % XID_Continue # Mc   [2] VIETNAMESE ALTERNATE READING MARK CA..VIETNAMESE ALTERNATE READING MARK NHAY
    ; between_unicode_range(0x17000, 0x187F7, Character) % XID_Continue # Lo [6136] TANGUT IDEOGRAPH-17000..TANGUT IDEOGRAPH-187F7
    ; between_unicode_range(0x18800, 0x18CD5, Character) % XID_Continue # Lo [1238] TANGUT COMPONENT-001..KHITAN SMALL SCRIPT CHARACTER-18CD5
    ; between_unicode_range(0x18CFF, 0x18D08, Character) % XID_Continue # Lo  [10] KHITAN SMALL SCRIPT CHARACTER-18CFF..TANGUT IDEOGRAPH-18D08
    ; between_unicode_range(0x1AFF0, 0x1AFF3, Character) % XID_Continue # Lm   [4] KATAKANA LETTER MINNAN TONE-2..KATAKANA LETTER MINNAN TONE-5
    ; between_unicode_range(0x1AFF5, 0x1AFFB, Character) % XID_Continue # Lm   [7] KATAKANA LETTER MINNAN TONE-7..KATAKANA LETTER MINNAN NASALIZED TONE-5
    ; between_unicode_range(0x1AFFD, 0x1AFFE, Character) % XID_Continue # Lm   [2] KATAKANA LETTER MINNAN NASALIZED TONE-7..KATAKANA LETTER MINNAN NASALIZED TONE-8
    ; between_unicode_range(0x1B000, 0x1B122, Character) % XID_Continue # Lo [291] KATAKANA LETTER ARCHAIC E..KATAKANA LETTER ARCHAIC WU
    ; unicode_character(0x1B132, Character) % XID_Continue # Lo       HIRAGANA LETTER SMALL KO
    ; between_unicode_range(0x1B150, 0x1B152, Character) % XID_Continue # Lo   [3] HIRAGANA LETTER SMALL WI..HIRAGANA LETTER SMALL WO
    ; unicode_character(0x1B155, Character) % XID_Continue # Lo       KATAKANA LETTER SMALL KO
    ; between_unicode_range(0x1B164, 0x1B167, Character) % XID_Continue # Lo   [4] KATAKANA LETTER SMALL WI..KATAKANA LETTER SMALL N
    ; between_unicode_range(0x1B170, 0x1B2FB, Character) % XID_Continue # Lo [396] NUSHU CHARACTER-1B170..NUSHU CHARACTER-1B2FB
    ; between_unicode_range(0x1BC00, 0x1BC6A, Character) % XID_Continue # Lo [107] DUPLOYAN LETTER H..DUPLOYAN LETTER VOCALIC M
    ; between_unicode_range(0x1BC70, 0x1BC7C, Character) % XID_Continue # Lo  [13] DUPLOYAN AFFIX LEFT HORIZONTAL SECANT..DUPLOYAN AFFIX ATTACHED TANGENT HOOK
    ; between_unicode_range(0x1BC80, 0x1BC88, Character) % XID_Continue # Lo   [9] DUPLOYAN AFFIX HIGH ACUTE..DUPLOYAN AFFIX HIGH VERTICAL
    ; between_unicode_range(0x1BC90, 0x1BC99, Character) % XID_Continue # Lo  [10] DUPLOYAN AFFIX LOW ACUTE..DUPLOYAN AFFIX LOW ARROW
    ; between_unicode_range(0x1BC9D, 0x1BC9E, Character) % XID_Continue # Mn   [2] DUPLOYAN THICK LETTER SELECTOR..DUPLOYAN DOUBLE MARK
    ; between_unicode_range(0x1CCF0, 0x1CCF9, Character) % XID_Continue # Nd  [10] OUTLINED DIGIT ZERO..OUTLINED DIGIT NINE
    ; between_unicode_range(0x1CF00, 0x1CF2D, Character) % XID_Continue # Mn  [46] ZNAMENNY COMBINING MARK GORAZDO NIZKO S KRYZHEM ON LEFT..ZNAMENNY COMBINING MARK KRYZH ON LEFT
    ; between_unicode_range(0x1CF30, 0x1CF46, Character) % XID_Continue # Mn  [23] ZNAMENNY COMBINING TONAL RANGE MARK MRACHNO..ZNAMENNY PRIZNAK MODIFIER ROG
    ; between_unicode_range(0x1D165, 0x1D166, Character) % XID_Continue # Mc   [2] MUSICAL SYMBOL COMBINING STEM..MUSICAL SYMBOL COMBINING SPRECHGESANG STEM
    ; between_unicode_range(0x1D167, 0x1D169, Character) % XID_Continue # Mn   [3] MUSICAL SYMBOL COMBINING TREMOLO-1..MUSICAL SYMBOL COMBINING TREMOLO-3
    ; between_unicode_range(0x1D16D, 0x1D172, Character) % XID_Continue # Mc   [6] MUSICAL SYMBOL COMBINING AUGMENTATION DOT..MUSICAL SYMBOL COMBINING FLAG-5
    ; between_unicode_range(0x1D17B, 0x1D182, Character) % XID_Continue # Mn   [8] MUSICAL SYMBOL COMBINING ACCENT..MUSICAL SYMBOL COMBINING LOURE
    ; between_unicode_range(0x1D185, 0x1D18B, Character) % XID_Continue # Mn   [7] MUSICAL SYMBOL COMBINING DOIT..MUSICAL SYMBOL COMBINING TRIPLE TONGUE
    ; between_unicode_range(0x1D1AA, 0x1D1AD, Character) % XID_Continue # Mn   [4] MUSICAL SYMBOL COMBINING DOWN BOW..MUSICAL SYMBOL COMBINING SNAP PIZZICATO
    ; between_unicode_range(0x1D242, 0x1D244, Character) % XID_Continue # Mn   [3] COMBINING GREEK MUSICAL TRISEME..COMBINING GREEK MUSICAL PENTASEME
    ; between_unicode_range(0x1D400, 0x1D454, Character) % XID_Continue # L&  [85] MATHEMATICAL BOLD CAPITAL A..MATHEMATICAL ITALIC SMALL G
    ; between_unicode_range(0x1D456, 0x1D49C, Character) % XID_Continue # L&  [71] MATHEMATICAL ITALIC SMALL I..MATHEMATICAL SCRIPT CAPITAL A
    ; between_unicode_range(0x1D49E, 0x1D49F, Character) % XID_Continue # L&   [2] MATHEMATICAL SCRIPT CAPITAL C..MATHEMATICAL SCRIPT CAPITAL D
    ; unicode_character(0x1D4A2, Character) % XID_Continue # L&       MATHEMATICAL SCRIPT CAPITAL G
    ; between_unicode_range(0x1D4A5, 0x1D4A6, Character) % XID_Continue # L&   [2] MATHEMATICAL SCRIPT CAPITAL J..MATHEMATICAL SCRIPT CAPITAL K
    ; between_unicode_range(0x1D4A9, 0x1D4AC, Character) % XID_Continue # L&   [4] MATHEMATICAL SCRIPT CAPITAL N..MATHEMATICAL SCRIPT CAPITAL Q
    ; between_unicode_range(0x1D4AE, 0x1D4B9, Character) % XID_Continue # L&  [12] MATHEMATICAL SCRIPT CAPITAL S..MATHEMATICAL SCRIPT SMALL D
    ; unicode_character(0x1D4BB, Character) % XID_Continue # L&       MATHEMATICAL SCRIPT SMALL F
    ; between_unicode_range(0x1D4BD, 0x1D4C3, Character) % XID_Continue # L&   [7] MATHEMATICAL SCRIPT SMALL H..MATHEMATICAL SCRIPT SMALL N
    ; between_unicode_range(0x1D4C5, 0x1D505, Character) % XID_Continue # L&  [65] MATHEMATICAL SCRIPT SMALL P..MATHEMATICAL FRAKTUR CAPITAL B
    ; between_unicode_range(0x1D507, 0x1D50A, Character) % XID_Continue # L&   [4] MATHEMATICAL FRAKTUR CAPITAL D..MATHEMATICAL FRAKTUR CAPITAL G
    ; between_unicode_range(0x1D50D, 0x1D514, Character) % XID_Continue # L&   [8] MATHEMATICAL FRAKTUR CAPITAL J..MATHEMATICAL FRAKTUR CAPITAL Q
    ; between_unicode_range(0x1D516, 0x1D51C, Character) % XID_Continue # L&   [7] MATHEMATICAL FRAKTUR CAPITAL S..MATHEMATICAL FRAKTUR CAPITAL Y
    ; between_unicode_range(0x1D51E, 0x1D539, Character) % XID_Continue # L&  [28] MATHEMATICAL FRAKTUR SMALL A..MATHEMATICAL DOUBLE-STRUCK CAPITAL B
    ; between_unicode_range(0x1D53B, 0x1D53E, Character) % XID_Continue # L&   [4] MATHEMATICAL DOUBLE-STRUCK CAPITAL D..MATHEMATICAL DOUBLE-STRUCK CAPITAL G
    ; between_unicode_range(0x1D540, 0x1D544, Character) % XID_Continue # L&   [5] MATHEMATICAL DOUBLE-STRUCK CAPITAL I..MATHEMATICAL DOUBLE-STRUCK CAPITAL M
    ; unicode_character(0x1D546, Character) % XID_Continue # L&       MATHEMATICAL DOUBLE-STRUCK CAPITAL O
    ; between_unicode_range(0x1D54A, 0x1D550, Character) % XID_Continue # L&   [7] MATHEMATICAL DOUBLE-STRUCK CAPITAL S..MATHEMATICAL DOUBLE-STRUCK CAPITAL Y
    ; between_unicode_range(0x1D552, 0x1D6A5, Character) % XID_Continue # L& [340] MATHEMATICAL DOUBLE-STRUCK SMALL A..MATHEMATICAL ITALIC SMALL DOTLESS J
    ; between_unicode_range(0x1D6A8, 0x1D6C0, Character) % XID_Continue # L&  [25] MATHEMATICAL BOLD CAPITAL ALPHA..MATHEMATICAL BOLD CAPITAL OMEGA
    ; between_unicode_range(0x1D6C2, 0x1D6DA, Character) % XID_Continue # L&  [25] MATHEMATICAL BOLD SMALL ALPHA..MATHEMATICAL BOLD SMALL OMEGA
    ; between_unicode_range(0x1D6DC, 0x1D6FA, Character) % XID_Continue # L&  [31] MATHEMATICAL BOLD EPSILON SYMBOL..MATHEMATICAL ITALIC CAPITAL OMEGA
    ; between_unicode_range(0x1D6FC, 0x1D714, Character) % XID_Continue # L&  [25] MATHEMATICAL ITALIC SMALL ALPHA..MATHEMATICAL ITALIC SMALL OMEGA
    ; between_unicode_range(0x1D716, 0x1D734, Character) % XID_Continue # L&  [31] MATHEMATICAL ITALIC EPSILON SYMBOL..MATHEMATICAL BOLD ITALIC CAPITAL OMEGA
    ; between_unicode_range(0x1D736, 0x1D74E, Character) % XID_Continue # L&  [25] MATHEMATICAL BOLD ITALIC SMALL ALPHA..MATHEMATICAL BOLD ITALIC SMALL OMEGA
    ; between_unicode_range(0x1D750, 0x1D76E, Character) % XID_Continue # L&  [31] MATHEMATICAL BOLD ITALIC EPSILON SYMBOL..MATHEMATICAL SANS-SERIF BOLD CAPITAL OMEGA
    ; between_unicode_range(0x1D770, 0x1D788, Character) % XID_Continue # L&  [25] MATHEMATICAL SANS-SERIF BOLD SMALL ALPHA..MATHEMATICAL SANS-SERIF BOLD SMALL OMEGA
    ; between_unicode_range(0x1D78A, 0x1D7A8, Character) % XID_Continue # L&  [31] MATHEMATICAL SANS-SERIF BOLD EPSILON SYMBOL..MATHEMATICAL SANS-SERIF BOLD ITALIC CAPITAL OMEGA
    ; between_unicode_range(0x1D7AA, 0x1D7C2, Character) % XID_Continue # L&  [25] MATHEMATICAL SANS-SERIF BOLD ITALIC SMALL ALPHA..MATHEMATICAL SANS-SERIF BOLD ITALIC SMALL OMEGA
    ; between_unicode_range(0x1D7C4, 0x1D7CB, Character) % XID_Continue # L&   [8] MATHEMATICAL SANS-SERIF BOLD ITALIC EPSILON SYMBOL..MATHEMATICAL BOLD SMALL DIGAMMA
    ; between_unicode_range(0x1D7CE, 0x1D7FF, Character) % XID_Continue # Nd  [50] MATHEMATICAL BOLD DIGIT ZERO..MATHEMATICAL MONOSPACE DIGIT NINE
    ; between_unicode_range(0x1DA00, 0x1DA36, Character) % XID_Continue # Mn  [55] SIGNWRITING HEAD RIM..SIGNWRITING AIR SUCKING IN
    ; between_unicode_range(0x1DA3B, 0x1DA6C, Character) % XID_Continue # Mn  [50] SIGNWRITING MOUTH CLOSED NEUTRAL..SIGNWRITING EXCITEMENT
    ; unicode_character(0x1DA75, Character) % XID_Continue # Mn       SIGNWRITING UPPER BODY TILTING FROM HIP JOINTS
    ; unicode_character(0x1DA84, Character) % XID_Continue # Mn       SIGNWRITING LOCATION HEAD NECK
    ; between_unicode_range(0x1DA9B, 0x1DA9F, Character) % XID_Continue # Mn   [5] SIGNWRITING FILL MODIFIER-2..SIGNWRITING FILL MODIFIER-6
    ; between_unicode_range(0x1DAA1, 0x1DAAF, Character) % XID_Continue # Mn  [15] SIGNWRITING ROTATION MODIFIER-2..SIGNWRITING ROTATION MODIFIER-16
    ; between_unicode_range(0x1DF00, 0x1DF09, Character) % XID_Continue # L&  [10] LATIN SMALL LETTER FENG DIGRAPH WITH TRILL..LATIN SMALL LETTER T WITH HOOK AND RETROFLEX HOOK
    ; unicode_character(0x1DF0A, Character) % XID_Continue # Lo       LATIN LETTER RETROFLEX CLICK WITH RETROFLEX HOOK
    ; between_unicode_range(0x1DF0B, 0x1DF1E, Character) % XID_Continue # L&  [20] LATIN SMALL LETTER ESH WITH DOUBLE BAR..LATIN SMALL LETTER S WITH CURL
    ; between_unicode_range(0x1DF25, 0x1DF2A, Character) % XID_Continue # L&   [6] LATIN SMALL LETTER D WITH MID-HEIGHT LEFT HOOK..LATIN SMALL LETTER T WITH MID-HEIGHT LEFT HOOK
    ; between_unicode_range(0x1E000, 0x1E006, Character) % XID_Continue # Mn   [7] COMBINING GLAGOLITIC LETTER AZU..COMBINING GLAGOLITIC LETTER ZHIVETE
    ; between_unicode_range(0x1E008, 0x1E018, Character) % XID_Continue # Mn  [17] COMBINING GLAGOLITIC LETTER ZEMLJA..COMBINING GLAGOLITIC LETTER HERU
    ; between_unicode_range(0x1E01B, 0x1E021, Character) % XID_Continue # Mn   [7] COMBINING GLAGOLITIC LETTER SHTA..COMBINING GLAGOLITIC LETTER YATI
    ; between_unicode_range(0x1E023, 0x1E024, Character) % XID_Continue # Mn   [2] COMBINING GLAGOLITIC LETTER YU..COMBINING GLAGOLITIC LETTER SMALL YUS
    ; between_unicode_range(0x1E026, 0x1E02A, Character) % XID_Continue # Mn   [5] COMBINING GLAGOLITIC LETTER YO..COMBINING GLAGOLITIC LETTER FITA
    ; between_unicode_range(0x1E030, 0x1E06D, Character) % XID_Continue # Lm  [62] MODIFIER LETTER CYRILLIC SMALL A..MODIFIER LETTER CYRILLIC SMALL STRAIGHT U WITH STROKE
    ; unicode_character(0x1E08F, Character) % XID_Continue # Mn       COMBINING CYRILLIC SMALL LETTER BYELORUSSIAN-UKRAINIAN I
    ; between_unicode_range(0x1E100, 0x1E12C, Character) % XID_Continue # Lo  [45] NYIAKENG PUACHUE HMONG LETTER MA..NYIAKENG PUACHUE HMONG LETTER W
    ; between_unicode_range(0x1E130, 0x1E136, Character) % XID_Continue # Mn   [7] NYIAKENG PUACHUE HMONG TONE-B..NYIAKENG PUACHUE HMONG TONE-D
    ; between_unicode_range(0x1E137, 0x1E13D, Character) % XID_Continue # Lm   [7] NYIAKENG PUACHUE HMONG SIGN FOR PERSON..NYIAKENG PUACHUE HMONG SYLLABLE LENGTHENER
    ; between_unicode_range(0x1E140, 0x1E149, Character) % XID_Continue # Nd  [10] NYIAKENG PUACHUE HMONG DIGIT ZERO..NYIAKENG PUACHUE HMONG DIGIT NINE
    ; unicode_character(0x1E14E, Character) % XID_Continue # Lo       NYIAKENG PUACHUE HMONG LOGOGRAM NYAJ
    ; between_unicode_range(0x1E290, 0x1E2AD, Character) % XID_Continue # Lo  [30] TOTO LETTER PA..TOTO LETTER A
    ; unicode_character(0x1E2AE, Character) % XID_Continue # Mn       TOTO SIGN RISING TONE
    ; between_unicode_range(0x1E2C0, 0x1E2EB, Character) % XID_Continue # Lo  [44] WANCHO LETTER AA..WANCHO LETTER YIH
    ; between_unicode_range(0x1E2EC, 0x1E2EF, Character) % XID_Continue # Mn   [4] WANCHO TONE TUP..WANCHO TONE KOINI
    ; between_unicode_range(0x1E2F0, 0x1E2F9, Character) % XID_Continue # Nd  [10] WANCHO DIGIT ZERO..WANCHO DIGIT NINE
    ; between_unicode_range(0x1E4D0, 0x1E4EA, Character) % XID_Continue # Lo  [27] NAG MUNDARI LETTER O..NAG MUNDARI LETTER ELL
    ; unicode_character(0x1E4EB, Character) % XID_Continue # Lm       NAG MUNDARI SIGN OJOD
    ; between_unicode_range(0x1E4EC, 0x1E4EF, Character) % XID_Continue # Mn   [4] NAG MUNDARI SIGN MUHOR..NAG MUNDARI SIGN SUTUH
    ; between_unicode_range(0x1E4F0, 0x1E4F9, Character) % XID_Continue # Nd  [10] NAG MUNDARI DIGIT ZERO..NAG MUNDARI DIGIT NINE
    ; between_unicode_range(0x1E5D0, 0x1E5ED, Character) % XID_Continue # Lo  [30] OL ONAL LETTER O..OL ONAL LETTER EG
    ; between_unicode_range(0x1E5EE, 0x1E5EF, Character) % XID_Continue # Mn   [2] OL ONAL SIGN MU..OL ONAL SIGN IKIR
    ; unicode_character(0x1E5F0, Character) % XID_Continue # Lo       OL ONAL SIGN HODDOND
    ; between_unicode_range(0x1E5F1, 0x1E5FA, Character) % XID_Continue # Nd  [10] OL ONAL DIGIT ZERO..OL ONAL DIGIT NINE
    ; between_unicode_range(0x1E7E0, 0x1E7E6, Character) % XID_Continue # Lo   [7] ETHIOPIC SYLLABLE HHYA..ETHIOPIC SYLLABLE HHYO
    ; between_unicode_range(0x1E7E8, 0x1E7EB, Character) % XID_Continue # Lo   [4] ETHIOPIC SYLLABLE GURAGE HHWA..ETHIOPIC SYLLABLE HHWE
    ; between_unicode_range(0x1E7ED, 0x1E7EE, Character) % XID_Continue # Lo   [2] ETHIOPIC SYLLABLE GURAGE MWI..ETHIOPIC SYLLABLE GURAGE MWEE
    ; between_unicode_range(0x1E7F0, 0x1E7FE, Character) % XID_Continue # Lo  [15] ETHIOPIC SYLLABLE GURAGE QWI..ETHIOPIC SYLLABLE GURAGE PWEE
    ; between_unicode_range(0x1E800, 0x1E8C4, Character) % XID_Continue # Lo [197] MENDE KIKAKUI SYLLABLE M001 KI..MENDE KIKAKUI SYLLABLE M060 NYON
    ; between_unicode_range(0x1E8D0, 0x1E8D6, Character) % XID_Continue # Mn   [7] MENDE KIKAKUI COMBINING NUMBER TEENS..MENDE KIKAKUI COMBINING NUMBER MILLIONS
    ; between_unicode_range(0x1E900, 0x1E943, Character) % XID_Continue # L&  [68] ADLAM CAPITAL LETTER ALIF..ADLAM SMALL LETTER SHA
    ; between_unicode_range(0x1E944, 0x1E94A, Character) % XID_Continue # Mn   [7] ADLAM ALIF LENGTHENER..ADLAM NUKTA
    ; unicode_character(0x1E94B, Character) % XID_Continue # Lm       ADLAM NASALIZATION MARK
    ; between_unicode_range(0x1E950, 0x1E959, Character) % XID_Continue # Nd  [10] ADLAM DIGIT ZERO..ADLAM DIGIT NINE
    ; between_unicode_range(0x1EE00, 0x1EE03, Character) % XID_Continue # Lo   [4] ARABIC MATHEMATICAL ALEF..ARABIC MATHEMATICAL DAL
    ; between_unicode_range(0x1EE05, 0x1EE1F, Character) % XID_Continue # Lo  [27] ARABIC MATHEMATICAL WAW..ARABIC MATHEMATICAL DOTLESS QAF
    ; between_unicode_range(0x1EE21, 0x1EE22, Character) % XID_Continue # Lo   [2] ARABIC MATHEMATICAL INITIAL BEH..ARABIC MATHEMATICAL INITIAL JEEM
    ; unicode_character(0x1EE24, Character) % XID_Continue # Lo       ARABIC MATHEMATICAL INITIAL HEH
    ; unicode_character(0x1EE27, Character) % XID_Continue # Lo       ARABIC MATHEMATICAL INITIAL HAH
    ; between_unicode_range(0x1EE29, 0x1EE32, Character) % XID_Continue # Lo  [10] ARABIC MATHEMATICAL INITIAL YEH..ARABIC MATHEMATICAL INITIAL QAF
    ; between_unicode_range(0x1EE34, 0x1EE37, Character) % XID_Continue # Lo   [4] ARABIC MATHEMATICAL INITIAL SHEEN..ARABIC MATHEMATICAL INITIAL KHAH
    ; unicode_character(0x1EE39, Character) % XID_Continue # Lo       ARABIC MATHEMATICAL INITIAL DAD
    ; unicode_character(0x1EE3B, Character) % XID_Continue # Lo       ARABIC MATHEMATICAL INITIAL GHAIN
    ; unicode_character(0x1EE42, Character) % XID_Continue # Lo       ARABIC MATHEMATICAL TAILED JEEM
    ; unicode_character(0x1EE47, Character) % XID_Continue # Lo       ARABIC MATHEMATICAL TAILED HAH
    ; unicode_character(0x1EE49, Character) % XID_Continue # Lo       ARABIC MATHEMATICAL TAILED YEH
    ; unicode_character(0x1EE4B, Character) % XID_Continue # Lo       ARABIC MATHEMATICAL TAILED LAM
    ; between_unicode_range(0x1EE4D, 0x1EE4F, Character) % XID_Continue # Lo   [3] ARABIC MATHEMATICAL TAILED NOON..ARABIC MATHEMATICAL TAILED AIN
    ; between_unicode_range(0x1EE51, 0x1EE52, Character) % XID_Continue # Lo   [2] ARABIC MATHEMATICAL TAILED SAD..ARABIC MATHEMATICAL TAILED QAF
    ; unicode_character(0x1EE54, Character) % XID_Continue # Lo       ARABIC MATHEMATICAL TAILED SHEEN
    ; unicode_character(0x1EE57, Character) % XID_Continue # Lo       ARABIC MATHEMATICAL TAILED KHAH
    ; unicode_character(0x1EE59, Character) % XID_Continue # Lo       ARABIC MATHEMATICAL TAILED DAD
    ; unicode_character(0x1EE5B, Character) % XID_Continue # Lo       ARABIC MATHEMATICAL TAILED GHAIN
    ; unicode_character(0x1EE5D, Character) % XID_Continue # Lo       ARABIC MATHEMATICAL TAILED DOTLESS NOON
    ; unicode_character(0x1EE5F, Character) % XID_Continue # Lo       ARABIC MATHEMATICAL TAILED DOTLESS QAF
    ; between_unicode_range(0x1EE61, 0x1EE62, Character) % XID_Continue # Lo   [2] ARABIC MATHEMATICAL STRETCHED BEH..ARABIC MATHEMATICAL STRETCHED JEEM
    ; unicode_character(0x1EE64, Character) % XID_Continue # Lo       ARABIC MATHEMATICAL STRETCHED HEH
    ; between_unicode_range(0x1EE67, 0x1EE6A, Character) % XID_Continue # Lo   [4] ARABIC MATHEMATICAL STRETCHED HAH..ARABIC MATHEMATICAL STRETCHED KAF
    ; between_unicode_range(0x1EE6C, 0x1EE72, Character) % XID_Continue # Lo   [7] ARABIC MATHEMATICAL STRETCHED MEEM..ARABIC MATHEMATICAL STRETCHED QAF
    ; between_unicode_range(0x1EE74, 0x1EE77, Character) % XID_Continue # Lo   [4] ARABIC MATHEMATICAL STRETCHED SHEEN..ARABIC MATHEMATICAL STRETCHED KHAH
    ; between_unicode_range(0x1EE79, 0x1EE7C, Character) % XID_Continue # Lo   [4] ARABIC MATHEMATICAL STRETCHED DAD..ARABIC MATHEMATICAL STRETCHED DOTLESS BEH
    ; unicode_character(0x1EE7E, Character) % XID_Continue # Lo       ARABIC MATHEMATICAL STRETCHED DOTLESS FEH
    ; between_unicode_range(0x1EE80, 0x1EE89, Character) % XID_Continue # Lo  [10] ARABIC MATHEMATICAL LOOPED ALEF..ARABIC MATHEMATICAL LOOPED YEH
    ; between_unicode_range(0x1EE8B, 0x1EE9B, Character) % XID_Continue # Lo  [17] ARABIC MATHEMATICAL LOOPED LAM..ARABIC MATHEMATICAL LOOPED GHAIN
    ; between_unicode_range(0x1EEA1, 0x1EEA3, Character) % XID_Continue # Lo   [3] ARABIC MATHEMATICAL DOUBLE-STRUCK BEH..ARABIC MATHEMATICAL DOUBLE-STRUCK DAL
    ; between_unicode_range(0x1EEA5, 0x1EEA9, Character) % XID_Continue # Lo   [5] ARABIC MATHEMATICAL DOUBLE-STRUCK WAW..ARABIC MATHEMATICAL DOUBLE-STRUCK YEH
    ; between_unicode_range(0x1EEAB, 0x1EEBB, Character) % XID_Continue # Lo  [17] ARABIC MATHEMATICAL DOUBLE-STRUCK LAM..ARABIC MATHEMATICAL DOUBLE-STRUCK GHAIN
    ; between_unicode_range(0x1FBF0, 0x1FBF9, Character) % XID_Continue # Nd  [10] SEGMENTED DIGIT ZERO..SEGMENTED DIGIT NINE
    ; between_unicode_range(0x20000, 0x2A6DF, Character) % XID_Continue # Lo [42720] CJK UNIFIED IDEOGRAPH-20000..CJK UNIFIED IDEOGRAPH-2A6DF
    ; between_unicode_range(0x2A700, 0x2B739, Character) % XID_Continue # Lo [4154] CJK UNIFIED IDEOGRAPH-2A700..CJK UNIFIED IDEOGRAPH-2B739
    ; between_unicode_range(0x2B740, 0x2B81D, Character) % XID_Continue # Lo [222] CJK UNIFIED IDEOGRAPH-2B740..CJK UNIFIED IDEOGRAPH-2B81D
    ; between_unicode_range(0x2B820, 0x2CEA1, Character) % XID_Continue # Lo [5762] CJK UNIFIED IDEOGRAPH-2B820..CJK UNIFIED IDEOGRAPH-2CEA1
    ; between_unicode_range(0x2CEB0, 0x2EBE0, Character) % XID_Continue # Lo [7473] CJK UNIFIED IDEOGRAPH-2CEB0..CJK UNIFIED IDEOGRAPH-2EBE0
    ; between_unicode_range(0x2EBF0, 0x2EE5D, Character) % XID_Continue # Lo [622] CJK UNIFIED IDEOGRAPH-2EBF0..CJK UNIFIED IDEOGRAPH-2EE5D
    ; between_unicode_range(0x2F800, 0x2FA1D, Character) % XID_Continue # Lo [542] CJK COMPATIBILITY IDEOGRAPH-2F800..CJK COMPATIBILITY IDEOGRAPH-2FA1D
    ; between_unicode_range(0x30000, 0x3134A, Character) % XID_Continue # Lo [4939] CJK UNIFIED IDEOGRAPH-30000..CJK UNIFIED IDEOGRAPH-3134A
    ; between_unicode_range(0x31350, 0x323AF, Character) % XID_Continue # Lo [4192] CJK UNIFIED IDEOGRAPH-31350..CJK UNIFIED IDEOGRAPH-323AF
    ; between_unicode_range(0xE0100, 0xE01EF, Character) % XID_Continue # Mn [240] VARIATION SELECTOR-17..VARIATION SELECTOR-256
  }.
