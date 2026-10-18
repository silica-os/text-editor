<h1 align="center">Text Editor</h1>

<p align="center">
  <b>The text editor of Silica.</b><br>
  Plain and rich text documents.
</p>

<p align="center">
  <img alt="Flutter: app" src="https://img.shields.io/badge/Flutter-app-02569B?style=flat-square&logo=flutter">
  <img alt="license: MIT / Apache-2.0" src="https://img.shields.io/badge/license-MIT%20%2F%20Apache--2.0-3a3a3a?style=flat-square">
  <img alt="status: alpha" src="https://img.shields.io/badge/status-alpha-2f80ed?style=flat-square">
</p>

A Flutter app for the [Silica desktop](https://github.com/silica-linux/silica-desktop), built on
[`silica_ui`](https://github.com/silica-linux/silica-ui) like [Mustache](https://github.com/silica-linux/mustache).
App id `dev.frascella.TextEditor`, icon `text-editor` from silica-icons.

Plain text in any encoding Text Editor knows (UTF-8, UTF-16, ISO Latin 1, with the byte order
mark and line endings kept) and rich text as RTF: fonts, sizes, colours, bold, italic, underline,
strikethrough, paragraph styles, bulleted and numbered lists. Each document in its own window,
Open Recent, Save, Save As, Duplicate, Rename, Revert, documents with a file saved by themselves,
find and replace, Document Info, Wrap to Page, zoom, and a status bar with the caret's position
for plain text.

Behaviors and measurements come from observations of macOS 27 in silica-reference (clean-room:
nothing copied, texts and graphics are our own). Built with `cargo xtask bundle <path>` and
installed with `cargo xtask install-app <path>` from silica-desktop.

## License

MIT OR Apache-2.0.
