# A Markdown Viewer in the Manner of LaTeX

This page is itself a markdown file. Open any `.md` file with **⌘O**, or drop one onto the window, and it will be set the same way: Latin Modern type, a narrow justified column, hyphenated lines, and paragraphs that run together with an indented first line instead of a gap.

The second paragraph of a run is indented, exactly as TeX would do it. The first paragraph after a heading is not. Straight quotes become "curly" ones, and two or three hyphens turn into en and em dashes -- like this --- without any effort on your part.

## Sections

Headings are sized like `\section` and `\subsection`. The very first heading of a document is centred and treated as its title.

### Lists

Lists keep the modest indentation of the `itemize` and `enumerate` environments:

- a first point, kept short;
- a second point, with a nested list beneath it:
  - a dash marks the second level;
  - as it does in a LaTeX article;
- and a third.

1. Numbered lists work as well.
2. They use the same spacing.

### Quotations

> A quotation is indented on both sides and carries no decoration, in the manner of the `quote` environment. It is justified along with the rest of the text.

## Mathematics

Inline formulae sit naturally in the text: $e^{i\pi} + 1 = 0$. Subscripts, superscripts, and probabilities render as mathematics:

- $h_1$: all cherry, with prior probability $0.1$.
- $h_2$: 75% cherry and 25% lime, with prior probability $0.2$.
- $h_3$: 50% cherry and 50% lime, with prior probability $0.4$.
- $h_4$: 25% cherry and 75% lime, with prior probability $0.2$.
- $h_5$: all lime, with prior probability $0.1$.

Use `$...$` for inline math and `$$...$$` for a centred display:

$$
P(h_i \mid D) = \frac{P(D \mid h_i)\,P(h_i)}{\sum_{j=1}^{5} P(D \mid h_j)\,P(h_j)}
$$

LaTeX delimiters `\(...\)` and `\[...\]` also work, as do fenced blocks marked `math`. Code stays literal, and an escaped dollar sign such as `\$5` displays as \$5.

## Tables and code

Tables follow the `booktabs` convention: a heavy rule above and below, a light one under the header, and no vertical lines.

| Typeface      | Designer     | Year |
| ------------- | ------------ | ---: |
| Computer Modern | Donald Knuth | 1978 |
| Latin Modern  | Jackowski and Nowacki | 2003 |
| Palatino      | Hermann Zapf | 1949 |

Code is set in a monospaced face between two thin rules:

```python
def fib(n):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a
```
