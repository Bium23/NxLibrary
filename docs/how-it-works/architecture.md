# Arcane — guida tecnica

Questa guida descrive **come funziona l'app oggi**, area per area. Non contiene storia né stati di validazione: lo storico è nel [CHANGELOG](../../CHANGELOG.md) e nelle note datate, cosa ha provato il maintainer è in [validation.md](../working-on-it/validation.md).

Ordine di lettura per chi lavora sul codice:
1. [AGENTS.md](../../AGENTS.md): le regole.
2. Questa guida: la mappa.
3. [conventions.md](../working-on-it/conventions.md): come si costruisce una cosa nuova.
4. [flows.md](flows.md): i percorsi completi.
5. Il documento dell'area, se c'è (per esempio [steam.md](steam.md)).
6. [file-map.md](../working-on-it/file-map.md): un file per riga.

Il [README](../../README.md) è la guida d'uso; la [guida di sviluppo](../working-on-it/development.md) raccoglie build, runtime, CI e release.

**Engine attuale:** pin `461a5f9f95fc9fc40a690bb2a82eb23f1f03bdca`, definito in `AppViewModel.pinnedEngineCommit`. Il suo lock certifica Metal `32023.922`, asset Apple `27B47`, con Xcode minimo `27.2`. Le revisioni di ogni pin sono in [upstream-upgrades](../history/engine-upgrades/README.md).

## Indice

- [Struttura e dipendenze](#struttura-e-dipendenze)
- [Avvio e stato dell'app](#avvio-e-stato-dellapp)
- [Catalogo, fonti e libreria](#catalogo-fonti-e-libreria)
- [Navigazione e focus](#navigazione-e-focus)
- [Impostazioni](#impostazioni)
- [Lingua e regione](#lingua-e-regione)
- [Setup, engine e compatibilità](#setup-engine-e-compatibilità)
- [Sorgenti e porting](#sorgenti-e-porting)
- [Avvio dei giochi e sessioni](#avvio-dei-giochi-e-sessioni)
- [Pagina del gioco](#pagina-del-gioco)
- [Cheat](#cheat)
- [Mod](#mod)
- [Salvataggi, backup e recupero](#salvataggi-backup-e-recupero)
- [Spazio su disco](#spazio-su-disco)
- [Artwork, metadati e voti](#artwork-metadati-e-voti)
- [Interfaccia Selene e input](#interfaccia-selene-e-input)
- [Dati su disco](#dati-su-disco)
- [Aggiornamenti e distribuzione](#aggiornamenti-e-distribuzione)
- [Verifica e manutenzione](#verifica-e-manutenzione)
- [Steam](steam.md): documento a parte

## Struttura e dipendenze

[Package.swift](../../Package.swift) dichiara tre target. La toolchain Swift è quella di Xcode, con deployment minimo macOS 26 (`LSMinimumSystemVersion` 26.0 nell'app). *Perché:* è la versione più vecchia che il maintainer prova, e il porting chiede comunque macOS 26.6 per Xcode 27.2.

| Target | Compito |
|---|---|
| `NXLibrary` | Eseguibile SwiftUI, integrazione AppKit, controller, notifiche, coordinamento e rendering. |
| `NXLibraryCore` | Modelli, persistenza, parsing, gestione file, contratti del motore, processi e logica delle funzionalità. |
| `NXLibraryCoreTests` | Test XCTest del Core, con dati sintetici e dipendenze sostituibili. |

Il Core ha una cartella per area: `App`, `Catalog`, `Library`, `Selene`, `Details`, `Artwork`, `Achievements`, `Mods`, `Settings`, `Steam`. Tutto ciò che è Switch (Setup, build, avvio, impostazioni del gioco, cheat, store Nintendo, salvataggi e i loro backup, mod RomFS e GameBanana, la parte nxnative del catalogo e della libreria, lo spazio delle app portate) sta in `Porting/`, con una sottocartella per parte. *Perché:* il confine fra la base e il modulo Porting si vede dal percorso; i file della base che usano ancora tipi di `Porting/` sono i legami che il contratto della fonte dovrà tagliare.

`NXLibrary` dipende da `NXLibraryCore`. Il Core usa anche framework macOS, fra cui Combine, AppKit, ImageIO, CommonCrypto e IOKit. Il package non dichiara dipendenze SwiftPM esterne.

```mermaid
flowchart TD
    Entry["NXLibraryApp → MainView"] --> Shell["AppShellView"]
    Shell --> Router["AppRouter e schermate SwiftUI"]
    Shell --> VM["AppViewModel, modelli Switch e modelli dei pannelli"]
    Shell --> Stores["Settings, sessioni, artwork e monitor dei giochi"]
    VM --> Core["Servizi e modelli NXLibraryCore"]
    Core --> Disk["Application Support, app e log"]
    Core --> Process["BuildService e CommandRunner"]
    Process --> Engine["Checkout nxnative al commit fissato"]
    Core --> Network["Cataloghi artwork, metadati e release"]
```

Il checkout nxnative fornisce estrattore, rewriter, shader, profili dei giochi e runtime dei giochi compilati. Arcane prepara gli argomenti, controlla i requisiti e presenta lo stato delle operazioni. La cache dello stato upstream si riusa soltanto quando il suo commit di base coincide con il pin.

## Avvio e stato dell'app

**Finestra e menu.**
- `NXLibraryApp.swift` registra una sola `Window` e i comandi della barra menu. File → Add Game sostituisce New Window: controller, updater e catalogo condiviso non offrono un flusso a più finestre.
- `AppDelegate.swift` registra il font Material Icons e gestisce chiusura e riapertura della finestra. `MainView.swift` presenta `AppShellView`.
- `NativeMenuCommands` osserva il tracking dei menu AppKit e rinvia le azioni al turno successivo della coda principale, mantenendo l'input sospeso durante il passaggio.
- La shell pubblica le disponibilità nella scena attiva tramite `FocusedValues`: benvenuto, Setup, pannelli e assenza di selezione disabilitano i comandi che non si applicano. Mouse, tastiera e controller non cambiano selezione sotto un menu nativo.
- In Spotlight, Game Details usa `SpotlightState.showGameDetails` come il comando interno e conserva il titolo selezionato; in Collection apre la pagina Details. Game Options blocca l'hit testing del contenuto sottostante.

**Profilo dei dati.**
- `AppDataProfile` e `AppData` centralizzano percorsi e preferenze. Il marker di build `NXLibraryDevelopmentProfile` e il bundle ID `local.nxlibrary.development` distinguono la Dev dalla release; la release usa i percorsi di sempre.
- `DevelopmentStartupView` prepara il profilo in background prima di costruire gli store e la shell, senza schermata di preparazione. `LaunchReveal` tiene trasparente la finestra fino al primo frame del moonlight (il drawable presentato, su entrambi i percorsi di rendering), con ripiego dopo 1 s, poi la mostra con una dissolvenza di 0,25 s. Un errore mostra il recupero senza aspettare il moonlight. *Perché:* la transizione fullscreen parte da una finestra già disegnata. `DevelopmentProfileImporter` legge la sorgente senza attivare gli store che la potrebbero riparare, copia in staging una lista dichiarata di dati, verifica gli hash e attiva la destinazione separata.
- Le preferenze storiche appartengono a una lista esplicita; file di credenziali e nuovi token non si copiano per semplice prefisso. Le sessioni rimaste aperte nella copia terminano all'ultimo heartbeat registrato. Ripetere l'avvio non reimporta e non sovrascrive la Dev. La copia fallisce con Retry/Close, senza ripiegare sul profilo stabile.
- Nella Dev il recupero dei salvataggi e la riconciliazione automatica delle icone non partono all'avvio. `DevelopmentOperationStore`, escluso dall'import, registra le richieste esplicite di build e icone e ne permette la ripresa dopo un riavvio. La pulizia automatica visita solo la Temp del profilo Dev, non lo staging sui volumi condivisi. Il factory dei `ModStore` disabilita la manutenzione automatica: consultare e aggiornare le schede non scrive l'overlay né elimina installazioni residue, e la lettura usa lo stato reale dell'overlay. Le azioni manuali agiscono sui giochi reali.
- `release.sh` rifiuta un marker Dev nel pacchetto, e `AppUpdate` rifiuta un pacchetto del genere come aggiornamento.

**Shell.**
- `AppShellState` prepara coordinatore, router, lingua e tema sul main actor prima di pubblicare la shell pronta. L'inserimento nella finestra già visibile conserva gli oggetti preparati. Il bootstrap prepara catalogo e profilo prima della shell, quindi il modello usa quel documento senza una seconda lettura fallibile durante l'inizializzazione.
- `AppShellView.swift` possiede gli oggetti condivisi tramite `@StateObject`: `AppViewModel`, router, impostazioni, sessioni, artwork, monitor dei giochi e updater. Imposta palette, canvas Selene, preferenze di accessibilità e livelli sovrapposti. Benvenuto, Setup, menu, ricerca, opzioni di un gioco e conferme ricevono una priorità esplicita nell’input.
- La shell condivide un solo `AppSettingsStore` con router e coordinatore. L'avvio rispetta i flag di verifica del motore e di scansione della libreria; senza scansione carica il catalogo salvato.
- `startInFullscreen` sta in `AppSettings` (default false), compare in Search e Changed e torna al default con il reset di Start-up. `StartupWindowView` lo legge alla creazione e lo applica una sola volta alla finestra visibile e attiva, dopo `LaunchReveal.whenShown`. `isWindowSettling` tiene ferma l’entrata fino alla notifica di fine transizione, con ripiego a 4 s dall’aggancio alla finestra. Cambiare la preferenza non altera la finestra corrente.

**Coordinatore.**
- `AppViewModel.swift` coordina libreria e catalogo, Locate Sources e rimozione delle sorgenti, lancio (con salvataggi cloud e mod), primo avvio, apertura di Game options, chiusura e rimozione dei giochi, spazio su disco, icona di Arcane nel Dock, avvisi e registro, e tiene lo stato del porting che legge la home.
  - Crea i modelli Switch descritti qui sotto (`lazy var`, per esempio `app.porting`) e li dà alle schermate che li mostrano.
  - Le estensioni `AppViewModel+…` collegano catalogo, fonti, controller, salvataggi, diagnostica, mod, installazioni in attesa, la tile del porting e la chiave SteamGridDB; altre dividono il coordinatore per compito (libreria, lancio, azioni su un gioco, file di un gioco, spazio su disco). Sono parti dello stesso oggetto osservabile; chi scrive le proprietà `private(set)` resta nel file del tipo.
- `PortingModel` tiene Add Game: la bozza (cartella o file scelti, scansione, titoli trovati, selezione delle sorgenti, nome, bundle ID, scelte per il primo avvio, controllo delle chiavi, spazio su disco) e la build: avvio, eventi del motore, annullamento, fine, notifiche, azioni sugli errori riconosciuti e ciò che il passo Porting ne mostra (passo del wizard, fasi, avanzamento, esito ed errore). Tiene anche le cartelle della build e quella finale dell'app, lo spazio libero, le sorgenti che l'engine accetta, l'ultimo comando (per la diagnostica), la durata delle fasi finali per la stima e la pulizia all'avvio dei temporanei vecchi di un giorno (`PortingModel.sweepStaleBuildTemp`, statica perché gira in background).
  - Le viste di Add Game e la riga Game files di Impostazioni → Libreria lo osservano da sole, così un cambio di fase ridisegna solo quelle schermate.
  - Il resto di Arcane legge di un porting solo `isBuilding`, `currentBuildGameID` e `portingProgress` (la tile della home), che restano sul coordinatore; la stima della tile prende da `PortingModel` la durata delle fasi finali.
  - Raggiunge il resto dell'app solo da `PortingModel.app`: libreria, chiavi, engine, catalogo e i valori di Game options. *Perché:* quell'elenco è ciò che il modulo Porting dovrà chiedere alla base.
  - Le installazioni in attesa (`AppViewModel+PendingInstall`) restano sul coordinatore. *Perché:* le avviano anche Play, i salvataggi e la chiusura di un gioco, e il loro dialogo appartiene alla libreria.
- `SetupModel` tiene il Setup Switch: cartella, validità e commit dell'engine, ciò che l'engine sa leggere (`engineSourceCapabilities`), controllo Upstream e Newest engine (`SetupModel+NewestEngine`), chiavi importate (`KeyStore`, riepilogo, importazione), controllo dell'ambiente, compatibilità, override della toolchain non testata e gate (`canPassToolchainGate`).
  - Lo osservano da sole le schermate che ne mostrano una parte: Impostazioni (Setup and engine, Keys, About, la lista Changed), Add Game, Game options, la home e la pagina del gioco (Rebuild segue il gate) e l'offerta di aggiornamento della shell (l'Xcode richiesto).
  - Come `PortingModel`, raggiunge il resto dell'app solo da `SetupModel.app`; `pinnedEngineCommit` resta sul coordinatore.
- `RuntimeSettingsModel` legge e scrive le scelte salvate di un gioco già costruito: Game options, More settings, il ripristino dei default per i nuovi giochi, le variabili che il build supporta. Lo usano anche il porting (scrive le scelte della bozza) e Play. `GameOptionsPresentation` nella base riceve da quelle scelte solo `GameOptionsBuildSettings` (chiavi fisse, righe visibili, scala di rendering, altre impostazioni); la conversione da `GameSettingsSnapshot` sta in `Porting/Details/GameOptionsPresentation+Porting.swift`.
  - Non tiene stato e nessuna vista lo osserva: la verità sono i file del gioco, e le schermate tengono la loro copia.
  - Raggiunge il coordinatore solo da `RuntimeSettingsModel.app`, per il registro, l'avviso di salvataggio fallito e i default dei nuovi giochi.
- `CheatsModel` dice cosa sono i cheat di un gioco e cosa fare dei file aggiunti (vedi [Cheat](#cheat)). Non pubblica nulla: pannello Cheats, riga di Game options e pagina del gioco lo leggono quando si aprono o si ricaricano. Se l'engine dell'app ha i cheat lo dice git, che `prepare(for:)` interroga fuori dal thread principale; finché la risposta manca, `cheatContext(for:)` è nil e chi legge non mostra nulla sui cheat. Da `CheatsModel.app` legge solo la cartella dell'engine.
- `AppIconModel` scrive l'icona nell'app del gioco (vedi [Artwork, metadati e voti](#artwork-metadati-e-voti)) e tiene ciò che serve mentre lo fa: icone in corso o da rifare, log delle build che aspettano l'esito, la richiesta di Play in attesa e l'avanzamento per gioco.
  - Lo osserva da sola Change artwork, per la riga di stato dell'icona.
  - Raggiunge il resto dell'app solo da `AppIconModel.app`: libreria, catalogo, avvisi, Play e lo stato della build. La ricerca online dell'icona automatica (`AppViewModel.automaticIconArtwork`) resta sul coordinatore perché la usa anche Steam.
- `StoreMetadataModel` (`app.store`) tiene ciò che lo store Nintendo dice di ogni gioco nella lingua dell'app: caricamento alla selezione o all'apertura, coda in background dopo un cambio di lingua, screenshot di ripiego, scelte di Change metadata sopra i dati dello store, cache.
  - Lo osservano da sole le schermate che lo mostrano: Spotlight, Collection, la pagina del gioco, Game options, Change artwork, Change metadata, la schermata di lancio e la card di fine sessione (attraverso la shell).
  - Raggiunge il resto dell'app solo da `StoreMetadataModel.app`: libreria, gioco in primo piano e chiave di personalizzazione. L'indice delle copertine GameTDB (`refreshBoxArtIndex`) resta con `boxArt` sul coordinatore, perché serve le copertine di tutta la libreria.
- Gli stati di un solo pannello hanno il loro modello: `SetupCheckModel`, `SavePanelModel` (anteprima, operazione in corso, errore, ultimo backup, importazione riuscita) e gli altri elencati in [conventions.md](../working-on-it/conventions.md#1-dove-va-il-codice). Gli aggiornamenti destinati alla UI si pubblicano sulla coda principale.

**Primo avvio.**
- Il primo avvio apre su `found`: cosa c'è già sul Mac, letto senza cambiare nulla.
  `FirstRunFindings` conta i giochi Steam per Mac installati (`.nativeReady`) e le app portate nella
  cartella Game apps; `FirstRunFindingsReader` legge in un worker annullabile. Open library è utilizzabile anche durante la lettura: annulla la richiesta prima di completare il Setup, senza inventare risultati o attivare fonti non scelte. Le fonti restano aggiungibili dalle Impostazioni; un risultato tardivo è scartato dal requestID.
- La scoperta usa `CatalogSourcesModel.discoveryRoot`: cartella scelta nella fonte, anche spenta,
  altrimenti quella standard. Una lettura incompleta o fallita mostra Retry senza interruttore;
  non equivale a nessun gioco trovato. Retry ripete la lettura senza attivare la fonte.
- La riga Steam pronta ha un interruttore acceso; le app portate sono una riga informativa;
  Porting apre i requisiti. `FirstRunSetup.steamChoice` si salva in `NXLibrary_SetupSteamChoice`
  finché il Setup è incompleto, così resta anche dopo una chiusura durante Porting.
  Quando il primo avvio finisce da Open library, Your games o Skip, la shell applica la scelta
  con `CatalogSourcesModel.configure`. Open library completa il Setup; la fonte Switch si
  accende solo se c'erano app portate, che entrano subito nella libreria.
- Dalla card Porting il Setup prosegue in Get ready e Your games; B su Get ready torna a `found` durante il primo avvio. Skip for now completa l'introduzione anche con libreria vuota. La verifica prima di ogni porting resta obbligatoria, e i pannelli di build possono avviarla su richiesta. I risultati asincroni di un checkout precedente si scartano, e il porting registra la propria fotografia della toolchain.
- `FirstRunSetup` tiene insieme pagina corrente e completamento. `NXLibrary_SetupPage` permette di riprendere una configurazione interrotta; `NXLibrary_SetupSteamChoice` conserva la scelta facoltativa (acceso, spento o mai scelta) e si elimina al completamento, dopo averla mantenuta nel modello per la shell; `NXLibrary_SetupCompleted` mantiene compatibili gli utenti già configurati e impedisce ripetizioni automatiche dopo Skip. Una configurazione completata non torna mai a `found`; Open Setup riapre manualmente Get ready e Your games senza rendere incompleta una configurazione precedente.
- `YourGamesSetupView` aspetta la scansione prima di distinguere libreria vuota o pronta; Open library e Skip tornano alla libreria. `FoundGamesSetupView` e Your games disegnano le righe con `SetupCardRow`. Le pagine condividono backdrop, indicatore, transizioni e canale di input; Add Game sospende il proprio input quando Setup è davanti.
- **Benvenuto in Arcane.** Chi aggiorna da NX Library vede una volta `ArcaneWelcomeView`: il nome nuovo, quattro novità, l'offerta di Steam se è trovato con giochi e la sua fonte è spenta (la ricerca e l’attivazione usano la stessa `discoveryRoot`; Add accende la fonte con `CatalogSourcesModel.configure`, Not now non accende nulla) e Open library. `ArcaneWelcome` decide: Setup completato, `AppSettings.welcomeArcaneShown` falso e nessun recupero in corso.
- `AppShellState` decide il benvenuto prima di pubblicare la shell, così la libreria non compare in mezzo. Benvenuto e pagine Setup chiedono lo sfondo alla shell come ogni pagina (`SeleneBackdropRequest`): il moonlight è uno solo, quindi chiuderli lascia lo stesso sfondo in movimento. I recuperi si aprono sopra; se il benvenuto non era dovuto all’avvio, la shell lo presenta più tardi solo quando Setup, dialoghi, lancio e visore sono chiusi e nessuna operazione sui salvataggi è in corso (`hasActiveSaveOperations`). Il Setup ha precedenza nel disegno e nell’input.
- Fino alla fine della dissolvenza del benvenuto, `AppViewModel.isWelcomeOpen` fa cedere la tastiera ai monitor delle schermate sotto e trattiene l’entrata di Spotlight, come `isUpdateOfferOpen` per l’offerta di aggiornamento; `ShellOverlayInputTests` controlla che ogni monitor ceda a entrambi. Ogni uscita (Open library, B, Esc) prima sfuma, poi salva e passa alla libreria (`SeleneTheme.screenDuration` dopo). Le uscite e la fine di un primo Setup impostano `welcomeArcaneShown`, così un’installazione nuova non lo vede mai. Non tocca `RunningGameMonitor` né `SteamPlayCoordinator`: un gioco aperto resta giocabile.

## Catalogo, fonti e libreria

**Il catalogo comune.**
- `CatalogGame` conserva il record della sua fonte, un `any CatalogSourceRecord`: il `PortedGame` completo per nxnative (conformità in `Porting/Catalog/PortedGame+Catalog.swift`) oppure `SteamCatalogGame` (`SteamCatalogGame+Record.swift`). Il protocollo porta identità, preferito e nascosto, validazione, presenza (`CatalogRecordPresence`) e termini di ricerca; due voci sono uguali solo con record dello stesso tipo e valore. Nome, UUID e scelte personali hanno un solo proprietario; il riferimento alle personalizzazioni conserva chiave e namespace dell'integrazione. Non si costruisce mai un falso gioco nxnative per Steam.
  - `CatalogIntegration` è un nome aperto (`"steam"` nella base, `"nxnative"` dichiarato dal modulo). I tipi che un lettore conosce (`CatalogRecordKinds`) arrivano al decoder in `userInfo`; senza, conosce solo Steam. `CatalogStore` li riceve alla creazione insieme all'import legacy (`CatalogLegacyImport`): `CatalogStore(directory:)` del modulo passa `CatalogRecordKinds.standard` e `CatalogLegacyImport.nxnative`. *Perché:* la base legge il catalogo senza conoscere il formato Switch, e senza il modulo i giochi Switch restano conservati.
- `CatalogGamePresentation` espone installazioni, operazioni supportate e un target di avvio tipizzato, senza avviare servizi o consultare il disco. La disponibilità dell'avvio resta distinta dal supporto dell'operazione, e una fonte disattivata non produce un target utilizzabile.
- `CatalogDocument` (versione 1) contiene revisioni, fonti abilitate e fingerprint della base legacy riconosciuta alla conversione o dopo una scelta esplicita di conservare il catalogo.
  - Un gioco o una fonte la cui `integration` non è nota (scritti da una versione più nuova, o da una con un modulo di fonte in più) si legge come `CatalogJSON` in `preservedGames` / `preservedSources` e si riscrive intatto dopo quelli noti; nessuna proiezione, ricerca o schermata lo vede e nessuno lo modifica. `validate()` ne controlla solo la forma (`integration` stringa, `data` oggetto), l'unicità della fonte e dell'`id`. I numeri restano `Decimal`. *Perché:* un catalogo con una fonte in più non deve diventare illeggibile né perdere giochi. `CatalogGame` da solo continua a rifiutare un'integrazione sconosciuta.
- `CatalogStore` legge input regolari fino a 16 MiB.
  - Un profilo senza catalogo riceve il documento dell'import legacy, se lo store ne ha uno e il file c'è; altrimenti un catalogo vuoto con una fonte spenta per ogni tipo noto.
  - `CatalogLegacyImport` dà i nomi dei due file (principale e backup) e la conversione. Quello del modulo (`CatalogLegacyImport.nxnative`, in `Porting/Catalog/CatalogStore+Porting.swift`) converte direttamente i byte di `library.json` (formato precedente, descritto da `LibraryFile`) con `CatalogDocument.converting`, mantiene UUID, record e chiavi e lascia `library.json` intatto.
  - Il fingerprint della base legacy, la sua verifica a ogni lettura e il conflitto (`legacyConflictCandidate`, `keepCurrentLibrary`) usano gli stessi due file; uno store senza import legacy non ne ha.
  - Le scritture concorrenti usano un lock non bloccante e la revisione attesa. Il candidato si serializza, si rilegge e si valida prima della pubblicazione atomica; una copia valida precede la sostituzione del principale.
  - Archivio danneggiato, versione sconosciuta, input legacy cambiato e principale assente con backup richiedono un recupero esplicito, mai una libreria vuota automatica. L'offerta di ripristino conserva gli hash di principale e backup: se i file cambiano, l'offerta non vale più; il principale danneggiato si conserva e il backup resta intatto.
  - Se il catalogo è valido ma la vecchia app modifica gli input legacy, `DevelopmentStartupView` offre **Keep Arcane's library**. `CatalogLegacyConflictCandidate` cattura le impronte di catalogo, backup e input; `keepCurrentLibrary` le rivalida sotto lock e archivia i byte presenti in una cartella esclusiva `catalog-conflict-*` prima di riconoscere la nuova base legacy. Mantiene giochi e fonti Arcane, senza fusione e senza scrivere sui file legacy. Il catalogo e il suo restore point usano la stessa base riconosciuta; una successiva modifica legacy torna a bloccare letture e scritture. *Perché:* una vecchia copia riaperta dopo un aggiornamento manuale non deve imporre di scartare il catalogo nuovo.
  - `commitUncertain` segnala un errore della sincronizzazione finale dopo una possibile pubblicazione: il chiamante rilegge la revisione prima di ritentare.
  - Il formato usa i valori Date Codable per conservare le frazioni; solo l'ingresso legacy usa ISO8601.
- `CatalogRepository` è l'unico writer del catalogo. Carica la versione corrente e applica ogni modifica tipizzata una volta; non ritenta da solo operazioni con effetti sui file. Le modifiche nxnative (`updateNXNative`, `mergeNXNative`, `recordNXNativeBuild`) sono estensioni in `Porting/Catalog/CatalogRepository+Porting.swift` sopra la sua `transaction`. Le scansioni confrontano la generazione osservata con build, installazione e sorgenti correnti prima di aggiornare i campi; una richiesta di refresh durante una scansione resta in coda.
- `AppViewModel` pubblica il catalogo e una proiezione nxnative di sola lettura. Scansioni, icone, sorgenti e risultati delle build passano dallo stesso repository; le righe mostrate non si salvano mai come libreria di ripiego.
- Il risultato di una build aggiorna soltanto i campi di sua competenza. Un risultato non salvato resta in `CatalogBuildRecoveries` (`Porting/Catalog/`) per il retry della generazione giusta; le installazioni automatiche aspettano che sia risolto. Il risultato e il menu File tengono disponibile l'azione di salvataggio anche dopo la chiusura dell'avviso.
- `CatalogPersonalizations` porta i riferimenti alle viste e ai loader; i percorsi nxnative restano quelli di sempre, i dati personali Steam hanno una radice separata. L'importatore Dev comprende i file del catalogo.

**I giochi Switch (nxnative).**
- `PortedGame` rappresenta un titolo nxnative: identità, app installata, sorgenti, impostazioni runtime, ultimo porting, toolchain e installazione eventualmente differita.
- `ImportService` scansiona i bundle `.app` nelle sole cartelle scelte e riconosce un gioco da `DMTitleID` o dal bundle ID `org.nxnative.<title ID>`. La visita è in ampiezza, fino a sei livelli e 4000 cartelle, con deduplicazione dei percorsi canonici. Non entra in bundle e package e non segue i link delle sottocartelle.
- Limiti e letture fallite producono avvisi con motivo e azione utile, visibili accanto a Scan game apps e, nel primo Setup, sotto Game apps. Non aprono dialoghi automatici né cicli di Retry all'avvio e non cancellano il catalogo; una scansione successiva li aggiorna o li toglie.
- `appsForLibrary` sceglie una sola osservazione per titolo: il percorso già registrato se esiste, altrimenti la più recente. Un'app fuori dall'area scandita lascia invariata la sua voce. Merge e metadati usano la stessa scelta.
- `NXNativeLibraryMerge` parte dalla voce salvata e aggiorna esplicitamente i dati osservati. Conserva impostazioni, identità, preferiti, installazione in attesa ed errore dell'ultimo porting, e la provenienza di una build installata.
- L'aggiunta o il collegamento esplicito delle sorgenti usa `merge(replacingSources: true)`: la selezione confermata sostituisce sorgenti, workspace e percorso della cache, anche se i file precedenti esistono ancora. I file originali restano sul disco. Le scansioni automatiche conservano la selezione registrata e il bundle installato.
- `GameResourceState` riconcilia app, sorgenti e stato. Conserva build in corso e workspace non ancora compilati, distingue app mancante da file d'origine mancanti e mantiene Play per una build esistente. Le viste usano `PortingPills.unavailable` per il motivo breve e l'azione primaria disabilitata; `PortingTileLook.locked` riusa sfocatura e lucchetto. La voce resta in libreria: non si cerca l'app spostata, e Refresh controlla le cartelle già configurate. Un cambio di cartella durante la scansione scarta il contesto precedente e avvia quella nuova.
- `AppSizeCache` ricorda le dimensioni per percorso e data di modifica.
- Settings → Library usa un'unica riga **Scan game apps** per scoperta e refresh, disabilitata durante la scansione (anche come azione del controller). Collection conserva il proprio ingresso per importare build esistenti.

**Le fonti.**
- `CatalogSourcesModel` tiene configurazione e stato della fonte Steam e la richiesta di scansione corrente. La lettura avviene su un worker annullabile. Disattivazione, cambio di cartella o nuova richiesta invalidano il risultato precedente. La generazione salvata distingue anche disattivazione e riattivazione sulla stessa radice; nei cataloghi schema 1 più vecchi il valore mancante si legge come una sentinella fissa. Un risultato valido si applica all'ultima revisione conservando le modifiche indipendenti ai preferiti.
- `SteamCatalogReconciler` applica snapshot già letti, con un ticket legato alla revisione e alla radice. La fusione mantiene UUID, preferiti, nascosti e installazioni storiche. Un titolo ambiguo resta da verificare, una scansione parziale conserva le osservazioni non viste, una fonte assente segnala indisponibilità; l'assenza diventa "non rilevato" solo con uno snapshot completo. `needsInstallationReview` tiene l'ambiguità separata dalla disponibilità del disco. Nessun record o file di gioco viene eliminato.
- Menu → Manage sources e Settings → Sources attivano Steam, aggiornano o annullano la ricerca, scelgono la sua cartella e recuperano titoli nascosti o installazioni da controllare. L'avvio scansiona solo Steam già abilitato. Adottare esplicitamente sorgenti o build Switch abilita nxnative nello stesso catalogo; una scansione passiva non attiva un'esperienza non scelta.
- Tutto il resto di Steam è in [steam.md](steam.md).

**La libreria mostrata.**
- `CatalogLibraryProjection` seleziona le voci delle fonti attive. Spotlight, Collection e ricerca usano gli stessi record, UUID, filtri e ordine salvato; le viste specifiche ricevono il record reale.
- I giochi Steam mostrano l'icona della propria app Mac e la fonte, senza interrogare servizi Nintendo né riscrivere bundle. Hanno la stessa testata, pagina e Opzioni dei giochi nxnative. I titoli nascosti restano recuperabili dalle fonti.
- Menu e comandi specifici nxnative ricevono soltanto `PortedGame`: selezionare un gioco Steam non può avviare una build né aprire salvataggi o mod Switch.

## Navigazione e focus

- `AppRouter` gestisce schermata corrente, cronologia di ritorno e richieste di selezione. `SpotlightState`, `LibrarySelectionState`, `DetailsFocus`, `MenuSelectionModel` e `FocusIndex` descrivono il focus indipendentemente dal disegno SwiftUI. `LibraryQuery` applica ricerca, filtri e ordinamento a qualunque gioco che dia `LibraryQueryRecord` (id, nome, preferito, nascosto, installato, termini di ricerca); le entrate per `PortedGame` di filtro, selezione e Surprise me sono estensioni in `Porting/Library/`.
- Le viste principali sono Spotlight, Collection e Details. Ricerca, Add Game, Console, Game Options e Settings si raggiungono dalla shell e dalle azioni del router. Le estensioni `…+Input.swift` traducono tastiera, mouse e controller in modifiche ai modelli di focus.
- **Righe di tessere.**
  - `SpotlightTileArtwork` e `SteamArtwork` leggono l'immagine già decodificata dalla cache anche nel primo body, prima della `.task`. `TileArtMemo` distingue fonte, richiesta e revisione della scelta personale, con limiti di 200 immagini e 160 MB. `GameIconProvider` ricorda anche i giochi senza icona quadrata, per percorso dell'app e del workspace: la build sposta il gioco sulla sua app, e `forget` legge di nuovo dopo un cambio d'icona. Steam include il build ID dell'installazione e rivalida i file nel task senza svuotare l'immagine durante la lettura. *Perché:* tornando da Settings le viste sono nuove, ma l'arte già caricata non deve passare dal ripiego mentre il task riparte.
  - Le righe di Spotlight e Collection mettono ogni tessera al suo posto e scorrono con un'unica camera (`SpotlightRowGeometry`): la riga si muove come un pezzo solo, e una tessera creata al bordo mentre la riga scorre non arriva prima delle vicine.
  - Lo scorrimento è una molla smorzata: a pressioni rapide riprende la velocità che ha invece di ripartire ogni volta. Le tessere si creano quattro oltre ogni bordo dello schermo.
  - In Spotlight posto e dimensione di ogni tessera e la camera si ricavano da un solo valore animato, la posizione della selezione (un indice, con frazioni a metà strada). *Perché:* animati separatamente, la crescita di una tessera partiva un paio di fotogrammi dopo il suo spostamento e la tessera si staccava dalla vicina.
  - Una selezione che salta più tessere scorre attraverso quelle in mezzo; mentre una tessera è sollevata per spostarla cresce solo lei.
  - In Spotlight sinistra e destra sulla riga lavorano sulla lista filtrata. La parte sotto gli screenshot si monta quando la pagina sale, così navigare tra tessere evita il calcolo di descrizioni, classifica e link fuori schermo.
- **Entrata di Spotlight** (`SpotlightView+Entrance`, tempi e fasi in `SpotlightEntrance`).
  - C’è solo la prima volta che una home si vede dopo l’avvio, se è Spotlight (`AppViewModel.homeSeen`, che segna anche Collection), con **Entrance animation** accesa e mai con Riduci movimento. La chiave `introAnimation` resta compatibile; la shell usa lo stesso interruttore per il suono di avvio.
  - Benvenuto e Setup, fino alla fine della chiusura, e la finestra che prende il fullscreen tengono l’entrata coperta. L’arte è nascosta (`ArtReveal.hidden`); riga e informazioni si preparano a opacità 0,001, mentre barra e pillola sono nascoste e non ricevono input. *Perché:* il primo disegno delle tessere avviene prima del volo. Benvenuto e Setup chiedono alla shell lo stesso sfondo condiviso, così chiuderli lascia lo stesso moonlight in movimento.
  - Scoperta la home, il moonlight ha 0,5 s da solo. Poi l’entrata aspetta, per al massimo un altro secondo, che finisca la prima ricerca dell’arte (`TileArtPendingKey`, da `SpotlightTileArtwork` e `SteamArtwork`).
  - L’arte entra in 1,4 s con la curva di `OpacityFade`, come lo scorrimento fra giochi. Il moonlight continua a muoversi finché l’arte è entrata; anche la prima immagine arrivata tardi sfuma (`SeleneArtLayerView.heldOnce`).
  - Ogni tessera visibile parte più vicina al centro della riga (75% della distanza), con scala 0,35 e spostamento verticale −18 unità; vola in 0,9 s, con dissolvenza di 0,5 s, da 0,6 s più 0,06 s per tessera. Le tessere oltre il bordo destro fanno solo una dissolvenza, al massimo dodici. `EntranceFlight` e `EntranceFade` calcolano movimento e opacità su orologi lineari avviati insieme, con il ritardo dentro ogni effetto.
  - Le informazioni salgono di 40 unità da 1,3 s, in 0,8 s, con dissolvenza di 0,7 s; il titolo sotto la selezione arriva da 2 s. `SpotlightEntrance.end(of:)` determina l’atterraggio finale. Le [misure dell’entrata](../history/reviews/2026-11-17-entrance-frames.md) descrivono metodo, campioni e limiti della sonda temporanea.
  - Barra in alto (tab e orologio) e hint dei pulsanti (`SeleneHomeChrome.hintsHeld`) arrivano per ultimi, insieme: a volo finito sfumano in 0,4 s (`SpotlightEntrance.controlsFade`). La pillola del filtro sale con lo sfondo.
  - Nessun input salta l’entrata. Fino all’atterraggio (`Phase.takesInput`) Spotlight ignora controller, tasti e rotella e non riceve clic; passano solo le scorciatoie con ⌘, ⌃ o ⌥. *Perché:* l’entrata è l’apertura dell’app e va vista intera. Un volo iniziato atterra comunque entro 5 s (`SpotlightEntrance.longestWait`), così l’input non resta mai bloccato.
  - Uscendo da Spotlight, ridimensionando durante il volo o accendendo Riduci movimento, tutto atterra subito, barra e hint compresi.
- **Cursore a schermo intero.** `FullscreenCursorView` (un NSView nella shell) osserva finestra, mouse e transizioni native; `CursorIdleState` decide la visibilità con il tempo monotono.
  - In fullscreen, con il mouse nel contenuto, il puntatore si nasconde dopo tre secondi senza movimento. Cambi di schermata, menu interni, ricerca, opzioni, tastiera, controller, clic e scroll non lo rendono visibile; un movimento riavvia il ritardo.
  - La posizione reale si campiona anche dal timer, perché i loop nativi di menu e controlli possono consumare gli eventi prima del monitor locale. Durante un menu nativo non parte un nuovo nascondimento, ma un puntatore già nascosto resta nascosto; alla chiusura si riallinea lo stato AppKit.
  - Pannelli di sistema, perdita di focus e uscita dal fullscreen ripristinano la visibilità. Il distacco rimuove monitor, timer e osservatori e ripristina il precedente `acceptsMouseMovedEvents`.

## Impostazioni

**La barra laterale.** `SettingsSidebarGroup` raggruppa le sezioni: Search e Changed, poi quattro gruppi.
- **General:** Start-up, Navigation, Spotlight, Sound & music, Look, Controllers, Online services.
- **Library:** Sources, Games, Storage. Valgono per i giochi di ogni fonte.
- **Porting:** Setup and engine, Keys, Library, New games, Cloud saves, Storage. Valgono solo per i giochi convertiti.
- **System:** About, Console. In `SettingsAboutSection`, il pulsante di sostegno volontario a tutta larghezza, prima dei crediti, mostra l’icona di Buy Me a Coffee e apre la pagina nel browser predefinito. Clic, tastiera e controller usano la stessa azione.

Regole della barra:
- Porting è l'unico gruppo di piattaforma (`isPlatform`): Search, Changed e il titolo di pagina chiamano le sue sezioni col nome del gruppo ("Porting · New games").
- `SettingsSection` dichiara i casi nell'ordine della barra, quindi `allCases` la percorre come è disegnata. I `rawValue` sono identità e non cambiano: `sources` è la pagina Sources, `library` e `games` sono Library e New games di Porting; i casi nuovi (`libraryGames`, `keys`, `cloudSaves`, `portingStorage`, `console`) hanno identità proprie.
- Ogni riga di `SettingsCatalog` tiene il suo `rowID` quando cambia sezione.
- Dove stanno le righe che si potrebbero cercare altrove:
  - schermata di lancio, Surprise me, card della sessione e giochi nascosti in Library → Games, perché valgono per ogni fonte;
  - Rumble e Rumble strength in Porting → New games, perché sono default copiati nei nuovi giochi convertiti;
  - prod.keys in Porting → Keys; Check engine at launch e Setup in Setup and engine, dove Compatibility ripete già il controllo dell'ambiente;
  - Refresh library at launch e Box covers in Porting → Library;
  - le cache di compilazione, per gioco e per tutti, in Porting → Storage; spazio usato, log, cache di metadati e artwork e backup in Library → Storage;
  - App icon in Look: è l'icona del Dock.
- Online services (`apiServices`) raccoglie IGDB (voti) e SteamGridDB (artwork). La nota iniziale dice che le connessioni sono facoltative e che le fonti pubbliche funzionano senza chiavi. Non esiste un reset di gruppo che elimini le credenziali.

**Chi decide cosa.**

| Punto dell'interfaccia | Autorità |
|---|---|
| Settings → Porting → New games | Valori iniziali copiati nei nuovi titoli, vibrazione compresa. |
| Game Options → Next launch | Configurazione di quel titolo, applicata al prossimo avvio. |
| Use new game defaults | Copia una volta i default correnti nel gioco selezionato. |
| Add Game → Review | Nuovo titolo: parte dai default. Titolo esistente: `GameRuntimeConfig.forReview` legge le sue opzioni effettive. La conferma salva i valori mostrati. |
| Cloud saves | Preferenza riapplicata prima di ogni avvio, compreso Off. |
| Controllers | Navigazione della libreria. |

- Options e Play passano da `RuntimeSettingsModel`. Un build con le scelte salvate usa `NXNativeGameSettings`; uno più vecchio ripiega su `GameRuntimeConfig.load`: prima le preferenze per titolo in UserDefaults, poi `env.txt` del titolo, poi quello nel bundle, infine i valori del modello.
- Il rebuild ricava `languageForBuild` dalla configurazione del titolo e non tiene una lingua separata dal wizard. I default globali cambiati non aggiornano da soli i giochi già aggiunti. Search e Changed attribuiscono la vibrazione a Porting · New games.

**Catalogo e salvataggio.**
- `SettingsCatalog` descrive i singoli controlli: la base tiene le righe delle sezioni fuori dal gruppo Porting, `SettingsCatalog+Porting.swift` quelle del gruppo Porting e compone l'elenco completo `all`, ordinato per sidebar. *Perché:* ogni sezione viene da un solo elenco, così l'ordine resta quello dichiarato. Changed riceve anche le differenze delle preferenze esterne ad `AppSettings`. Le azioni del controller si aggiornano con lo stato dei pannelli e mantengono il focus per identità. About pubblica azioni selezionabili.
- Reset group è possibile dove `SettingsReset.canReset` lo dice. `SettingsReset.reset` rimette ai default i valori `AppSettings` della sezione in una sola assegnazione (la base in `resetShared`, New games in `SettingsReset+Porting.swift`); la schermata azzera accanto le preferenze esterne (tema applicato, icona dell'app, zona morta della levetta, cartella Game apps) e segnala la cartella delle sorgenti conservata. Cloud saves e le credenziali non hanno reset.
- `AppSettings` tiene le impostazioni del modulo Porting (`gameDefaults`, `cloudSaves`, `cloudSavesPickedFolder`, elencate in `moduleKeys`) come `CatalogJSON` intatto in `moduleValues`; `AppSettings+Porting.swift` le legge e scrive con i tipi del modulo, sotto le stesse chiavi. Un valore assente o illeggibile vale il suo default; un file nuovo scrive la chiave solo dopo una scelta. Le altre chiavi sconosciute si scartano. *Perché:* una chiave ritirata può contenere un segreto (la vecchia chiave SteamGridDB).
- `AppSettingsStore` salva `settings.json` tramite un file temporaneo, pubblica gli errori e conserva una copia di un file illeggibile prima di permetterne la sostituzione. La UI usa un dialogo Selene con Retry per una scrittura fallita.
  In Spotlight e Collection l'ultimo gioco selezionato è stato di navigazione nello stesso store, senza notificare gli osservatori delle impostazioni a ogni movimento. Lo store include lo stesso campo nel JSON, accoda la scrittura in background e sostituisce le scritture ancora in attesa con la selezione più recente. Un salvataggio esplicito e la chiusura conservano la selezione corrente.
- `GameRuntimeConfig.save` propaga gli errori di `env.txt` e salva le preferenze per titolo solo dopo una scrittura riuscita. Un `env.txt` illeggibile si conserva e si segnala.

## Lingua e regione

**Scelta della lingua.**
- `AppLanguage` definisce auto/en/it/fr/de/es/pt-BR/zh-Hans. `AppLocale` risolve le preferenze ordinate del Mac e una regione indipendente, valida i codici e mappa pt-BR a pt soltanto per Nlib.
- Per il cinese `AppLanguage.supported` accetta zh-Hans e zh senza script; zh-Hant, TW, HK e MO passano alla preferenza successiva, perché non c'è una traduzione tradizionale. I formati usano `zh-Hans_<regione>`, Nlib riceve `zh` (senza descrizioni cinesi, quindi About this game cerca l'introduzione di Wikipedia) e Steam `schinese`.
- `AppSettings` conserva i due override in modo additivo: vecchi file e scelte non riconosciute tornano ad Automatic.
- `DevelopmentStartupView` carica un solo `AppSettingsStore`, configura il locale e passa lo store a `MainView` e `AppShellView`. Gli initializer delle viste non pubblicano cambi di locale, perché il controllo sincrono della toolchain può far rientrare il run loop mentre SwiftUI costruisce i propri StateObject.

**Propagazione alle viste.**
- `AppLocalization` pubblica il contesto. La shell lo propaga alle viste tramite `nxAppLocale`, una dipendenza SwiftUI esplicita che non ricrea identità o stato.
- Settings passa questo valore alla barra laterale, e `SettingsSection.title(in:)` risolve le categorie nel contesto ricevuto, anche con il focus sulle righe. Righe, informazioni, pannelli e suggerimenti condivisi usano lo stesso valore.
- `L10n` tiene al massimo un bundle per ciascuna delle sette lingue. Le risorse iniettate restano isolate, senza memorizzare testi interpolati o dati personali. Cattura il contesto per il lavoro asincrono e legge il catalogo compilato, cercando prima nel bundle installato. Non si usa nessun servizio esterno di posizione o traduzione.

**Testi.**
- I testi controllati dall'app sono nel catalogo condiviso `NXLibraryCore/Resources/Localizable.xcstrings`, con interpolazioni e plurali.
- Restano indipendenti dalla lingua: dati personali, rawValue salvati, regex, eventi dell'engine, variabili `DM_*` e identità dei controlli.
- I componenti Settings risolvono le etichette alla presentazione e mantengono i rowID originali; le righe con i nomi dei giochi usano i titoli così come sono. Search confronta anche i testi tradotti.
- I testi upstream noti di `launcher.json` si localizzano solo nella presentazione; valori e note sconosciute tengono il testo upstream.
- Il nome dell'app, "Arcane", sta in `AppIdentity.name` e non si traduce: le viste che mostrano solo il nome lo leggono da lì, e il catalogo non contiene più il vecchio nome. Bundle ID, cartelle dei dati, chiavi delle preferenze e segni `.nxlibrary-*` tengono il nome storico, perché cambiarli separerebbe i dati di chi aggiorna.
- Ogni richiesta di rete si presenta con `AppIdentity.userAgent()`, cioè `Arcane/<versione> (macOS; +https://github.com/Bium23/NxLibrary)`.
- **Open project docs** in About apre `AppIdentity.documentationPage`, il README online, nel browser predefinito: è la guida per i giocatori e si apre su ogni Mac, senza dipendere da dove sta il codice sorgente.

**Start-up.**
- Start-up ospita lingua e regione. `LocalePicker` offre la scelta diretta delle lingue e cerca i nomi localizzati delle regioni per codice stabile, con input da tastiera e controller distinto da Settings.
- Le righe distinguono la lingua di menu, generi e descrizioni dai soli formati regionali. Il cambio non ricrea router o sessioni e non cambia la lingua di nessun gioco. Date e dimensioni seguono il locale scelto; nomi dei giorni e durate sono localizzati.

**Generi e descrizioni.**
- `GameGenre` traduce alla presentazione i generi noti senza modificare metadati e scelte salvate; i generi sconosciuti restano come sono.
- `NintendoStoreMetadataService` legge le vecchie cache come inglesi e salva i percorsi per lingua e regione, riusando i dati tra regioni della stessa lingua.
  - Un cambio di sola regione non aggiorna i metadati. Un cambio di lingua conserva la scheda visibile, legge la cache fuori dal thread principale e, con dati freschi già presenti, chiede solo la descrizione tradotta.
  - `cachedForDisplay` dà alla pagina la voce della lingua dell'app o, se manca, la più recente in un'altra lingua, con la sua nota di lingua: un'app aperta in una lingua nuova non mostra pagine vuote. Quella voce non è mai fresca per la nuova lingua, quindi la descrizione si chiede comunque.
  - Dopo un cambio di lingua `StoreMetadataModel.refreshLocalizedMetadata` mette in coda ogni gioco della libreria, prima quello in primo piano; `queueLanguageFetch` li chiede una richiesta alla volta, nella lingua corrente, perché il giocatore non debba aprirli uno per uno. All'avvio `preloadCachedStoreMetadata` mette in coda i giochi mostrati in un'altra lingua (`isInLanguage`), per esempio dopo un cambio di lingua del Mac ad app chiusa.
  - Un gioco che non ottiene la lingua per un errore va in attesa. Tre errori di fila fermano il giro, perché provider o rete sono giù e chiedere ogni gioco non serve. I giochi in attesa si richiedono dopo cinque minuti, al massimo tre volte per lingua, o subito quando `ConnectivityWatcher` vede il Mac tornare online (in quel caso `forgetDescriptionRetries` toglie l'attesa di un minuto).
  - Gli ID 0400 dei giochi Switch 2 sono ammessi al lookup Nlib come gli 0100.
  - `descriptionCheckedAt` distingue un ripiego già controllato da una vecchia cache mai cercata nella lingua richiesta. Una traduzione vuota, o il 404 "Game not found" di Nlib per un gioco che non ha, si ricontrolla dopo 24 ore; dopo un errore di rete o un'altra risposta si riprova dopo un minuto. `languageResolved` dice se la lingua è sistemata (trovata, confermata assente o inglese).
  - Chiede una descrizione Nlib localizzata anche quando il catalogo US ne ha già una inglese, e non invia parametri di regione non documentati.
  - Se qualcosa fallisce, si tiene prima una descrizione tradotta già in cache, senza rinnovarne la freschezza; altrimenti si tiene il ripiego inglese.
  - Il modello conserva la lingua della descrizione, e Details e Spotlight la indicano quando è diversa da quella dell'app. Le scelte personali hanno la precedenza.
  - `metadataLocaleGeneration` impedisce a una risposta vecchia di ripopolare la UI dopo un cambio di lingua. Screenshot e artwork restano condivisi.

**Controlli.** SwiftPM compila le risorse e `build_app.sh` le include prima della firma. `check_localizations.py` verifica copertura delle sei lingue, segnaposto, plurali e risorse compilate; `release.sh` ripete il controllo sullo ZIP estratto. Le traduzioni sono bozze dell'agente, non revisioni di madrelingua.

## Setup, engine e compatibilità

**Ambiente.**
- `SystemDetector` e `EngineLocation` trovano checkout e cartelle dell'utente.
- `NXNativeEnvironment` raccoglie lo stato di Python, strumenti, Xcode e Metal. I tool dell'engine sono eseguibili nativi: .NET non serve.
- `EngineToolchain` risolve Python e `PATH`, preferendo il runtime incluso nel bundle quando c'è.

**Setup.**
- `SetupProbe` raccoglie i dati del Setup. `SetupCheck` li traduce in schede, stati e azioni. `SetupCheckModel` esegue i controlli in background, compresa la lettura di `xcode-select` a ogni ricontrollo (4 s), e coordina installazioni e avanzamento. `SetupActions` prepara gli argomenti Git per portare un checkout gestibile al pin.
- Get ready mostra soltanto i cinque requisiti tecnici, in una griglia 3 + 2. I problemi alle cartelle non riaprono questa schermata.
- Your games presenta Game apps, la cartella unica in cui cercare giochi nxnative esistenti e installare le prime build.
  - Il default `~/Applications` si prepara al primo uso solo se non è già stato scelto o ricordato un percorso. Le destinazioni personalizzate o confermate restano ricordate anche quando non sono disponibili.
  - La lettura basta per scoperta e Play; le nuove installazioni richiedono la scrittura.
  - Game files è una preferenza facoltativa in Settings → Library, separata dalla selezione temporanea del wizard.
  - Cambiare Game apps non sposta le app registrate; cambiare Game files non sostituisce i sorgenti di un titolo senza conferma esplicita. `GameFoldersCopy` mantiene coerenti i nomi.
- Con un engine che riconosce le cartelle estratte, Setup permette di proseguire senza chiavi. Le sorgenti cifrate continuano a richiederle e a passare dal controllo preliminare.

**Gate di compatibilità.**
- `SetupModel.refreshCompatibility` esegue in background `NXNativeEnvironment` e `CompatibilityChecker`. Quest'ultimo verifica commit, modifiche del checkout, contratto CLI e compilatore Metal richiesto dal lock del motore. `ToolchainRequirements.current` contiene Xcode minimo e asset Metal. `ToolchainGateCopy` spiega il risultato nella UI.
- Una build con l'override del gate riceve `toolchainVerified=false` e `--allow-other-metal`.
- Play valuta la disponibilità dell'app già installata separatamente dal gate per un nuovo porting.

**Newest engine.** L'engine più nuovo è una scelta esplicita del giocatore (Settings → Setup and engine → **Newest engine**).
- Dopo il controllo Upstream, che misura sempre i commit rispetto al pin, `NewestEngine.fetchLock` legge il lock di main da GitHub. Se certifica un Metal diverso da quello del lock del pin, la riga dice che serve una versione più nuova di Arcane e non offre il cambio.
- `NewestEngineSwitcher` rifiuta un checkout con file modificati, scarica, rilegge il lock con git e solo allora fa `checkout --detach`.
- La scelta (`NewestEngineChoice`) è salvata e diventa il commit atteso dal gate e quello registrato nelle build. Accende l'override, che resta bloccato finché la scelta è attiva, e marca le build come non testate. Il gate mostra **Newest engine** in arancione, mai Certified.
- Il Setup continua a installare il pin, ma per il commit scelto mostra la scheda pronta in arancione con **Back to tested** e non la riporta indietro da solo.
- La scelta decade quando il checkout non è più su quel commit, o quando un aggiornamento di Arcane porta un pin che lo contiene. Se l'override l'aveva acceso la scelta, torna spento. Settings e Setup usano la stessa frase (`NewestEngineCopy.note`).

**Capacità dell'engine adottate** (la decisione per ogni pin è nella sua nota in `history/engine-upgrades/`):
- **Cartelle estratte e pacchetti con più contenuti:** `EnginePackageReader` riusa il lettore content-meta upstream; `ExtractedSourceCatalog` legge NPDM e profili registrati senza chiavi.
- **NUP e cartelle senza profilo:** quando lo script espone `survey_nup` / `survey_dump`, `EngineSourceCapabilities` li accetta e l'engine li porta con un profilo provvisorio. Review mostra **Not tested with this engine yet** per qualunque sorgente senza profilo.
- **File `.zs` danneggiati:** il classificatore dell'engine controlla i file `.zs` danneggiati in NUP e cartelle (riga `files.format`).
- **Programmi NUP:** `NUPSourceCatalog` conserva programma, applicazione e base DLC distinti in
  `NUPProgramSelection`, facoltativo sui record storici. Le conversioni UI e i sorgenti salvati mantengono
  la selezione. Un engine con il contratto multiprogramma riceve `--program` esplicito, anche zero per
  i vecchi record, così un rebuild non segue un nuovo default. Metadati discordanti o un checkout
  incapace di selezionare il programma fermano il build; non viene mascherato l'ID.
- **NUP senza base:** Review offre solo le versioni di update (la più recente selezionata, una sempre scelta), e la build passa quella versione con `--package`, mai `v0`.
- **Archivio pipeline mancante:** `stage_end` con `warn: true` mostra ⚠ sulla fase e una spiegazione in **Ready to play** (`BuildWarningCopy`).
- **Preparazione del primo avvio:** quando l'engine riporta `Prewarm pipelines`, `PortingETA` mostra un'attività localizzata invece di riusare la durata finale di un vecchio build. Il tempo trascorso resta nella lista delle fasi; senza un conteggio non si inventa una percentuale. Un warning di questa fase spiega che il gioco prepara le pipeline mancanti al primo avvio.
- **Cache shader in un file:** cache di compilazione e librerie shader sono un file ciascuna (`shader/cache/cas.db`, `msl/b-<chain>.img`); Arcane non legge dentro nessuno dei due. Quando l'engine sposta una vecchia cache, con l'evento `say` `moving the compile cache …` (`PortingProgress.shaderCacheWorkMessage`), `PortingProgress.isUpdatingShaderCache` si accende e `PortingETA` mostra **Updating shader cache** senza avanzare la percentuale né stimare una durata. Lo stato si azzera alla fase o al passo successivo e a fine build; `PortingFailureEngineTests` verifica che l'engine del pin stampi ancora quel testo.
- **Errori delle chiavi:** si riconoscono le chiavi troppo vecchie (con la versione firmware quando è nota) e il ticket comune mancante nel pacchetto. Quest'ultimo usa il kind salvato `keys` con un dettaglio identificativo, così anche un launcher precedente legge la voce durante un rollback. La UI spiega il ticket senza proporre di sostituire le chiavi o forzare il porting.
- **Interfaccia dei giochi:** la guida dei controlli elenca l'uscita con Home (2 s, poi A) e Shift + frecce per la levetta destra. Le righe nuove di `settings.tsv` (120 fps, upscaler del gioco, forma dell'immagine) arrivano da sole tramite Game options.
- **Salvataggi:** un salvataggio con nomi creati prima di 7c23cc0 si rinomina al primo mount, quindi una build più vecchia dello stesso gioco potrebbe non leggerlo più.
- **Strumenti di sviluppo:** `.github/requirements/tools.txt` dell'engine elenca numpy, pillow e texture2ddecoder, usati solo da strumenti di sviluppo; `EngineRuntimeRequirementsTests.notBundled` ne registra il motivo. dav1d si compila dalle sorgenti incluse dell'engine, e il runtime del frontend non cambia.
- **Non adottati:** `--seen-shaders`, un selettore manuale dei programmi, le opzioni per i profili provvisori, i diagnostici come nuovi interruttori e gli hook per incorporare la vista del gioco in un frontend (Arcane avvia app di gioco separate).

## Sorgenti e porting

Il percorso completo è in [flows.md](flows.md#5-costruire-un-gioco-switch-add-game).

**Le sorgenti.**
- La preferenza **Game files** conserva solo il percorso iniziale del selettore. `PortingModel` la legge (`gameFilesFolder`) ma non la assegna a `selectedGameFolder` all'avvio: quell'assegnazione avvia una scansione. Il refresh della libreria riguarda le app installate; scegliere cartella o file in Add game avvia la lettura dei sorgenti. *Perché:* aprire la libreria non richiede di enumerare una cartella protetta come Download. I rebuild usano le sorgenti registrate sul gioco.
- `SourceSelection` tiene separati contenuti selezionati e file fisici: un pacchetto si conta e si collega una sola volta, il DLC incorporato resta incluso e la versione scelta passa con `-p`.
- `GameFileItem` conserva, se serve, layout e requisito di selezione del titolo; i vecchi JSON continuano a indicare pacchetti. Questi requisiti e la selezione NUP si verificano prima del build, anche dopo un cambio di checkout. Il programma salvato deve corrispondere al title ID del gioco; il DLC usa la base add-on dichiarata dall’applicazione.
- Le cartelle estratte si collegano nel layout `base/`, `updates/<version>/`, `dlc/<title>/0/romfs/`. Il restaging rimuove i link esclusi e i contenitori vuoti, preservando cache e originali.
- Un pacchetto illeggibile non nasconde gli altri giochi validi: la scansione tiene i risultati e segnala i file saltati.

**Il percorso, passo per passo.**
1. **Scelta dei file.** `AddGameView` raccoglie cartelle o file. `SourceCatalog` riconosce NSP, XCI, NSZ e XCZ e raggruppa base, aggiornamenti e DLC.
   - I file scelti si scandiscono e collegano uno per uno, senza includere altri pacchetti della cartella né cambiare la preferenza globale Game files.
   - La bozza si azzera solo dopo la conferma del selettore. Più titoli richiedono una scelta esplicita.
   - Le riletture dello stesso titolo mantengono nome, impostazioni e selezioni di update/DLC anche se cambiano gli UUID delle righe.
2. **Chiavi.** `PortingModel.refreshKeyCheck` chiama `KeyCheck` sulle sorgenti selezionate. Il risultato vale per la selezione corrente, quindi un controllo precedente non abilita un porting diverso.
3. **Workspace.** `WorkspaceManager` usa la cartella sorgente così com'è oppure prepara un workspace di collegamenti simbolici, riusando una cache esistente. `BuildScratch` sceglie dove mettere workspace e app temporanea: sul volume dell'app.
   - Se la cartella delle app è su un altro volume locale APFS o Mac OS esteso, vanno in `.nxlibrary-build/` accanto alle app, così il disco del Mac non serve e l'installazione è una rinomina. exFAT e FAT accettano i link ma tengono gli attributi in file `._` che rompono la firma; il tipo lo dà `statfs`.
   - Negli altri casi (stesso volume, exFAT, rete) restano in Application Support.
   - Una cartella `workspaces` spostata dal giocatore su quel volume resta dov'è, e un workspace gestito già su quel volume conserva la sua cache.
   - Un workspace gestito rimasto su un altro volume si cancella quando ne nasce uno nuovo, tranne se il gioco non è ancora costruito e punta ancora lì.
   - Il controllo dello spazio misura ogni volume usato una sola volta. La pulizia all'avvio guarda anche le `.nxlibrary-build/Temp`, e cancellare un gioco o le sue sorgenti tocca solo i workspace riconosciuti da `BuildScratch.isManaged`.
4. **Ultimo controllo.** `PortingModel.beginBuild` ricontrolla requisiti, spazio, chiavi e destinazione. `BuildCommandBuilder` produce eseguibile, argomenti, cartella di lavoro e ambiente.
5. **Processo.** `BuildService` avvia il processo del motore e gestisce il suo gruppo di processi. Raccoglie stdout e stderr, scrive il log e tiene attiva l'asserzione contro lo stop per inattività. Se il processo non parte, chiude subito log e pipe.
6. **Avanzamento.** `BuildEventParser` decodifica il progresso JSON e `PortingProgress` lo aggrega per la UI: gli shader arrivano fino al 90%, le fasi finali occupano il restante 10%. Il modello alimenta wizard, tile, percentuale e stima del tempo.
7. **Installazione.** `BuildOutputInstaller` valida il bundle temporaneo e pubblica il gioco con `renamex_np`: `RENAME_SWAP` scambia atomicamente due app esistenti, `RENAME_EXCL` installa la prima copia senza sovrascrivere una destinazione comparsa nel frattempo. Sullo stesso volume usa direttamente il bundle pronto; fra volumi diversi prepara prima una copia nascosta accanto alla destinazione, e l'app corrente resta disponibile fino allo scambio.
8. **Installazione in attesa.** Se il gioco è aperto, o un'operazione sui salvataggi trattiene l'installazione, `PendingInstall` conserva il risultato temporaneo. `AppViewModel+PendingInstall` lo riprende quando può ottenere l'accesso.

**Destinazione.**
- `GameAppDestination` centralizza il percorso mostrato nella review, il volume controllato per lo spazio e la destinazione effettiva.
- Le prime build usano Game apps; un rebuild conserva l'app esistente se il suo percorso è sicuro, anche dopo un cambio di cartella. Un nome già usato da un altro titolo riceve un percorso distinto.
- La destinazione si fissa prima del porting e resta tale anche nelle installazioni differite. Le installazioni richiedono che la cartella esista ancora: se si scollega o non è più scrivibile, il risultato pronto si conserva per Retry. Il packaging del frontend può creare la propria cartella di installazione.

**Installazione fallita.**
- Se il motore termina bene con un bundle valido e fallisce solo l'installazione, `BuildResult.heldApp` conserva la build pronta, e `installationFailed` distingue questo caso dal porting fallito. `PortingModel` registra la stessa `PendingInstall` usata per i giochi aperti.
- Un dialogo Selene offre Retry e Close: Retry installa quel bundle senza riavviare il motore, Close conserva la build. Anche gli errori delle installazioni differite passano da questo dialogo, e la schermata del porting offre Retry installation finché la build resta in attesa.
- Un errore di scrittura del catalogo conserva lo stato in memoria e impedisce che una scansione immediata lo sostituisca con quello precedente.

**Ricevuta di installazione.**
- Prima della pubblicazione l'installer scrive accanto all'app una piccola ricevuta, con il percorso di staging e l'identità filesystem dei bundle. Ne resta una per destinazione, aggiornata al porting successivo.
- Se il processo termina prima del salvataggio del catalogo, il tentativo successivo riconosce l'app già pubblicata e completa il record, anche dopo la pulizia dello staging. *Perché:* evita un secondo scambio che rimetterebbe la vecchia app al suo posto.
- Una destinazione modificata da fuori durante lo stesso tentativo causa un errore prudente. La vecchia app e l'eventuale sorgente copiata si eliminano solo dopo la pubblicazione.

**Tempo e stime.**
- La fase attiva mostra il tempo trascorso; durate ed ETA passano alle ore oltre i 60 minuti. Un timer a 1 Hz sul main run loop aggiorna la fase, mentre il controllo di `logs/pso_offline_mac.log` gira fuori dal main thread.
- `PipelineArchiveProgress` legge soltanto log modificati dopo l'inizio della fase e conta i gruppi dichiarati `ready`, distinguendo `compiled` e `reused`. I file temporanei del compilatore e le chiavi delle vecchie cache non contano come lavoro finito. Le dimensioni dei gruppi vengono dal log, senza assumere quelle predefinite.
- La stima riguarda le pipeline, non il confezionamento dell'app che segue. Un formato sconosciuto non inventa un avanzamento. Cambi di fase, annullamento e fine build invalidano i controlli ancora in corso.
- Durante `Prewarm pipelines` la riga mostra **Preparing the first launch**: la durata precedente può non includere questo lavoro, quindi non viene usata come ETA. Fine build e annullamento rimuovono l'attività insieme allo stato di porting.

**Esito.**
- `BuildRecord` conserva esito e provenienza del build.
- `PortingFailureClassifier` riconosce i messaggi del motore, compreso lo spazio richiesto da `pack_app.py`, e propone un'azione, presentata da `PortingModel.performFailureAction`. Il ripiego sulle chiavi vale solo per le sorgenti che le richiedono.
  - Alcuni casi restano del tipo `unknown` con un dettaglio, perché una versione precedente sappia ancora leggere il motivo salvato: la lingua che il gioco non ha (`missing-language:`) e le tabelle shader diverse da quelle del profilo del gioco (`shader-profile-mismatch`). Il secondo dice entrambe le cause possibili, file di un'altra versione o profilo non ancora rigenerato dall'engine, senza dare la colpa al giocatore.
- `PortingNotice` decide se notificare l'esito mentre l'app è in background. `NotificationService` gestisce la notifica di sistema e la destinazione del clic. Il permesso si richiede quando un porting supera i controlli preliminari e parte, mai durante l’avvio o per la sola libreria Steam. Il delegate resta registrato all’avvio per aprire il gioco o l’errore da una notifica precedente.

## Avvio dei giochi e sessioni

I percorsi completi sono in [flows.md](flows.md#3-play-di-un-gioco-switch-nxnative) (Switch) e in [steam.md](steam.md) (Steam).

**Preparazione.**
- Il flusso Play controlla operazioni sui salvataggi, recuperi e installazioni in attesa.
- `GameRuntimeConfig` traduce le impostazioni in variabili `DM_*`. `LauncherSettingsReader` legge il contratto `launcher.json` del gioco e decide i controlli supportati, con un ripiego per le app più vecchie.
- `LaunchService` scrive `env.txt`, conserva le variabili non gestite tramite il merge del modello runtime e avvia il bundle con `NSWorkspace.OpenConfiguration`, passando anche `DM_LAUNCHER=0`.
- `CloudSavesPreferences` applica la preferenza cloud al dominio del gioco prima del lancio. Off rimuove anche all'avvio la preferenza cloud salvata dal launcher del gioco. Gli override avanzati `DM_SAVE_SYNC`, nei file o nell'ambiente, mantengono la precedenza del motore: `SaveLocation.inspect` ne segnala l'origine e blocca le operazioni incompatibili con la sincronizzazione attiva.

**Firma dell'icona in corso.**
- Play durante la firma dell'icona apre il dialogo Selene **Preparing** con **Cancel**. `IconLaunchWait` lega la richiesta all'identità del gioco e del dialogo; chiudere o sostituire il dialogo revoca la richiesta.
- Solo l'ultimo aggiornamento dell'icona riuscito può riprendere Play, che rilegge il gioco corrente e ripete tutti i controlli su salvataggi e app. Un errore non avvia il gioco.
- Cancel lascia finire la firma, che serve a mantenere valido il bundle. L'attesa usa `launchingGameId` e blocca anche l'aggiornamento del frontend.

**Schermata di lancio.**
- `RunningGameMonitor` confronta i bundle ID della libreria con le applicazioni in esecuzione (`RunningAppsTracker` nella base, `RunningGames.matchingIDs` per i giochi portati in `Porting/Library/`) e offre Resume e Close Game. `LaunchReadinessProbe` aspetta una finestra visibile del processo per chiudere la schermata di lancio.
- La schermata ha una finestra propria, come la "launch cover" di Selene (`LaunchCoverWindow`). È senza bordi e trasparente (appare sfumando sopra la libreria), sta sopra ogni app, il Dock e la barra dei menu, su ogni Space compresi quelli a schermo intero, e non viene mai attivata.
- Quando un gioco si apre a schermo intero, la schermata scorre via con la libreria e rientra con lo Space del gioco, coprendolo finché il gioco non disegna. *Perché:* tenuta nel solo Space di Arcane, lì si vedeva lo sfondo della scrivania; il maintainer preferisce la schermata (prova con MTGA, 15 nov 2026).
- Il gioco parte dietro di lei; Steam che prende il primo piano o macOS che cambia Space restano dietro, quindi Arcane non deve mai riprendersi il primo piano.
- Play Steam accoda la richiesta fino a quando AppKit ordina e invia il pannello al server delle finestre. Arcane lascia al pannello il passaggio SwiftUI di preparazione prima che Steam possa cambiare Space. Se il pannello manca, Play procede comunque entro un secondo. Solo la richiesta ancora corrente può partire.
- La schermata d'attesa mostra artwork, logo o titolo del gioco secondo lo stile scelto, con l'angolo inferiore destro libero.
- Il movimento è quello di Selene (`LaunchMotion`), in Core Animation così resta fluido mentre il gioco o Steam si avviano:
  - l'arte si avvicina piano (scala da 1,04 a 1,12 in 20 s);
  - il logo entra una sola volta, poco dopo la dissolvenza della schermata (0,36 s): appare in 0,75 s mentre sale di 30 unità in 1 s, poi resta fermo. Al massimo metà larghezza e 38% dell'altezza, come Selene;
  - con Riduci movimento l'arte resta ferma e il logo appare soltanto.

**Sessioni.** `PlaySessionStore` registra avvio, heartbeat, fine e riconciliazione delle sessioni; un avvio porta l'id del gioco, l'identità della fonte e, se c'è, il bundle ID dell'app. `ActivitySummary` aggrega la settimana; `LibraryPresentation` e `GameDetailPresentation` preparano i valori delle schermate. Le entrate per un gioco portato (`start(for:)`, `SessionSummary` e `LibraryPresentation` per `PortedGame`, l'entrata di `LibraryPresentation` per `CatalogGame` che riceve i fatti dello store Nintendo) sono estensioni in `Porting/Library/`.

## Pagina del gioco

**Pannello Details.**
- La colonna destra della pagina del gioco, nella Spotlight e in Details, si chiude con lo stesso pannello per ogni fonte (`DetailsPanel`). Sono righe etichetta → valore con una piccola icona grigia (Developer, Publisher, Version, Size on disk, Installed in), direttamente sulla pagina, con separatori sottili e senza riquadro.
- La card Achievements, che si preme, ha un fondo trasparente al 5% (10% su hover e focus) e il bordo, senza materiale sfocato aggiuntivo.
- Sotto ci sono i link Reveal in Finder, Store page e HowLongToBeat (`DetailsLink`, `SeleneActionGrid`, focus `DetailsFocus.actionsZone` / `.actions`).
- `DetailsFacts` nel Core sceglie le righe: una riga senza valore non compare. Le entrate di un gioco portato (`DetailsFacts.switchGame`, `GameDetailPresentation(game:metadata:…)`, `MoreLikeThis.pick` per `PortedGame`) sono estensioni in `Porting/Details/`. Steam non mostra mai la versione (il build ID è tecnico) e, senza un'installazione disponibile (download in corso), mostra solo Developer e Publisher. Cartella e volume arrivano per nome visualizzato, mai come percorso.
- Lo stato tecnico (sorgenti, engine, toolchain, build bloccata) non sta sulla pagina. Rebuild, Attach sources, Open log, Saves e, senza descrizione, Search Nintendo Store stanno in Options; un problema che ferma il giocatore resta nella nota di Play. Nella pagina Details le righe vanno su due colonne.

**Voto della critica.**
- L'ultima riga del pannello, dopo Installed in, mostra cinque stelle proporzionali, il voto originale /100 e la fonte. È una riga informativa, senza card o finestre aggiuntive, e non aggiunge azioni al focus.
- Caricamento e voto assente hanno un testo esplicito, senza fingere un voto zero. Provenienza, data del voto, ambito ed eventuale ripiego sulla copia salvata stanno nel testo accessibile e nell'aiuto.
- La media utenti IGDB usa "Voto utenti" e "Utenti · IGDB", conservando stelle, numero e posizione della riga. Le fonti sono descritte in [Artwork, metadati e voti](#artwork-metadati-e-voti).

**Fascia Mods.** Sta tra Details e More like this: vedi [Mod](#mod).

**More like this.** La fascia condivisa `DetailsMoreBand` mostra fino a sei giochi, dopo Mods per Switch e sotto About e Details per Steam. `MoreLikeThis` ordina per generi, sviluppatore ed editore in comune. Esclude il gioco corrente e quelli nascosti. Steam dà precedenza ai titoli Steam e cerca titoli Switch correlati quando non trova corrispondenze Steam. Usa scelte personali e metadati già disponibili, con i generi nella lingua dell'interfaccia. La cache Steam si legge all'apertura della pagina e la fascia compare solo con corrispondenze effettive.

## Cheat

- `CheatLocator` legge title ID, build ID e percorso secondo il contratto del launcher.
- `EngineAncestry` e `CheatStatus` decidono se l'app del gioco contiene il supporto ai cheat, dal commit del registro di build o, per un'app importata, da `DMCommit` nel suo `Info.plist`.
- `EngineAncestry.answer` lancia `git merge-base --is-ancestor` in un task staccato, una volta per commit, e tiene la risposta fino alla chiusura di Arcane. Le viste leggono solo `keptAnswer`, che git non lo lancia mai: riga e pannello si aprono dentro un aggiornamento di SwiftUI. La riga di Game options mostra il valore, il pannello le sue righe e Copy diagnostics la riga Cheats dopo la risposta.
- `CheatFile` riproduce il parsing di codici e metadati del motore. `CheatInstall` decide se un file appartiene alla build, richiede conferma o va rifiutato.
- `CheatStore` legge e modifica file, metadati, master switch e selezione `.enabled`. `CheatsModel` (`app.cheats`) espone contesto, stato della riga e informazioni per la diagnostica. `CheatsPanel` presenta lista, importazione, conferme e switch. La pagina del gioco legge "Cheats on" all'apertura, al cambio del gioco, alla chiusura di Game options e al ritorno da Finder (`reloadCheats`), non a ogni ridisegno; una lettura nuova annulla quella precedente.
- Le modifiche richiedono il gioco chiuso. Il motore legge i file installati al lancio.

## Mod

**Mod locali.**
- Le mod di file (RomFS) di un gioco stanno in `~/Library/Application Support/nxnative/<title ID>/mods/<cartella>/romfs`.
- `ModFolderScanner` trova le cartelle e il loro `romfs`, anche nel formato Atmosphère. Un file lasciato lì (per esempio un archivio non estratto) compare come "non è una mod"; i file nascosti come `.DS_Store` non contano per i conflitti.
- `ModStore` tiene ordine e stato acceso/spento in `~/Library/Application Support/NXLibrary/mods/<TID>.json`. Nell'`env.txt` del gioco scrive solo la riga `DM_ROMFS_OVERLAY` (con `EnvFileEditor`), che il motore legge al lancio: le mod accese, la prima vince, senza rebuild. Il valore non supera 4077 byte, il buffer di riga del launcher.
- Remove sposta la cartella nel Cestino. Niente modifiche mentre il gioco è aperto.
- All'apertura della pagina e del pannello, `sync()` toglie dalla riga le mod sparite. Finché Arcane non ha mai gestito le mod di un gioco, non tocca una riga `DM_ROMFS_OVERLAY` scritta a mano.
- `AppViewModel+Mods` crea lo store e traduce gli errori; `ModsPanel` (Game options → Mods; `GameOptionsFiles` legge configurazione, impostazioni, cheat e mod una volta per apertura) e la fascia Mods della pagina (`DetailsModsBand`) presentano lo stato. Le mod che modificano il codice (exefs) non funzionano con il motore.

**GameBanana** (`Porting/Mods/GameBanana/`: installa mod RomFS, formato Switch; la bottega e il suo focus `ModStoreFocus` stanno lì). Le descrizioni passano da `HTMLPlainText` della base, come quelle di Steam e dei database.
- `GameBananaClient` parla con l'API pubblica (apiv11 e, per il contenuto degli archivi, la vecchia Core API). Usa un solo User-Agent, al massimo 4 richieste insieme, e una cache su disco in `~/Library/Caches/NXLibrary/gamebanana`:
  - ricerche 1 giorno, pagine delle mod 6 ore;
  - contenuto degli archivi per sempre, tranne un elenco vuoto, perché GameBanana può ancora leggere un file nuovo;
  - senza rete usa anche le voci scadute.
- `GameBananaMatch` abbina il gioco per nome (preferisce la voce "(Switch)" e chiede quando non è sicuro); `GameBananaMatchStore` ricorda la scelta per title ID in `Application Support/NXLibrary/gamebanana/matches.json`.
- `AvailableModsFinder` scorre le mod più scaricate e tiene solo quelle che `ModSupport` riconosce: un'unica cartella `romfs` per questo title ID, niente exefs, IPS o pchtxt, niente mod obsolete, private o con content rating.
- `ModInstaller` scarica con `ModDownload` (solo host `*.gamebanana.com`) e controlla dimensione e MD5. Legge e controlla l'archivio con `/usr/bin/bsdtar`, rifiuta percorsi `..`, symlink e hard link prima di estrarre, lo estrae in una cartella nascosta dentro `mods` e passa l'albero a `ModStore.adopt`. Un aggiornamento manda la versione vecchia nel Cestino e tiene posto e stato.
- I link presi dall'API valgono solo se sono `https` su un host GameBanana. Ogni mod mostra autore e link alla sua pagina, e la fascia dice "Mod data provided by GameBanana".

**Fascia Mods della pagina.**
- Compare sia nella pagina del gioco della Spotlight sia in Details, tra Details e More like this (focus `.mods` in `SpotlightState`, `DetailsFocus.modsZone`).
- È una griglia di sei tessere per riga che non scorre di lato (`ModsBandLayout`): Sinistra e Destra restano nella riga, Giù scende di riga e dall'ultima passa a More like this.
- `ModsBandHost` tiene per entrambe le pagine mod installate, GameBanana e pannelli. In Spotlight legge le mod all'apertura della pagina del gioco. Cambiare selezione sulla riga svuota la fascia precedente senza leggere quella successiva, così la lettura delle mod resta fuori dallo scorrimento.
  Le [misure dei primi cambi gioco](../history/reviews/2026-11-18-spotlight-glide.md) mostrano il costo della lettura prima e dopo.
- Play riconcilia le cartelle delle mod prima di avviare il gioco, anche dalla riga. Se la cartella o i record non si leggono, `ModStore.sync` conserva entrambi i file di stato. La Dev mantiene il divieto di manutenzione automatica dell'overlay.
- `GameBananaBandModel` coordina abbinamento, ricerca e installazioni. Cambiando gioco dimentica le mod del precedente; alla prima apertura di un gioco in ogni avvio toglie gli avanzi di un'installazione interrotta (`ModStore.removeLeftoverInstalls`). `GameBananaFindModel` tiene lo stato della ricerca per nome.
- Le mod trovate entrano al massimo in due gruppi: le prime cinque, accanto ad Add mods, appena ci sono, poi tutte le altre a ricerca finita. Ogni gruppo aspetta (al massimo 1,2 s, `imageWait`) che la sua arte sia decodificata (`prepareImages`, cioè `GameBananaImageView.prepare`, in parallelo) ed entra con un'unica dissolvenza. Una tessera di stato spinta più in là sfuma nel nuovo posto invece di attraversare la griglia.
- Un'installazione è per un file (`GameBananaBandModel.installFiles`): solo la sua riga mostra avanzamento ed esito, le altre aspettano che finisca.

**Pannello della mod.**
- `ModDetailPanel` e `GameBananaFindPanel` sono i pannelli sopra la pagina.
- La descrizione mostra otto righe con Read more subito sotto; Read more la apre tutta (`TextScroll.windowHeight`) e i file, sotto il titolo Files, scendono.
- La colonna (intestazione, descrizione, file) scorre dentro il pannello quando è più alta, al massimo 980 unità. Si scorre con rotella o trackpad, e con Su/Giù, che prima leggono a passi quello che c'è prima della riga seguente e poi spostano il fuoco e mostrano la riga intera (`TextScroll.step`). I bordi sfumano dove c'è altro, e una barra sottile dice dove si è.
- Lo scorrimento sta in `ModsBandHost.detailScroll`, un oggetto a parte, così muoverlo ridisegna solo il pannello e non la pagina sotto.

**Store delle mod.**
- Lo store è la card **Mods** della Spotlight (`SpotlightCard.mods`). La sua visibilità sta in `showsModsCard`, mai in `spotlightCards`, così la versione rilasciata legge ancora le impostazioni.
- Giù dalla card porta il focus a `.store`, e `ModStoreHost` muove `ModStoreFocus` dentro la pagina (`ModStorePage`). La pagina contiene:
  - una barra di ordinamento;
  - Featured, con dissolvenza tra le prime cinque;
  - le mod popolari dei tuoi giochi;
  - una riga per categoria (`ModCategory`, raggruppate dai nomi delle categorie GameBanana);
  - una riga per gioco, dal più giocato di recente.
- `ModStoreLayout` costruisce le sezioni e dà a ognuna un'altezza fissa, così lo scorrimento non misura nulla e si disegnano solo le sezioni vicine al focus.
- `ModStoreModel` apre dalle copie su disco (`ModCatalogSnapshots`, `~/Library/Caches/NXLibrary/gamebanana/store`) e aggiorna in background quelle più vecchie di 6 ore, due giochi alla volta, pubblicando un gioco intero per volta. Un gioco senza abbinamento si abbina solo se il nome è certo. L'ordinamento è locale sulle mod già trovate.
- Le immagini decodificate restano in memoria (`GameBananaImageView`, che le prepara in anticipo con `prewarm` per le prime tessere di ogni riga).
- La copertina della card (`ModStoreLayout.coverArt`) sono le prime quattro mod del Featured per popolarità, qualunque sia l'ordinamento, con i giochi in ordine di title ID. All'avvio si legge dalle copie su disco dei tuoi giochi ed è la stessa che trova lo store aperto. Cambia solo se lo store trova mod nuove, e solo dopo che tutte e quattro le immagini sono decodificate, in un'unica dissolvenza.
- Sulla riga, la faccia della card è un mosaico sfocato dell'arte delle mod migliori con il puzzle al centro (`ModsCardCover`, dalle copie su disco prima che lo store abbia cercato; senza arte, il gradiente Selene).
  `AppShellState` possiede `ModStoreHost`, che Spotlight osserva: il mosaico pronto sopravvive alla navigazione. Uscire dalla home continua a chiudere il pannello e fermare lo store.

  A ogni ritorno gli snapshot vengono rivalidati rispetto agli abbinamenti GameBanana, mantenendo la cover finché la lettura finisce; un risultato vuoto la rimuove. Cambiare i title ID la invalida subito e le identità delle richieste scartano letture precedenti; una cover pubblicata dal catalogo invalida lo snapshot ancora in lettura. Gli stati transitori idle/loading del catalogo non svuotano il mosaico.

  I record Installed/Update vengono riletti a ogni apertura, con generazione separata per scartare letture precedenti a una chiusura o installazione.
- Lo sfondo del Featured si sfoca una volta sola, fuori dal main thread, su una copia di 240 px (`GameBananaBlur`): nessuna sfocatura gira a ogni frame.
- Mentre la pagina scorre, `ModStoreHost.hold(until:)` trattiene le mod trovate in background e ricostruisce le sezioni solo a pagina ferma (il log `store rebuild … ms` misura ogni ricostruzione).
- Con la card selezionata lo sfondo diventa oro: vedi [Interfaccia Selene e input](#interfaccia-selene-e-input). Il pannello della mod è lo stesso della fascia; `GameBananaBandModel.attach(store:)` installa nella cartella del gioco della mod.

## Salvataggi, backup e recupero

Il percorso completo è in [flows.md](flows.md#6-importare-o-ripristinare-un-salvataggio). Tutto il motore sta in `Porting/Saves/`. *Perché:* backup, ripristino e import hanno la forma dei salvataggi nxnative (componenti `account`, `device`, `user2`…`user8`, registro `save.users`, journal del pull cloud, Title ID); un motore comune si estrae quando un'altra fonte ha salvataggi.

**Riconoscimento e anteprima.**
- Il flusso usa il title ID e conserva i percorsi interni del salvataggio per ogni gioco. `SaveLocation` ammette l'ID esadecimale di 16 caratteri, risolve il percorso predefinito e legge la configurazione cloud effettiva. `AppViewModel+Saves` verifica anche l'identità nel bundle installato e le preferenze del gioco.
- `RyujinxSaveFolder` riconosce `bis/user/save/<indice>`, risale dalle sottocartelle, confronta il title ID in `ExtraData0` e seleziona l'intero albero committed `0`. Le cartelle di esportazione ordinarie mantengono la propria struttura. Il tipo User/Device è una scelta separata dal nome della cartella sorgente.
- `SaveSnapshotStore.stageImport` prepara una copia temporanea vicino alla destinazione. L'anteprima contiene inventario, hash SHA-256, attributi estesi e impronta del salvataggio attuale. `SaveRestorePreview.swift` prepara allo stesso modo un ripristino da backup. Alla conferma si ricontrollano sorgente, staging e salvataggio attuale.

**Copia protettiva e sostituzione.**
- `SaveSlot` descrive account e device, `user2`…`user8` e il file registro `users` (`save.users`).
  Gli altri pezzi sono directory. Le cartelle transazionali dell’engine (`.work` / `.new`) non entrano
  nell’inventario; il registro si copia come file regolare, con limite 64 KiB e senza seguirne link.
- `SaveSnapshotStore` crea un backup verificato di tutti i pezzi locali committed presenti, compresa
  la loro assenza. Il manifest resta schema 1 per soli account/device e usa schema 2 per gli utenti
  aggiuntivi o il registro. I vecchi backup non si riscrivono; versioni o dichiarazioni incoerenti si rifiutano.
- `SaveTransaction` prepara lo staging, salva il journal `.nxlibrary-save-transaction.json` e cambia
  soltanto i pezzi dichiarati in `mutatedSlots`. Usa `renamex_np(RENAME_SWAP)` per scambiare file o
  directory e spostamenti per presenza/assenza. Il registro si scambia per ultimo.
- L’importazione da cartella modifica solo User oppure Device; registro e utenti aggiuntivi restano
  intatti, senza ricopiarli o scambiarli. Il restore schema 1 modifica solo i due slot storici e conserva
  gli altri utenti correnti. Il restore schema 2 applica tutto il gruppo, comprese le assenze, sempre
  dopo un backup di sicurezza. La conferma spiega l’ambito prima di agire.
- Il cloud dell’engine copre soltanto utente principale e device. Il pannello e le impostazioni lo
  dichiarano; un backup locale completo non equivale alla sincronizzazione di tutti gli utenti.
- `SaveOperationGate` assegna lease per title ID, coordinando salvataggi, Play e installazioni anche quando più voci della libreria condividono lo stesso gioco.

**Integrità e recupero.**
- `SaveFileIO` centralizza copie, hash, metadati, controlli dei percorsi, scritture durevoli e punti di errore sostituibili nei test.
- La verifica normalizza provenienza e label di accesso gestite da macOS, più il campo agente della quarantena. Confronta i metadati guest e il contenuto dei file. Manifest e journal precedenti passano dalla stessa normalizzazione.
- Prima e dopo ogni scambio si verificano contenuto live e originale spostato in staging; una modifica
  inattesa conserva journal e artefatti. La pulizia registra l’intenzione e l’inventario verificato nel journal prima di eliminare i residui, un elemento alla volta; si riprende anche dopo una cancellazione parziale e rifiuta dati nuovi o cambiati.
- All’avvio o al refresh, un journal incompleto porta al rollback al salvataggio precedente verificato.
  Il journal 1 osserva solo account/device, conservando eventuali utenti comparsi dopo l’interruzione;
  il journal 2 osserva il gruppo completo. `mutatedSlots` manca nei journal storici, che conservano
  l’ambito dei due slot originali. Un journal committed verifica il risultato prima della pulizia.
  La recovery può a sua volta interrompersi e riprendere. Il gioco deve restare chiuso anche per lanci esterni.
- Dati modificati da fuori o copie non verificabili tengono il recupero bloccato e conservano gli artefatti per l'intervento. Play aspetta la risoluzione.

**Pannello e backup.**
- `SavesPanel` offre: apertura della cartella, backup manuale, destinazione, importazione, refresh e cartella dei backup con la data dell'ultima copia. L'anteprima From → To è in `SaveImportDetails`.
- Dopo ogni importazione riuscita, `SavePanelModel` pubblica un evento e la vista mostra `SeleneSuccessNotice`, che si chiude dopo tre secondi; il timer si annulla quando il pannello scompare.
- I backup sono copie locali conservate finché l'utente non li gestisce. Sono automatici prima di importazione e ripristino, oppure manuali con Back up now.
- Importazione e ripristino richiedono la sincronizzazione cloud davvero disattivata. I casi rifiutati e le verifiche sono descritti nelle sezioni Saves del README e dei test.
- Storage → Save backups apre la cartella comune degli snapshot; le copie si creano dal pannello Saves.

## Spazio su disco

**Misura.**
- Settings → Storage e Porting → Storage usano `StorageManager.snapshot` (`Porting/Library/`: misura le app portate, le loro cache e i loro log). `GameStorageUsage` distingue app, cache e log per voce, compresi i giochi nascosti, e ordina le cache dalla più grande.
- `StorageSize` distingue file assenti da percorsi non leggibili o volumi scollegati.
- Le misure sono dimensioni logiche dei file, compresi quelli nascosti. La visita fisica fts non segue i collegamenti interni e scarta le misure incomplete in caso di errore. I percorsi canonici condivisi si misurano e si contano una sola volta nei totali.
- Lo spazio libero è quello della cartella Game apps corrente, senza ripiegare sul disco interno se questa manca.

**Pulizia.**
- La conferma per gioco conserva identità e percorso scelti. Prima di cancellare, il coordinatore ricontrolla la voce corrente.
- `StorageManager` richiede la cartella `<title ID>_build` immediatamente sotto il workspace registrato. Rifiuta file ordinari e cache che siano symlink, e protegge app, sorgenti e installazioni differite di tutte le voci.
- Un collegamento dentro la cache si rimuove senza visitarne la destinazione. Le cache condivise sono indicate sia nella riga sia nella conferma.
- Non si rimuove l'intera cartella workspace né si modifica il catalogo: una ricompilazione ricrea la cache.

**Esecuzione.**
- Misura e pulizia girano sulla coda utility. `isCleaningStorage` blocca nuove pulizie, build e installazioni dell'updater; i giochi già installati restano avviabili.
- Una misura superata da cambi di libreria o destinazione si ripete. A fine pulizia si pubblica l'esito, si mostrano gli eventuali errori e si ricalcolano le dimensioni.
- Le righe dei giochi hanno identità UUID stabili per mouse, tastiera e controller.

## Artwork, metadati e voti

**Sfondi delle schermate.**
- Look distingue Wallpaper e Library screens. Game backgrounds è un controllo positivo: On mostra l'artwork del titolo in Spotlight e Collection, Off tiene il wallpaper. Riusa la preferenza `keepWallpaperOnGames` invertendo solo il binding.
- Details usa sempre l'artwork del gioco, e la schermata di avvio segue le proprie impostazioni globali. Wallpaper sizing riguarda il wallpaper, Library shade le maschere delle schermate della libreria.

**Fonti dell'artwork.**
- `NintendoStoreMetadataService`, `GameTDBStore`, Title DB e le sorgenti di artwork raccolgono descrizioni, date, generi, copertine, loghi, sfondi e screenshot.
- `ArtworkNames` confronta i nomi per limitare i candidati al gioco o alle sue edizioni. `ArtworkPicker` e `MetadataOptions` aggregano i risultati per i selettori; `ArtworkPicks` e `MetadataPicks` conservano le scelte manuali. Le proposte di un gioco Switch (`ArtworkCandidates.list(for:entries:…)`, `MetadataOptions`, `MetadataPicks.applied`) stanno in `Porting/Store/`; `GameTitleKey` confronta i nomi per le ricerche online e per GameTDB.
- `ArtworkStore` tiene la cache delle immagini. `BoxArtService` risolve le copertine Switch di GameTDB. `GameArtLoader` e `SeleneHeroArt` alimentano sfondo e logo delle schermate.

**Change artwork.**
- Le scelte manuali per titolo hanno la precedenza. La riga di stato ha altezza stabile, testo breve per la ricerca e l'indicazione di dove va l'immagine; segnala Home: wallpaper quando lo sfondo della home dipende dal wallpaper globale.
- LaunchBox e SteamGridDB non entrano nella griglia automatica: ciascuno ha un riquadro **Browse online** con una griglia propria (`ArtworkBrowseSource`). La ricerca è precompilata e modificabile, i risultati sono per lo slot aperto, ogni immagine ha il suo credito e X apre la pagina del gioco sulla sorgente.
- La griglia carica solo le anteprime. Il file pieno (`ArtworkCandidate.full`) si scarica alla scelta e si ridimensiona come ogni scelta manuale.
- LaunchBox non ha API: ricerca e pagina del gioco si leggono come TheGamesDB, e immagini e dimensioni vengono dal payload `__NUXT_DATA__`. SteamGridDB usa l'API v2 con la chiave personale dell'utente (file `0600`, mai nei log).
- Per i giochi senza screenshot Title DB, caricare i metadati (selezione o apertura del gioco) chiede una volta a LaunchBox gli screenshot Gameplay e li conserva 30 giorni (`ScreenshotFallbackStore`). Le scansioni della libreria non avviano richieste.

**Icone automatiche.**
- `AutomaticIconResolver` riempie l'icona di un'app che non ne ha una, solo senza scelta manuale e senza un esplicito Only here. Le app con un'icona propria restano intatte.
- `ArtworkStore.automaticIcon` prova Title DB e poi una corrispondenza esatta normalizzata in Switch Icon Showdown, senza confondere sequel, omonimi o edizioni. Un title ID Switch 2 da solo non identifica una Switch 2 Edition.
- La cache PNG è separata da `ArtworkPicks`, con attribuzione e una sola piccola voce negativa per gioco (15 minuti). Il resolver condivide le richieste concorrenti, limita dimensioni e tempi delle risposte, verifica host e immagini quadrate e consulta `robots.txt` prima del download secondario.
- Switch Icon Showdown esclude `/images/` dai crawler, quindi il resolver non scarica le sue immagini (stato in [validation.md](../working-on-it/validation.md)).
- Fallimenti di rete o ricerche ambigue non fanno fallire il porting. Nessun file del motore viene modificato.

**Icona dell'app del gioco.** L'icona scelta in Change artwork (slot Icon, conservata a 1024 px) diventa anche l'icona dell'app del gioco in Finder e nel Dock (`AppIconWriter`, `AppIconModel`, raggiunto come `app.appIcon`).
- **La scelta.**
  - Il pop-up offre **Only here** / **Use on the Mac** per ogni gioco, anche senza icona propria o non ancora costruito.
  - `PortedGame.appIconOnMac` memorizza la scelta esplicita: false vieta la scrittura (anche per NUP e dump), true la richiede quando c'è una scelta Icon, nil applica la regola delle vecchie librerie (`usesPickedAppIcon` oppure assenza dell'icona originale) fino alla prossima scelta. Riconciliazione e scrittura condividono `wantsPickedAppIcon`.
  - Only here ripristina l'icona originale, o la sua assenza, se era già applicata una personalizzata.
  - Automatic rimuove solo la scelta dell'immagine e conserva la destinazione. Usa prima l'originale (anche dal backup durante una personalizzazione), poi l'icona estratta o quella online. Se non trova un sostituto, il writer ripristina l'originale o la sua assenza, senza lasciare la vecchia immagine personalizzata.
  - La tile Icon location cambia la destinazione anche senza una scelta. La tile Automatic mostra l'anteprima risolta; lo stato distingue ricerca, firma e icona non disponibile.
- **La scrittura.**
  - Crea `Resources/AppIcon.icns`, marca `Info.plist` con `NXLibraryAppIcon`, rifirma il bundle ad hoc come l'engine e verifica con `codesign --verify --deep --strict`.
  - L'icona originale resta in `Application Support/NXLibrary/app-icons/<TitleID>/`; ogni errore rimette a posto i file toccati.
  - Avviene dopo ogni build installata (la rebuild sostituisce l'app), all'avvio e quando un gioco si chiude, mai mentre il gioco gira o si costruisce.
  - Durante la firma (circa 50 secondi per un gioco di 9–12 GB) avvio e build del gioco aspettano, e la riga di stato di Change artwork mostra l'avanzamento. Una scelta fatta mentre la stessa app si firma si riesegue alla fine, così vale l'ultima.
- **Log e riconciliazione.**
  - `AppIconProgress` tiene i testi condivisi fra UI e log. Dopo una build installata, anche differita, l'esito si aggiunge al log della build già chiuso dall'engine e al log della UI; l'assenza di artwork non cambia il successo della build. La riga si scrive solo dopo l'ultimo aggiornamento in coda.
  - Scansioni e rebuild conservano la preferenza. Dopo ogni scansione `AppIconModel.reconcileAppIcons` confronta lo stato voluto con l'app (marca `NXLibraryAppIcon`) e rimette in coda le differenze.

**Change metadata** (`ChangeMetadataView`). Il selettore propone, per descrizione, generi, sviluppatore, editore e data, i valori delle fonti disponibili per nxnative e Steam.
- **Comportamento del selettore.**
  - Caricare le proposte non modifica `MetadataPicks`, `SteamPersonalizations` o i dati dello store. A decide solo il campo in anteprima, Automatic rimuove l'override, Write your own resta disponibile.
  - Le descrizioni mantengono la lingua originale e lo dicono nel sottotitolo. Non si aggiungono artwork né sostituzioni automatiche.
  - Il valore adottato è una copia personale, non un abbonamento alla fonte: compare una sola volta in "La tua scelta", con la spunta. Le righe delle fonti restano alternative, senza spunte multiple quando condividono lo stesso testo. Salvataggio e rimozione conservano il focus per identità della riga.
  - Le righe hanno identità per fonte e alternativa, non per testo scaricato, quindi caricamento, disponibilità e cambio di campo non ricreano la lista. Sono dichiarati campo assente, risultato ambiguo, valore uguale ad Automatic, copia salvata e fonte non disponibile.
  - Le righe senza azione non mostrano A Choose. Un errore permette Retry anche dal controller, senza doppie richieste. Ogni fonte aggiorna solo le sue righe, e una risposta si ignora se la query è cambiata. Il focus resta sulla scelta corrente quando arrivano nuove righe e torna ad Automatic se la scelta sparisce, senza aprire il campo di testo.
  - `SeleneExpandableText` conserva estratto (240 caratteri) e testo completo alla stessa larghezza: `Layout` risolve subito la geometria finale e SwiftUI anima frame e dissolvenza. *Perché:* interpolare le misure dentro `Layout` sposterebbe il bersaglio di `scrollTo` mentre si chiude la riga precedente. Espansione e scroll usano la stessa curva, con allineamento iniziale per leggere il titolo delle descrizioni lunghe; Riduci movimento li disattiva. Vale solo per i metadati: gli altri `SeleneOptionRow` non cambiano. `scripts/check_metadata_text_layout.swift` verifica fuori schermo altezze, cambio di contenuto e destinazioni dello scroll.
- **LaunchBox e TheGamesDB** sono alternative nello stesso selettore per i giochi già gestiti.
  - La ricerca usa titolo, edizione e piattaforma, non il negozio; lo Steam ID aiuta dove è supportato ma non è necessario. GameTDB e Title DB restano fonti Nintendo.
  - Si leggono su richiesta una ricerca e una scheda pubblica per database, con parser separati e cache di sole proposte, senza scaricare l'intero Metadata.zip né duplicare un catalogo di immagini. I parser verificano anche la scheda finale, rifiutano le ambiguità e non eliminano parole di edizione.
  - Mac ha la precedenza su PC/Windows: una proposta PC è dichiarata come tale e non fornisce una falsa data Mac.
  - `DatabaseMetadataService` ha due istanze esplicite, ognuna con cache separata per la query pubblica e al massimo quattro ricerche attive. Lettori della stessa query condividono il lavoro; uscire dall'ultimo lettore annulla la richiesta senza salvare un'assenza.
  - Pagine fino a 2 MiB, cache fino a 256 KiB per proposta. Host e percorsi sono vincolati, cookie e redirect disabilitati; errori HTTP e corpi inattesi non diventano metadati.
  - Dati validi durano sette giorni, assenze e ambiguità un giorno. Un errore conserva la proposta precedente come copia salvata e non crea una cache negativa; Retry forza un nuovo tentativo senza cambiare i valori personali. La cache sta dentro `metadata` ed è compresa nei conteggi e nella pulizia delle informazioni del negozio.
  - `LaunchBoxArt.searchURL` genera direttamente la forma canonica in minuscolo, così si evita il redirect 301.
  - Se IGDB è configurato, un suo nome canonico verificato può affinare la ricerca pubblica, senza inviare account, percorsi o attività.
- `OnlineArtwork.find` riceve la piattaforma della richiesta. TheGamesDB cerca Mac OS (37), poi PC (1), oppure Switch (4971) / Switch 2 (5021). La scheda finale deve confermare titolo e piattaforma prima di proporre immagini, senza prendere il primo omonimo. LaunchBox e TheGamesDB sono attribuiti in About.
- Le vecchie assenze di copertina Switch 2 si riprovano con un'identità del resolver distinta, conservando le immagini salvate e le assenze Switch valide.

**Voti della critica.** `CriticRatingService.preferred` ordina i risultati: prima la critica IGDB (con credenziali), poi la critica Wikidata, infine la media utenti IGDB. Un voto pubblico della critica prevale quindi su una media utenti, anche se arriva per prima.
- **Wikidata.**
  - `WikidataRatings` verifica nome o alias esatti (anche il campo `match` degli alias), il tipo videogioco e l'eventuale ID Steam. Per Steam prova prima P1733, l'ID pubblico esatto, verificato di nuovo nelle dichiarazioni dell'entità. Le query tolgono soltanto i simboli ™/®/©, conservando sequel ed edizioni.
  - Abbinamenti ambigui o ID contrastanti non pubblicano un voto.
  - Seleziona solo medie /100 documentate di OpenCritic, Metacritic o CriticDB. Preferisce la piattaforma corrispondente, altrimenti un voto senza piattaforma dichiarata. Non prende il voto Windows per macOS, non converte percentuali di raccomandazione e non fa medie fra fonti.
- **Servizio Wikidata.** `CriticRatingService` interroga solo l'API pubblica Wikidata, senza chiavi, cookie o scraping.

**Descrizioni da Wikipedia.** Quando lo store non ha la descrizione nella lingua dell'app, About this game (Spotlight e Details) mostra l'introduzione di Wikipedia in quella lingua, senza nessun gesto del giocatore.
- `WikipediaDescriptions.wanted` decide dal testo stesso, letto con NaturalLanguage, perché Steam non dice in che lingua risponde: la descrizione è vuota o in un'altra lingua. Sotto i 40 caratteri o con fiducia sotto 0,6 si tiene lo store. Le lingue si confrontano per codice base (pt è pt-BR), il cinese anche per scrittura. Una descrizione scelta dal giocatore (`"custom"`, o un override Steam) non si sostituisce mai.
- L'identità del gioco è quella dei voti: `WikidataRatings.entity` (ID Steam P1733 oppure nome o alias esatti, tipo videogioco). `WikipediaDescriptionService` chiede le sitelink di quell'entità, poi l'introduzione in testo semplice da `<lingua>.wikipedia.org` (`pt` per pt-BR; per il cinese `zh` con `variant=zh-cn`, così il testo arriva in semplificato con i nomi della Cina continentale). Accetta solo `www.wikidata.org` e le sette edizioni, sulla sessione di `CriticRatingService`.
- Cache in `Application Support/NXLibrary/descriptions/wikipedia/`, per query e lingua: un'introduzione resta 30 giorni, "nessuna voce" un giorno. Un errore di rete non si salva e ferma le richieste per 60 secondi. Settings → Storage → Metadata cache la conta e la svuota con quella dello store.
- La pagina chiede solo quando la risposta dello store nella lingua dell'app è definitiva (`GameDetailPresentation.descriptionSettled`): mentre la nuova lingua arriva resta il testo vecchio con il suo avviso, così il testo cambia una volta sola. Aspetta 300 ms prima di chiedere, come per i voti, e mostra il testo solo se la risposta è per lo stesso gioco e la stessa lingua (`WikipediaAbout.matching`). Sotto il testo `WikipediaCredit` dice "From Wikipedia, CC BY-SA." e apre la voce, come chiede la licenza; Wikipedia è anche nei crediti di About.
- Senza voce, per esempio un gioco che su Wikidata condivide la voce con la sua coppia (Pokémon Brilliant Diamond e Shining Pearl), resta il testo dello store con l'avviso della lingua.
  - Serializza e unisce le richieste, limita dimensione e durata e sospende le richieste dopo un errore.
  - La cache `ratings/wikidata` del profilo corrente dura sette giorni per un voto e un giorno per un'assenza verificata; offline conserva il dato con la sua data. La data di scaricamento resta distinta da quella del voto.
  - Cambiare gioco annulla il lettore e impedisce di pubblicare un risultato precedente. Niente viene scritto nel catalogo, nei dati Steam o nei giochi.
- **IGDB (facoltativo)**, in Settings → Online services.
  - **Credenziali.**
    - Il dialogo chiede Client ID e Client Secret dell'applicazione Twitch personale, in cinque passi brevi con i campi del portale, il requisito email/2FA e un link diretto alla registrazione. Controlla la connessione prima di salvare e si può annullare anche durante la verifica. Tastiera e controller della pagina sotto sono sospesi.
    - Search trova IGDB, About contiene l'attribuzione, e nel bundle non c'è nessuna credenziale condivisa.
    - `IGDBCredentialsStore` conserva le credenziali solo nel profilo corrente, in `credentials/igdb.json` con modo 0600, dentro una cartella `credentials` riportata a 0700, esclusa dall'importazione Dev. Non passano da `AppSettings`, UserDefaults, log o URL.
    - Il Client Secret va nel corpo del POST a Twitch; solo il token derivato e il Client ID raggiungono IGDB. I token stanno in memoria, si rinnovano a scadenza o una sola volta dopo 401 e non si scrivono su disco.
  - **Client.** `IGDBClient` è l'unico accesso Twitch/IGDB per voti e metadati: host e endpoint vincolati, redirect e cookie rifiutati, una coda seriale fino a otto lavori con distanza fra le richieste, limiti di dimensione e durata, annullamento e messaggi senza il corpo del server. *Perché:* separare autenticazione e rete dai servizi evita di duplicare token e limiti.
  - **Voti.**
    - `IGDBRatingService` preferisce `aggregated_rating` e `aggregated_rating_count`, valida solo con almeno 3 recensioni (`IGDBRatings.minimumCriticReviews`). Altrimenti usa `rating` e `rating_count` come media utenti esplicita, mai `total_rating`, che è un dato misto.
    - Nome o alias e piattaforma devono corrispondere, oppure l'ID Steam deve essere verificato su `external_games` con `external_game_source.name`. La console deriva da `PortedGame.isSwitch2`, come Details, e distingue `switch` (IGDB 130) da `switch2` (IGDB 508; Wikidata Q122761124), senza mai allargare il filtro alle due console insieme. La console fa parte della chiave di entrambe le cache.
    - La media IGDB è del gioco, non di un port specifico, e conserva questo ambito.
    - `CriticRating` distingue provenienza IGDB e Wikidata, e con `audience` critica da utenti (nil nelle vecchie cache vuol dire critica). `CriticRating.isValid` applica lo stesso minimo di 3 recensioni, quindi le cache con 1–2 recensioni si richiedono di nuovo. Le vecchie assenze IGDB senza versione si riprovano una volta. Togliere IGDB esclude anche i suoi voti utenti.
    - La cache IGDB è per client pubblico e identità del gioco, senza segreti o token, e conserva offline il voto datato. Configurare o rimuovere il provider invalida richieste e token e ridisegna la riga tramite una revisione posseduta da `IGDBSettings`.
  - **Metadati.**
    - `IGDBMetadataParser` usa le stesse regole di nome, alias e piattaforma dei voti. Per Steam verifica `external_games.uid` e la fonte Steam; zero risultati permettono il ripiego per nome, un'identità ambigua non si indovina.
    - Le aziende sono qualificate dai flag developer/publisher, non dalla semplice presenza nell'elenco. Una data richiede la piattaforma corrispondente e il formato `YYYYMMDD`: una data Windows non diventa Mac, e un anno o un mese non diventano un giorno inventato.
    - `IGDBMetadataService` conserva solo la proposta e l'identità verificate, per client pubblico e query, in `metadata/igdb`: sette giorni per i dati, uno per assenze o ambiguità. Gli errori non diventano assenze in cache, e i dati salvati restano disponibili offline con un avviso. Risposte tardive o di credenziali rimosse non si pubblicano.
- **Download a blocchi.** I download di Wikidata, IGDB, LaunchBox/TheGamesDB e Steam passano da `BoundedDownload`, che conserva i blocchi ricevuti da URLSession invece di leggere un byte alla volta. Limiti di dimensione, rifiuto dei redirect e annullamento restano gli stessi.

Prove e misure di queste scelte: [docs/history/reviews/2026-11-16-ratings-metadata-evidence.md](../history/reviews/2026-11-16-ratings-metadata-evidence.md).

**Sfondi online.**
- I parser dei provider sono in `OnlineBackgrounds.swift`. `OnlineBackgroundService` gestisce rete, progressi, miniature e crediti.
- `OnlineBrowser` e `OnlineTransfer`, in `OnlineBrowsePanel.swift`, alimentano la griglia e l'importazione nel selettore dei temi. `ThemeStore` unisce palette, wallpaper inclusi e file importati.
- Impostazioni rapide → Theme mantiene due passaggi: colori con anteprima viva, poi sfondo. Il focus si muove nella griglia delle palette e si ferma ai suoi bordi; A applica la palette e continua allo sfondo. L’anteprima usa il renderer animato quando il movimento è consentito.

## Interfaccia Selene e input

**Canvas, temi e componenti.**
- `SeleneCanvas` scala il canvas 1920×1080 nello spazio disponibile, e `SeleneCanvasEnvironment` espone unità e font alle viste. `SeleneTheme` ricava colori e curve di animazione dalla palette. `MaterialIcon` elenca i glifi; `SeleneFonts` registra il font e li rende in SwiftUI.
- I componenti condivisi in `Views/Components` disegnano righe, switch, pill, focus, suggerimenti dei tasti, dialoghi e conferme. Quando usarli è in [conventions.md](../working-on-it/conventions.md#3-una-schermata-o-un-pannello-selene).

**Suggerimenti dei tasti.**
- Le barre `SeleneHintsBar` stanno a 32 unità Selene dal fondo (`SeleneBottomScrim.hintsBottom`). I simboli sono da 30 unità; solo Q/E e i corrispondenti LB/RB accanto ai filtri Achievements sono da 22, con area cliccabile di 30×36. Il margine sinistro aggiuntivo è 18.
- Le schermate con la barra in un VStack riservano lo spazio nel layout. Spotlight e Achievements riservano invece una fascia trasparente di 84 unità e tengono il focus sopra la sfumatura inferiore.
- In Details la barra è ancorata alla finestra: il contenuto sparisce prima dei comandi, e le fasce in focus salgono insieme alla barra. La stessa posizione vale per le opzioni, il visualizzatore di screenshot e le schermate Home.

**Movimento.**
- L'anello e il riflesso della tessera selezionata (`SeleneTileRing`, `SeleneShine`) girano in Core Animation (`TileMotionLayers`). Curve e campioni stanno in `TileMotion`; il bagliore si disegna una volta con SwiftUI (`ImageRenderer`) e poi si dissolve soltanto, così a schermo fermo l'app non ridisegna nulla tra un frame e l'altro. Con Riduci movimento l'anello resta il disegno SwiftUI fermo.
- Un blocco che scorre per un offset animato passa da `GlideGroup` (`geometryGroup`): pagina Spotlight, pagina del gioco, lista Achievements, pannello Mod, riga Collection. *Perché:* SwiftUI trasmette l'offset a ogni elemento, e un'altra animazione nello stesso momento (una dissolvenza, un ventaglio, un'immagine che arriva) ne cambiava i tempi, così testi, icone e stelle scivolavano a velocità diverse. Il gruppo risolve lo scorrimento una volta per tutto il blocco, e un nuovo blocco che scorre deve usarlo.
- La preferenza Riduci movimento unisce l'impostazione dell'app a quella di sistema. Le viste la leggono da `seleneReduceMotion`, insieme agli altri valori dell'ambiente Selene.

**Sfondo.**
- `SeleneBackdrop` combina gradiente, wallpaper e sfondo animato. Dentro la shell dichiara una `SeleneBackdropRequest` (stile, pausa, Mods e opacità); una sola istanza nella shell conserva il renderer attraverso i cambi di pagina. Le pagine continuano a possedere artwork e maschere. `ShellBackdropCover` assegna la precedenza a Setup, benvenuto e scelta tema: gli strati inferiori restano montati e caldi con opacità minima ma senza input, quelli superiori rimangono visibili. Il blur di opzioni/Add game/Console si applica anche al backdrop condiviso. Senza richiesta si conserva il frame e si ferma il movimento; fuori dalla shell il componente disegna autonomamente. La shell pubblica anche la palette completa in `SeleneBackdropStyle`: un cambio di soli colori invalida il valore condiviso anche con lo stesso wallpaper e la stessa card. Sfondo, superficie Metal e maschere leggono questo snapshot, evitando di aspettare un altro evento della pagina. `MoonlightRenderer` e `MoonlightShaders` rendono la parte Metal; `LiveBackdrop` usa AVFoundation per i video in loop.
  - **Arcane** (ID storico `selene`) mantiene il blu classico come predefinito, con il gradiente radiale originale `0x102A5C` → `0x03081A`. Il fallback mantiene il gradiente lineare storico `0x17244A` → `0x0C142C` → `0x05080F`. **Arcane Crystal** (`arcane-crystal`) dispone fili diagonali; **Arcane Flow** (`arcane-flow`) usa curve più ampie. Entrambi mantengono soltanto filamenti e una luce diffusa tenue, senza piani o fasci luminosi. Il metadato opzionale `moonlight` della palette seleziona `MoonlightSurface`; palette senza metadato o con valore sconosciuto restano classiche. Nessuna nuova preferenza: il selettore e Look salvano lo stesso `colorThemeID`.
  - I filamenti sono funzioni analitiche nello stesso passaggio Metal della luce: nucleo luminoso antialias di circa un pixel fisico, fili secondari più deboli ed estremi sfumati. Due onde viaggianti piegano le curve lungo la loro lunghezza, invece di spostare un bordo rigido; la forma di base varia su120/140s e i bagliori intorno a100–120s. Nei soli temi alternativi i dischi sfocati grandi sono attenuati per lasciare leggibili i fili. Rosa a sinistra e ciano a destra cambiano di pochi livelli RGB su180s (`MoonlightChromatics` condiviso col fallback), senza attraversare lo spettro. Nessuna immagine o video: il movimento appartiene alle superfici.
  - Le particelle sono sempre morbide, senza un selettore: due stili quasi indistinguibili non giustificano una scelta in più. Il decoder ignora l’eventuale campo storico `particleStyle`, senza modificare le altre preferenze, e non lo riscrive.
  - Colore e particelle avanzano con l’orologio del display link esistente, senza timer SwiftUI. Background motion spento e Riduci movimento tengono fermo l’orologio; il fallback senza Metal resta statico. Gli altri temi mantengono la loro palette. Le uniform interpolano superficie, variante Flow, tint e presenza; la cache dei campioni fermi comprende gli stessi valori. Le regole di pausa, Riduci movimento e passaggio all’artwork restano condivise nel percorso esistente. Senza Metal il ripiego mantiene soltanto bagliori statici nei colori locali.
  - Nella Dev, la categoria locale `backdrop-transition` registra creazione e prima presentazione di ogni renderer, oltre all’apertura di Settings e allo stato del fullscreen iniziale. Non registra input o dati del giocatore.
  - Le misure GPU fuori schermo e i loro limiti sono nella [nota del 17 novembre](../history/reviews/2026-11-17-arcane-moonlight.md).
- **Arte dei giochi.** `SeleneArtLayer` è una pila di `CALayer` animati nel render server.
  - Ogni nuova immagine entra sopra ciò che si vede, che resta fermo sotto finché la nuova non è entrata. Così una dissolvenza interrotta riparte da ciò che è a schermo (niente salti, niente moonlight che traspare) e non scatta se il main thread è occupato.
  - Ciò che un layer mostra durante una dissolvenza si calcola sull'orologio (`OpacityFade`, la stessa curva dell'animazione), non dal presentation layer, che per un layer aggiunto nello stesso passaggio non esiste ancora. *Perché:* altrimenti due immagini in fila fanno saltare la prima a piena opacità.
  - Scorrendo veloce, i livelli che lasciano passare meno di mezzo gradino a 8 bit (`ArtStack`) escono subito, così la pila resta di pochi livelli.
  - Se tenere l'arte del gioco precedente lo decide `BackdropArtRule` sulla selezione che il body vede, così il primo render di una nuova selezione, prima di `onChange`, non toglie l'arte per poi rimetterla.
  - Su una card Spotlight tiene l'arte dell'ultimo gioco senza mostrarla (`loadHero(keepsWithoutGame:)`), così tornare allo stesso gioco non ricarica nulla.
- **Card Mods.**
  - Con la card selezionata lo sfondo non mostra arte: il moonlight sfuma in 1,2 s verso l'oro (`SeleneBackdrop.modsTint`), anche sopra una wallpaper, che resta ferma sotto.
  - Colore e fondo oro sono uniform dello shader, che `MoonlightLayerView` interpola sul suo thread: la sfumatura non dipende dal main thread e il frame costa uguale. Da fermo il display link gira solo per la durata della sfumatura.
  - Lasciando la card verso un gioco, l'oro resta finché l'arte del gioco non è arrivata (`SpotlightView.modsBackdrop`), così il passaggio è uno solo.
  - Sopra una wallpaper il moonlight oro resta montato, nascosto e fermo finché non serve, ed entra ed esce con l'uniform `presence` sul suo thread.

**Input e suoni.**
- `GameControllerService` produce `GamepadAction` e riconosce i simboli dei tasti. La shell dà l'input al livello attivo.
- `AppShellView.nativeDialogOwnsInput` dà precedenza a un alert in attesa (`alertMessage`), a `NSApp.modalWindow`, alla sheet nella finestra key o allegata alla finestra key/main. Controller, tastiera e disponibilità dei menu condividono questo controllo; la tastiera controlla anche la finestra dell'evento. Il controller scarta l'azione prima di inoltrarla a qualunque schermata o dialogo interno. *Perché:* il controller non attraversa i monitor `NSEvent` che già cedono la tastiera ai dialoghi nativi. `run_review.py` esegue il routing reale con stati sintetici, compreso il ritorno ai comandi dopo la chiusura.
- `ButtonPrompts` esclude i segnaposto fatti solo di forme, comprese varianti come `capsule.portrait.fill`, e usa in quel caso i simboli della marca riconosciuta; conserva i glifi significativi come `circle.circle` e `square.circle`.
- `HoldDetector` e i modelli di focus rendono verificabili mapping e navigazione.
- `SoundEffectService` risolve i cue tramite `SeleneImporter` e applica volume e attivazione.

## Dati su disco

I percorsi sono relativi alla home. `Application Support/NXLibrary` è `~/Library/Application Support/NXLibrary`; la Dev usa la radice del suo profilo (`AppData`).

| Percorso | Contenuto e proprietario |
|---|---|
| `Application Support/NXLibrary/library.json` e `.bak` | Input del formato precedente, conservati intatti dopo la conversione da `CatalogStore`. |
| `Application Support/NXLibrary/catalog.json` e `.bak` | Catalogo comune e copia valida, gestiti da `CatalogStore` attraverso `CatalogRepository`. |
| `Application Support/NXLibrary/settings.json` | Impostazioni globali, gestite da `AppSettingsStore`. |
| `Application Support/NXLibrary/play-sessions.json` | Sessioni e tempi di gioco, gestiti da `PlaySessionStore`. Array semplice delle ultime 200 sessioni, leggibile anche dalle versioni precedenti. |
| `Application Support/NXLibrary/play-sessions-totals.json` | Tempo e ultima partita delle sessioni oltre le 200, per gioco: `totalDuration(for:)` e `lastPlayed(for:)` li sommano alle sessioni recenti. |
| `Application Support/NXLibrary/keys/prod.keys` | Chiavi importate da `KeyStore`, con permessi `0600`. |
| `Application Support/NXLibrary/credentials/igdb.json` | Credenziali IGDB personali (`0600`, cartella `0700`), escluse dall'importazione Dev. |
| `Application Support/NXLibrary/app-sizes.json` | Cache delle dimensioni dei bundle. |
| `Application Support/NXLibrary/workspaces/` e `Temp/` | Collegamenti alle sorgenti, workspace e app temporanee dei porting, quando l'app va sul volume del Mac (o su un volume che non accetta link simbolici). |
| `Application Support/NXLibrary/artwork/` | Cache di immagini, copertine, screenshot e miniature online. |
| `Application Support/NXLibrary/metadata/` | Cache dei metadati dello store e delle proposte di IGDB, LaunchBox e TheGamesDB. |
| `Application Support/NXLibrary/ratings/` | Cache dei voti (Wikidata, IGDB). |
| `Application Support/NXLibrary/descriptions/wikipedia/` | Cache delle introduzioni di Wikipedia per gioco e lingua. |
| `Application Support/NXLibrary/artwork-picks/` e `metadata-picks.json` | Scelte manuali di immagini e campi. |
| `Application Support/NXLibrary/app-icons/<TitleID>/` | Icona originale dell'app del gioco, conservata da `AppIconWriter`. |
| `Application Support/NXLibrary/SeleneImports/` | Suoni, wallpaper, video e relativi crediti importati. |
| `Application Support/NXLibrary/SaveBackups/<TID>/` | Snapshot datati, manifest e copie protettive. |
| `Application Support/NXLibrary/Logs/<TID>.log` | Log del porting costruito dall'app. |
| `Application Support/NXLibrary/mods/<TID>.json` | Ordine, stato e origine GameBanana delle mod di un gioco, gestiti da `ModStore`. |
| `Application Support/NXLibrary/gamebanana/matches.json` | Pagina GameBanana scelta per ogni gioco, gestita da `GameBananaMatchStore`. |
| `~/Library/Caches/NXLibrary/gamebanana/` | Cache delle risposte e delle immagini di GameBanana, comprese le copie dello store. |
| `~/Library/Application Support/nxnative/<TID>/` | `env.txt`, `save`, eventuale `save_device`, `save_user2`…`save_user8`, registro `save.users`, cheat, mod e dati runtime del motore. |
| `~/Library/Logs/nxnative/<TID>.log` | Log del gioco avviato. |
| `<Game apps>/<nome>.app` | Prima installazione del gioco; default `~/Applications`. I rebuild aggiornano l'app nella sua posizione. |
| Accanto al gioco: `.nxlibrary-install-<hash>.json` | Ultima ricevuta di installazione per quel percorso, gestita da `BuildOutputInstaller`. |
| Accanto al gioco: `.nxlibrary-incoming-<hash>.app` | Preparazione temporanea quando il bundle pronto si trova su un altro volume. |
| `<Game apps>/.nxlibrary-build/workspaces/<TID>/` e `Temp/` | Workspace e app temporanee dei porting quando la cartella delle app è su un altro volume (`BuildScratch`). |
| `UserDefaults` del bundle Arcane | Percorsi ricordati, stato del Setup, override della toolchain e cache di alcuni controlli. |

I dati Steam di Arcane sono descritti in [steam.md](steam.md#dati-su-disco-di-arcane).

Nel repository, `.build/` contiene gli output SwiftPM, `work/Runtime` il runtime preparato per il packaging, `work/release` i prodotti di release e `dist/` il DMG di sviluppo. Queste cartelle sono escluse da Git.

## Aggiornamenti e distribuzione

**Dialogo degli aggiornamenti.**
- Il controllo manuale (menu macOS e About) presenta `AppUpdateDialog` durante la richiesta e al suo esito: versione corrente, nuova release con note scorrevoli, errore con Retry, oppure avanzamento.
- Il dialogo ha priorità sull'input sottostante: frecce e controller scorrono le note e scelgono le azioni, Escape chiude. Chiuderlo durante il download lascia il trasferimento in corso.
- Una richiesta manuale durante un controllo automatico impedisce una seconda offerta automatica per la stessa risposta. Le note mostrano la propria versione anche quando la candidata è più recente dell'ultima release pubblica.

**Regole di installazione.**
- `AppUpdateState` descrive gli stati nel Core. `AppUpdate.mayInstall` richiede una versione più recente e una copia installabile: i controlli manuali di copie di sviluppo o in sola lettura leggono le release senza autorizzarne la sostituzione.
- Una copia di release che macOS esegue come copia temporanea (App Translocation, `AppUpdate.isTranslocated`) non si aggiorna mai: a ogni avvio `AppShellView` chiede di spostarla in Applicazioni con un `SettingsNotice` (`AppUpdate.asksToBeMoved`). Il pulsante apre `/Applications`, perché il percorso temporaneo non aiuta a ritrovare l'originale.
- Il gate si verifica prima del download e prima dell'installazione, insieme ai controlli e ai lease esistenti. Il motivo dell'attesa arriva al dialogo come valore, così la chiusura di un gioco aggiorna il pulsante Update.

**Download e verifica.**
- `AppUpdater` coordina gli aggiornamenti da `Bium23/NxLibrary`, senza autenticazione. Le regole di versione, requisiti, digest, identità del bundle e installazione sono in `AppUpdate`.
- La release si accetta solo se lo zip `NXLibrary-<versione>.zip` sta nel percorso di download di quel repository. `AppUpdate.successorRepository` (`Bium23/Arcane`) è il nome che il repository può prendere: dopo una rinomina GitHub risponde alla vecchia API delle release con link sotto il nome nuovo, quindi anche quel percorso è accettato, scritto esattamente come lo restituisce GitHub.
- `AppUpdateDownload` limita il trasferimento alla dimensione dichiarata e agli host HTTPS di GitHub.
- `validate_update.py` verifica struttura e percorsi, poi estrae contando i dati davvero decompressi tramite il Python incluso. Prima della sostituzione si controllano versione, marker, identificativo e firma del bundle.
- La firma ad hoc protegge il contenuto sigillato ma non identifica da sola il maintainer.
- `AppUpdate.install` copia il candidato in una cartella esclusiva `.arcane-update.*` sul volume di destinazione e scambia i bundle con `RENAME_SWAP`, mantenendo il nome corrente. Le copie già presenti accanto all’app non vengono usate né rimosse. L’app precedente va nel Cestino; se il Cestino fallisce, resta nella cartella esclusiva. Un errore prima dello scambio pulisce soltanto il candidato posseduto; la cartella finale si rimuove solo se vuota. *Perché:* nomi prevedibili come `(new)` e `(old)` possono appartenere al giocatore.
- Prima dell'installazione l'updater ottiene un'esclusione globale dal `SaveOperationGate`: aspetta che finiscano le operazioni in corso su salvataggi, Play e installazioni e impedisce nuovi ingressi durante sostituzione e riavvio. Un recupero bloccato senza I/O attivo non impedisce l'aggiornamento. Il coordinatore esclude nuovi porting mentre l'app si aggiorna.

**Nome del file alla chiusura.**
- Lo zip dell'aggiornamento contiene sempre `NXLibrary.app`, perché le copie precedenti leggono quel nome, e l'installazione tiene il nome del file corrente. Il nome Arcane arriva al file alla chiusura.
- `AppDelegate.applicationWillTerminate` chiede ad `AppBundleRename.target` se rinominare. Lo fa solo una copia release, non traslocata, che si chiama `NX Library.app`, in una cartella scrivibile senza un `Arcane.app` accanto.
- Non rinomina mentre una build, un aggiornamento o un'operazione sui salvataggi usa ancora il bundle (`AppDelegate.isBusy`, impostato da `AppShellState`), né quando un riavvio è in programma (`AppDelegate.relaunchScheduled`, da Restart app e dall'updater): l'aiuto che riapre l'app usa il percorso attuale.
- *Perché alla chiusura:* rinominare un bundle in esecuzione lascia `Bundle.main` sul percorso vecchio fino al riavvio. Il Dock segue la rinomina nella stessa cartella ([sonda](../history/reviews/2026-11-17-dock-rename-probe.md)).
- Un errore va nel log e non ferma la chiusura. La copia Dev non si rinomina mai: la ricostruisce `build_app.sh`.

**Changelog dell'engine.** `UpstreamChecker` consulta il changelog del motore e `UpstreamCopy` lo presenta. L'adozione di un nuovo commit segue la procedura manuale di [AGENTS.md](../../AGENTS.md) e delle [note di upgrade](../history/engine-upgrades/README.md).

**Script di build e release.**
- `bundle_runtime.sh` prepara Python e strumenti da `runtime.lock`, controlla gli hash e sistema i riferimenti Mach-O con `relink_macho.py`.
- `build_app.sh` compila e confeziona bundle, risorse, plist e firma ad hoc, poi installa il bundle completo attraverso `BuildOutputInstaller` dopo firma e verifica. Il suo parametro di destinazione permette di preparare una copia temporanea prima di sostituire quella installata.
- `release.sh` richiede un albero pulito e il runtime pronto, esegue suite Swift e tutti i controlli `Tests/CatalogAppChecks/run_*.py` senza UI, imposta versione e marker di release e crea ZIP e DMG. `--publish` abilita tag e pubblicazione su GitHub, solo con autorizzazione esplicita dell'utente. `build_dmg.sh` confeziona un bundle già costruito.
- Il runtime e i contenuti versionati si verificano con `scripts/check_publication.py`.

## Verifica e manutenzione

**Test.**
- La suite Core usa fixture sintetiche, cartelle temporanee, runner e confini I/O sostituibili. Copre modelli, persistenza, sorgenti, chiavi, contratti CLI, processi, installazione, lancio, stato della UI, artwork, cheat e transazioni dei salvataggi. Il [catalogo dei test](../working-on-it/file-map.md#test-e-fixture) indica la responsabilità di ogni file.
- `run_nup_programs.py` verifica i convertitori reali UI/persistenza e gli argomenti NUP; con uno snapshot
  immutabile dell’engine verifica anche il probe Python su un contenitore sintetico. `run_save_restart.py`
  arresta e riavvia processi distinti nei checkpoint di sostituzione e recovery, conservando backup e
  dati non committed; non apre finestre né accede ai salvataggi del giocatore.
- `NX_TEST_ENGINE_REPO` permette al controllo dei messaggi del motore di usare un checkout separato; un valore esplicito non valido è un errore. Durante una revisione, `NX_TEST_ENGINE_COMMIT` seleziona l'hash completo del candidato prima di cambiare il pin; senza override il test controlla sempre il pin.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
bash scripts/build_app.sh
codesign --verify --deep --strict "$HOME/Applications/Arcane Dev.app"
```

**Prove interattive.** Le esegue l'utente; gli agenti svolgono controlli sul codice, test automatici e build/installazione, secondo `AGENTS.md`.

**Per una modifica.** Parti dall'area in questa guida e nel catalogo dei file, segui il collegamento al file e leggi i chiamanti reali. Segui la ricetta di [conventions.md](../working-on-it/conventions.md) e aggiorna i documenti come dice la sua sezione 10.
