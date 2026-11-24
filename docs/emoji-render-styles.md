# Emoji rendering styles (Google Noto)

Fluxdo's **Reading → Emoji style** is a local presentation preference. The
setting is **Normal** by default and can be switched to **Animated** or **3D**
without changing the emoji that is sent to Discourse.

| Mode | Asset source | Format | URL pattern |
| --- | --- | --- | --- |
| Normal | Site/Discourse original | Source format | Original server URL |
| Animated | Google Animated Noto Emoji | Animated WebP | `https://fonts.gstatic.com/s/e/notoemoji/latest/{codepoints}/512.webp` |
| 3D | Google Noto 3D Emoji | PNG | `https://fonts.gstatic.com/s/e/noto3demoji/latest/{codepoints}/512.png` |

The source key is formed from Unicode scalar values (lowercase hexadecimal)
joined with underscores, including variation selectors and ZWJ when present.
For example: `1f600` (😀) or `1f469_200d_1f4bb` (👩‍💻).

**Fallbacks:** Site-defined custom emoji are never overridden. Unsupported
Unicode/shortcode sequences, missing assets, failed downloads, and decoding
errors use the original Discourse emoji. Google assets are only requested
after the user explicitly chooses Animated or 3D. Animated WebP is decoded
via the existing image pipeline; 3D PNG is a pre-rendered illustration,
not a live 3D model.

## Artwork attribution and licenses

- **Animated Noto Emoji** © Google LLC. The animated artwork is
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
  Source: [Google Animated Noto Emoji](https://googlefonts.github.io/noto-emoji-animation/).
- **Noto 3D Emoji** © Google LLC. Project and applicable licenses:
  [googlefonts/noto-emoji](https://github.com/googlefonts/noto-emoji).
  Source: [Google Noto Emoji library](https://googlefonts.github.io/noto-emoji-files/).

These Google-hosted artworks are not included in the Fluxdo binary.
The user-selected visuals are fetched on demand and cached by the existing
image cache. Do not remove these credits when distributing a modified client.

## Static artwork sets

The appearance selector (Noto, Twemoji, Fluent UI, OpenMoji and Unicode)
uses Discourse's generated PNG artwork, not the device's installed emoji
font. It downloads on demand through the shared emoji cache. The public
Discourse Emoji CDN is tried first, followed by the pinned
[discourse-emojis distribution](https://github.com/discourse/discourse-emojis/tree/b805eda63e1768ea861ff2fe00cf30c2ce2c504b/dist/emoji)
and then the original site image. The distribution contains shortcode aliases
and skin-tone variants. Artwork is licensed by the respective upstream
projects; see the upstream distribution and its license notices. Both the
static and animated/3D preferences affect post bodies only; custom emoji
and other UI remain unchanged.
