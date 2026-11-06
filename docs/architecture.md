# NX Library — guida tecnica

Aggiornata il 5 novembre 2026 sul codice del repository. La mappa comprende 253 file Swift di produzione e 104 file di test e supporto ai test. Il ramo porta nxnative al candidato 04df08d4 (6 novembre 2026, 1057 test Swift superati): il pin resta un candidato finché il maintainer non conferma un build certificato e un avvio visibile. Le funzioni della 0.1.3 e della 0.1.4 aggiunte dopo l'ultima conferma restano in attesa di validazione manuale.

Questa guida descrive il funzionamento attuale. Il [catalogo dei file](file-map.md) assegna una responsabilità a ogni file versionato, suddiviso per area.

Il [README](../README.md) è la guida d'uso; la [guida di sviluppo](development.md) raccoglie build, runtime, CI e release. Il [changelog](../CHANGELOG.md) distingue il lavoro non pubblicato dalle versioni distribuite. Il runtime e i contenuti versionati vengono verificati da `scripts/check_publication.py`; `build_app.sh` installa il bundle completo attraverso `BuildOutputInstaller`, dopo firma e verifica.

## Indice

- [Struttura e dipendenze](#struttura-e-dipendenze)
- [Avvio e stato dell’app](#avvio-e-stato-dellapp)
- [Libreria e navigazione](#libreria-e-navigazione)
- [Setup e compatibilità](#setup-e-compatibilità)
- [Sorgenti e porting](#sorgenti-e-porting)
- [Avvio dei giochi e sessioni](#avvio-dei-giochi-e-sessioni)
- [Cheats](#cheats)
- [Salvataggi, backup e recupero](#salvataggi-backup-e-recupero)
- [Artwork, metadati e sfondi](#artwork-metadati-e-sfondi)
- [Interfaccia Selene e input](#interfaccia-selene-e-input)
- [Dati su disco](#dati-su-disco)
- [Aggiornamenti e distribuzione](#aggiornamenti-e-distribuzione)
- [Verifica e manutenzione](#verifica-e-manutenzione)

## Struttura e dipendenze

[Package.swift](../Package.swift) dichiara tre target. La toolchain Swift è quella di Xcode, con deployment minimo macOS 13.

| Target | Compito |
|---|---|
| `NXLibrary` | Eseguibile SwiftUI, integrazione AppKit, controller, notifiche, coordinamento e rendering. |
| `NXLibraryCore` | Modelli, persistenza, parsing, gestione file, contratti del motore, processi e logica delle funzionalità. |
| `NXLibraryCoreTests` | Test XCTest del Core, con dati sintetici e dipendenze sostituibili. |

`NXLibrary` dipende da `NXLibraryCore`. Il Core usa anche framework macOS, fra cui Combine, AppKit, ImageIO, CommonCrypto e IOKit. Il package attuale usa i framework del sistema e non dichiara dipendenze SwiftPM esterne.

```mermaid
flowchart TD
    Entry["NXLibraryApp → MainView"] --> Shell["AppShellView"]
    Shell --> Router["AppRouter e schermate SwiftUI"]
    Shell --> VM["AppViewModel e modelli dei pannelli"]
    Shell --> Stores["Settings, sessioni, artwork e monitor dei giochi"]
    VM --> Core["Servizi e modelli NXLibraryCore"]
    Core --> Disk["Application Support, app e log"]
    Core --> Process["BuildService e CommandRunner"]
    Process --> Engine["Checkout nxnative al commit fissato"]
    Core --> Network["Cataloghi artwork, metadati e release"]
```

Il checkout nxnative fornisce estrattore, rewriter, shader, profili dei giochi e runtime dei giochi compilati. NX Library prepara gli argomenti, controlla i requisiti e presenta lo stato delle operazioni. Il pin attuale è `4a0551e4b9abc75ea736006e4dbd30fcac0d03a4`, definito in `AppViewModel.pinnedEngineCommit`. La cache dello stato upstream viene riutilizzata soltanto quando il suo commit di base coincide con il pin.

## Avvio e stato dell’app

`NXLibraryApp.swift` registra una sola `Window` e i comandi della barra menu. File → Add Game sostituisce New Window: controller, updater e catalogo condiviso non offrono un flusso multi-finestra. `AppDelegate.swift` registra il font Material Icons e gestisce chiusura e riapertura della finestra. `MainView.swift` presenta `AppShellView`.

`AppShellView.swift` possiede gli oggetti condivisi tramite `@StateObject`. Comprendono `AppViewModel`, router, impostazioni, sessioni di gioco, artwork, monitor dei giochi e updater. Imposta palette, canvas Selene, preferenze di accessibilità e livelli sovrapposti. Intro, Setup, menu, ricerca, opzioni di un gioco e conferme ricevono una priorità esplicita nell’input.

`NativeMenuCommands` osserva il tracking dei menu AppKit e rinvia le azioni al turno successivo della coda principale, conservando la sospensione dell’input durante il passaggio. La shell pubblica le disponibilità nella scena attiva tramite `FocusedValues`: intro, Setup, pannelli e assenza di selezione disabilitano i comandi non applicabili. Mouse, monitor tastiera e dispatch controller non cambiano selezione sotto un menu nativo. In Spotlight, Game Details usa `SpotlightState.showGameDetails` come il comando interno e conserva il titolo selezionato; in Collection apre la pagina Details. Game Options blocca l’hit testing del contenuto sottostante.

`startInFullscreen` viene salvato in AppSettings, ha default false per i vecchi file, compare in Search/Changed e viene ripristinato dal reset Start-up. `StartupWindowView` legge il valore alla creazione e applica una sola volta la modalità alla finestra visibile e attiva. Cambiare la preferenza non altera la finestra corrente.


`AppViewModel.swift` coordina libreria, rilevamento dell’ambiente, selezione delle sorgenti, porting e lancio. Le estensioni `AppViewModel+…` contengono le integrazioni di cheats, salvataggi, diagnostica, controlli delle chiavi, toolchain e installazioni in attesa. Sono parti dello stesso oggetto osservabile.

La shell condivide un solo `AppSettingsStore` con router e coordinatore. L’avvio rispetta i flag di verifica del motore e scansione della libreria; senza scansione carica il catalogo salvato. Il primo Setup accompagna l'utente in Get ready e Your games, dove Skip for now completa l'introduzione anche con libreria vuota. La verifica prima di ogni porting resta obbligatoria. I pannelli di build possono avviarla su richiesta. I risultati asincroni relativi a un checkout precedente vengono scartati e il porting registra la propria fotografia della toolchain.

`FirstRunSetup` tiene insieme pagina corrente e completamento: `NXLibrary_SetupPage` permette di riprendere una prima configurazione interrotta, mentre `NXLibrary_SetupCompleted` mantiene compatibili gli utenti già configurati e impedisce ripetizioni automatiche dopo Skip. Open Setup riapre manualmente entrambi i passaggi senza rendere incompleta una configurazione precedente. `YourGamesSetupView` aspetta la scansione prima di distinguere libreria vuota o pronta; Open library e Skip tornano alla libreria. I due passaggi condividono backdrop, indicatore, transizioni e canale di input; Add Game sospende il proprio input quando Setup è davanti.

`SetupCheckModel` e `SavePanelModel` possiedono lo stato dei rispettivi pannelli. `SavePanelModel`, per esempio, mantiene anteprima, operazione in corso, errore, ultimo backup ed evento di importazione riuscita. Gli aggiornamenti destinati alla UI vengono pubblicati sulla coda principale.

## Libreria e navigazione

`PortedGame` rappresenta un titolo della libreria. Include identità, app installata, sorgenti, impostazioni runtime, ultimo porting, toolchain e installazione eventualmente differita. `LibraryFile` è il contenitore persistito in `library.json`.

`GameResourceState` riconcilia app, sorgenti e stato: conserva build in corso e workspace non ancora compilati, distingue app mancante e file di origine mancanti e mantiene Play per una build esistente. Le viste usano `PortingPills.unavailable` per il motivo breve e l'azione primaria disabilitata; `PortingTileLook.locked` riusa sfocatura e lucchetto. La voce rimane in libreria. Non viene aggiunta alcuna ricerca dell'app spostata; Refresh controlla le cartelle già configurate. Un cambio cartella durante la scansione scarta il contesto precedente e avvia quella nuova.

`ImportService` scansiona i bundle `.app`, legge `Info.plist`, riconosce gli identificativi nxnative e produce le voci importabili. La candidata UX aggiunge una visita breadth-first nelle sole cartelle scelte, fino a sei livelli e 4000 directory, con deduplicazione dei percorsi canonici. Non entra in bundle/package e non segue i symlink delle sottocartelle. Limiti e letture fallite producono avvisi con motivo e azione utile: sono visibili accanto a Scan game apps nelle impostazioni e, nel primo Setup, sotto Game apps. Non aprono dialoghi automatici né un ciclo Retry all’avvio e non cancellano il catalogo. Una scansione successiva aggiorna o rimuove gli avvisi. `appsForLibrary` seleziona una sola osservazione per titolo: il percorso già registrato se esiste, altrimenti la prima osservazione del risultato ordinato dalla più recente. Se un'app esiste fuori dall'area scandita, la sua voce resta invariata. Merge e metadati usano la stessa selezione.

`AppSizeCache` ricorda le dimensioni in funzione di percorso e data di modifica. `LibraryStore` carica e salva il catalogo, conserva `library.json.bak` e offre il merge delle voci. Il coordinamento applicativo riconcilia app trovate, dati già salvati e sorgenti disponibili.

La candidata UX integra `FullscreenCursorView` nella shell. Un NSView osserva la propria finestra, il mouse e le transizioni native; `CursorIdleState` decide la visibilità usando il tempo monotono. In fullscreen attivo, con mouse nel contenuto, il puntatore si nasconde dopo tre secondi senza movimento. Cambi di schermata, menu interni, ricerca, opzioni, tastiera/controller, click e scroll non lo rendono visibile. La posizione reale viene campionata anche dal timer: i loop nativi di menu e controlli possono consumare gli eventi prima del monitor locale. Durante un menu nativo si sospende il nuovo nascondimento, senza svelare un puntatore già nascosto; alla chiusura viene riallineato lo stato AppKit. Un movimento riavvia il ritardo. Pannelli di sistema, perdita di focus e uscita fullscreen ripristinano la visibilità. Il distacco rimuove monitor, timer e osservatori e ripristina il precedente `acceptsMouseMovedEvents`. **Il maintainer ha confermato la revisione 2 di scansione e cursore e, nella candidata finale 0.1.2, menu nativi, dialogo aggiornamenti, avvio fullscreen, riga di scansione e gate certificato.**

Il merge parte dalla voce persistita e aggiorna esplicitamente i dati osservati dalla scansione. Conserva impostazioni, identità, preferiti, installazione in attesa ed errore dell’ultimo porting. Restano le regole precedenti per associare le sorgenti e conservare la provenienza di una build installata.

Settings → Library usa un'unica riga **Scan game apps**, con la stessa azione per scoperta e refresh. La riga e l'azione controller sono disabilitate durante la scansione. Il catalogo Search usa lo stesso nome; Collection conserva il proprio ingresso per importare build esistenti.

L’aggiunta o il collegamento esplicito delle sorgenti usa `merge(replacingSources: true)`: la selezione confermata sostituisce sorgenti, workspace e percorso della cache, anche se i file precedenti esistono ancora. I file originali restano sul disco. Le scansioni automatiche continuano a conservare la selezione già registrata e il bundle installato.

### Ambito delle impostazioni

| Punto dell’interfaccia | Autorità |
|---|---|
| Settings → Games → New games | Valori iniziali copiati nei nuovi titoli. |
| Game Options → Next launch | Configurazione di quel titolo, applicata al prossimo avvio. |
| Use new game defaults | Copia una volta i default correnti nel gioco selezionato. |
| Add Game → Review | Nuovo titolo: parte dai default. Titolo esistente: `GameRuntimeConfig.forReview` legge le sue opzioni effettive. La conferma salva i valori mostrati. |
| Cloud saves | Preferenza riapplicata prima di ogni avvio, compreso Off. |
| Controllers | Navigazione della libreria; il sottogruppo New games contiene i default della vibrazione. |

Options e Play leggono `GameRuntimeConfig.load`: preferenze per titolo in UserDefaults, poi `env.txt` del titolo, quello nel bundle e infine i valori del modello. Il rebuild ricava `languageForBuild` dalla configurazione del titolo e non conserva una lingua separata dal wizard. Le modifiche dei default globali non aggiornano automaticamente i giochi già aggiunti. Search e Changed attribuiscono la vibrazione a Controllers.

Il catalogo Settings descrive i singoli controlli; Changed riceve anche le differenze delle preferenze esterne ad AppSettings. Le azioni da controller si aggiornano con lo stato dei pannelli e mantengono il focus per identità. About pubblica azioni selezionabili. Il reset aggiorna AppSettings con una sola assegnazione e segnala le scelte cloud/percorso preservate.

`AppSettingsStore` pubblica gli errori e conserva una copia dei file illeggibili prima di consentirne la sostituzione. La UI usa un dialogo Selene, con Retry per una scrittura fallita. `GameRuntimeConfig.save` propaga gli errori di env.txt e persiste le preferenze per titolo dopo la scrittura riuscita. Un env.txt illeggibile viene conservato e segnalato.

`AppRouter` gestisce schermata corrente, cronologia di ritorno e richieste di selezione. I modelli `SpotlightState`, `LibrarySelectionState`, `DetailsFocus`, `MenuSelectionModel` e `FocusIndex` descrivono il focus indipendentemente dal disegno SwiftUI. `LibraryQuery` applica ricerca, filtri e ordinamento.

Le viste principali sono Spotlight, Collection e Details. Ricerca, Add Game, Console, Game Options e Settings sono raggiunti dalla shell e dalle azioni del router. Le estensioni `…+Input.swift` traducono tastiera, mouse e controller in modifiche ai modelli di focus. Le righe di Spotlight e Collection mettono ogni tessera al suo posto nella riga e scorrono con un'unica camera (`SpotlightRowGeometry`): la riga si muove come un pezzo solo, e una tessera creata al bordo mentre la riga ancora scorre non arriva prima delle vicine. Lo scorrimento è una molla smorzata, che a pressioni rapide riprende la velocità che ha invece di ripartire a ogni pressione; le tessere si creano quattro oltre ogni bordo dello schermo. In Spotlight posto e dimensione di ogni tessera e la camera si ricavano da un solo valore animato, la posizione della selezione (un indice, con frazioni a metà strada): animati separatamente (offset, scala, camera), la crescita di una tessera iniziata mentre la riga ancora scorreva partiva un paio di fotogrammi dopo il suo spostamento, e la tessera si staccava da quella alla sua destra. Una selezione che salta più tessere scorre attraverso quelle in mezzo; mentre una tessera è sollevata per spostarla cresce solo lei.

## Setup e compatibilità

`SystemDetector` e `EngineLocation` individuano checkout e cartelle dell’utente. `NXNativeEnvironment` raccoglie lo stato di Python, strumenti, Xcode, Metal e .NET. `EngineToolchain` risolve Python e `PATH`, preferendo il runtime incluso nel bundle quando disponibile.

`SetupProbe` costruisce i dati del Setup. `SetupCheck` li traduce in schede, stati e azioni. `SetupCheckModel` esegue i controlli in background e coordina installazioni e avanzamento. `SetupActions` prepara gli argomenti Git per portare un checkout gestibile al pin. `DotnetRelease` seleziona il pacchetto Microsoft e verifica SHA-512 prima dell’apertura nell’Installer di macOS.

Get ready mostra soltanto i sei requisiti tecnici, in una griglia 3×2; i problemi alle cartelle non riaprono questa schermata. Your games presenta Game apps, la cartella unica in cui cercare giochi nxnative esistenti e installare le prime build. Il default `~/Applications` può essere preparato al primo uso solo se non è già stato scelto o ricordato un percorso. Le destinazioni personalizzate o confermate rimangono ricordate anche quando non disponibili. La lettura basta per scoperta e Play; le nuove installazioni richiedono scrittura. Game files rimane una preferenza facoltativa in Settings → Library, separata dalla selezione temporanea del wizard. Cambiare Game apps non sposta app già registrate; cambiare Game files non sostituisce i sorgenti di un titolo senza conferma esplicita. `GameFoldersCopy` mantiene i nomi coerenti.

`CompatibilityChecker` verifica commit, modifiche del checkout, contratto CLI e compilatore Metal richiesto dal lock del motore. `ToolchainRequirements.current` contiene Xcode minimo, major .NET e asset Metal. `ToolchainGateCopy` produce la spiegazione del risultato per la UI.

Il lock del pin attuale certifica Metal `32023.922`, asset Apple `27B47`, con Xcode minimo `27.2`. La [nota dell’upgrade del 6 novembre](upstream-upgrades/2026-11-06-4a0551e4-04df08d4-review.md) registra la revisione del candidato 04df08d4; quella [del 5 novembre](upstream-upgrades/2026-11-05-b64a5ff0-4a0551e4-review.md) registra gate certificato senza override, build reale di Wonder con archivio pipeline e avvio confermato dall’utente per 4a0551e4. Un build con override riceve `toolchainVerified=false` e `--allow-other-metal`. Play valuta la disponibilità dell’app già installata separatamente dal gate per un nuovo porting.

L'engine più nuovo è una scelta esplicita del giocatore (Settings → Engine → **Newest engine**). Dopo il controllo Upstream, che misura sempre i commit rispetto al pin, `NewestEngine.fetchLock` legge il lock di main da GitHub: se certifica un Metal diverso da quello del lock del pin, la riga dice che serve un NX Library più nuovo e non offre il cambio. `NewestEngineSwitcher` rifiuta un checkout con file modificati, scarica, rilegge il lock con git e solo allora fa `checkout --detach`. La scelta (`NewestEngineChoice`) è salvata, diventa il commit atteso dal gate e quello registrato nelle build, accende l'override (che resta bloccato finché la scelta è attiva) e marca le build come non testate; il gate mostra **Newest engine** in arancione, mai Certified. Il Setup continua a installare il pin, ma per il commit scelto mostra la scheda pronta in arancione con **Back to tested** e non la riporta indietro da solo. La scelta decade quando il checkout non è più su quel commit o quando un aggiornamento di NX Library porta un pin che lo contiene; se l'override l'aveva acceso la scelta, torna spento. Settings e Setup usano la stessa frase (`NewestEngineCopy.note`).

Il candidato `04df08d4` non cambia CLI, eventi di progresso, compilatore Metal né lettori NUP e cartelle (`pack_nup`, `pack_dump`). Cache di compilazione e librerie shader diventano un file ciascuna (`shader/cache/cas.db`, `msl/b-<chain>.img`): NX Library non legge dentro nessuno dei due. Il primo build di un gioco dopo l'aggiornamento sposta prima la vecchia cache nel nuovo file e lo annuncia con `moving the compile cache …`; `PortingProgress.isUpdatingShaderCache` lo mostra come **Updating shader cache**. Il nuovo `.github/requirements/tools.txt` dell'engine elenca numpy, pillow e texture2ddecoder, usati solo da strumenti di sviluppo: `EngineRuntimeRequirementsTests.notBundled` ne registra il motivo.

Il pin `4a0551e4` aggiorna shader, runtime e profili (compresi nuovi giochi Switch 2) e porta le righe `Front-ends:` nei commit dell'engine, lette a ogni re-pin. Tre capacità hanno un riflesso nell'interfaccia: `stage_end` con `warn: true` (archivio pipeline mancante) mostra ⚠ sulla fase e una spiegazione in **Ready to play** (`BuildWarningCopy`); quando lo script espone `survey_nup` / `survey_dump`, `EngineSourceCapabilities` accetta NUP e cartelle estratte senza profilo, che l'engine porta con un profilo provvisorio, e Review mostra **Not tested with this engine yet** per qualunque sorgente senza profilo; la guida dei controlli elenca l'uscita con Home (2 s, poi A). Dopo 0.1.3 anche un NUP senza base (777a5f6c) è accettato: Review offre solo le versioni di update (la più recente selezionata, una sempre scelta) e la build passa quella versione con `--package`, mai `v0`. Le nuove righe di `settings.tsv` (120 fps, upscaler del gioco, forma dell'immagine) arrivano da sole tramite Game options. `--seen-shaders`, `--program` e le opzioni per i profili provvisori non vengono adottate. Un salvataggio con nomi creati prima di 7c23cc0 viene rinominato al primo mount: una build più vecchia dello stesso gioco potrebbe non leggerlo più.

Il pin precedente `b64a5ff0` aggiorna audio, allineamento memoria, rendering, shader e profili; aggiunge il controllo chiavi anticipato e la pulizia cache. NUP resta un formato sorgente non esposto dal frontend, i diagnostici non diventano nuovi toggle e i controlli FPS rimangono quelli già supportati. Le precedenti correzioni AV1 restano incluse. Il motore compila dav1d dalle proprie sorgenti incluse; il runtime del frontend non cambia. Gli hook per incorporare la vista del gioco in un frontend non vengono adottati: NX Library avvia app di gioco separate.

## Sorgenti e porting

L'integrazione di [nxnative 163a9905](upstream-upgrades/2026-11-02-2716f78-163a9905-review.md) aggiunge un ingresso per cartelle estratte e metadati per pacchetti con più contenuti. `EnginePackageReader` riusa il lettore content-meta upstream; `ExtractedSourceCatalog` legge NPDM e profili registrati senza chiavi. `SourceSelection` tiene separati contenuti selezionati e file fisici: un pacchetto si conta e si collega una sola volta, il DLC incorporato rimane incluso e la versione scelta viene passata con `-p`.

`GameFileItem` conserva facoltativamente layout e requisito di selezione del titolo; i vecchi JSON continuano a indicare pacchetti. Questi requisiti sono verificati prima del build anche cambiando checkout. Le cartelle estratte sono collegate nel layout `base/`, `updates/<version>/`, `dlc/<title>/0/romfs/`; il restaging rimuove link esclusi e contenitori vuoti, preservando cache e originali. Un pacchetto illeggibile non nasconde gli altri giochi validi: la scansione mantiene i risultati e segnala i file saltati.

Con un engine che riconosce cartelle estratte, Setup permette di proseguire senza chiavi. La selezione di pacchetti cifrati continua a richiederle e a eseguire il preflight. La guida In game include Shift + frecce per la levetta destra delle nuove build. L'integrazione è inclusa nella versione principale al pin riportato sopra.

1. `AddGameView` raccoglie cartelle o file. `SourceCatalog` riconosce NSP, XCI, NSZ e XCZ e raggruppa base, aggiornamenti e DLC. Le selezioni di file vengono scandite e collegate singolarmente, senza includere altri pacchetti della cartella né modificare la preferenza globale Game files. Il reset della bozza avviene solo dopo la conferma del selettore. Più titoli richiedono una scelta esplicita; le riletture dello stesso titolo mantengono nome, impostazioni e selezioni logiche di update/DLC anche se cambiano gli UUID delle righe.
2. `AppViewModel+KeyCheck` invoca `KeyCheck` sulle sorgenti selezionate. Il risultato dipende dalla selezione corrente, così un controllo precedente non abilita un porting diverso.
3. `WorkspaceManager` usa la cartella sorgente in loco oppure prepara un workspace di collegamenti simbolici. Gestisce anche il riuso di una cache esistente. `BuildScratch` sceglie dove: workspace e app temporanea stanno sul volume dell'app. Se la cartella delle app è su un altro volume locale APFS o Mac OS esteso vanno in `.nxlibrary-build/` accanto alle app (exFAT e FAT accettano i link ma tengono gli attributi in file `._` che rompono la firma dell'app; `statfs` dà il tipo), così il disco del Mac non serve e l'installazione è una rinomina; altrimenti (stesso volume, exFAT, rete) restano in Application Support. Una cartella `workspaces` che il giocatore ha spostato su quel volume resta dov'è, e un workspace gestito già su quel volume conserva la sua cache. Un workspace gestito rimasto su un altro volume viene cancellato quando ne nasce uno nuovo, tranne se il gioco non è ancora costruito e punta ancora lì. Il controllo dello spazio misura ogni volume usato una volta sola; la pulizia all'avvio guarda anche le `.nxlibrary-build/Temp`, e cancellare un gioco o le sue sorgenti tocca solo workspace riconosciuti da `BuildScratch.isManaged`.
4. Il coordinatore ricontrolla requisiti, spazio, chiavi e destinazione. `BuildCommandBuilder` produce eseguibile, argomenti, directory di lavoro e ambiente.
5. `BuildService` avvia il processo del motore, gestisce il gruppo di processi, raccoglie stdout e stderr, scrive il log e mantiene l’asserzione contro lo stop per inattività.
6. `BuildEventParser` decodifica il progresso JSON. `PortingProgress` lo aggrega per la UI, con gli shader fino al 90% e le fasi finali nel restante 10%. Il modello alimenta wizard, tile, percentuale e stima del tempo.
7. `BuildOutputInstaller` valida il bundle temporaneo e pubblica il gioco con `renamex_np`: `RENAME_SWAP` scambia atomicamente due app esistenti; `RENAME_EXCL` installa la prima copia senza sovrascrivere una destinazione comparsa nel frattempo. Sullo stesso volume usa direttamente il bundle pronto. Fra volumi diversi prepara prima una copia nascosta accanto alla destinazione, lasciando disponibile l’app corrente fino allo scambio.
8. Se il gioco è aperto o l’installazione è trattenuta da un’operazione sui salvataggi, `PendingInstall` conserva il risultato temporaneo. `AppViewModel+PendingInstall` lo riprende quando può acquisire l’accesso necessario.

`GameAppDestination` centralizza il percorso mostrato nella review, il volume controllato per lo spazio e la destinazione effettiva. Le prime build usano Game apps; un rebuild conserva l'app esistente quando il suo percorso è sicuro, anche dopo un cambio di cartella. I conflitti di nome con app di altri titoli ricevono un percorso distinto. La destinazione viene fissata prima del porting e rimane tale anche nelle installazioni differite. Le installazioni dei giochi richiedono che la cartella esista ancora: se si disconnette o diventa non scrivibile, il risultato pronto viene conservato per Retry. Il packaging del frontend continua a poter creare la propria cartella di installazione.

Se il motore termina correttamente con un bundle valido e fallisce solo l’installazione, `BuildResult.heldApp` conserva la build pronta e `installationFailed` distingue questo caso dal porting fallito. Il coordinatore registra la stessa `PendingInstall` già usata per i giochi aperti. Un dialogo Selene offre Retry e Close: Retry installa quel bundle senza riavviare il motore; Close conserva la build. Gli errori delle installazioni differite passano dallo stesso dialogo. La schermata del porting offre anche Retry installation finché la build resta in attesa. Un errore di scrittura del catalogo conserva lo stato in memoria e impedisce che una scansione immediata lo sostituisca con quello precedente.

Prima della pubblicazione, l’installer registra una piccola ricevuta accanto all’app con percorso di staging e identità filesystem dei bundle. Una ricevuta per destinazione resta dopo il successo e viene aggiornata al prossimo porting: se il processo termina prima del salvataggio del catalogo, il tentativo successivo riconosce l’app già pubblicata e completa il record, anche dopo la pulizia dello staging. Evita così un secondo scambio che rimetterebbe la vecchia app al suo posto. Una destinazione modificata esternamente durante lo stesso tentativo causa un errore conservativo. La vecchia app e l’eventuale sorgente copiata vengono eliminate solo dopo la pubblicazione.

`BuildRecord` conserva l’esito e la provenienza del build. `PortingFailureClassifier` riconosce i messaggi del motore e propone un’azione, presentata da `AppViewModel+Porting`. `PortingNotice` decide se notificare l’esito mentre l’app è in background. `NotificationService` gestisce la notifica di sistema e la destinazione del clic.

Gli adattamenti di b64a5ff0 riconoscono i nuovi errori di chiavi troppo vecchie, conservando la versione firmware quando conosciuta, e il ticket comune mancante nel pacchetto. Quest'ultimo usa il kind persistito `keys` con un dettaglio identificativo: anche un launcher precedente riesce a leggere la voce durante un rollback. La UI corrente offre la spiegazione sul ticket senza proporre di sostituire le chiavi o forzare il porting. L'evento `say` con cui l'engine sposta una vecchia cache shader nel nuovo file (`PortingProgress.shaderCacheWorkMessage`) accende `PortingProgress.isUpdatingShaderCache`; `PortingETA` mostra **Updating shader cache** senza avanzare la percentuale né stimare una durata. Lo stato si azzera a stage o step successivo e al termine del build. `PortingFailureEngineTests` verifica che l'engine del pin stampi ancora quel testo.

## Avvio dei giochi e sessioni

Il flusso Play controlla operazioni di salvataggio, recuperi e installazioni in attesa. `GameRuntimeConfig` traduce le impostazioni in variabili `DM_*`. `LauncherSettingsReader` legge il contratto `launcher.json` del gioco e determina i controlli supportati, con fallback per le app più vecchie.

`LaunchService` scrive `env.txt`, conserva le variabili non gestite tramite il merge del modello runtime e avvia il bundle con `NSWorkspace.OpenConfiguration`. Passa anche `DM_LAUNCHER=0`. `CloudSavesPreferences` applica la preferenza cloud al dominio del gioco prima del lancio.

Off rimuove la preferenza cloud salvata dal launcher del gioco anche all’avvio. Gli override avanzati `DM_SAVE_SYNC` nei file o nell’ambiente mantengono la precedenza del motore: `SaveLocation.inspect` ne segnala l’origine e mantiene il blocco delle operazioni incompatibili con la sincronizzazione attiva.

`RunningGameMonitor` confronta i bundle ID della libreria con le applicazioni in esecuzione e offre Resume e Close Game. `LaunchReadinessProbe` attende una finestra visibile del processo per chiudere la schermata di lancio. `PlaySessionStore` registra avvio, heartbeat, fine e riconciliazione delle sessioni. `ActivitySummary` aggrega la settimana, mentre `LibraryPresentation` e `GameDetailPresentation` preparano i valori delle schermate.

## Cheats

`CheatLocator` legge title ID, build ID e percorso secondo il contratto del launcher. `EngineAncestry` e `CheatStatus` determinano se l’app del gioco contiene il supporto ai cheats, dal commit del registro di build o, per un'app importata, da `DMCommit` nel suo `Info.plist`. `CheatFile` riproduce il parsing dei codici e dei metadati del motore. `CheatInstall` decide se un file appartiene alla build, richiede conferma o va rifiutato.

`CheatStore` legge e modifica file, metadati, master switch e selezione `.enabled`. `AppViewModel+Cheats` espone contesto, stato della riga e informazioni per la diagnostica. `CheatsPanel` presenta lista, importazione, conferme e switch. Il gioco chiuso è una condizione delle modifiche. I file installati vengono poi letti dal motore al lancio.

Le mod di file (RomFS) di un gioco stanno in `~/Library/Application Support/nxnative/<title ID>/mods/<cartella>/romfs`. `ModFolderScanner` trova le cartelle e il loro `romfs` (anche nel formato Atmosphère); un file lasciato lì (un archivio non estratto) compare come "non è una mod", e i file nascosti come `.DS_Store` non contano per i conflitti. `ModStore` tiene ordine e stato acceso/spento in `~/Library/Application Support/NXLibrary/mods/<TID>.json` e scrive nell'`env.txt` del gioco solo la riga `DM_ROMFS_OVERLAY` (con `EnvFileEditor`), che il motore legge al lancio: le mod accese, la prima vince, senza rebuild. Il valore non supera 4077 byte (il buffer di riga del launcher). Remove sposta la cartella nel Cestino; nessuna modifica mentre il gioco è aperto. All'apertura della pagina del gioco e del pannello, `sync()` toglie dalla riga le mod sparite; finché NX Library non ha mai gestito le mod di quel gioco non tocca una riga `DM_ROMFS_OVERLAY` scritta a mano. `AppViewModel+Mods` crea lo store e traduce gli errori; `ModsPanel` (Game options → Mods) e la fascia Mods della pagina del gioco (`DetailsModsBand`) presentano lo stato. Le mod che modificano il codice (exefs) non funzionano con il motore.

Le mod di GameBanana compaiono nella stessa fascia (`Services/GameBanana/`). `GameBananaClient` parla con l'API pubblica (apiv11 e, per il contenuto degli archivi, la vecchia Core API), con un solo User-Agent, al massimo 4 richieste insieme e una cache su disco in `~/Library/Caches/NXLibrary/gamebanana` (ricerche 1 giorno, pagine delle mod 6 ore, contenuto degli archivi per sempre, tranne un elenco vuoto, perché GameBanana può ancora leggere un file nuovo; senza rete usa anche le voci scadute). `GameBananaMatch` abbina il gioco per nome (preferisce la voce "(Switch)", chiede quando non è sicuro) e `GameBananaMatchStore` ricorda la scelta per title ID in `Application Support/NXLibrary/gamebanana/matches.json`. `AvailableModsFinder` scorre le mod più scaricate e tiene solo quelle che `ModSupport` riconosce: un'unica cartella `romfs` per questo title ID, niente exefs, IPS o pchtxt, niente mod obsolete, private o con content rating. `ModInstaller` scarica (`ModDownload`, solo host `*.gamebanana.com`), controlla dimensione e MD5, legge e controlla l'archivio con `/usr/bin/bsdtar`, lo estrae in una cartella nascosta dentro `mods`, rifiuta percorsi `..`, symlink e hard link prima di estrarre, e passa l'albero a `ModStore.adopt`; un aggiornamento manda la versione vecchia nel Cestino e tiene posto e stato. La fascia Mods compare sia nella pagina del gioco della Spotlight sia in Details, tra Build & Sources e More like this (focus `.mods` in `SpotlightState`, `DetailsFocus.modsZone`); è una griglia di sei tessere per riga che non scorre di lato (`ModsBandLayout`: Sinistra/Destra restano nella riga, Giù scende di riga e dall'ultima passa a More like this): `ModsBandHost` tiene per entrambe mod installate, GameBanana e pannelli, e chiede a GameBanana solo quando la pagina è aperta, non mentre si scorre la riga. `GameBananaBandModel` coordina abbinamento, ricerca e installazioni per la pagina del gioco: cambiando gioco dimentica le mod del precedente, e alla prima apertura di un gioco in ogni avvio toglie gli avanzi di un'installazione interrotta (`ModStore.removeLeftoverInstalls`); `GameBananaFindModel` tiene lo stato della ricerca per nome. Le mod trovate entrano nella fascia in due gruppi al massimo: le prime cinque, accanto ad Add mods, appena ci sono, poi tutte le altre a ricerca finita; ogni gruppo aspetta (al massimo 1,2 s, `imageWait`) che la sua arte sia decodificata (`prepareImages`, cioè `GameBananaImageView.prepare`, in parallelo) ed entra con un'unica dissolvenza, e una tessera di stato spinta più in là sfuma nel nuovo posto invece di attraversare la griglia. I link presi dall'API valgono solo se sono `https` su un host GameBanana; `ModDetailPanel` e `GameBananaFindPanel` sono i pannelli sopra la pagina. Nel pannello della mod la descrizione mostra otto righe con Read more subito sotto; Read more la apre tutta (`TextScroll.windowHeight`) e i file, sotto il titolo Files, scendono. La colonna (intestazione, descrizione, file) scorre dentro il pannello quando è più alta (al massimo 980u): con rotella o trackpad, e con Su/Giù, che prima leggono a passi quello che c'è prima della riga seguente e poi spostano il fuoco e mostrano la riga intera (`TextScroll.step`); i bordi sfumano dove c'è altro e una barra sottile dice dove si è. Lo scorrimento sta in `ModsBandHost.detailScroll`, un oggetto a parte, così muoverlo ridisegna solo il pannello e non la pagina sotto. Un'installazione è per un file (`GameBananaBandModel.installFiles`): solo la sua riga ne mostra avanzamento ed esito, le altre aspettano che finisca. Ogni mod mostra autore e link alla sua pagina, e la fascia dice "Mod data provided by GameBanana".

Lo store è la card **Mods** della Spotlight (`SpotlightCard.mods`; la sua visibilità sta in `showsModsCard`, mai in `spotlightCards`, così la versione rilasciata legge ancora le impostazioni). Giù dalla card porta il focus a `.store` e `ModStoreHost` muove `ModStoreFocus` dentro la pagina (`ModStorePage`): barra di ordinamento, Featured (dissolvenza tra le prime cinque), mod popolari dei tuoi giochi, una riga per categoria (`ModCategory`, raggruppate dai nomi delle categorie GameBanana) e una per gioco, dal più giocato di recente. `ModStoreLayout` costruisce le sezioni e dà a ognuna un'altezza fissa, così lo scorrimento non misura nulla e si disegnano solo le sezioni vicine al focus. `ModStoreModel` apre dalle copie su disco (`ModCatalogSnapshots`, `~/Library/Caches/NXLibrary/gamebanana/store`) e aggiorna in background quelle più vecchie di 6 ore, due giochi alla volta, pubblicando un gioco intero per volta; un gioco senza abbinamento si abbina solo se il nome è certo. L'ordinamento è locale sulle mod già trovate. Le immagini decodificate restano in memoria (`GameBananaImageView`, che le prepara in anticipo con `prewarm` per le prime tessere di ogni riga). La copertina della card Mods (`ModStoreLayout.coverArt`) sono le prime quattro mod del Featured per popolarità, qualunque sia l'ordinamento, coi giochi in ordine di title ID: all'avvio la si legge dalle copie su disco dei tuoi giochi ed è la stessa che trova lo store aperto. Cambia solo se lo store trova mod nuove, e solo dopo che tutte e quattro le immagini sono decodificate (`GameBananaImageView.prepare`), in un'unica dissolvenza. Lo sfondo del Featured è sfocato una volta sola, fuori dal main thread, su una copia di 240 px (`GameBananaBlur`): nessuna sfocatura gira a ogni frame. Mentre la pagina scorre, `ModStoreHost.hold(until:)` trattiene le mod trovate in background e ricostruisce le sezioni solo a pagina ferma (il log `store rebuild … ms` misura ogni ricostruzione). Sulla riga, la faccia della card è un mosaico sfocato dell'arte delle mod migliori col puzzle al centro (`ModsCardCover`, dalle copie su disco prima che lo store abbia cercato; senza arte, il gradiente Selene). Con la card selezionata lo sfondo non mostra arte: il moonlight sfuma in 1,2 s verso l'oro (`SeleneBackdrop.modsTint`), anche sopra una wallpaper, che resta ferma sotto. Colore e fondo oro sono uniform dello shader (il fondo lo disegna il passaggio di luce che gira comunque), che `MoonlightLayerView` interpola sul suo thread: la sfumatura non dipende dal main thread e il frame costa uguale; da fermo il display link gira solo per la durata della sfumatura. Lasciando la card verso un gioco, l'oro resta finché l'arte del gioco non è arrivata (`SpotlightView.modsBackdrop`), così il passaggio è uno solo. L'arte dei giochi (`SeleneArtLayer`) è una pila di `CALayer` animati nel render server: ogni nuova immagine entra sopra ciò che si vede, che resta fermo sotto finché non è entrata, così una dissolvenza interrotta riparte da ciò che è a schermo (niente salti, niente moonlight che traspare) e non scatta se il main thread è occupato. Ciò che un layer mostra durante una dissolvenza si calcola sull’orologio (`OpacityFade`, la stessa curva dell’animazione), non dal presentation layer, che per un layer aggiunto nello stesso passaggio non esiste ancora: due immagini in fila non fanno saltare la prima a piena opacità. Scorrendo veloce, i livelli che lasciano passare meno di mezzo gradino a 8 bit (`ArtStack`) escono subito, così la pila resta di pochi livelli invece di un’immagine a tutto schermo per ogni gioco passato. Se tenere l’arte del gioco precedente lo decide `BackdropArtRule` sulla selezione che il body vede, così il primo render di una nuova selezione, prima di `onChange`, non toglie l’arte per poi rimetterla. Sopra una wallpaper il moonlight oro resta montato, nascosto e fermo finché non serve, ed entra ed esce con l'uniform `presence` sul suo thread. Su una card Spotlight tiene l'arte dell'ultimo gioco (`loadHero(keepsWithoutGame:)`) senza mostrarla, così tornare allo stesso gioco non ricarica nulla. Il pannello della mod è lo stesso della fascia; `GameBananaBandModel.attach(store:)` installa nella cartella del gioco della mod.

## Salvataggi, backup e recupero

### Riconoscimento e anteprima

Il flusso usa il title ID e conserva i percorsi interni del salvataggio per ogni gioco. `SaveLocation` ammette l’ID esadecimale di 16 caratteri, risolve il percorso predefinito e legge la configurazione cloud effettiva. `AppViewModel+Saves` verifica anche l’identità nel bundle installato e le preferenze del gioco.

`RyujinxSaveFolder` riconosce `bis/user/save/<indice>`, risale dalle sottocartelle, confronta il title ID in `ExtraData0` e seleziona l’intero albero committed `0`. Le cartelle di esportazione ordinarie mantengono la propria struttura. Il tipo User/Device è una scelta separata dal nome della cartella sorgente.

`SaveSnapshotStore.stageImport` prepara una copia temporanea vicino alla destinazione. L’anteprima contiene inventario, hash SHA-256, attributi estesi e impronta del salvataggio attuale. `SaveRestorePreview.swift` prepara allo stesso modo un ripristino da backup. Alla conferma vengono ricontrollati sorgente, staging e salvataggio attuale.

### Copia protettiva e sostituzione

`SaveTransaction` crea prima un backup verificato dei due slot committed, inclusa l’eventuale assenza di uno slot. Persiste poi il journal `.nxlibrary-save-transaction.json` e sostituisce ciascuna directory con staging sullo stesso volume. Usa `renamex_np(RENAME_SWAP)` per scambiare due directory esistenti e spostamenti per i casi di presenza o assenza.

L’importazione sostituisce lo slot scelto. Il ripristino applica l’intero snapshot, compresa la presenza o assenza dei due slot. `SaveOperationGate` assegna lease per title ID, coordinando salvataggi, Play e installazioni anche quando più voci della libreria condividono lo stesso gioco.

### Integrità e recupero

`SaveFileIO` centralizza copie, hash, metadati, controlli dei percorsi, scritture durevoli e punti di errore sostituibili nei test. La verifica normalizza provenienza e label di accesso gestite da macOS, più il campo agente della quarantena. Confronta i metadati guest e il contenuto dei file. I manifest e i journal precedenti passano dalla stessa normalizzazione.

All’avvio o al refresh, un journal incompleto porta al rollback del salvataggio precedente verificato. Un journal committed richiede la verifica del risultato prima della pulizia. Dati modificati esternamente o copie non verificabili mantengono il recupero bloccato e conservano gli artefatti per l’intervento. Play attende la risoluzione.

`SavesPanel` espone apertura cartella, backup manuale, destinazione, importazione, refresh e cartella backup con data dell’ultima copia. L’anteprima From → To è in `SaveImportDetails`. Dopo ogni importazione riuscita, `SavePanelModel` pubblica un nuovo evento e la vista mostra `SeleneSuccessNotice`, che si chiude dopo tre secondi. Il timer della vista si annulla quando il pannello scompare.

Storage → Save backups apre la cartella comune degli snapshot. Il vecchio export ZIP di Storage è stato rimosso; la creazione delle copie passa dal pannello Saves.

I backup sono copie locali conservate fino alla gestione dell’utente. Sono automatici prima di importazione e ripristino, oppure manuali con Back up now. Importazione e ripristino richiedono sincronizzazione cloud effettivamente disattivata. I casi rifiutati e le verifiche eseguite sono descritti nelle sezioni Saves del README e dei test.

## Artwork, metadati e sfondi

Look distingue Wallpaper e Library screens. Game backgrounds è un controllo positivo: On mostra l’artwork del titolo in Spotlight e Collection, Off mantiene il wallpaper. Riusa la preferenza `keepWallpaperOnGames` invertendo soltanto il binding, senza migrazione dei dati. Details continua a usare l’artwork del gioco; il layout di avvio segue le proprie impostazioni globali. Wallpaper sizing riguarda il wallpaper e Library shade le maschere delle schermate della libreria.

Change artwork conserva la precedenza delle scelte manuali per titolo. La riga di stato ha altezza stabile, testo breve per la ricerca e indicazione della destinazione dell’immagine; segnala Home: wallpaper quando lo sfondo della home è governato dal wallpaper globale.

LaunchBox e SteamGridDB non entrano nella griglia automatica: ciascuno ha un riquadro **Browse online** che apre una griglia propria (`ArtworkBrowseSource`), con ricerca precompilata e modificabile, risultati per lo slot aperto, credito per immagine e X per la pagina del gioco sulla sorgente. La griglia carica solo le anteprime; il file pieno (`ArtworkCandidate.full`) si scarica alla scelta e viene ridimensionato come ogni scelta manuale. LaunchBox non ha API: ricerca e pagina gioco si leggono come TheGamesDB, e immagini e dimensioni vengono dal payload `__NUXT_DATA__`. SteamGridDB usa l’API v2 con la chiave personale dell’utente (file `0600`, mai registrata nei log). Per i giochi senza screenshot Title DB, il caricamento dei metadati (selezione o apertura del gioco) chiede una volta a LaunchBox gli screenshot Gameplay e li conserva 30 giorni (`ScreenshotFallbackStore`); le scansioni della libreria non avviano richieste.

`NintendoStoreMetadataService`, `GameTDBStore`, Title DB e le sorgenti di artwork raccolgono descrizioni, date, generi, copertine, loghi, sfondi e screenshot. `ArtworkNames` confronta i nomi per limitare i candidati al gioco o alle sue edizioni. `ArtworkPicker` e `MetadataOptions` aggregano i risultati per i selettori. `ArtworkPicks` e `MetadataPicks` conservano le scelte manuali.

L'icona scelta in Change artwork (slot Icon, conservata a 1024 px) diventa anche l'icona dell'app del gioco in Finder e nel Dock (`AppIconWriter`, `AppViewModel+AppIcon`). Un'app senza icona propria (NUP Switch 2, dump) la riceve subito; un'app con l'icona del gioco la riceve solo se il giocatore lo sceglie nel pop-up dopo la scelta; Automatic rimette l'icona del gioco. La scrittura crea `Resources/AppIcon.icns`, marca `Info.plist` con `NXLibraryAppIcon`, rifirma il bundle ad hoc come l'engine e verifica con `codesign --verify --deep --strict`; l'icona originale resta in `Application Support/NXLibrary/app-icons/<TitleID>/`, e ogni errore rimette i file toccati. Avviene dopo ogni build installata (la rebuild sostituisce l'app, e l'engine ricrea il pacchetto se trova file cambiati), all'avvio e quando un gioco si chiude, mai mentre il gioco gira o si costruisce; durante la firma (circa 50 secondi per un gioco di 9–12 GB) avvio e build del gioco attendono, e la riga di stato di Change artwork mostra l'avanzamento. Una scelta fatta mentre la stessa app si firma viene rieseguita alla fine, così vale l'ultima. Dopo ogni scansione della libreria `reconcileAppIcons` confronta lo stato voluto con l'app (marca `NXLibraryAppIcon`) e rimette in coda le differenze, per esempio una scelta fatta mentre l'app era stata spostata.

`ArtworkStore` mantiene la cache immagini. `BoxArtService` risolve le copertine Switch di GameTDB. `GameArtLoader` e `SeleneHeroArt` alimentano sfondo e logo delle schermate con caricamento e cache dedicati.

Per gli sfondi online, i parser dei provider sono in `OnlineBackgrounds.swift`. `OnlineBackgroundService` gestisce rete, progressi, miniature e crediti. `OnlineBrowser` e `OnlineTransfer`, definiti in `OnlineBrowsePanel.swift`, alimentano la griglia e l’importazione nel selettore temi. `ThemeStore` unisce palette, wallpaper inclusi e file importati.

## Interfaccia Selene e input

`SeleneCanvas` scala il canvas 1920×1080 nello spazio disponibile. `SeleneCanvasEnvironment` espone unità e font alle viste. `SeleneTheme` ricava colori e curve di animazione dalla palette. `MaterialIcon` elenca i glifi, mentre `SeleneFonts` registra il font e li rende in SwiftUI.

I componenti condivisi in `Views/Components` disegnano righe, switch, pill, focus, suggerimenti dei tasti, dialoghi e conferme. L'anello e il riflesso della tile selezionata (`SeleneTileRing`, `SeleneShine`) girano in Core Animation (`TileMotionLayers`): curve e campioni stanno in `TileMotion`, il bagliore è disegnato una volta da SwiftUI (`ImageRenderer`) e poi solo dissolto, così a schermo fermo l'app non ridisegna nulla tra un frame e l'altro. Con Reduce motion l'anello resta il disegno SwiftUI fermo. `SeleneBackdrop` combina gradiente, wallpaper e sfondo animato. `MoonlightRenderer` e `MoonlightShaders` rendono la componente Metal dell’interfaccia. `LiveBackdrop` usa AVFoundation per i video in loop.

`GameControllerService` produce `GamepadAction` e riconosce i simboli dei tasti. La shell assegna l’input al livello attivo. `ButtonPrompts` esclude i segnaposto costituiti soltanto da forme, comprese varianti come `capsule.portrait.fill`, e usa in quel caso i simboli della marca riconosciuta; conserva glifi significativi come `circle.circle` e `square.circle`. `HoldDetector` e i modelli di focus rendono verificabili mapping e navigazione. `SoundEffectService` risolve i cue tramite `SeleneImporter` e applica le impostazioni di volume e attivazione.

La preferenza Riduci movimento unisce l’impostazione dell’app a quella di sistema. Le viste consumano `seleneReduceMotion`, insieme agli altri valori dell’ambiente Selene.

## Dati su disco

I percorsi sono relativi alla home dell’utente. `Application Support/NXLibrary` corrisponde a `~/Library/Application Support/NXLibrary`.

| Percorso | Contenuto e proprietario |
|---|---|
| `Application Support/NXLibrary/library.json` e `.bak` | Catalogo e ultima copia valida, gestiti da `LibraryStore`. |
| `Application Support/NXLibrary/settings.json` | Impostazioni globali, gestite da `AppSettingsStore`. |
| `Application Support/NXLibrary/play-sessions.json` | Sessioni e tempi di gioco, gestiti da `PlaySessionStore`. |
| `Application Support/NXLibrary/keys/prod.keys` | Chiavi importate da `KeyStore`, con permessi `0600`. |
| `Application Support/NXLibrary/app-sizes.json` | Cache dimensioni dei bundle. |
| `Application Support/NXLibrary/workspaces/` e `Temp/` | Collegamenti alle sorgenti, workspace e app temporanee dei porting, quando l'app va sul volume del Mac (o su un volume che non accetta link simbolici). |
| `Application Support/NXLibrary/artwork/` | Cache immagini, copertine, screenshot e miniature online. |
| `Application Support/NXLibrary/metadata/` | Cache dei metadati dello store. |
| `Application Support/NXLibrary/artwork-picks/` e `metadata-picks.json` | Scelte manuali di immagini e campi. |
| `Application Support/NXLibrary/SeleneImports/` | Suoni, wallpaper, video e relativi crediti importati. |
| `Application Support/NXLibrary/SaveBackups/<TID>/` | Snapshot datati, manifest e copie protettive. |
| `Application Support/NXLibrary/Logs/<TID>.log` | Log di porting costruito dall’app. |
| `~/Library/Application Support/nxnative/<TID>/` | `env.txt`, `save`, eventuale `save_device`, cheats e dati runtime del motore. |
| `Application Support/NXLibrary/mods/<TID>.json` | Ordine, stato e origine GameBanana delle mod di un gioco, gestiti da `ModStore`. |
| `Application Support/NXLibrary/gamebanana/matches.json` | Pagina GameBanana scelta per ogni gioco, gestita da `GameBananaMatchStore`. |
| `~/Library/Caches/NXLibrary/gamebanana/` | Cache delle risposte e delle immagini di GameBanana. |
| `~/Library/Logs/nxnative/<TID>.log` | Log del gioco avviato. |
| `<Game apps>/<nome>.app` | Prima installazione del gioco; default `~/Applications`. I rebuild aggiornano l'app nella sua posizione esistente. |
| Accanto al gioco: `.nxlibrary-install-<hash>.json` | Ultima ricevuta di installazione per quel percorso, gestita da `BuildOutputInstaller`. |
| Accanto al gioco: `.nxlibrary-incoming-<hash>.app` | Preparazione temporanea quando il bundle pronto si trova su un altro volume. |
| `<Game apps>/.nxlibrary-build/workspaces/<TID>/` e `Temp/` | Workspace e app temporanee dei porting quando la cartella delle app è su un altro volume (`BuildScratch`). |
| `UserDefaults` del bundle NX Library | Percorsi ricordati, stato Setup, override toolchain e cache di alcuni controlli. |

Nel repository, `.build/` contiene gli output SwiftPM. `work/Runtime` è il runtime preparato per il packaging, `work/release` contiene i prodotti di release e `dist/` il DMG di sviluppo. Queste cartelle sono escluse da Git. Il catalogo descrive i file versionati separatamente dai dati personali creati durante l’uso.

## Aggiornamenti e distribuzione

Il controllo manuale da menu macOS e About presenta `AppUpdateDialog` sia durante la richiesta sia al suo esito: versione corrente, nuova release con note scorrevoli, errore con Retry o progresso. Il dialogo ha priorità sull’input sottostante; frecce/controller scorrono le note e selezionano le azioni, Escape chiude. La chiusura durante il download lascia il trasferimento in corso. Una richiesta manuale durante un controllo automatico impedisce una successiva seconda offerta automatica per la stessa risposta. Le note mostrano la propria versione anche quando la candidata è più recente dell’ultima release pubblica.

`AppUpdateState` descrive gli stati nel Core. `AppUpdate.mayInstall` impone versione più recente e copia installabile: i controlli manuali di copie di sviluppo o in sola lettura leggono le release, senza autorizzarne la sostituzione. Il gate viene verificato prima del download e prima dell’installazione, insieme ai controlli e ai lease già esistenti. Il motivo di attesa viene passato al dialogo come valore, così la chiusura di un gioco aggiorna il pulsante Update.


`UpstreamChecker` consulta il changelog del motore e `UpstreamCopy` lo presenta. L’adozione di un nuovo commit passa dalla procedura manuale in [AGENTS.md](../AGENTS.md) e dalle [note di upgrade](upstream-upgrades/README.md).

`AppUpdater` coordina gli aggiornamenti di NX Library da `Bium23/NxLibrary`, senza autenticazione. Le regole di versione, requisiti, digest, identità del bundle e installazione sono in `AppUpdate`. Le copie di sviluppo non si sostituiscono. `AppUpdateDownload` limita il trasferimento alla dimensione dichiarata e agli host HTTPS di GitHub. `validate_update.py` verifica struttura e percorsi, poi estrae contando i dati effettivamente decompressi tramite il Python incluso; prima della sostituzione vengono controllati versione, marker, identificativo e firma del bundle. La firma ad hoc protegge il contenuto sigillato ma non identifica autonomamente il manutentore. La prova interattiva A → B resta necessaria.

Prima dell’installazione, l’updater acquisisce un’esclusione globale dal `SaveOperationGate`: aspetta operazioni save/Play/installazioni attive e impedisce nuovi ingressi durante sostituzione e riavvio. Un recupero bloccato senza I/O attivo non impedisce l’aggiornamento. Il coordinatore esclude nuovi porting mentre l’app viene aggiornata.

`bundle_runtime.sh` prepara Python e strumenti da `runtime.lock`, controlla gli hash e sistema i riferimenti Mach-O con `relink_macho.py`. `build_app.sh` compila e confeziona il bundle, risorse, plist e firma ad hoc. Il suo parametro di destinazione permette di preparare una copia temporanea prima della sostituzione della copia installata.

`release.sh` richiede albero pulito e runtime pronto, imposta versione e marker di release e crea ZIP e DMG. `--publish` abilita tag e pubblicazione GitHub con autorizzazione esplicita dell’utente. Il repository contiene anche `build_dmg.sh` per confezionare un bundle già costruito.

## Verifica e manutenzione

`NX_TEST_ENGINE_REPO` permette al controllo dei messaggi del motore di usare un checkout separato; il valore esplicito non valido produce un errore. Durante una revisione, `NX_TEST_ENGINE_COMMIT` seleziona l'hash completo del candidato prima di cambiare il pin dell'app; senza override il test controlla sempre il pin. La suite Core usa fixture sintetiche, directory temporanee, runner e confini I/O sostituibili. Copre modelli, persistenza, sorgenti, chiavi, contratti CLI, processi, installazione, lancio, UI state, artwork, cheats e transazioni dei salvataggi. Il [catalogo dei test](file-map.md#test-e-fixture) indica la responsabilità di ogni file.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
bash scripts/build_app.sh
codesign --verify --deep --strict "$HOME/Applications/NXLibrary.app"
```

Le prove interattive dell’app e dei giochi sono eseguite dall’utente. Gli agenti svolgono controlli sul codice, test automatici e build/installazione, secondo `AGENTS.md`.

Per una modifica, partire dall’area nel catalogo, seguire il collegamento al file e leggere i chiamanti reali. Aggiornare la descrizione quando cambia la responsabilità di un file. I piani datati registrano il lavoro svolto, mentre questa guida e il catalogo descrivono l’organizzazione corrente.
