# zgx.zeron.sh: design brief

**Direction: a precision instrument on warm paper.** zgx is about doing exactly the work a change needs and nothing else. The site should feel the same way: calm, exact, and quietly confident, with one signal colour that only appears where something matters.

## Type

- **Display:** Instrument Serif (roman and italic). It sets headlines, page titles and the wordmark, giving the site a voice no other Rust GUI docs have.
- **Text and UI:** Geist Sans.
- **Data, labels and code:** Geist Mono. Eyebrows, axis ticks, table heads and keyboard hints sit in mono capitals at 11–12 px with +0.08em tracking.
- **Scale (1.25 ratio, 16 px base):** 12 / 13 / 15.5 (docs body) / 17 (landing body) / 22 / 28 / 44 (docs title) / 56 (section) / 88 (hero).
- **Tracking:** serif display runs at −0.015em with line-height 0.95–1.05; sans headings at −0.02em.

## Colour

- **Neutrals:** warm stone, not zinc. Light is paper `#f8f7f4` with ink `#161614` and a white surface. Dark is tuned separately, not inverted: a green-black `#0b0c0b` with warm ink `#f1f0ea`.
- **Accent:** one signal green, emerald `#0d7a52` in light and mint `#46d39a` in dark. It's used for zgx's marks in charts, the active nav item, links on hover, focus and one hero emphasis. Never for decoration at large.
- **Data:** rival frameworks get blue, amber and violet, validated for CVD, each with its own shape.
- **Contrast:** every text pair is AA or better, and every code token is checked by `scripts/check-contrast.mjs`.

## Space

- **Rhythm:** an 8 px base. Sections sit 128 px apart on desktop and 80 px on a phone.
- **Measure:** docs prose is capped near 72 characters.
- **Edges:** hairline rules (1 px at 9–12% ink) separate rather than boxes. Cards are used only for things you pick: doc sets, stats and code.

## Surfaces

- **Paper:** a fine dot grid fades out behind the hero.
- **Cards:** white or near-black, with a 1 px border and a 1 px top highlight. Borders darken and cards lift 2 px on hover.
- **Code:** sits on its own surface, with a filename tab bar and the language in mono.
- **Docs chrome:** the sidebar and table of contents sit on a slightly darker paper than the page, so the reading column is the brightest thing on screen.

## Motion

- **Hero:** words rise 8 px and fade in, staggered by 50 ms.
- **Chart:** marks travel out from the zgx line to their values when the chart scrolls into view, the one place motion carries meaning.
- **Hover:** transitions take 150 ms ease-out.
- **Reduced motion:** with `prefers-reduced-motion`, all of it turns off.

## What we take from each

- **fumadocs.dev:** the doc-set switcher as the docs' spine, and search that is always one key away.
- **linear.app:** confident, tight display type, and dark mode designed rather than derived.
- **vercel.com/docs:** code blocks with filename bars, crisp hairlines, and nothing decorative competing with content.
- **tailwindcss.com:** large, opinionated headlines, a visible grid as texture, and generous whitespace in docs.
- **react.dev:** side-by-side code that teaches by comparison, and readable, friendly docs typography.
