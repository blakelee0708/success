/// Picks the particle a Korean word takes, by whether it ends in a 받침.
///
/// Names typed by a family are the reason this exists: `'$name과'` reads
/// right for 민준 and wrong for 영희, and the screen it was wrong on was
/// the one where a senior decides to cut off their child.
///
/// A word that does not end in a Hangul syllable - latin, digits, nothing -
/// takes the 받침 form, which is the one that still reads when spoken.
String particle(String word, {required String batchim, required String plain}) {
  if (word.isEmpty) return batchim;
  final last = word.runes.last;
  if (last < 0xAC00 || last > 0xD7A3) return batchim;
  return (last - 0xAC00) % 28 == 0 ? plain : batchim;
}

/// 과 / 와.
String gwaWa(String word) => '$word${particle(word, batchim: '과', plain: '와')}';

/// 이 / 가.
String iGa(String word) => '$word${particle(word, batchim: '이', plain: '가')}';
