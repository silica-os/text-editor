# AGENTS.md

Text Editor is a Silica app: the rules of `silica-desktop/AGENTS.md` apply (clean-room, assets,
never crash, everything is a command, measured parity, English everywhere). On top of them:

- Interface texts are our own words, in English with translations (`lib/l10n/*.arb`).
- Look and measures come from the Amalfi kit (`App · Text Editor`, `Apps/Text Editor/*`);
  values the kit does not give are named constants marked provisional in `lib/src/style.dart`.
- RTF is read and written from the specification (`lib/src/model/rtf.dart`); no third-party
  converters.
- User files are precious: a save writes a copy aside first, then the file in place (keeping its
  permissions and links); a file changed by another program is never overwritten silently.
- Before every commit: `dart format --set-exit-if-changed lib test`,
  `flutter analyze --fatal-infos`, `flutter test`, `tool/check_assets.sh`.
- No dead controls: a feature that does not work is not shown, and has an issue.
- Nothing may reach the user's desktop from tests (`lib/src/external.dart`, `startsNothing`);
  tests write their files in temporary directories only.
