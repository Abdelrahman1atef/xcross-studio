# Third-party notices

## AssetKit

`lib/shared/assets/` and `lib/src/shared/assets/` are a Dart port of parts of
[AssetKit](https://github.com/xtool-org/AssetKit) (commit `e763558b55fcbb5a443b1d7b2c6f0972d8bd14f7`), a clean-room
`actool` implementation. The port does not include AssetKit's vendored LZFSE encoder (`Sources/CLZFSE`, Apple,
BSD-3-Clause); bitmaps are stored as LZFSE uncompressed blocks instead. Deviations are listed in
`specs/004-icon-launch-screen/plan.md`.

```text
MIT License

Copyright (c) 2026 the AssetKit contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
