# Terra Mia (Roblox)

**Ricostruisci un borgo italiano abbandonato.** Coltivi e allevi in fattoria
per riaprire una a una le botteghe del paese: tornano gli abitanti, si
riaccendono le luci, arrivano i turisti.

È la versione Roblox del prototipo Godot
[`rikigianga24/TerraMia`](https://github.com/rikigianga24/TerraMia): stesse
regole, stessi numeri, stessa pianta del borgo, stessi testi in quattro lingue.
Il documento di design è in [`docs/design.md`](docs/design.md) (copia da quel
repository).

## Requisiti

- [Roblox Studio](https://create.roblox.com/)
- [Rokit](https://github.com/rojo-rbx/rokit), che installa gli strumenti di
  `rokit.toml`: Rojo (sincronizza il codice con Studio), StyLua, Selene e Lune
- Il plugin di Rojo per Studio (`rojo plugin install`)
- Python 3, solo per rigenerare testi e pianta del borgo

## Avvio

```bash
rokit install
```

```bash
rojo serve
```

In Studio apri un luogo vuoto (*Baseplate* va bene: il prato e tutto il resto
li costruisce lo script), nel plugin di Rojo premi **Connect**, poi **Play**.
Il codice in `src/` finisce in Studio e ogni modifica si sincronizza da sola.

Per avere i salvataggi anche in Studio: *File → Game Settings → Security →
Enable Studio Access to API Services* (il luogo deve essere pubblicato almeno
una volta). Senza, si gioca lo stesso ma la partita non viene salvata, e il
gioco lo dice.

In alternativa, senza tenere aperto `rojo serve`:

```bash
rojo build -o TerraMia.rbxl
```

## Come si gioca (prototipo)

- **Ogni giocatore ha la sua fattoria**: fino a 8 per server, ai lati della
  strada bianca che sale al borgo. Si vedono anche le fattorie degli altri.
- **Strumenti** (barra in basso): Raccogli, Zappa, Semina, Annaffia, Concime.
  Si tocca o si clicca un quadrante; tenendo premuto e trascinando si lavorano
  tanti quadranti di fila. Le piante pronte si raccolgono con qualsiasi
  strumento.
- **Zappa:** i quadranti d'erba vanno in coda, 15 secondi l'uno, anche a gioco
  chiuso. Ritoccare un quadrante in coda lo toglie.
- **Semina e acqua:** il seme resta un sacchetto finché non lo annaffi. Il
  pozzo si riempie di una goccia ogni 90 secondi, fino a 20.
- **Concime** (dal livello 2): raddoppia il prossimo raccolto.
- **Nuova terra:** tocca un lotto con il cartello "In vendita". Servono monete,
  un livello minimo e oggetti antichi (dagli ordini e dal forziere che compare
  ogni giorno sulla fattoria).
- **Negozio:** semi, alberi, concime, animali con i biberon, falegnameria e
  cucina, decorazioni. Animali e strutture si posano toccando un punto libero.
- **Il borgo:** il pulsante *Borgo* porta alla porta del paese, in cima alla
  collina. Avvicinati a un edificio e premi il tasto del prompt (E su
  computer): l'abitante racconta cosa serve per riaprirlo. Al restauro il
  rudere sparisce nella polvere e l'edificio torna com'era, con le luci e il
  camino acceso. Ognuno vede il borgo della propria partita.
- **Ordini e turisti:** la bacheca in piazza (o il pulsante *Ordini*, da
  ovunque) mostra gli ordini degli abitanti e, dopo due restauri, i visitatori.
- **Lingua:** quella di Roblox del giocatore; il pulsante in alto a destra la
  cambia (italiano, inglese, francese, spagnolo).

## Struttura

```
default.project.json        come Rojo monta src/ nel gioco
src/shared/   -> ReplicatedStorage.Shared (server e client)
  GameData.luau             dati statici: colture, edifici, livelli, prezzi (dal documento)
  Rules.luau                regole e stato della partita (porting di game_state.gd)
  Locale.luau               traduzioni: Locale.tr("CHIAVE", ...)
  Strings.luau              testi in 4 lingue (generato da tools/translations_source.py)
  BorgoLayout.luau          pianta del borgo (generata da tools/gen_borgo.py)
  WorldConfig.luau          misure e posizioni del mondo 3D
src/server/   -> ServerScriptService.Server
  Main.server.luau          giocatori, fattorie, azioni dal client, tempo, salvataggi
  PlayerData.luau           salvataggio nel DataStore
  WorldBuilder.luau         costruisce luce, prato, strade, collina, mura, edifici, bacheca
  FarmView.luau             la fattoria 3D di un giocatore, aggiornata dallo stato
  Build.luau                pezzi base (blocchi, alberi, tetti, etichette) e colori
src/client/   -> StarterPlayerScripts.Client
  Main.client.luau          avvio del client
  ClientState.luau          ultimo stato arrivato dal server, strumento in mano
  Hud.luau                  contatori in alto, strumenti e pulsanti in basso, messaggi
  Panels.luau               negozio, bacheca, edifici, terreni, strutture, magazzino
  FarmInput.luau            tocchi e clic sulla propria fattoria
  BorgoLocal.luau           il borgo restaurato secondo la propria partita, testi nel mondo
  FarmFx.luau               animazioni delle piante: crescita, maturazione, raccolto
  Ui.luau                   pezzi d'interfaccia e colori del tema
src/tests/    -> ServerStorage.Tests
  RulesTests.luau           test delle regole (porting di tests/test_game_state.gd)
tools/
  translations_source.py    testi in 4 lingue -> src/shared/Strings.luau
  gen_borgo.py              pianta del borgo -> src/shared/BorgoLayout.luau
  run_tests.luau            lancia i test con Lune, fuori da Studio
docs/design.md              documento di design
```

### Scelte tecniche

- **Il server decide.** Lo stato di ogni giocatore vive sul server
  (`Rules`); il client chiede le azioni con il RemoteEvent `Act` e riceve lo
  stato intero con `State` e i messaggi da tradurre con `Message`. Ogni
  argomento che arriva dal client viene controllato (tipo, intervallo,
  esistenza), e c'è un limite di richieste al secondo.
- **Timer reali.** Come nel gioco Godot ogni timer è un timestamp Unix
  assoluto (`Rules.now()`, l'ora del server), quindi il tempo scorre anche a
  gioco chiuso. Al rientro e ogni secondo `Rules.tick` aggiorna moka, pozzo,
  zappa, forziere e turisti.
- **Dati in un posto solo.** Tempi, livelli, prezzi stanno in `GameData.luau`;
  il bilanciamento si fa lì. Le regole sono le stesse di `game_state.gd`.
- **Testi mai nel codice.** I messaggi del server sono chiavi con argomenti
  (`{key, args}`); il client li traduce nella lingua del giocatore. Anche le
  etichette nel mondo (nomi degli edifici, "In vendita") hanno solo la chiave
  (attributo `L10nKey`) e il testo lo mette il client.
- **Un borgo, tante partite.** Il server costruisce ogni edificio due volte,
  rudere e restaurato; il client mostra quello giusto. Le modifiche fatte dal
  client restano solo sul suo schermo.
- **Piante 3D da Blender.** Le colture con un modello (grano, lattuga,
  pomodoro, carota, vite, anguria, castagno, ciliegio, fico, nocciolo, ulivo,
  zafferano, aglio, carciofo, cipolla, mandorlo, melanzana, more, patata,
  pistacchio, rosmarino, zucchina) usano i modelli in `ReplicatedStorage.Modelli` (uno per pianta,
  `TerraMia_<Nome>`, con le fasi `Fase1`…`Fase4` e `Raccolto`). Non sono in
  `src/`: stanno nel luogo pubblicato, quindi con `rojo serve` va aperto quel
  luogo, non un Baseplate. Germoglio nella prima metà della crescita, poi
  crescita, poi matura; gli alberi raccolti restano secchi finché non si
  annaffiano. Le altre piante sono ancora a blocchi.
- **Animazioni sul client.** Il server segna le piante appena cambiate con
  l'attributo `Fx`; `FarmFx` le fa rimbalzare, saltare quando maturano e
  volare dal contadino quando si raccolgono. Chi entra dopo non le rivede.
- **Fattorie grandi:** 8 fattorie da 18×18 quadranti di 6 stud (108 stud di
  lato), due file da quattro ai lati della strada (`WorldConfig`).
- **Il resto è grafica provvisoria a blocchi** costruita da codice, con i
  colori della direzione artistica del prototipo. Collina e strade usano il
  Terrain di Roblox.
- **Salvataggi** nel DataStore `TerraMia_v1`, una chiave per giocatore. Se il
  caricamento fallisce la partita non viene sovrascritta.
- **Modalità sviluppatore** (`GameData.DEV_MODE`): monete infinite e livello
  massimo, ma solo dentro Studio, mai nel gioco pubblicato.

## Testi e lingue

I testi stanno in `tools/translations_source.py`, con le quattro versioni di
ogni chiave. Dopo una modifica:

```bash
python3 tools/translations_source.py
```

Lo script controlla anche che ogni lingua abbia gli stessi segnaposto (`%d`,
`%s`) dell'italiano.

## Pianta del borgo

```bash
python3 tools/gen_borgo.py
```

È lo stesso generatore del prototipo Godot (vie, piazza, colle), che ora
scrive `src/shared/BorgoLayout.luau`.

## Test

Fuori da Studio, con Lune:

```bash
lune run tools/run_tests
```

Dentro Studio, dalla barra dei comandi (*View → Command Bar*):

```lua
require(game.ServerStorage.Tests.RulesTests)()
```

Entrambi stampano `TUTTI I TEST OK` o i controlli falliti.

## Pubblicazione

1. *File → Publish to Roblox*.
2. *Game Settings → Places*: **Max Players 8** (una fattoria a testa; il
   numero sta in `WorldConfig.MAX_PLOTS`).
3. *Game Settings → Security*: abilita le API Services per il DataStore.
4. Controlla che `GameData.DEV_MODE` sia `false` (in ogni caso vale solo in
   Studio).

## Cosa manca rispetto al prototipo Godot

- La grafica illustrata (sprite Flux, icone), la musica e gli effetti sonori:
  su Roblox vanno caricati come asset dal *Asset Manager* di Studio e
  richiamati per ID. Sono nel repository Godot (`assets/`).
- Il contadino che cammina fino al quadrante: qui il contadino è l'avatar del
  giocatore e le azioni sono immediate.
- Gli animali che girano per la fattoria, i carretti e le auto sulla strada,
  gli abitanti a passeggio nel borgo.
- Il tutorial dei primi 15 minuti (è anche nella roadmap del prototipo).

Fuori scopo per ora (dal documento): scambi tra giocatori, classifiche, chat.
Su Roblox però le fattorie degli altri si vedono già: le visite tra amici
vengono quasi gratis.
