import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/utils/markdown_latex.dart';

void main() {
  group('normalizeDollarLatex', () {
    test('converts inline and block math', () {
      expect(
        normalizeDollarLatex(r'Area is $\pi r^2$.'),
        r'Area is \(\pi r^2\).',
      );
      expect(normalizeDollarLatex(r'$x$'), r'\(x\)');
      expect(
        normalizeDollarLatex('\$\$\n\\int_0^1 x\\,dx\n\$\$'),
        r'\[\int_0^1 x\,dx\]',
      );
    });

    test('leaves prices alone', () {
      const prices = r'It costs $5 to $10, or $1,299.99 on sale.';
      expect(normalizeDollarLatex(prices), prices);
      expect(
        normalizeDollarLatex(r'Pay $20 now and $30 later'),
        r'Pay $20 now and $30 later',
      );
    });

    test('leaves fenced code alone', () {
      const shell = '```bash\necho \$HOME and \$PATH\n```';
      expect(normalizeDollarLatex(shell), shell);

      const tilde = '~~~php\n\$x = \$y;\n~~~\nthen \$a\$';
      expect(
        normalizeDollarLatex(tilde),
        '~~~php\n\$x = \$y;\n~~~\nthen \\(a\\)',
      );
    });

    test('leaves an unclosed fence alone while streaming', () {
      const partial = 'Run this:\n```js\nconst s = `\${a} and \${b}`';
      expect(normalizeDollarLatex(partial), partial);
    });

    test('leaves inline code alone', () {
      const inline = r'Use `$HOME` and `$x$` but $y$ is math.';
      expect(
        normalizeDollarLatex(inline),
        r'Use `$HOME` and `$x$` but \(y\) is math.',
      );
      expect(
        normalizeDollarLatex(r'Try ``echo `$a$` `` now'),
        r'Try ``echo `$a$` `` now',
      );
    });

    test('turns escaped dollars into literal dollars', () {
      expect(normalizeDollarLatex(r'Only \$5 today'), r'Only $5 today');
      expect(normalizeDollarLatex(r'\$x\$ stays text'), r'$x$ stays text');
    });

    test('returns text without dollars unchanged', () {
      const plain = 'No math here, just `code` and **bold**.';
      expect(identical(normalizeDollarLatex(plain), plain), isTrue);
    });
  });
}
