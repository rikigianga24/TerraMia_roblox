# Terra Mia (Roblox) — note per Claude

- Gioco Roblox in Luau, sincronizzato con Rojo (`default.project.json`). È il porting del
  prototipo Godot `rikigianga24/TerraMia`: regole e numeri devono restare uguali a quelli.
- Il design è in `docs/design.md`; la fonte aggiornata è il documento Claude Docs
  "Terra Mia — Documento di design". Commenti e documentazione in italiano.
- Dati statici solo in `src/shared/GameData.luau`; le regole in `src/shared/Rules.luau`.
  Le funzioni di Rules che cambiano lo stato girano solo sul server; il client le usa solo
  per leggere (avanzamenti, "si può fare?").
- Il server è autoritativo: ogni azione nuova va aggiunta in `ACTIONS` di
  `src/server/Main.server.luau`, controllando tipo e intervallo di ogni argomento.
- Timer = timestamp Unix assoluti (`Rules.now()`), mai contatori che avanzano a ogni frame.
- Lo stato è una tabella semplice che va nel DataStore e nei RemoteEvent: solo numeri,
  stringhe, booleani, liste e dizionari con chiavi stringa. Un campo nuovo va in
  `Rules.newGame`; `Rules.migrate` lo aggiunge ai salvataggi vecchi.
- Indentazione con tab (`stylua.toml`).
- Dopo ogni modifica alle regole lancia i test: `lune run tools/run_tests`
  (oppure in Studio `require(game.ServerStorage.Tests.RulesTests)()`).
- Nessun testo visibile scritto nel codice: si aggiunge una chiave in
  `tools/translations_source.py` (it, en, fr, es), si lancia
  `python3 tools/translations_source.py` e si usa `Locale.tr("CHIAVE")`. Rules non produce
  testo: emette `{key, args}` con `Rules.emit` e li traduce il client. Nomi di piante,
  prodotti ed edifici con `Locale.crop()`, `Locale.product()`, `Locale.building()`...
  Nelle etichette 3D si mette solo l'attributo `L10nKey` (vedi `Build.label`).
- Font Fredoka (`Enum.Font.FredokaOne`); colori dell'interfaccia solo in `src/client/Ui.luau`,
  colori del mondo in `src/server/Build.luau`.
- Pianta del borgo: si modifica `tools/gen_borgo.py` e si rigenera
  `src/shared/BorgoLayout.luau` (`python3 tools/gen_borgo.py`).
- Il borgo è condiviso ma ogni giocatore lo vede restaurato secondo la sua partita:
  il server costruisce le versioni "Ruin" e "Restored" e il client mostra quella giusta
  (`src/client/BorgoLocal.luau`).
