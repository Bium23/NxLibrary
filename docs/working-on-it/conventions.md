# Arcane — come si costruisce

Questa guida dice **dove va una cosa nuova e come si scrive**, partendo da quello che il codice fa già. Prima di scrivere codice nuovo, trova qui la ricetta che corrisponde e segui il file d'esempio indicato. Se nessuna ricetta va bene, non inventarne una in silenzio: proponila al maintainer e, una volta approvata, aggiungila qui.

Gli altri documenti:
- [architecture.md](../how-it-works/architecture.md): come funziona ogni area;
- [flows.md](../how-it-works/flows.md): i percorsi completi, dall'input all'effetto;
- [file-map.md](file-map.md): un file per riga;
- [validation.md](validation.md): cosa ha validato il maintainer.

## 1. Dove va il codice

| Cosa | Dove | Perché |
|---|---|---|
| Modelli, regole, parsing, persistenza, rete, processi, decisioni di focus e di layout calcolabili | `Sources/NXLibraryCore` | Si prova con XCTest senza finestre. |
| Codice del Core di un'area | La cartella dell'area: `App`, `Catalog`, `Library`, `Selene`, `Details`, `Artwork`, `Achievements`, `Saves`, `Mods`, `Settings`, `Steam` | Ogni area si trova da un solo posto. |
| Codice del Core che è Switch (nxnative, chiavi, store Nintendo, RomFS, `env.txt`) | `Sources/NXLibraryCore/Porting/` e la sottocartella della parte: `Setup`, `Build`, `Launch`, `GameSettings`, `Cheats`, `Store`, `Saves`, `Mods` | Il confine fra base e modulo si vede dal percorso. |
| Viste SwiftUI, integrazione AppKit, controller, coordinamento degli store | `Sources/NXLibrary` | Dipende dal Core, mai il contrario. |
| Testi mostrati all'utente | `NXLibraryCore/Resources/Localizable.xcstrings` | Un solo catalogo per le sette lingue. |
| Test | `Tests/NXLibraryCoreTests`; prove senza finestre dei corpi reali delle viste in `Tests/CatalogAppChecks`; controlli del pacchetto in `Tests/PublicationChecks` | — |

Regole:
- **Una decisione sta nel Core se si può scrivere senza SwiftUI.** Esempi:
  - quali righe mostra il pannello Details: `DetailsFacts`;
  - dove si sposta il focus: `SpotlightState`, `DetailsFocus`, `ModStoreFocus`;
  - la geometria di una riga: `SpotlightRowGeometry`, `GridListLayout`.

  La vista disegna e traduce l'input.
- **Un file fuori da `Porting/` che usa un tipo di `Porting/` è un legame da tagliare, non un esempio da seguire.** Il codice nuovo della base non aggiunge legami di questo tipo.
- **Un file oltre circa 800 righe si divide per compito** in estensioni `Tipo+Compito.swift` nella stessa cartella. Esempi: `PortingModel+Build.swift`, `SpotlightView+Input.swift`. Le proprietà memorizzate restano nel file del tipo; un membro `private` che serve da un altro file diventa interno, mai `public`. Un controllo senza finestre che legge il sorgente di un tipo legge tutti i suoi file (`PortingModel*.swift`).
- **`public` solo nel Core**, per ciò che l'app usa. Il target app è un eseguibile che nessuno importa: i suoi tipi restano interni.
- **Non far crescere `AppViewModel`.** Uno stato che appartiene a una sola schermata o a un solo pannello ha il suo modello. Esempi: `SavePanelModel`, `SetupCheckModel`, `ModStoreHost`, `AchievementsScreenModel`, `CatalogSourcesModel`. Le estensioni `AppViewModel+…` servono solo a collegare il coordinatore a un servizio del Core.
- **Una parte del modulo Switch ha il suo modello di area.** Esempi: `PortingModel`, `SetupModel`, `RuntimeSettingsModel`, `CheatsModel`, `AppIconModel`, `StoreMetadataModel`.
  - È una `final class` con `unowned let app: AppViewModel`; il coordinatore la crea come `lazy var` con un nome breve (`app.porting`).
  - Raggiunge il resto di Arcane solo da `app`. *Perché:* quell'elenco è ciò che il modulo dovrà chiedere alla base.
  - È `ObservableObject` solo se pubblica stato. Ogni schermata che mostra quello stato lo osserva con `@ObservedObject` (dall'`init` o passato dalla shell), mai attraverso il coordinatore.
  - Un lavoro in background non tocca il modello: è una funzione statica (`PortingModel.sweepStaleBuildTemp`).
  - Nessun nome è uguale fra il modello e il coordinatore.
- **Un solo writer per ogni file su disco.** Il catalogo lo scrive solo `CatalogRepository`, le impostazioni solo `AppSettingsStore`, le sessioni solo `PlaySessionStore`, le mod di un gioco solo `ModStore`.

## 2. Una fonte di giochi (Steam oggi, CrossOver e altre domani)

Esempio completo: Steam, documentato in [steam.md](../how-it-works/steam.md).

- Il gioco entra nel catalogo comune come `CatalogGame` con il **suo payload reale** (`SteamCatalogGame`, `PortedGame`). Non si costruisce mai un gioco di un'altra fonte finto.
- Cosa offre la pagina lo dice `CatalogGamePresentation`: installazioni, operazioni supportate, `CatalogLaunchTarget`. L'ordine delle Opzioni comuni sta in `CatalogGameOptions`. Una fonte dichiara cosa sa fare; non aggiunge schermate parallele.
- I comandi di una fonte ricevono solo il suo payload: i comandi Switch prendono `PortedGame`, quindi non possono partire da un gioco Steam.
- La lettura avviene su un worker annullabile, con limiti di dimensione e di cartelle. Il risultato porta una generazione o un ticket, e un risultato superato non si pubblica (`SteamCatalogReconciler`, `CatalogSourcesModel`).
- Un'assenza non è una cancellazione. Un disco scollegato, una scansione parziale o un titolo ambiguo conservano la voce, gli UUID e le scelte personali.
- I file di altre applicazioni si leggono e non si scrivono mai. Le letture protette passano da `InstallationFileSnapshot` e `InstallationDirectorySnapshot`.
- La fonte è facoltativa: se è spenta non si legge nulla e il resto si comporta come prima.
- **La funzione sta nell'app, il formato sta nella fonte.** Salvataggi, mod e cheat sono una sola schermata ciascuno; la fonte dice dove sono i file e come si leggono.

## 3. Una schermata o un pannello Selene

Esempi: `AchievementsScreen` con `AchievementsScreenModel` (schermata intera), `SavesPanel` con `SavePanelModel` (pannello), `ModStorePage` con `ModStoreHost` (pagina che scorre).

- **Misure in unità del canvas** 1920×1080: `canvas.u(…)` da `SeleneCanvasEnvironment`, mai punti fissi. Colori, curve e font vengono da `SeleneTheme` e `SeleneFonts`, le icone da `MaterialIcon`.
- **Componenti condivisi prima di tutto** (`Views/Components`):
  - `SeleneOptionRow`, `SeleneSettingsRow`;
  - `SelenePillButton`, `SeleneSwitch`, `SeleneValueChip`;
  - `SeleneConfirmDialog`, `SeleneSuccessNotice`;
  - `SeleneHintsBar`, `GamePrimaryActions`, `DetailsPanel`.

  Un componente nuovo nasce solo se nessuno di questi va bene.
- **Focus nel Core, input in un file `+Input`.** Lo stato del focus è un tipo del Core con i suoi test. La vista ha un'estensione `…+Input.swift` che traduce tastiera, mouse e controller in azioni sul modello.
- **Priorità dell'input:** menu e dialoghi nativi vengono prima delle schermate dell'app. La shell (`AppShellView`, `nativeDialogOwnsInput`) sospende il controller prima del routing e condivide il controllo con tastiera e menu. Nell'app dà l'input al livello più alto: un pannello sopra la pagina sospende l'input della pagina sotto.
- **Suggerimenti dei tasti:** `SeleneHintsBar` alla posizione condivisa `SeleneBottomScrim.hintsBottom` (32 unità dal fondo). I simboli vengono da `ButtonPrompts`.
- **Movimento:**
  - un blocco che scorre di un offset animato passa per `GlideGroup`;
  - i loop continui (anelli, bagliori, sfondi) girano in Core Animation o Metal, mai con timer SwiftUI a 30 fps;
  - Riduci movimento si legge da `seleneReduceMotion` e ferma tutto ciò che si muove da solo.
- **Suoni:** `SoundEffectService` con i cue Selene esistenti.
- **Testi:** frasi brevi e semplici, nelle sei lingue (sezione 7).

## 4. Un'impostazione

Esempio: qualunque riga di `SettingsCatalog`.

1. Il valore sta in `AppSettings`, con un default. La decodifica è **compatibile**: un file vecchio senza il campo prende il default, e un valore sconosciuto torna ad Automatic.
2. La riga si dichiara in `SettingsCatalog` (`row`/`action`) con identità stabile, sezione, titolo e descrizione. Così compare in **Search** e in **Changed** e torna al valore iniziale con il reset del gruppo.
3. Va nella sezione giusta di `SettingsSection` / `SettingsSidebarGroup`. Una sezione di piattaforma contiene solo impostazioni che agiscono sui giochi di quella piattaforma. Ogni impostazione sta in un solo posto.
4. Le preferenze fuori da `AppSettings`, come cloud o percorsi, compaiono in Changed attraverso il catalogo. Le credenziali non passano mai da `AppSettings` (sezione 6).

## 5. Un file su disco

Esempi: `AppSettingsStore`, `CatalogStore`, `PlaySessionStore`, `ModStore`.

- **Percorsi solo da `AppData`** (`AppData.supportRoot`, `AppData.cacheRoot`, `AppData.preferences`), così la copia Dev resta separata dalla release. Un file nuovo che la Dev deve ricevere va aggiunto alla lista dichiarata di `DevelopmentProfileImporter`; credenziali e token non si copiano.
- **Formato con versione** e lettura compatibile con i file vecchi; un campo nuovo è sempre facoltativo.
- **Scrittura sicura:** si scrive su un file temporaneo nella stessa cartella e lo si sostituisce in un passo solo. Per un file importante si tiene una copia valida (`.bak`) e si rilegge il candidato prima di pubblicarlo (`CatalogStore`).

  Oggi ogni store scrive per conto suo: non esiste un aiuto condiviso. Un nuovo store segue `CatalogStore` per i dati importanti e `AppSettingsStore` per le preferenze.
- **Un file illeggibile non si sovrascrive in silenzio:** si conserva e si segnala con un dialogo e Retry. Mai una libreria vuota automatica.
- **Eliminare:** si sposta nel Cestino, salvo nei casi documentati. Esempi: la cache di build di un gioco, le cartelle temporanee riconosciute da `BuildScratch.isManaged`.

## 6. Rete, chiavi e dati privati

Esempi: `BoundedDownload`, `GameBananaClient`, `IGDBClient`, `SteamMetadataService`.

- Ogni download passa da `BoundedDownload`, con limite di dimensione, redirect rifiutati e annullamento. Gli host sono fissati in un elenco.
- Richieste coalescenti, un numero massimo in contemporanea, cache su disco con una durata, e uso della copia salvata senza rete. Un errore non diventa un "non trovato" salvato in cache.
- Un risultato che arriva tardi (dopo un cambio di gioco o di lingua, o dopo la rimozione delle credenziali) non si pubblica.
- **Chiavi e credenziali** in un file con modo `0600`, dentro una cartella `0700`. Non vanno mai in log, URL, `AppSettings` o `UserDefaults`. `DiagnosticsReport` toglie la home e i valori che sembrano chiavi.
- Nessun dato personale o privato va in rete, e nessun dato dei giochi altrui viene scritto.

## 7. Testi e lingue

- Ogni testo dell'interfaccia passa da `L10n.text` / `L10n.format` e sta in `Localizable.xcstrings` con en, it, fr, de, es, pt-BR e zh-Hans.
- Le identità restano in inglese e non si traducono: rawValue salvati, rowID, variabili `DM_*`, eventi dell'engine.
- I nomi dei simboli SF (`systemImage`, `systemName`, `systemSymbolName`) sono letterali e non passano da `L10n`: tradotti non trovano il simbolo. `check_localizations.py` lo verifica sui sorgenti.
- Le viste leggono la lingua da `nxAppLocale`, così un cambio di lingua non ricrea stato o focus.
- Controllo: `scripts/check_localizations.py`, che verifica copertura, segnaposto e plurali.

## 8. Lavoro in background e stato

- Il lavoro su file e rete gira fuori dal thread principale; ciò che cambia l'interfaccia si pubblica sul main actor.
- Un processo si aspetta con `Process.runWithExitWait` (o `CommandRunning`), mai con `waitUntilExit`: quello fa girare il run loop mentre aspetta, e un comando atteso dentro un aggiornamento di SwiftUI lo fa ripartire a metà e chiudere l'app.
- Un comando di cui una vista ha bisogno gira in un task fuori dal thread principale prima che la vista lo legga; la vista legge solo la risposta tenuta. Esempio: `EngineAncestry.answer` e `keptAnswer`, chiesti da `CheatsModel.prepare(for:)`.
- Un `body` e l'initializer di una vista non leggono file: si ridisegnano a ogni cambio della shell. Ciò che viene dal disco si legge quando la pagina si apre o quando può cambiare (`GameOptionsFiles`, `GameDetailView.reloadCheats`), e un'assenza si ricorda (`GameIconProvider`).
- Ogni lavoro annullabile porta un'identità (generazione, ticket, UUID del gioco). Il risultato si applica solo se l'identità è ancora quella attuale.
- Le operazioni su un gioco che si escludono a vicenda (salvataggi, Play, installazioni, aggiornamento dell'app) passano da `SaveOperationGate`.
- Niente ritardi a tempo, ridisegni forzati o errori nascosti per far "sembrare" che funzioni (AGENTS.md).

## 9. Test

- Prima il test che fallisce, poi il codice (TDD). Per un bug: prima la causa, poi un test che la riproduce.
- I dati sono sintetici, in cartelle temporanee, con dipendenze sostituibili: `CommandRunner`, trasporti di rete iniettati, `SaveTestHome`, `SteamTestSupport`, `CatalogTestSupport`. Niente file reali dell'utente, niente chiavi o ROM.
- Si prova il comportamento, non il mock.
- La build di release compila senza warning: un warning nuovo si risolve nello stesso commit che lo introduce.
- Comandi in [development.md](development.md#verification). I test non sostituiscono la validazione del maintainer.

## 10. Documentazione

Ogni modifica aggiorna, nello stesso commit:
- la riga del file in [file-map.md](file-map.md) e il totale;
- la sezione della sua area in [architecture.md](../how-it-works/architecture.md), o il documento dell'area (come [steam.md](../how-it-works/steam.md));
- il percorso in [flows.md](../how-it-works/flows.md), se cambia un flusso;
- [validation.md](validation.md), se il maintainer ha validato qualcosa o se c'è una cosa nuova da validare;
- questa guida, se nasce una ricetta nuova approvata.

I documenti descrivono il **presente**. Lo storico ("prima faceva…") va nel [CHANGELOG](../../CHANGELOG.md), nelle note datate (`docs/history/engine-upgrades/`, `docs/history/reviews/`) o nella cronologia git. Il **perché** di una scelta resta invece accanto alla scelta, in una frase.
