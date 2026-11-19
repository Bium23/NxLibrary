# Arcane — catalogo dei file

Aggiornato il 19 novembre 2026. Copertura di **719 file** del progetto, compresi i controlli di pubblicazione, la CI con regressioni app senza UI, il master dell’icona, le guide per sviluppo e media, gli screenshot del README, l'integrazione di nxnative, il canale di aggiornamento e il primo avvio che parte da ciò che è già sul Mac, il setup del porting con cartella unica per scoperta e installazione dei giochi. Le cartelle personali, gli output generati e gli appunti non versionati sono esclusi.

La [guida tecnica](../how-it-works/architecture.md) spiega come collaborano i componenti. Qui ogni riga identifica un file e la sua responsabilità. Le sezioni Core seguono le funzionalità, quelle UI seguono schermate e componenti. Le viste usano i modelli e i servizi del Core attraverso il coordinamento applicativo.

Le cartelle generate `.build/`, `work/` e `dist/` e i dati personali in Application Support sono descritti nella guida.

## Indice

- [Progetto e configurazione](#progetto-e-configurazione)
- [Ingresso e shell dell’app](#ingresso-e-shell-dellapp)
- [Coordinamento applicativo](#coordinamento-applicativo)
- [Modelli dello stato applicativo](#modelli-dello-stato-applicativo)
- [Integrazione con macOS e servizi applicativi](#integrazione-con-macos-e-servizi-applicativi)
- [Core · libreria, stato e sessioni](#core--libreria-stato-e-sessioni)
- [Core · Setup, motore e chiavi](#core--setup-motore-e-chiavi)
- [Core · sorgenti, porting, installazione e lancio](#core--sorgenti-porting-installazione-e-lancio)
- [Core · cheat e mod](#core--cheat-e-mod)
- [Core · salvataggi e cloud](#core--salvataggi-e-cloud)
- [Core · artwork, metadati e sfondi online](#core--artwork-metadati-e-sfondi-online)
- [Core · presentazione Selene, focus e impostazioni](#core--presentazione-selene-focus-e-impostazioni)
- [Core · catalogo comune e fonti](#core--catalogo-comune-e-fonti)
- [Core · Steam](#core--steam)
- [Core · achievement](#core--achievement)
- [Core · lingua e testi](#core--lingua-e-testi)
- [Core · profilo dei dati](#core--profilo-dei-dati)
- [UI · Add Game e porting](#ui--add-game-e-porting)
- [UI · Spotlight](#ui--spotlight)
- [UI · Collection e Details](#ui--collection-e-details)
- [UI · Game Options, cheats e salvataggi](#ui--game-options-cheats-e-salvataggi)
- [UI · Settings](#ui--settings)
- [UI · Setup, avvio, ricerca e console](#ui--setup-avvio-ricerca-e-console)
- [UI · componenti condivisi](#ui--componenti-condivisi)
- [UI · temi, rendering e sfondi](#ui--temi-rendering-e-sfondi)
- [UI · fonti, Steam e libreria mista](#ui--fonti-steam-e-libreria-mista)
- [UI · achievement](#ui--achievement)
- [Test e fixture](#test-e-fixture)
- [Script di sviluppo e packaging](#script-di-sviluppo-e-packaging)
- [Risorse incluse](#risorse-incluse)
- [Screenshot e demo](#screenshot-e-demo)
- [Documentazione tecnica e registri datati](#documentazione-tecnica-e-registri-datati)

## Progetto e configurazione

La pubblicazione comprende anche [CONTRIBUTING.md](../../CONTRIBUTING.md), [SECURITY.md](../../SECURITY.md), [la CI](../../.github/workflows/ci.yml) e [il modello di segnalazione](../../.github/ISSUE_TEMPLATE/bug_report.yml). Descrivono come segnalare problemi e suggerimenti, le verifiche del maintainer, il canale per le vulnerabilità e i controlli automatici.

| File | Responsabilità |
|---|---|
| [.github/FUNDING.yml](../../.github/FUNDING.yml) | Collega il pulsante Sponsor del repository alla pagina Buy Me a Coffee di Arcane. |
| [.gitignore](../../.gitignore) | Esclude output di build, bundle, cache, work e file personali dell’IDE dal versionamento. |
| [AGENTS.md](../../AGENTS.md) | Definisce vincoli per gli agenti, procedura di upgrade del motore e verifiche assegnate all’utente. |
| [CHANGELOG.md](../../CHANGELOG.md) | Registra le modifiche visibili all'utente per versione. |
| [LICENSE](../../LICENSE) | Contiene la licenza MIT di Arcane. |
| [NOTICE](../../NOTICE) | Conserva attribuzioni del motore al pin corrente, dei componenti, dei loghi e delle altre risorse riutilizzate. |
| [Package.swift](../../Package.swift) | Dichiara i target SwiftPM, le loro dipendenze e il deployment macOS minimo. |
| [README.md](../../README.md) | Presenta Arcane come libreria e launcher Mac, con guide, requisiti, sostegno volontario, crediti e note legali. |
| [runtime.lock](../../runtime.lock) | Fissa versioni, download e hash del runtime Python e degli strumenti inclusi nel bundle. |
| [VERSION](../../VERSION) | Versione in sviluppo usata dal packaging e verificata dalla procedura di release. |

## Ingresso e shell dell’app

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/NXLibraryApp.swift](../../Sources/NXLibrary/NXLibraryApp.swift) | Punto @main, finestra SwiftUI, notifiche interne e comandi della barra menu. |
| [Sources/NXLibrary/AppDelegate.swift](../../Sources/NXLibrary/AppDelegate.swift) | Registra Material Icons, gestisce il ciclo della finestra, completa la scrittura della selezione alla chiusura e dà a una copia release il nome `Arcane.app`. |
| [Sources/NXLibrary/Views/MainView.swift](../../Sources/NXLibrary/Views/MainView.swift) | Presenta AppShellView come contenuto della finestra principale. |
| [Sources/NXLibrary/Views/Shell/AppShellView.swift](../../Sources/NXLibrary/Views/Shell/AppShellView.swift) | Possiede il backdrop persistente e aggiorna le richieste delle pagine e la palette nello snapshot reattivo, possiede lo stato condiviso, passa a Spotlight il modello Mods della shell, compone schermate e overlay (compreso il benvenuto in Arcane) e assegna priorità all’input; `nativeDialogOwnsInput` sospende controller, tastiera e comandi dei menu sotto alert e selettori nativi; all’avvio chiede di spostare in Applicazioni una copia temporanea. |
| [Sources/NXLibrary/Views/Shell/FullscreenCursorView.swift](../../Sources/NXLibrary/Views/Shell/FullscreenCursorView.swift) | Gestisce il cursore inattivo nella sola finestra fullscreen del launcher, sospendendolo per pannelli e menu e ripristinando gli eventi al distacco. |
| [Sources/NXLibrary/Views/Shell/StartupWindowView.swift](../../Sources/NXLibrary/Views/Shell/StartupWindowView.swift) | Applica il fullscreen dopo la comparsa della finestra e segnala fine transizione o scadenza alla fase dell’entrata. |
| [Sources/NXLibrary/Views/Shell/MenuOverlayView.swift](../../Sources/NXLibrary/Views/Shell/MenuOverlayView.swift) | Disegna il control center con azioni, focus e sottomenu Power. |
| [Sources/NXLibraryCore/NXLibraryCore.swift](../../Sources/NXLibraryCore/NXLibraryCore.swift) | Espone la versione nominale del modulo Core. |
| [LaunchReveal.swift](../../Sources/NXLibrary/Views/Launch/LaunchReveal.swift) | Rende visibile la finestra al primo frame del moonlight, con dissolvenza e scadenza, poi consente il fullscreen; integra il bootstrap con un NSView non interattivo. |
| [DevelopmentStartupView.swift](../../Sources/NXLibrary/Views/Launch/DevelopmentStartupView.swift) | Avvio asincrono senza schermata di preparazione, recupero degli errori e scelta esplicita sul conflitto legacy prima di costruire la shell. |
| [AppShellState.swift](../../Sources/NXLibrary/Views/Shell/AppShellState.swift) | Prepara coordinatore, router, fonti, lingua e tema. Condivide lo store con il delegato alla chiusura e conserva la cover Mods durante la navigazione. |

## Coordinamento applicativo

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/ViewModels/AppViewModel.swift](../../Sources/NXLibrary/ViewModels/AppViewModel.swift) | Coordina libreria e catalogo, sorgenti, lancio (con la sincronizzazione delle mod prima di Play), primo avvio, Game options, spazio su disco e icona di Arcane nel Dock. Crea i modelli Switch, conserva la scelta Steam del Setup, tiene lo stato del porting letto dalla home e non scansiona Game files all’avvio. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Mods.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Mods.swift) | Crea lo `ModStore` di un gioco, il valore della riga Mods e le frasi per ogni errore. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Controller.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Controller.swift) | Conserva il contesto di gioco per i comandi e offre il collegamento alla cartella dei save. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Diagnostics.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Diagnostics.swift) | Raccoglie ambiente, toolchain e ultimo build per il rapporto diagnostico ripulito. |
| [Sources/NXLibrary/ViewModels/AppViewModel+PendingInstall.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+PendingInstall.swift) | Riprende le installazioni differite e gestisce errore e nuovo tentativo sul bundle pronto, rispettando i lease. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Porting.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Porting.swift) | Prepara tile, pill e stima del tempo del porting per la home. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Saves.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Saves.swift) | Risolve contesto e identità dei save, coordina i lease e avvia i recuperi pendenti. |
| [Sources/NXLibrary/ViewModels/AppViewModel+SteamGridDB.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+SteamGridDB.swift) | Verifica, salva e rimuove la chiave SteamGridDB dell’utente senza registrarne il valore. |
| [Sources/NXLibrary/ViewModels/AppIconModel.swift](../../Sources/NXLibrary/ViewModels/AppIconModel.swift) | Applica o ripristina l’icona dell’app del gioco dopo build, avvio e chiusura del gioco, senza toccare giochi in esecuzione o in build; Change artwork ne osserva l’avanzamento e raggiunge il coordinatore solo da `app`. |
| [Sources/NXLibrary/ViewModels/CheatsModel.swift](../../Sources/NXLibrary/ViewModels/CheatsModel.swift) | Adatta Core e bundle installato al pannello Cheats, alla riga di stato, alla pagina del gioco e alla diagnostica; raggiunge il coordinatore solo da `app`. |
| [Sources/NXLibrary/ViewModels/PortingModel.swift](../../Sources/NXLibrary/ViewModels/PortingModel.swift) | Tiene Add Game: bozza, scansione e selezione delle sorgenti, scelte per il primo avvio, controllo delle chiavi, spazio su disco, cartelle della build e dell'app, passo del wizard e stato della build mostrato. Avvia la build, ne segue eventi e fine, ricorda ultimo comando e durata delle fasi finali, pulisce i temporanei vecchi all'avvio, chiede il permesso delle notifiche quando un porting parte e presenta le azioni sugli errori riconosciuti; raggiunge il coordinatore solo da `app`. |
| [Sources/NXLibrary/ViewModels/RuntimeSettingsModel.swift](../../Sources/NXLibrary/ViewModels/RuntimeSettingsModel.swift) | Legge e scrive le scelte salvate di un gioco per il prossimo avvio (Game options, More settings, default dei nuovi giochi) e dice quali impostazioni il build supporta. |
| [Sources/NXLibrary/ViewModels/SavePanelModel.swift](../../Sources/NXLibrary/ViewModels/SavePanelModel.swift) | Gestisce refresh, anteprime, backup, importazione, ripristino, errori e conferma temporanea di successo. |
| [Sources/NXLibrary/ViewModels/SetupCheckModel.swift](../../Sources/NXLibrary/ViewModels/SetupCheckModel.swift) | Esegue probe e installazioni del Setup in background, con avanzamento e ricontrollo periodico. |
| [Sources/NXLibrary/ViewModels/SetupModel.swift](../../Sources/NXLibrary/ViewModels/SetupModel.swift) | Tiene il Setup Switch: cartella, validità e commit dell'engine, sorgenti che l'engine sa leggere, controllo Upstream e scelta della cartella; chiavi importate (percorso, validità, riepilogo, importazione e selettore); controllo dell'ambiente, compatibilità, override della toolchain non testata, gate e suo riepilogo, Python e Xcode dell'engine, versioni Metal. Ricarica override, scelta di Newest engine e ultimo controllo Upstream. Raggiunge il coordinatore solo da `app`. |
| [Sources/NXLibrary/ViewModels/SetupModel+NewestEngine.swift](../../Sources/NXLibrary/ViewModels/SetupModel+NewestEngine.swift) | Usa l’engine più nuovo o torna a quello testato, accende l’override e controlla se main è utilizzabile. |
| [Sources/NXLibrary/ViewModels/StoreMetadataModel.swift](../../Sources/NXLibrary/ViewModels/StoreMetadataModel.swift) | Tiene i dati dello store Nintendo per gioco nella lingua dell'app: caricamento, coda delle lingue in background, screenshot di ripiego, scelte di Change metadata e cache; le schermate che li mostrano lo osservano. |

## Modelli dello stato applicativo

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Models/AppIconAppearanceMode.swift](../../Sources/NXLibrary/Models/AppIconAppearanceMode.swift) | Enumera le varianti dell’icona dell’app selezionabili dall’utente. |
| [Sources/NXLibrary/Models/BuildStageItem.swift](../../Sources/NXLibrary/Models/BuildStageItem.swift) | Rappresenta una fase del porting nella lista di avanzamento. |
| [Sources/NXLibrary/Models/BuildState.swift](../../Sources/NXLibrary/Models/BuildState.swift) | Enumera gli esiti e lo stato operativo del porting nella UI. |
| [Sources/NXLibrary/Models/GameDetailsInfo.swift](../../Sources/NXLibrary/Models/GameDetailsInfo.swift) | Ispeziona DLC e salvataggi del bundle e prepara dimensioni e dettagli del gioco. |
| [Sources/NXLibrary/Models/GamepadType.swift](../../Sources/NXLibrary/Models/GamepadType.swift) | Definisce brand dei controller e azioni astratte GamepadAction. |
| [Sources/NXLibrary/Models/LogEntry.swift](../../Sources/NXLibrary/Models/LogEntry.swift) | Rappresenta messaggi, livelli e identità delle righe di log mostrate dall’app. |
| [Sources/NXLibrary/Models/PlayedGame.swift](../../Sources/NXLibrary/Models/PlayedGame.swift) | Gioco nxnative o Steam per schermata di lancio e card di fine sessione. |
| [Sources/NXLibrary/Models/NXLibraryError.swift](../../Sources/NXLibrary/Models/NXLibraryError.swift) | Raggruppa errori applicativi e relative spiegazioni, compresi i rifiuti prima del porting. |
| [Sources/NXLibrary/Models/SelectableGame.swift](../../Sources/NXLibrary/Models/SelectableGame.swift) | Rappresenta le sorgenti selezionabili e l’ordinamento delle versioni nel wizard. |
| [Sources/NXLibrary/Models/UpstreamCheckState.swift](../../Sources/NXLibrary/Models/UpstreamCheckState.swift) | Rappresenta gli stati del controllo del changelog upstream. |

## Integrazione con macOS e servizi applicativi

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Services/AppUpdater.swift](../../Sources/NXLibrary/Services/AppUpdater.swift) | Coordina controllo release, download, verifica, installazione e riavvio di Arcane. |
| [Sources/NXLibrary/Services/NativeMenuCommands.swift](../../Sources/NXLibrary/Services/NativeMenuCommands.swift) | Coordina tracking, disponibilità nella scena e passaggio differito dai menu macOS alle azioni del launcher. |
| [Sources/NXLibrary/Services/GameControllerService.swift](../../Sources/NXLibrary/Services/GameControllerService.swift) | Rileva controller e rimappature, gestisce tap e hold e produce azioni e simboli dei pulsanti. |
| [Sources/NXLibrary/Services/LaunchReadinessProbe.swift](../../Sources/NXLibrary/Services/LaunchReadinessProbe.swift) | Attende una finestra visibile del gioco (per bundle o, per Steam, per pid) per terminare la schermata di lancio. |
| [Sources/NXLibrary/Services/NotificationService.swift](../../Sources/NXLibrary/Services/NotificationService.swift) | Invia notifiche dei porting e instrada i clic verso il titolo o l’errore interessato. |
| [Sources/NXLibrary/Services/OnlineBackgroundService.swift](../../Sources/NXLibrary/Services/OnlineBackgroundService.swift) | Carica pagine e miniature e scarica wallpaper o video conservando progressi e crediti. |
| [Sources/NXLibrary/Services/RunningGameMonitor.swift](../../Sources/NXLibrary/Services/RunningGameMonitor.swift) | Riconcilia applicazioni in esecuzione e libreria e offre Resume e chiusura del gioco. |
| [Sources/NXLibrary/Services/LibraryWindow.swift](../../Sources/NXLibrary/Services/LibraryWindow.swift) | Riporta davanti la finestra di Arcane dopo un gioco nxnative o Steam, mai sopra un gioco della libreria. |
| [Sources/NXLibrary/Services/SoundEffectService.swift](../../Sources/NXLibrary/Services/SoundEffectService.swift) | Riproduce i cue Selene e applica attivazione, volume e file importati. |
| [Sources/NXLibrary/Services/SystemDetector.swift](../../Sources/NXLibrary/Services/SystemDetector.swift) | Individua checkout nxnative, root personale e possibili percorsi delle chiavi. |

## Core · libreria, stato e sessioni

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Models/PortedGame.swift](../../Sources/NXLibraryCore/Models/PortedGame.swift) | Modello persistente del gioco con bundle, sorgenti, impostazioni, build e installazione in attesa. |
| [Sources/NXLibraryCore/Models/GameStorageUsage.swift](../../Sources/NXLibraryCore/Models/GameStorageUsage.swift) | Dimensioni per gioco e totali: distingue assenza e indisponibilità, segnala cache condivise e conserva identità stabili per il focus. |
| [Sources/NXLibraryCore/Models/LibraryFile.swift](../../Sources/NXLibraryCore/Models/LibraryFile.swift) | Contenitore versionato del catalogo della libreria. |
| [Sources/NXLibraryCore/Models/GameStatus.swift](../../Sources/NXLibraryCore/Models/GameStatus.swift) | Enumera disponibilità e stato del gioco rispetto ad app, sorgenti e porting. |
| [Sources/NXLibraryCore/Models/GameResourceState.swift](../../Sources/NXLibraryCore/Models/GameResourceState.swift) | Distingue app mancanti, sorgenti assenti e workspace non compilati, riconcilia gli stati e conserva Play per una build esistente. |
| [Sources/NXLibraryCore/Models/BackdropArt.swift](../../Sources/NXLibraryCore/Models/BackdropArt.swift) | Regola che tiene l’arte del gioco precedente sullo sfondo Spotlight (`BackdropArtRule`) dissolvenza di un layer calcolata sull’orologio (`OpacityFade`) e livelli ormai coperti da togliere (`ArtStack`). |
| [Sources/NXLibraryCore/Models/TileMotion.swift](../../Sources/NXLibraryCore/Models/TileMotion.swift) | Curve e campioni dei loop di ring, bagliore e riflesso della tile selezionata, sull'orologio condiviso. |
| [Sources/NXLibraryCore/Models/TextScroll.swift](../../Sources/NXLibraryCore/Models/TextScroll.swift) | Scorrimento della colonna del pannello della mod: altezza della descrizione dopo Read more, limiti, riga a fuoco mostrata intera e passo Su/Giù che legge prima della riga seguente. |
| [Sources/NXLibraryCore/Models/AppSettings.swift](../../Sources/NXLibraryCore/Models/AppSettings.swift) | Definisce impostazioni globali, default e decodifica compatibile; ignora la scelta storica delle particelle. |
| [Sources/NXLibraryCore/Models/LibraryFilter.swift](../../Sources/NXLibraryCore/Models/LibraryFilter.swift) | Definisce filtri, PlayHistory e query condivisa per ricerca/ordine del catalogo misto, conservando l’API nxnative. |
| [Sources/NXLibraryCore/Models/LibrarySelectionState.swift](../../Sources/NXLibraryCore/Models/LibrarySelectionState.swift) | Mantiene selezione e spostamento nel risultato filtrato della Collection. |
| [Sources/NXLibraryCore/Models/LibraryPresentation.swift](../../Sources/NXLibraryCore/Models/LibraryPresentation.swift) | Formatta metadati e statistiche temporali per le schermate della libreria. |
| [Sources/NXLibraryCore/Models/GameDetailPresentation.swift](../../Sources/NXLibraryCore/Models/GameDetailPresentation.swift) | Prepara badge, disponibilità delle azioni, date e dati della pagina Details. |
| [Sources/NXLibraryCore/Models/PlaySession.swift](../../Sources/NXLibraryCore/Models/PlaySession.swift) | Descrive una sessione persistibile con gioco e riferimenti temporali. |
| [Sources/NXLibraryCore/Models/ActivitySummary.swift](../../Sources/NXLibraryCore/Models/ActivitySummary.swift) | Aggrega sessioni, giorni e tempi della settimana per la scheda Activity. |
| [Sources/NXLibraryCore/Models/MoreLikeThis.swift](../../Sources/NXLibraryCore/Models/MoreLikeThis.swift) | Ordina i giochi correlati per generi, sviluppatore ed editore, con precedenza alla stessa fonte e ripiego facoltativo. |
| [Sources/NXLibraryCore/Services/ImportService.swift](../../Sources/NXLibraryCore/Services/ImportService.swift) | Scansiona bundle nxnative e ne ricava identità, versione, percorso e dimensioni. |
| [Sources/NXLibraryCore/Models/CursorIdleState.swift](../../Sources/NXLibraryCore/Models/CursorIdleState.swift) | Politica del ritardo di visibilità del puntatore e reset su mouse o perdita di eleggibilità. |
| [Sources/NXLibraryCore/Services/AppSizeCache.swift](../../Sources/NXLibraryCore/Services/AppSizeCache.swift) | Conserva dimensioni per percorso e data del bundle e decide lo stato vuoto della libreria. |
| [Sources/NXLibraryCore/Services/AppSettingsStore.swift](../../Sources/NXLibraryCore/Services/AppSettingsStore.swift) | Pubblica impostazioni ed errori, preserva i file illeggibili e salva settings.json in modo atomico. Tiene l'ultima selezione fuori dalle notifiche e la scrive in background. |
| [Sources/NXLibraryCore/Services/PlaySessionStore.swift](../../Sources/NXLibraryCore/Services/PlaySessionStore.swift) | Registra avvio, heartbeat, fine e riconciliazione delle sessioni di gioco; unisce i totali esterni (Steam) con le sessioni successive. |
| [Sources/NXLibraryCore/Navigation/AppRouter.swift](../../Sources/NXLibraryCore/Navigation/AppRouter.swift) | Gestisce route, ritorno, menu, ricerca e richieste Spotlight; ShellBackdropCover definisce quali strati sono coperti da Setup, benvenuto e scelta tema. |
| [Sources/NXLibraryCore/Models/GameFocus.swift](../../Sources/NXLibraryCore/Models/GameFocus.swift) | Quando un gioco che esce riporta Arcane davanti: solo se era l’app in primo piano e nessun altro gioco della libreria è aperto. |
| [Sources/NXLibraryCore/Models/SessionSummary.swift](../../Sources/NXLibraryCore/Models/SessionSummary.swift) | Cosa dice la card di fine sessione: gioco, durata di questa sessione e totale scritto come nelle info del gioco; niente card sotto i dieci secondi. |

## Core · Setup, motore e chiavi

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Models/ToolchainRequirements.swift](../../Sources/NXLibraryCore/Models/ToolchainRequirements.swift) | Centralizza requisiti Xcode e asset Metal e confronta versioni numeriche. |
| [Sources/NXLibraryCore/Models/ToolchainInfo.swift](../../Sources/NXLibraryCore/Models/ToolchainInfo.swift) | Registra provenienza e verifica della toolchain associata a un build. |
| [Sources/NXLibraryCore/Models/ToolchainGateCopy.swift](../../Sources/NXLibraryCore/Models/ToolchainGateCopy.swift) | Traduce il gate in testi distinguendo Metal certificato, precedente e successivo. |
| [Sources/NXLibraryCore/Models/SetupCheck.swift](../../Sources/NXLibraryCore/Models/SetupCheck.swift) | Converte fatti e override del Setup in schede, stati, azioni e condizioni di riapertura. |
| [Sources/NXLibraryCore/Models/FirstRunSetup.swift](../../Sources/NXLibraryCore/Models/FirstRunSetup.swift) | Coordina pagina e completamento del Setup, scelta Steam persistente fino alla fine, ripresa, focus e consumo unico delle selezioni da Your games. |
| [Sources/NXLibraryCore/Models/FirstRunFindings.swift](../../Sources/NXLibraryCore/Models/FirstRunFindings.swift) | Conta giochi Steam e app portate senza modifiche; distingue lettura incompleta da assenza e permette nuove letture annullabili. |
| [Sources/NXLibraryCore/Models/ArcaneWelcome.swift](../../Sources/NXLibraryCore/Models/ArcaneWelcome.swift) | Decide quando compare il benvenuto in Arcane, l'offerta di Steam, il focus e come ogni uscita lo segna visto. |
| [Sources/NXLibraryCore/Models/GameFoldersCopy.swift](../../Sources/NXLibraryCore/Models/GameFoldersCopy.swift) | Condivide nomi delle cartelle, formati e descrizioni tra Setup, Settings e selettori dei percorsi. |
| [Sources/NXLibraryCore/Models/SetupGrid.swift](../../Sources/NXLibraryCore/Models/SetupGrid.swift) | Calcola disposizione, centratura e navigazione del focus nella griglia del Setup. |
| [Sources/NXLibraryCore/Models/UpstreamCopy.swift](../../Sources/NXLibraryCore/Models/UpstreamCopy.swift) | Prepara i testi del changelog upstream e dell’adozione degli aggiornamenti tramite Arcane. |
| [Sources/NXLibraryCore/Services/NXNativeEnvironment.swift](../../Sources/NXLibraryCore/Services/NXNativeEnvironment.swift) | Ispeziona strumenti, Python, Xcode e Metal e restituisce uno stato dell’ambiente. |
| [Sources/NXLibraryCore/Services/EngineLocation.swift](../../Sources/NXLibraryCore/Services/EngineLocation.swift) | Risolve checkout predefinito o scelto e produce i candidati per prod.keys. |
| [Sources/NXLibraryCore/Services/EngineToolchain.swift](../../Sources/NXLibraryCore/Services/EngineToolchain.swift) | Individua runtime incluso o venv del checkout e prepara ambiente e PATH dei processi. |
| [Sources/NXLibraryCore/Services/EnginePackageReader.swift](../../Sources/NXLibraryCore/Services/EnginePackageReader.swift) | Legge content meta e capacità del checkout, compresa selezione NUP multiprogramma, senza esporre chiavi. |
| [Sources/NXLibraryCore/Models/BuildWarningCopy.swift](../../Sources/NXLibraryCore/Models/BuildWarningCopy.swift) | Testo mostrato a fine build per `warn` dell’engine: archivio mancante o pipeline da preparare al primo avvio. |
| [Sources/NXLibraryCore/Models/ReleaseNotesLayout.swift](../../Sources/NXLibraryCore/Models/ReleaseNotesLayout.swift) | Divide le note di release in titoli, voci e testo, una riga per volta, per il dialogo degli aggiornamenti. |
| [Sources/NXLibraryCore/Services/NewestEngine.swift](../../Sources/NXLibraryCore/Services/NewestEngine.swift) | Scelta dell’engine più nuovo: testi condivisi, lettura del Metal dal lock di main, cambio di commit con git senza toccare file modificati. |
| [Sources/NXLibraryCore/Services/NUPSourceCatalog.swift](../../Sources/NXLibraryCore/Services/NUPSourceCatalog.swift) | Legge NUP con base o soli update; tiene distinti programma, applicazione e base DLC tramite il lettore upstream e conserva il default selezionato. |
| [Sources/NXLibraryCore/Services/DirectorySize.swift](../../Sources/NXLibraryCore/Services/DirectorySize.swift) | Misura le cartelle con fts come du, così il refresh non resta bloccato su app grandi in dischi esterni (issue #2). |
| [Sources/NXLibraryCore/Services/NXNativeGameSettings.swift](../../Sources/NXLibraryCore/Services/NXNativeGameSettings.swift) | Legge l’elenco impostazioni del build, i valori attuali e le chiavi fissate da env.txt. |
| [Sources/NXLibraryCore/Services/SavedChoicesStore.swift](../../Sources/NXLibraryCore/Services/SavedChoicesStore.swift) | Legge e scrive le scelte salvate launcher.<env> nel dominio preferenze dell’app gioco. |
| [Sources/NXLibraryCore/Services/CompatibilityChecker.swift](../../Sources/NXLibraryCore/Services/CompatibilityChecker.swift) | Controlla commit, modifiche del checkout, Metal e opzioni CLI richieste dal frontend. |
| [Sources/NXLibraryCore/Services/SetupProbe.swift](../../Sources/NXLibraryCore/Services/SetupProbe.swift) | Raccoglie i fatti mostrati dal Setup usando comandi e controlli mirati. |
| [Sources/NXLibraryCore/Services/SetupActions.swift](../../Sources/NXLibraryCore/Services/SetupActions.swift) | Costruisce le operazioni Git ammesse per installare o allineare il motore al pin. |
| [Sources/NXLibraryCore/Services/InstallProgress.swift](../../Sources/NXLibraryCore/Services/InstallProgress.swift) | Interpreta avanzamento Git, percentuali, byte e righe parziali per le installazioni. |
| [Sources/NXLibraryCore/Services/KeyStore.swift](../../Sources/NXLibraryCore/Services/KeyStore.swift) | Valida le chiavi, espone solo il riepilogo e pubblica atomicamente la copia gestita con permessi 0600. |
| [Sources/NXLibraryCore/Services/KeyCheck.swift](../../Sources/NXLibraryCore/Services/KeyCheck.swift) | Legge intestazioni NCA e ticket e verifica se le chiavi possono aprire le sorgenti selezionate. |
| [Sources/NXLibraryCore/Services/CommandRunner.swift](../../Sources/NXLibraryCore/Services/CommandRunner.swift) | Confine sostituibile per comandi e output, con esecuzione sincrona o streaming delle righe. |
| [Sources/NXLibraryCore/Services/UpstreamChecker.swift](../../Sources/NXLibraryCore/Services/UpstreamChecker.swift) | Consulta i commit upstream tramite HTTP e produce stato e collegamento di confronto. |

## Core · sorgenti, porting, installazione e lancio

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Models/GameFileItem.swift](../../Sources/NXLibraryCore/Models/GameFileItem.swift) | Sorgenti salvate con layout, requisiti e selezione NUP facoltativa, compatibile con i vecchi record. |
| [NUPProgramSelection.swift](../../Sources/NXLibraryCore/Models/NUPProgramSelection.swift) | Identità tipizzata del programma NUP, applicazione e base add-on; indice ricavato dal programma, persistito con i sorgenti. |
| [Sources/NXLibraryCore/Models/SourceSelection.swift](../../Sources/NXLibraryCore/Models/SourceSelection.swift) | Scelte dei contenuti, dimensioni e versione di build; verifica coerenza e supporto del programma NUP e ne vincola l’indice nel rebuild. |
| [Sources/NXLibraryCore/Models/BuildRecord.swift](../../Sources/NXLibraryCore/Models/BuildRecord.swift) | Conserva esito, tempi, log e provenienza di un porting. |
| [Sources/NXLibraryCore/Models/TargetPlatform.swift](../../Sources/NXLibraryCore/Models/TargetPlatform.swift) | Definisce il target mac-app e le sue etichette per l’interfaccia. |
| [Sources/NXLibraryCore/Models/GameRuntimeConfig.swift](../../Sources/NXLibraryCore/Models/GameRuntimeConfig.swift) | Persiste opzioni per titolo, prepara Review e lingua del rebuild, mappa DM_* e unisce env.txt. |
| [Sources/NXLibraryCore/Models/LauncherSettings.swift](../../Sources/NXLibraryCore/Models/LauncherSettings.swift) | Legge launcher.json e verifica i controlli supportati, con fallback per le build precedenti. |
| [Sources/NXLibraryCore/Models/AppIconProgress.swift](../../Sources/NXLibraryCore/Models/AppIconProgress.swift) | Stati e testi della preparazione icona, con esito informativo aggiunto al log della build conclusa. |
| [Sources/NXLibraryCore/Models/IconLaunchWait.swift](../../Sources/NXLibraryCore/Models/IconLaunchWait.swift) | Conserva una richiesta Play durante la firma dell'icona e la revoca su annullamento, errore o chiusura del dialogo. |
| [Sources/NXLibraryCore/Services/PipelineArchiveProgress.swift](../../Sources/NXLibraryCore/Services/PipelineArchiveProgress.swift) | Legge il log pipeline della build corrente e conta solo i gruppi confermati pronti dal motore. |
| [Sources/NXLibraryCore/Models/PortingProgress.swift](../../Sources/NXLibraryCore/Models/PortingProgress.swift) | Aggrega eventi del motore in fasi e percentuale complessiva; identifica archivio e prewarm senza dedurre conteggi dal tempo trascorso. |
| [Sources/NXLibraryCore/Models/PortingPresentation.swift](../../Sources/NXLibraryCore/Models/PortingPresentation.swift) | Definisce fallimento persistito, ETA, attività senza stima del prewarm, aspetto della tile e pill del porting. |
| [Sources/NXLibraryCore/Models/PortingFailureReason.swift](../../Sources/NXLibraryCore/Models/PortingFailureReason.swift) | Classifica messaggi del motore e rifiuti preliminari in motivazioni e azioni spiegabili, comprese le tabelle shader diverse dal profilo del gioco. |
| [Sources/NXLibraryCore/Models/PortingNotice.swift](../../Sources/NXLibraryCore/Models/PortingNotice.swift) | Decide quando notificare l’esito di un porting e prepara il relativo messaggio. |
| [Sources/NXLibraryCore/Models/PendingInstall.swift](../../Sources/NXLibraryCore/Models/PendingInstall.swift) | Conserva un bundle pronto in attesa e ne gestisce installazione, scarto e aggiornamento del record, anche dopo una pubblicazione interrotta. |
| [Sources/NXLibraryCore/Models/RunningGames.swift](../../Sources/NXLibraryCore/Models/RunningGames.swift) | Confronta bundle ID e mantiene uno snapshot delle applicazioni in esecuzione. |
| [Sources/NXLibraryCore/Services/SourceCatalog.swift](../../Sources/NXLibraryCore/Services/SourceCatalog.swift) | Riconosce sorgenti NSP/XCI/NSZ/XCZ e raggruppa titoli, update e DLC; DetectedSource conserva la selezione NUP tipizzata. |
| [Sources/NXLibraryCore/Services/ExtractedSourceCatalog.swift](../../Sources/NXLibraryCore/Services/ExtractedSourceCatalog.swift) | Verifica il layout di un gioco estratto, legge NPDM e profilo registrato e rileva update e DLC. |
| [Sources/NXLibraryCore/Services/WorkspaceManager.swift](../../Sources/NXLibraryCore/Services/WorkspaceManager.swift) | Prepara collegamenti simbolici, verifica link interrotti e adotta workspace e cache esistenti. |
| [Sources/NXLibraryCore/Services/BuildScratch.swift](../../Sources/NXLibraryCore/Services/BuildScratch.swift) | Sceglie dove stanno workspace e app temporanea (sul volume dell'app quando può ospitarli), riconosce i workspace gestiti e le cartelle temporanee da pulire. |
| [Sources/NXLibraryCore/Services/BuildCommand.swift](../../Sources/NXLibraryCore/Services/BuildCommand.swift) | Valore con eseguibile, argomenti, ambiente e directory di lavoro del processo di porting. |
| [Sources/NXLibraryCore/Services/BuildCommandBuilder.swift](../../Sources/NXLibraryCore/Services/BuildCommandBuilder.swift) | Contratto CLI nxnative: Mac, JSON, versione pacchetto, selezione --program esplicita e override toolchain. |
| [Sources/NXLibraryCore/Services/BuildEvent.swift](../../Sources/NXLibraryCore/Services/BuildEvent.swift) | Definisce gli eventi di fase, step, avanzamento e log ricevuti dal motore. |
| [Sources/NXLibraryCore/Services/BuildEventParser.swift](../../Sources/NXLibraryCore/Services/BuildEventParser.swift) | Decodifica eventi JSON e tratta le altre righe come log. |
| [Sources/NXLibraryCore/Services/BuildService.swift](../../Sources/NXLibraryCore/Services/BuildService.swift) | Avvia il porting, gestisce processi, cancellazione, log ed eventi; conserva il bundle valido quando fallisce solo l’installazione. |
| [Sources/NXLibraryCore/Services/BuildOutputInstaller.swift](../../Sources/NXLibraryCore/Services/BuildOutputInstaller.swift) | Pubblica il bundle con rinomina o scambio atomico, prepara copie fra volumi e riconosce i tentativi già completati tramite ricevuta. |
| [Sources/NXLibraryCore/Services/GameAppDestination.swift](../../Sources/NXLibraryCore/Services/GameAppDestination.swift) | Risolve la destinazione condivisa da review e porting, conserva i percorsi dei rebuild, evita conflitti di nome e verifica la cartella di destinazione. |
| [Sources/NXLibraryCore/Services/LaunchService.swift](../../Sources/NXLibraryCore/Services/LaunchService.swift) | Scrive l’ambiente runtime e avvia il bundle del gioco tramite NSWorkspace. |
| [Sources/NXLibraryCore/Services/StorageManager.swift](../../Sources/NXLibraryCore/Services/StorageManager.swift) | Misura app, cache e log per gioco e totali senza duplicare percorsi condivisi; verifica cartelle e sorgenti prima della pulizia selettiva. I backup appartengono al flusso Saves. |
| [Sources/NXLibraryCore/Services/DiagnosticsReport.swift](../../Sources/NXLibraryCore/Services/DiagnosticsReport.swift) | Genera il rapporto diagnostico e rimuove percorso home e valori riconosciuti come chiavi. |
| [Sources/NXLibraryCore/Services/AppUpdate.swift](../../Sources/NXLibraryCore/Services/AppUpdate.swift) | Definisce repository, versioni, verifica del download e sostituzione atomica dell’app in staging esclusivo, con conservazione della vecchia copia se il Cestino fallisce; riconosce la copia temporanea di App Translocation. |
| [Sources/NXLibraryCore/Services/AppBundleRename.swift](../../Sources/NXLibraryCore/Services/AppBundleRename.swift) | Decide se una copia release che si chiama ancora `NX Library.app` diventa `Arcane.app` alla chiusura, e fa lo spostamento nella stessa cartella. |
| [Sources/NXLibraryCore/Models/AppUpdatePresentation.swift](../../Sources/NXLibraryCore/Models/AppUpdatePresentation.swift) | Definisce gli stati dell’updater e il gate di installazione per versione e tipo di copia. |
| [Sources/NXLibraryCore/Services/AppUpdateDownload.swift](../../Sources/NXLibraryCore/Services/AppUpdateDownload.swift) | Scarica gli aggiornamenti con limiti di dimensione, redirect HTTPS vincolati a GitHub e gestione del file temporaneo. |

## Core · cheat e mod

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Models/CheatFile.swift](../../Sources/NXLibraryCore/Models/CheatFile.swift) | Decodifica cheats, sezioni, metadati e collegamenti dei codici secondo il parser del motore. |
| [Sources/NXLibraryCore/Models/CheatInstall.swift](../../Sources/NXLibraryCore/Models/CheatInstall.swift) | Valuta file e cartelle in ingresso rispetto a title ID, build ID e necessità di conferma. |
| [Sources/NXLibraryCore/Models/CheatLocator.swift](../../Sources/NXLibraryCore/Models/CheatLocator.swift) | Risolve build ID, title ID e cartella cheats seguendo i file e l’ambiente del launcher. |
| [Sources/NXLibraryCore/Models/CheatStatus.swift](../../Sources/NXLibraryCore/Models/CheatStatus.swift) | Valuta il supporto del motore tramite ancestry e prepara stato della riga e indicatore attivo. |
| [Sources/NXLibraryCore/Models/CheatCopy.swift](../../Sources/NXLibraryCore/Models/CheatCopy.swift) | Centralizza testi di stato, rifiuto, importazione, sostituzione e rimozione dei cheats. |
| [Sources/NXLibraryCore/Services/CheatStore.swift](../../Sources/NXLibraryCore/Services/CheatStore.swift) | Legge e modifica cheats, file enabled, master switch e metadati della build corrente. |
| [Sources/NXLibraryCore/Services/ModStore.swift](../../Sources/NXLibraryCore/Services/ModStore.swift) | Ordine, interruttori, conflitti, Cestino e overlay delle mod RomFS. Ferma la riconciliazione se cartella o record non si leggono. |
| [Sources/NXLibraryCore/Services/ModFolderScanner.swift](../../Sources/NXLibraryCore/Services/ModFolderScanner.swift) | Elenca cartelle, archivi e file RomFS. La lettura stretta distingue una cartella vuota da una scansione fallita durante la riconciliazione. |
| [Sources/NXLibraryCore/Services/GameBanana/GameBananaAPI.swift](../../Sources/NXLibraryCore/Services/GameBanana/GameBananaAPI.swift) | URL, host fidati, modelli delle risposte di GameBanana e testo semplice dalle descrizioni HTML. |
| [Sources/NXLibraryCore/Services/GameBanana/GameBananaClient.swift](../../Sources/NXLibraryCore/Services/GameBanana/GameBananaClient.swift) | Richieste a GameBanana con User-Agent, limite di 4 alla volta e cache su disco. |
| [Sources/NXLibraryCore/Services/GameBanana/GameBananaImageCache.swift](../../Sources/NXLibraryCore/Services/GameBanana/GameBananaImageCache.swift) | Cache su disco delle immagini delle mod dal CDN di GameBanana. |
| [Sources/NXLibraryCore/Services/GameBanana/GameBananaMatch.swift](../../Sources/NXLibraryCore/Services/GameBanana/GameBananaMatch.swift) | Abbina un gioco alla sua pagina GameBanana per nome e ricorda la scelta. |
| [Sources/NXLibraryCore/Services/GameBanana/ModSupport.swift](../../Sources/NXLibraryCore/Services/GameBanana/ModSupport.swift) | Quali file di mod funzionano (solo RomFS), dov'è la loro cartella `romfs`, nomi di cartella sicuri. |
| [Sources/NXLibraryCore/Services/GameBanana/AvailableModsFinder.swift](../../Sources/NXLibraryCore/Services/GameBanana/AvailableModsFinder.swift) | Cerca le mod di un gioco che funzionano e capisce quando una mod installata ha un aggiornamento. |
| [Sources/NXLibraryCore/Services/GameBanana/ModInstaller.swift](../../Sources/NXLibraryCore/Services/GameBanana/ModInstaller.swift) | Controlla, estrae con `bsdtar` e installa una mod scaricata nella cartella del gioco. |
| [Sources/NXLibraryCore/Services/GameBanana/GameBananaBandModel.swift](../../Sources/NXLibraryCore/Services/GameBanana/GameBananaBandModel.swift) | Stato della fascia Mods di un gioco: abbinamento, mod che funzionano, installazioni. |
| [Sources/NXLibraryCore/Services/GameBanana/ModCatalog.swift](../../Sources/NXLibraryCore/Services/GameBanana/ModCatalog.swift) | Categorie nostre, ordinamenti e sezioni della pagina dello store (altezze fisse). |
| [Sources/NXLibraryCore/Services/GameBanana/ModCatalogSnapshots.swift](../../Sources/NXLibraryCore/Services/GameBanana/ModCatalogSnapshots.swift) | Le mod di ogni gioco salvate su disco, per aprire lo store subito; solo link GameBanana. |
| [Sources/NXLibraryCore/Services/GameBanana/ModStoreModel.swift](../../Sources/NXLibraryCore/Services/GameBanana/ModStoreModel.swift) | Dati dello store: apre dalle copie su disco, aggiorna in background due giochi alla volta, abbina solo se sicuro. |
| [Sources/NXLibraryCore/Models/ModStoreFocus.swift](../../Sources/NXLibraryCore/Models/ModStoreFocus.swift) | Focus nella pagina dello store, ancorato al tipo di sezione; ogni sezione ricorda la sua tessera. |
| [Sources/NXLibraryCore/Services/GameBanana/GameBananaFindModel.swift](../../Sources/NXLibraryCore/Services/GameBanana/GameBananaFindModel.swift) | Stato della ricerca per nome: campo, risultati, None of these. |
| [Sources/NXLibraryCore/Services/GameBanana/ModDownload.swift](../../Sources/NXLibraryCore/Services/GameBanana/ModDownload.swift) | Scarica un file di GameBanana con avanzamento e Cancel, solo da host fidati. |
| [Sources/NXLibraryCore/Models/ModsBandLayout.swift](../../Sources/NXLibraryCore/Models/ModsBandLayout.swift) | Ordine delle tessere della fascia Mods e movimento nella sua griglia (sei per riga). |
| [Sources/NXLibraryCore/Services/EnvFileEditor.swift](../../Sources/NXLibraryCore/Services/EnvFileEditor.swift) | Cambia una sola variabile di un `env.txt` lasciando intatte le altre righe. |
| [Sources/NXLibraryCore/Models/LocalMod.swift](../../Sources/NXLibraryCore/Models/LocalMod.swift) | Una cartella della cartella mods di un gioco, con il suo `romfs` e lo stato. |

## Core · salvataggi e cloud

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Models/SaveLocation.swift](../../Sources/NXLibraryCore/Models/SaveLocation.swift) | Percorsi e identità dei salvataggi; account/device, utenti locali aggiuntivi e file registro; cloud effettivo e percorsi sicuri. |
| [Sources/NXLibraryCore/Models/SaveSnapshot.swift](../../Sources/NXLibraryCore/Models/SaveSnapshot.swift) | Identità, inventario, manifest schema 1/2 e anteprime; rifiuta dichiarazioni storiche con componenti nuovi. |
| [Sources/NXLibraryCore/Models/SavePresentation.swift](../../Sources/NXLibraryCore/Models/SavePresentation.swift) | Riepiloghi e ambito dei restore storici/multiutente, nomi dei componenti e limite cloud a primario/device. |
| [Sources/NXLibraryCore/Models/CloudSaves.swift](../../Sources/NXLibraryCore/Models/CloudSaves.swift) | Descrive scelta cloud, cartelle iCloud o personalizzate e passaggi fra le opzioni. |
| [Sources/NXLibraryCore/Services/CloudSavesPreferences.swift](../../Sources/NXLibraryCore/Services/CloudSavesPreferences.swift) | Prepara la cartella e riapplica la scelta cloud ai domini dei giochi prima di ogni avvio, anche Off. |
| [Sources/NXLibraryCore/Services/RyujinxSaveFolder.swift](../../Sources/NXLibraryCore/Services/RyujinxSaveFolder.swift) | Riconosce contenitori Ryujinx, controlla il title ID e seleziona l’intero albero committed 0. |
| [Sources/NXLibraryCore/Services/SaveFileIO.swift](../../Sources/NXLibraryCore/Services/SaveFileIO.swift) | Copie, hash e xattr portabili; inventario di directory e registro regolare limitato, controlli dei percorsi e scritture durevoli. |
| [Sources/NXLibraryCore/Services/SaveSnapshotStore.swift](../../Sources/NXLibraryCore/Services/SaveSnapshotStore.swift) | Backup completi degli utenti locali e registro, formati storici compatibili, staging e import User/Device. |
| [Sources/NXLibraryCore/Services/SaveRestorePreview.swift](../../Sources/NXLibraryCore/Services/SaveRestorePreview.swift) | Staging e validazione dei pezzi registrati nel backup, compreso il file utenti, con rilevamento dei cambiamenti concorrenti. |
| [Sources/NXLibraryCore/Services/SaveTransaction.swift](../../Sources/NXLibraryCore/Services/SaveTransaction.swift) | Sostituzioni con ambito esplicito, backup completo e journal 1/2; verifica originali, recovery e pulizia parziale riprendibili con intento durevole. |
| [Sources/NXLibraryCore/Services/SaveOperationGate.swift](../../Sources/NXLibraryCore/Services/SaveOperationGate.swift) | Assegna lease per titolo e un’esclusione globale per l’updater; coordina salvataggi, Play, installazioni e recuperi. |

## Core · artwork, metadati e sfondi online

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Models/OnlineBackgrounds.swift](../../Sources/NXLibraryCore/Models/OnlineBackgrounds.swift) | Modella sorgenti e risultati e interpreta le risposte dei provider di sfondi fissi e video. |
| [Sources/NXLibraryCore/Services/AutomaticIconResolver.swift](../../Sources/NXLibraryCore/Services/AutomaticIconResolver.swift) | Risolve icone automatiche con cache, abbinamento prudente e rispetto delle restrizioni del provider. |
| [Sources/NXLibraryCore/Services/ArtworkStore.swift](../../Sources/NXLibraryCore/Services/ArtworkStore.swift) | Scarica, ridimensiona e conserva immagini e screenshot nella cache per titolo e tipo. |
| [Sources/NXLibraryCore/Services/AppIconWriter.swift](../../Sources/NXLibraryCore/Services/AppIconWriter.swift) | Scrive l’icona scelta nell’app del gioco, conserva l’originale, rifirma e verifica, e annulla tutto in caso di errore. |
| [Sources/NXLibraryCore/Services/ArtworkPicker.swift](../../Sources/NXLibraryCore/Services/ArtworkPicker.swift) | Aggrega candidati per cover, sfondo, icona e logo e conserva le scelte manuali. |
| [Sources/NXLibraryCore/Services/MetadataPicker.swift](../../Sources/NXLibraryCore/Services/MetadataPicker.swift) | Aggrega valori alternativi dei metadati e conserva gli override dell’utente per campo. |
| [Sources/NXLibraryCore/Services/BoxArtService.swift](../../Sources/NXLibraryCore/Services/BoxArtService.swift) | Trova copertine Switch in GameTDB e ricorda copertine e ricerche senza risultato. |
| [Sources/NXLibraryCore/Services/GameTDB.swift](../../Sources/NXLibraryCore/Services/GameTDB.swift) | Decodifica il database GameTDB, abbina nomi e regioni e conserva l’indice locale. |
| [Sources/NXLibraryCore/Services/NintendoStoreMetadata.swift](../../Sources/NXLibraryCore/Services/NintendoStoreMetadata.swift) | Consulta i cataloghi pubblici dello store e Title DB e conserva descrizioni, immagini e screenshot per lingua; finché la nuova lingua arriva, la pagina mostra l'ultima descrizione letta in un'altra. |
| [Sources/NXLibraryCore/Services/OnlineArtworkSources.swift](../../Sources/NXLibraryCore/Services/OnlineArtworkSources.swift) | Ricava artwork Steam e loghi da MediaWiki e Wikimedia Commons. |
| [Sources/NXLibraryCore/Services/SeleneImporter.swift](../../Sources/NXLibraryCore/Services/SeleneImporter.swift) | Importa suoni e wallpaper dalla cartella Selene dell’utente e risolve cue e fallback. |
| [Sources/NXLibraryCore/Services/MoreArtworkSources.swift](../../Sources/NXLibraryCore/Services/MoreArtworkSources.swift) | Aggiunge matching dei nomi e sorgenti Xbox, GOG, Nintendo Europe, wiki e altri cataloghi. |
| [Sources/NXLibraryCore/Services/ArtworkBrowse.swift](../../Sources/NXLibraryCore/Services/ArtworkBrowse.swift) | Sorgenti sfogliabili da Change artwork (LaunchBox, SteamGridDB): nomi cercati e risultati per tutti gli slot. |
| [Sources/NXLibraryCore/Services/LaunchBoxArt.swift](../../Sources/NXLibraryCore/Services/LaunchBoxArt.swift) | Legge ricerca e pagina gioco di LaunchBox; dal payload Nuxt ricava anteprime, file pieni, tipo, regione e dimensioni; screenshot Gameplay. |
| [Sources/NXLibraryCore/Services/SteamGridDBArt.swift](../../Sources/NXLibraryCore/Services/SteamGridDBArt.swift) | Conserva la chiave SteamGridDB in un file 0600 e interroga l’API v2 per griglie, hero, loghi e icone statiche accreditate. |
| [Sources/NXLibraryCore/Services/ScreenshotFallback.swift](../../Sources/NXLibraryCore/Services/ScreenshotFallback.swift) | Conserva per 30 giorni gli screenshot LaunchBox dei giochi senza screenshot Title DB e li sovrappone ai metadati. |
| [Sources/NXLibraryCore/Models/LibraryArtworkRole.swift](../../Sources/NXLibraryCore/Models/LibraryArtworkRole.swift) | Ruoli di layout delle immagini (copertina, quadrato, sfondo…) separati dal fornitore: un quadrato non chiede né ritaglia mai la copertina verticale. |

## Core · presentazione Selene, focus e impostazioni

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Models/ButtonPrompts.swift](../../Sources/NXLibraryCore/Models/ButtonPrompts.swift) | Traduce azioni in simboli o etichette per tastiera e controller Switch, Xbox e PlayStation. |
| [Sources/NXLibraryCore/Models/CollectionRow.swift](../../Sources/NXLibraryCore/Models/CollectionRow.swift) | Definisce proporzioni delle copertine e geometria della riga Collection. |
| [Sources/NXLibraryCore/Models/DetailsFacts.swift](../../Sources/NXLibraryCore/Models/DetailsFacts.swift) | Sceglie le righe del pannello Details per Switch e Steam: solo i valori presenti, niente di tecnico. |
| [Sources/NXLibraryCore/Models/CriticRating.swift](../../Sources/NXLibraryCore/Models/CriticRating.swift) | Identità pubblica del gioco e console (Mac, Switch, Switch 2), voto originale /100, provenienza e riempimento proporzionale delle cinque stelle. |
| [Sources/NXLibraryCore/Services/WikidataRatings.swift](../../Sources/NXLibraryCore/Services/WikidataRatings.swift) | Abbina titoli esatti e ID Steam; seleziona medie della critica documentate, senza confondere piattaforme o raccomandazioni. L'identità del gioco (`entity`) serve anche alle descrizioni di Wikipedia. |
| [Sources/NXLibraryCore/Services/BoundedDownload.swift](../../Sources/NXLibraryCore/Services/BoundedDownload.swift) | Lettura HTTP limitata a blocchi, senza redirect né byte per byte: usata da Wikidata, IGDB, LaunchBox/TheGamesDB e Steam. |
| [Sources/NXLibraryCore/Services/ConnectivityWatcher.swift](../../Sources/NXLibraryCore/Services/ConnectivityWatcher.swift) | Avvisa sul main thread quando il Mac torna online, perché il giro delle descrizioni riprenda da solo; la prima lettura non conta. |
| [Sources/NXLibraryCore/Services/WikipediaDescription.swift](../../Sources/NXLibraryCore/Services/WikipediaDescription.swift) | Quando una descrizione non è nella lingua dell'app, sitelink Wikidata e introduzione di Wikipedia in quella lingua (cinese in semplificato); servizio con cache misurabile e svuotabile, host fissi e nessun errore salvato come assenza. |
| [Sources/NXLibraryCore/Services/CriticRatingService.swift](../../Sources/NXLibraryCore/Services/CriticRatingService.swift) | Preferenza IGDB personale → Wikidata pubblico, cache Wikidata, ripiego offline e pausa dopo errori. |
| [Sources/NXLibraryCore/Services/IGDBCredentials.swift](../../Sources/NXLibraryCore/Services/IGDBCredentials.swift) | Credenziali Twitch personali in file 0600, validazione e messaggi sicuri senza segreti nei log. |
| [Sources/NXLibraryCore/Services/IGDBRatings.swift](../../Sources/NXLibraryCore/Services/IGDBRatings.swift) | Abbinamento IGDB esatto o tramite ID Steam, critica preferita e ripiego utenti esplicito, con provenienza distinta da Wikidata. |
| [Sources/NXLibraryCore/Services/IGDBRatingService.swift](../../Sources/NXLibraryCore/Services/IGDBRatingService.swift) | Cache dei voti, richieste coalescenti e verifica credenziali tramite il client IGDB condiviso. |
| [Sources/NXLibraryCore/Services/IGDBClient.swift](../../Sources/NXLibraryCore/Services/IGDBClient.swift) | Unico accesso Twitch/IGDB per voti e metadati: token in memoria, coda limitata seriale, host vincolati, rinnovo 401 e annullamento. |
| [Sources/NXLibraryCore/Services/IGDBMetadata.swift](../../Sources/NXLibraryCore/Services/IGDBMetadata.swift) | Proposte IGDB per campo: identità esatta, ruoli delle aziende e date complete della piattaforma corretta. |
| [Sources/NXLibraryCore/Services/IGDBMetadataService.swift](../../Sources/NXLibraryCore/Services/IGDBMetadataService.swift) | Ricerca metadati su richiesta, ID Steam verificato, cache separata e ripiego offline; nessuna scrittura delle scelte personali. |
| [Sources/NXLibraryCore/Services/DatabaseMetadata.swift](../../Sources/NXLibraryCore/Services/DatabaseMetadata.swift) | Proposte LaunchBox/TheGamesDB: identità e piattaforma verificate, campi separati, fonte esplicita e date della versione corretta. |
| [Sources/NXLibraryCore/Services/DatabaseMetadataService.swift](../../Sources/NXLibraryCore/Services/DatabaseMetadataService.swift) | Letture pubbliche limitate e annullabili, richieste condivise, cache testuale per gioco/piattaforma e recupero offline. |
| [Sources/NXLibraryCore/Models/DetailsFocus.swift](../../Sources/NXLibraryCore/Models/DetailsFocus.swift) | Gestisce zone e spostamenti del focus nei link e nelle bande di Details. |
| [Sources/NXLibraryCore/Models/FocusIndex.swift](../../Sources/NXLibraryCore/Models/FocusIndex.swift) | Mantiene un indice di focus entro i limiti di una lista. |
| [Sources/NXLibraryCore/Models/SettingsRowAction.swift](../../Sources/NXLibraryCore/Models/SettingsRowAction.swift) | Identifica azioni e righe Settings, mantenendo una sola azione primaria per riga senza accorpare giochi omonimi. |
| [Sources/NXLibraryCore/Models/GameOptionsPresentation.swift](../../Sources/NXLibraryCore/Models/GameOptionsPresentation.swift) | Definisce righe, livelli, etichette, scelte runtime e focus di Game Options. |
| [Sources/NXLibraryCore/Models/HoldDetector.swift](../../Sources/NXLibraryCore/Models/HoldDetector.swift) | Distingue pressione breve e prolungata usando un tempo fornito dal chiamante. |
| [Sources/NXLibraryCore/Models/MaterialIcon.swift](../../Sources/NXLibraryCore/Models/MaterialIcon.swift) | Elenca i glifi del font Material Icons incluso nel bundle. |
| [Sources/NXLibraryCore/Models/MenuSelectionModel.swift](../../Sources/NXLibraryCore/Models/MenuSelectionModel.swift) | Gestisce azioni selezionate nel control center e nelle scelte Power. |
| [Sources/NXLibraryCore/Models/MoonlightField.swift](../../Sources/NXLibraryCore/Models/MoonlightField.swift) | Genera in modo deterministico i dati delle particelle per lo sfondo Metal. |
| [MoonlightAppearance.swift](../../Sources/NXLibraryCore/Models/MoonlightAppearance.swift) | Identità delle superfici classica/Arcane/Flow e campionamento dei colori locali condiviso fra shader e fallback. |
| [Sources/NXLibraryCore/Models/ScreenshotViewerState.swift](../../Sources/NXLibraryCore/Models/ScreenshotViewerState.swift) | Mantiene indice e limiti della navigazione nel visualizzatore screenshot. |
| [Sources/NXLibraryCore/Models/SeleneCanvas.swift](../../Sources/NXLibraryCore/Models/SeleneCanvas.swift) | Calcola scala uniforme, stage centrato e conversione delle unità del canvas 1920×1080. |
| [Sources/NXLibraryCore/Models/SelenePalette.swift](../../Sources/NXLibraryCore/Models/SelenePalette.swift) | Decodifica palette e metadato opzionale moonlight, ordine del selettore e fallback Arcane con ID selene. |
| [Sources/NXLibraryCore/Models/SettingsCatalog.swift](../../Sources/NXLibraryCore/Models/SettingsCatalog.swift) | Descrive righe, ricerca e valori modificati; ogni riga tiene il suo `rowID` e sta in una sola sezione, vibrazione compresa tra i default dei nuovi giochi. |
| [Sources/NXLibraryCore/Models/SettingsSection.swift](../../Sources/NXLibraryCore/Models/SettingsSection.swift) | Sezioni di Settings con titoli e icone, dichiarate in ordine di sidebar, e `SettingsSidebarGroup`: General, Library, Porting (il gruppo di piattaforma) e System. |
| [Sources/NXLibraryCore/Models/SettingsReset.swift](../../Sources/NXLibraryCore/Models/SettingsReset.swift) | Reset group per sezione: quali sezioni si azzerano e quali valori di `AppSettings` tornano ai default. |
| [Sources/NXLibraryCore/Models/SpotlightPage.swift](../../Sources/NXLibraryCore/Models/SpotlightPage.swift) | Calcola estratti delle descrizioni e stati dello scorrimento della pagina Spotlight. |
| [Sources/NXLibraryCore/Models/SpotlightRow.swift](../../Sources/NXLibraryCore/Models/SpotlightRow.swift) | Costruisce la sequenza per UUID e salva riordini conservando giochi/fonti/card temporaneamente nascosti; Surprise mantiene il proprio contratto nxnative. |
| [Sources/NXLibraryCore/Models/SpotlightRowGeometry.swift](../../Sources/NXLibraryCore/Models/SpotlightRowGeometry.swift) | Posti delle tessere nella riga, camera unica che la fa scorrere e finestra delle tessere create; posto, scala e camera lungo lo scorrimento dalla posizione continua della selezione. |
| [Sources/NXLibraryCore/Models/SpotlightState.swift](../../Sources/NXLibraryCore/Models/SpotlightState.swift) | Gestisce selezione, focus (anche la card Achievements), azioni e spostamento delle tile su Spotlight. |
| [Sources/NXLibraryCore/Models/SpotlightEntrance.swift](../../Sources/NXLibraryCore/Models/SpotlightEntrance.swift) | Tempi e partenze del volo delle tessere, dissolvenza oltre il bordo, sfondo, informazioni, hint e fasi della prima entrata di Spotlight, compreso quando accetta input. |
| [Sources/NXLibraryCore/Models/ThemePicker.swift](../../Sources/NXLibraryCore/Models/ThemePicker.swift) | Gestisce il focus nella griglia colori, tab Wallpapers/Live e scelta dello sfondo successivo. |
| [Sources/NXLibraryCore/Models/WallpaperCatalog.swift](../../Sources/NXLibraryCore/Models/WallpaperCatalog.swift) | Elenca wallpaper e video, gruppi, nomi e file delle risorse incluse o importate. |
| [Sources/NXLibraryCore/Models/WallpaperPlacement.swift](../../Sources/NXLibraryCore/Models/WallpaperPlacement.swift) | Decide dove applicare uno sfondo scelto fra schermi principali e Settings. |
| [Sources/NXLibraryCore/Models/DisplayNameCache.swift](../../Sources/NXLibraryCore/Models/DisplayNameCache.swift) | Nomi visualizzati di cartelle e volumi letti una volta per URL: la pagina si ricostruisce a ogni disegno e un disco esterno in stop bloccherebbe ogni volta. |

## Core · catalogo comune e fonti

| File | Responsabilità |
|---|---|
| [CatalogGame.swift](../../Sources/NXLibraryCore/Models/CatalogGame.swift) | Record tipizzato nxnative/Steam, identità e personalizzazioni con namespace, osservazioni delle installazioni; lookup condiviso della prima installazione disponibile, separato dal gate di Play. |
| [CatalogDocument.swift](../../Sources/NXLibraryCore/Models/CatalogDocument.swift) | Schema, revisione, base legacy riconosciuta, configurazione delle fonti e validazione delle identità. |
| [CatalogGamePresentation.swift](../../Sources/NXLibraryCore/Models/CatalogGamePresentation.swift) | Contratto comune per presentazione, operazioni supportate e target di avvio; nessuna operazione I/O. |
| [CatalogStore.swift](../../Sources/NXLibraryCore/Services/Catalog/CatalogStore.swift) | Conversione conservativa, letture limitate, revisioni attese, lock e archiviazione esplicita del conflitto legacy senza fusione. |
| [CatalogPublication.swift](../../Sources/NXLibraryCore/Services/Catalog/CatalogPublication.swift) | Staging verificato, creazione esclusiva e sostituzione atomica, con confine di errore controllabile. |
| [CatalogRepository.swift](../../Sources/NXLibraryCore/Services/Catalog/CatalogRepository.swift) | Modifiche tipizzate sull'ultimo catalogo, senza replay di effetti esterni; risultati build limitati ai propri campi. |
| [NXNativeLibraryMerge.swift](../../Sources/NXLibraryCore/Services/NXNativeLibraryMerge.swift) | Algoritmo di merge nxnative usato dal repository del catalogo comune. |
| [CatalogRecovery.swift](../../Sources/NXLibraryCore/Models/CatalogRecovery.swift) | Offerte di recupero e conflitto legacy con impronte degli input, rivalidate all’accettazione. |
| [CatalogPersonalizations.swift](../../Sources/NXLibraryCore/Models/CatalogPersonalizations.swift) | Lookup personali immutabili per identità e radici distinte per integrazione. |
| [CatalogErrorCopy.swift](../../Sources/NXLibraryCore/Services/Catalog/CatalogErrorCopy.swift) | Errori recuperabili del catalogo nelle sei lingue. |
| [CatalogBuildRecoveries.swift](../../Sources/NXLibraryCore/Models/CatalogBuildRecoveries.swift) | Generazioni di build non ancora salvate, selezione del retry e conferma della sola generazione persistita. |
| [CatalogGameOptions.swift](../../Sources/NXLibraryCore/Models/CatalogGameOptions.swift) | Ordine unico delle operazioni comuni della libreria; ciò che una fonte può fare dipende dal suo record (nessuna modifica nxnative su un gioco Steam). |
| [CatalogSourcesModel.swift](../../Sources/NXLibraryCore/Services/Catalog/CatalogSourcesModel.swift) | Opt-in, worker annullabile e stato Steam; discoveryRoot conserva la cartella scelta anche con fonte spenta; pubblica solo documenti salvati dal repository. |
| [CatalogLibraryProjection.swift](../../Sources/NXLibraryCore/Models/CatalogLibraryProjection.swift) | Visibilità comune per fonti attive e giochi riconosciuti; nessuna scansione. |

## Core · Steam

| File | Responsabilità |
|---|---|
| [SteamBackgroundLaunch.swift](../../Sources/NXLibraryCore/Services/Steam/SteamBackgroundLaunch.swift) | Attesa di un gioco Steam avviato da Play: pazienza (15 s, 45 s se Play avvia Steam), stato della schermata di lancio, regole di «Keep Steam in the background». |
| [SteamKeyValues.swift](../../Sources/NXLibraryCore/Services/Steam/SteamKeyValues.swift) | Parser testuale limitato e lookup condivisi dei lettori: prima chiave, primo valore tipizzato o campo unico, con regole esplicite sui duplicati; nessuna direttiva eseguita. |
| [SteamPlaytimeReader.swift](../../Sources/NXLibraryCore/Services/Steam/SteamPlaytimeReader.swift) | Ore e ultima partita dell’account Steam più recente da `localconfig.vdf`; nient’altro del file esce dal tipo. |
| [SteamPlaytimeBaselines.swift](../../Sources/NXLibraryCore/Services/Steam/SteamPlaytimeBaselines.swift) | Totali Steam con il momento in cui sono stati visti; nuovo valore o account ripartono; mappa ai giochi del catalogo. |
| [SteamReturnFocus.swift](../../Sources/NXLibraryCore/Models/SteamReturnFocus.swift) | Quando un gioco Steam che esce riporta Arcane davanti: Play premuto qui, gioco in primo piano, nessun altro gioco aperto. |
| [SteamLaunchQuestions.swift](../../Sources/NXLibraryCore/Services/Steam/SteamLaunchQuestions.swift) | Domande con cui Steam ferma un avvio, dalle righe `GameAction` di `logs/console_log.txt`. `ShowInterstitials` è avanzamento; le domande contano dopo 1 s. |
| [SteamPlaytimeSync.swift](../../Sources/NXLibraryCore/Services/Steam/SteamPlaytimeSync.swift) | Una lettura dei file Steam e cosa fa (pubblica, conserva gli ultimi totali buoni dello stesso account o azzera); coda di una lettura alla volta. |
| [InstallationFileSnapshot.swift](../../Sources/NXLibraryCore/Services/Steam/InstallationFileSnapshot.swift) | Letture limitate e non bloccanti di file regolari; verifica dell'identità prima della pubblicazione. |
| [InstallationDirectorySnapshot.swift](../../Sources/NXLibraryCore/Services/Steam/InstallationDirectorySnapshot.swift) | Lettura incrementale delle cartelle, budget anche sulle voci nascoste e annullamento durante l'enumerazione. |
| [NativeMacApplication.swift](../../Sources/NXLibraryCore/Services/Steam/NativeMacApplication.swift) | Evidenze del bundle Mac e degli header eseguibili, architetture e categoria dichiarata, senza avvio. |
| [SteamLibrarySource.swift](../../Sources/NXLibraryCore/Services/Steam/SteamLibrarySource.swift) | Snapshot delle librerie/manifest dichiarati, disponibilità, ambiguità, limiti e annullamento; non modifica il catalogo. |
| [SteamPlayState.swift](../../Sources/NXLibraryCore/Services/Steam/SteamPlayState.swift) | Stato di Play per un gioco Steam: processi osservati con i percorsi risolti, passaggio a Steam, sessione solo quando gira l’app di questa installazione, attese e rifiuti. |
| [SteamBinaryKeyValues.swift](../../Sources/NXLibraryCore/Services/Steam/SteamBinaryKeyValues.swift) | Lettura limitata del formato KeyValues binario di Steam (`appcache/stats`): tipi noti, profondità, voci e dimensione; qualunque altro byte è un errore. |
| [SteamAchievementReader.swift](../../Sources/NXLibraryCore/Services/Steam/SteamAchievementReader.swift) | Achievement di un gioco per l’account corrente: schema (nomi nella lingua dell’app, poi inglese; nascosti; icone) e soli `AchievementTimes` del file delle statistiche; nessun file, account o statistiche: nessun dato. |
| [SteamAchievementRarity.swift](../../Sources/NXLibraryCore/Services/Steam/SteamAchievementRarity.swift) | Rarità pubblica (`GetGlobalAchievementPercentagesForApp`, senza chiave) (una percentuale non numerica, «nan» o «inf», si scarta) e indirizzi delle icone sull’host community-assets del CDN di Steam, solo per nomi di file semplici. |
| [SteamManifestWatcher.swift](../../Sources/NXLibraryCore/Services/Steam/SteamManifestWatcher.swift) | Uno stream FSEvents sulle cartelle `steamapps` delle librerie dell’ultima scansione; segnala solo i manifest `appmanifest_<AppID>.acf` e l’indice `libraryfolders.vdf` della radice, una volta per gruppo di eventi. |
| [SteamCatalogReconciler.swift](../../Sources/NXLibraryCore/Services/Catalog/SteamCatalogReconciler.swift) | Ticket e fusione pura degli snapshot Steam, identità conservate e assenza trattata secondo completezza. |
| [SteamMetadata.swift](../../Sources/NXLibraryCore/Services/Steam/SteamMetadata.swift) | Dati store Steam tipizzati, lingua e URL immagini verificati. |
| [SteamMetadataService.swift](../../Sources/NXLibraryCore/Services/Steam/SteamMetadataService.swift) | Fino a sei download coalescenti, cache per lingua, ripiego offline (anche in un'altra lingua) e immagini ridimensionate. Legge i tratti dei giochi correlati solo da cache. |
| [SteamPersonalizationStore.swift](../../Sources/NXLibraryCore/Services/Steam/SteamPersonalizationStore.swift) | Pubblicazione unica di metadati e riferimenti artwork; fallimenti e Automatic conservano le scelte coerenti. |
| [GameDetailPresentation+Steam.swift](../../Sources/NXLibraryCore/Models/GameDetailPresentation+Steam.swift) | Dati della pagina Steam e generi della testata Spotlight; ignora i dati di altri AppID e dà precedenza ai campi personali. |
| [SteamArtworkRequest.swift](../../Sources/NXLibraryCore/Services/Steam/SteamArtworkRequest.swift) | Cosa chiede la tile di un gioco Steam per ogni ruolo: prima la scelta personale, poi per il quadrato l’icona dell’app installata, mai la copertina; gli altri ruoli vanno all’arte dello store. |
| [SteamBackdropChoice.swift](../../Sources/NXLibraryCore/Services/Steam/SteamBackdropChoice.swift) | Sfondo automatico di un gioco Steam: arte 16:9 pulita (Xbox, GOG, TheGamesDB, fan art LaunchBox), poi il primo screenshot, per ultimo il banner della libreria ritagliato. |

Giochi in download: `SteamLibrarySource` (StateFlags senza il bit 4 → `.downloading`, cartella non letta), `SteamCatalogInstallation.isDownloading` e `SteamCatalogGame.isDownloading`/`needsReview`, `CatalogGamePresentation.isDownloading`, `PortingTileLook.downloading` con `PortingArtLook` (la scritta) e `PortingDownloadMark` → `DownloadMarkLayers` in `TileMotionLayers.swift` (il simbolo che pulsa, fuori dal `drawingGroup`), `SteamPlayCoordinator.openDownloads`, `CatalogSteamInfo` e `GamePrimaryActions.primaryWaveDots` (pulsante «Downloading» con i puntini, come «Porting»), il ritmo delle riscansioni in `CatalogSourcesModel.steamFilesChanged`..

## Core · achievement

| File | Responsabilità |
|---|---|
| [AchievementSummary.swift](../../Sources/NXLibraryCore/Models/AchievementSummary.swift) | Riepilogo puro per la tile e la schermata: conteggi, percentuale, gioco completato (`isComplete`), righe recenti con icona, conteggi per tier, sbloccati di recente, ultimo sblocco, filtri e ordini; maschera i nascosti ancora bloccati. |
| [AchievementTier.swift](../../Sources/NXLibraryCore/Models/AchievementTier.swift) | Tier a cristallo come i trofei PS5: Arcano (viola, al posto del Platino) per il gioco completato, Oro / Argento / Bronzo per rarità Steam (<10%, <30%, il resto); nomi tradotti e PNG nelle risorse del Core; `videoURL` dà il video in loop dell'Arcane (`crystal-arcane.mov`, HEVC con alpha a 384 px). |
| [AchievementsScreenState.swift](../../Sources/NXLibraryCore/Models/AchievementsScreenState.swift) | Filtro e selezione della schermata Achievements: due colonne, bordi fermi, LB/RB che girano i filtri. |
| [GridListLayout.swift](../../Sources/NXLibraryCore/Models/GridListLayout.swift) | Geometria di una lista a colonne di righe uguali: altezza, posizione di ogni riga, linee da disegnare, riga da mostrare e riga in vista più vicina. |

## Core · lingua e testi

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Models/AppIdentity.swift](../../Sources/NXLibraryCore/Models/AppIdentity.swift) | Nome visibile dell'app ("Arcane", non tradotto), il vecchio nome detto solo dal benvenuto, il nome del modulo Porting, pagina del progetto, guida online aperta da About e User-Agent unico delle richieste di rete. |
| [Sources/NXLibraryCore/Models/AppLocale.swift](../../Sources/NXLibraryCore/Models/AppLocale.swift) | Sette lingue, risoluzione delle preferenze e regione indipendente; nomi e ricerca delle regioni. |
| [Sources/NXLibraryCore/Models/GameGenre.swift](../../Sources/NXLibraryCore/Models/GameGenre.swift) | Generi noti tradotti alla presentazione; dati originali e generi personali conservati. |
| [Sources/NXLibraryCore/Services/AppLocalization.swift](../../Sources/NXLibraryCore/Services/AppLocalization.swift) | Contesto osservabile, lookup portabile delle risorse e interpolazioni/plurali. |
| [Sources/NXLibraryCore/Resources/Localizable.xcstrings](../../Sources/NXLibraryCore/Resources/Localizable.xcstrings) | Testi condivisi e traduzioni en/it/fr/de/es/pt-BR/zh-Hans. |

## Core · profilo dei dati

| File | Responsabilità |
|---|---|
| [AppDataProfile.swift](../../Sources/NXLibraryCore/Services/AppDataProfile.swift) | Policy di percorsi, cache, preferenze e staging del profilo. |
| [DevelopmentProfileImporter.swift](../../Sources/NXLibraryCore/Services/DevelopmentProfileImporter.swift) | Copia iniziale selettiva (compresa la scelta Steam del Setup), hash, validazione e ripresa senza modificare la sorgente. |
| [DevelopmentOperationStore.swift](../../Sources/NXLibraryCore/Services/DevelopmentOperationStore.swift) | Autorizzazioni persistenti per le operazioni richieste nella Dev, distinte da quelle importate. |

## UI · Add Game e porting

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/AddGame/AddGameView.swift](../../Sources/NXLibrary/Views/AddGame/AddGameView.swift) | Compone il wizard Choose/Review/Porting e gestisce ingresso, chiusura e navigazione. |
| [Sources/NXLibrary/Views/AddGame/AddGameView+Rows.swift](../../Sources/NXLibrary/Views/AddGame/AddGameView+Rows.swift) | Definisce righe, focus, conferme e input dei passaggi del wizard. |
| [Sources/NXLibrary/Views/AddGame/AddGameRows.swift](../../Sources/NXLibrary/Views/AddGame/AddGameRows.swift) | Rende le righe riutilizzabili per sorgenti e azioni di Add Game. |
| [Sources/NXLibrary/Views/AddGame/AddGameAction.swift](../../Sources/NXLibrary/Views/AddGame/AddGameAction.swift) | Identifica le azioni navigabili dei passaggi del wizard. |
| [Sources/NXLibrary/Views/AddGame/AddGameStepThreeView.swift](../../Sources/NXLibrary/Views/AddGame/AddGameStepThreeView.swift) | Mostra progresso, log, cancellazione ed esito del porting, con nuovo tentativo d’installazione per una build già pronta. |

## UI · Spotlight

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/Spotlight/SpotlightView.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightView.swift) | Compone home e tessere da una lista filtrata per render. Monta Dettagli, Mods e correlati quando sale la pagina. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightView+Input.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightView+Input.swift) | Traduce input, card, azioni, screenshot e riordino. Le frecce sulla riga usano solo le tessere, prima di costruire i dati della pagina. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightView+Entrance.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightView+Entrance.swift) | Coordina l’entrata su moonlight condiviso: coperture e fullscreen, pausa, attesa dell’arte, effetti di volo e dissolvenza, barra in alto e hint per ultimi, atterraggio di sicurezza; nessun input salta l’entrata. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightRowView.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightRowView.swift) | Disegna la riga di tile con finestra visibile, focus e titoli; la faccia della card Mods (`ModsCardCover`). |
| [Sources/NXLibrary/Views/Spotlight/SpotlightTopBar.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightTopBar.swift) | Disegna filtri, prompt dei dorsali e orologio condivisi con Collection. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightInfoView.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightInfoView.swift) | Mostra logo, Play/Options/Favorite, statistiche e stato di porting del gioco selezionato. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightCardInfoView.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightCardInfoView.swift) | Mostra informazioni e azioni delle card Collection, Surprise, Activity e Add Game. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightPageSections.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightPageSections.swift) | Modello della pagina inferiore con dettagli, link e giochi correlati del catalogo; generi e descrizione; la descrizione può venire da Wikipedia (`WikipediaAbout`). |
| [Sources/NXLibrary/Views/Spotlight/SpotlightScreenshotStrip.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightScreenshotStrip.swift) | Disegna la striscia di screenshot con focus e stile adattabile alle schermate. |
| [Sources/NXLibrary/Views/Spotlight/SeleneArtBackground.swift](../../Sources/NXLibrary/Views/Spotlight/SeleneArtBackground.swift) | Compone wallpaper, sfondo del gioco, transizioni e maschere leggendo la palette dallo snapshot condiviso; l'arte è un `CALayer` che dissolve nel render server (`SeleneArtLayer`) e che l'entrata di Spotlight tiene nascosto (`ArtReveal`). |
| [Sources/NXLibrary/Views/Spotlight/SeleneHeroArt.swift](../../Sources/NXLibrary/Views/Spotlight/SeleneHeroArt.swift) | Coordina il caricamento differito di hero e logo del gioco selezionato. |
| [Sources/NXLibrary/Views/Spotlight/GameArtLoader.swift](../../Sources/NXLibrary/Views/Spotlight/GameArtLoader.swift) | Carica e memorizza hero e loghi attraverso ArtworkStore e decoder immagini dedicati. |
| [Sources/NXLibrary/Views/Spotlight/GameArtLoader+Played.swift](../../Sources/NXLibrary/Views/Spotlight/GameArtLoader+Played.swift) | Hero e logo di un `PlayedGame` per schermata di lancio e card di fine sessione; per Steam le stesse scelte delle sue pagine. |

## UI · Collection e Details

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/Collection/CollectionView.swift](../../Sources/NXLibrary/Views/Collection/CollectionView.swift) | Compone libreria a copertine, filtri, informazioni e ripristino dell'ultima selezione tramite lo store. |
| [Sources/NXLibrary/Views/Collection/CollectionView+Input.swift](../../Sources/NXLibrary/Views/Collection/CollectionView+Input.swift) | Gestisce navigazione, azioni e selezione nella Collection. |
| [Sources/NXLibrary/Views/Collection/CollectionCoverRow.swift](../../Sources/NXLibrary/Views/Collection/CollectionCoverRow.swift) | Disegna copertine e scorrimento della riga Collection. |
| [Sources/NXLibrary/Views/Detail/GameDetailView.swift](../../Sources/NXLibrary/Views/Detail/GameDetailView.swift) | Compone la pagina Details e coordina bande, modello corrente e focus. |
| [Sources/NXLibrary/Views/Detail/GameDetailView+Input.swift](../../Sources/NXLibrary/Views/Detail/GameDetailView+Input.swift) | Gestisce azioni, screenshot, navigazione e passaggio ai giochi correlati da Details. |
| [Sources/NXLibrary/Views/Detail/DetailsBackground.swift](../../Sources/NXLibrary/Views/Detail/DetailsBackground.swift) | Compone hero e maschere dello sfondo dedicato alla pagina Details. |
| [Sources/NXLibrary/Views/Detail/DetailsTopBlock.swift](../../Sources/NXLibrary/Views/Detail/DetailsTopBlock.swift) | Mostra logo, crediti, azioni, statistiche, generi e descrizione del gioco, o l'introduzione di Wikipedia con il suo credito. |
| [Sources/NXLibrary/Views/Detail/DetailsBands.swift](../../Sources/NXLibrary/Views/Detail/DetailsBands.swift) | Disegna screenshot, mod e fascia correlati condivisa, con copertine Switch o Steam secondo la fonte. |
| [Sources/NXLibrary/Views/Detail/DetailsPanel.swift](../../Sources/NXLibrary/Views/Detail/DetailsPanel.swift) | Pannello Details uguale per ogni fonte: righe con icona, voto della critica in ultima riga e link in `SeleneActionGrid`; carica solo il voto del gioco mostrato. |
| [Sources/NXLibrary/Views/Detail/CriticRatingValue.swift](../../Sources/NXLibrary/Views/Detail/CriticRatingValue.swift) | Valore della riga Critic score: cinque stelle, numero /100 e fonte, senza finestre aggiuntive; caricamento e assenza espliciti. |
| [Sources/NXLibrary/ViewModels/IGDBSettings.swift](../../Sources/NXLibrary/ViewModels/IGDBSettings.swift) | Configurazione IGDB facoltativa: verifica prima del salvataggio, rimozione e invalidazione delle richieste/voti precedenti. |
| [Sources/NXLibrary/Views/Components/IGDBCredentialsDialog.swift](../../Sources/NXLibrary/Views/Components/IGDBCredentialsDialog.swift) | Guida sintetica in cinque passi, Client ID, Client Secret nascosto, verifica/salvataggio e annullamento; input Settings sospeso. |
| [Sources/NXLibrary/Views/Settings/SettingsAPISection.swift](../../Sources/NXLibrary/Views/Settings/SettingsAPISection.swift) | Pagina generale Servizi API: nota sulle fonti facoltative, IGDB e SteamGridDB con azioni e focus condivisi. |

## UI · Game Options, cheats e salvataggi

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/GameOptions/GameOptionsView.swift](../../Sources/NXLibrary/Views/GameOptions/GameOptionsView.swift) | Presenta opzioni del gioco, Edit details, impostazioni runtime e conferme delle azioni; `GameOptionsFiles` legge i file una volta per apertura. |
| [Sources/NXLibrary/Views/GameOptions/ChangeArtworkView.swift](../../Sources/NXLibrary/Views/GameOptions/ChangeArtworkView.swift) | Seleziona artwork per titolo da rete o file e indica dove viene usato, con stato ad altezza stabile. |
| [Sources/NXLibrary/Views/GameOptions/ChangeMetadataView.swift](../../Sources/NXLibrary/Views/GameOptions/ChangeMetadataView.swift) | Offre alternative per campo da store, Title DB, GameTDB e IGDB, oppure testo personale; anteprima, scelta, annullamento e retry con lo stesso input. |
| [Sources/NXLibrary/Views/GameOptions/CheatsPanel.swift](../../Sources/NXLibrary/Views/GameOptions/CheatsPanel.swift) | Presenta file, master switch, codici, importazione, rimozione e stato di scrittura dei cheats. |
| [Sources/NXLibrary/Views/GameOptions/ModsPanel.swift](../../Sources/NXLibrary/Views/GameOptions/ModsPanel.swift) | Game options → Mods: accende, ordina e sposta nel Cestino le mod RomFS, apre la cartella mods. |
| [Sources/NXLibrary/Views/Detail/ModDetailPanel.swift](../../Sources/NXLibrary/Views/Detail/ModDetailPanel.swift) | Dettaglio di una mod GameBanana: immagini, autore, versione, descrizione, Install/Update e link. |
| [Sources/NXLibrary/Views/Detail/GameBananaFindPanel.swift](../../Sources/NXLibrary/Views/Detail/GameBananaFindPanel.swift) | Cerca su GameBanana la pagina del gioco quando l'abbinamento automatico non basta. |
| [Sources/NXLibrary/ViewModels/ModStoreHost.swift](../../Sources/NXLibrary/ViewModels/ModStoreHost.swift) | Store della card Mods: mantiene la cover fra schermate, rivalida abbinamenti e snapshot; rilegge i badge a ogni apertura e scarta i risultati di generazioni precedenti. |
| [Sources/NXLibrary/Views/Store/ModStorePage.swift](../../Sources/NXLibrary/Views/Store/ModStorePage.swift) | Pagina dello store: barra di ordinamento, banner Featured, righe di tessere; disegna solo le sezioni vicine al focus. |
| [Sources/NXLibrary/Views/Store/GameBananaBlur.swift](../../Sources/NXLibrary/Views/Store/GameBananaBlur.swift) | Arte di una mod rimpicciolita e sfocata una volta, fuori dal main thread, e tenuta in memoria: sfondo del Featured. |
| [Sources/NXLibrary/ViewModels/ModsBandHost.swift](../../Sources/NXLibrary/ViewModels/ModsBandHost.swift) | Fascia Mods condivisa da Spotlight e Details. Legge mod installate, coordina GameBanana e pannelli, svuota i dati del gioco precedente sulla riga Spotlight. |
| [Sources/NXLibrary/ViewModels/GameBananaServices.swift](../../Sources/NXLibrary/ViewModels/GameBananaServices.swift) | Client, cache delle immagini e abbinamenti GameBanana condivisi da tutta l'app. |
| [Sources/NXLibrary/Views/GameOptions/SavesPanel.swift](../../Sources/NXLibrary/Views/GameOptions/SavesPanel.swift) | Presenta azioni sui save, anteprime, errori e popup di successo a scomparsa automatica. |
| [Sources/NXLibrary/Views/GameOptions/MoreSettingsPanel.swift](../../Sources/NXLibrary/Views/GameOptions/MoreSettingsPanel.swift) | Mostra le impostazioni del launcher.json senza riga dedicata: interruttori, scelte e intervalli; le righe fissate da env.txt restano attenuate. |
| [Sources/NXLibrary/Views/GameOptions/SaveImportDetails.swift](../../Sources/NXLibrary/Views/GameOptions/SaveImportDetails.swift) | Disegna percorsi From/To centrati, riquadri leggeri e freccia con riflesso direzionale. |

## UI · Settings

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/Settings/SettingsView.swift](../../Sources/NXLibrary/Views/Settings/SettingsView.swift) | Compone sidebar e gruppo attivo e coordina focus, input e reset; nella Dev registra apertura e stato del fullscreen per la diagnosi della transizione. |
| [Sources/NXLibrary/Views/Settings/SettingsSidebar.swift](../../Sources/NXLibrary/Views/Settings/SettingsSidebar.swift) | Disegna intestazione e sezioni sotto le intestazioni di gruppo (General, Switch, Steam, System). |
| [Sources/NXLibrary/Views/Settings/SettingsSectionContent.swift](../../Sources/NXLibrary/Views/Settings/SettingsSectionContent.swift) | Instrada il gruppo selezionato e fornisce sottotitoli e formattazioni condivise. |
| [Sources/NXLibrary/Views/Settings/SettingsSearchSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsSearchSection.swift) | Presenta ricerca e Changed, con apertura del gruppo della riga selezionata. |
| [Sources/NXLibrary/Views/Settings/SettingsStartUpSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsStartUpSection.swift) | Espone schermata iniziale, animazione d’entrata, Setup e controlli degli aggiornamenti all’avvio. |
| [Sources/NXLibrary/Views/Settings/SettingsNavigationSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsNavigationSection.swift) | Espone le preferenze di navigazione e dei suggerimenti dei tasti. |
| [Sources/NXLibrary/Views/Settings/SettingsSpotlightSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsSpotlightSection.swift) | Espone card, ordine e preferenze della home Spotlight. |
| [Sources/NXLibrary/Views/Settings/SettingsSoundSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsSoundSection.swift) | Espone volume e suoni e importa risorse da una cartella Selene. |
| [Sources/NXLibrary/Views/Settings/SettingsLookSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsLookSection.swift) | Espone palette, wallpaper, luminosità, adattamento, animazione e aspetto dell’icona. |
| [Sources/NXLibrary/Views/Settings/SettingsGamesSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsGamesSection.swift) | Porting → New games: default copiati nei nuovi giochi convertiti, vibrazione compresa. |
| [Sources/NXLibrary/Views/Settings/SettingsLibraryGamesSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsLibraryGamesSection.swift) | Library → Games: schermata di lancio, Surprise me, card della sessione e giochi nascosti. |
| [Sources/NXLibrary/Views/Settings/SettingsCloudSavesSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsCloudSavesSection.swift) | Porting → Cloud saves: scelta e cartella; chiarisce che sincronizzano solo primario e device. |
| [Sources/NXLibrary/Views/Settings/SettingsControllersSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsControllersSection.swift) | Espone controller, schema dei tasti e zona morta per la libreria. |
| [Sources/NXLibrary/Views/Settings/SettingsLibrarySection.swift](../../Sources/NXLibrary/Views/Settings/SettingsLibrarySection.swift) | Espone cartella della libreria, scansione e notifiche dei porting. |
| [Sources/NXLibrary/Views/Settings/SettingsStorageSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsStorageSection.swift) | Library → Storage: spazio occupato, log, cache di metadati e artwork, cartella comune dei backup verificati. |
| [Sources/NXLibrary/Views/Settings/SettingsPortingStorageSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsPortingStorageSection.swift) | Porting → Storage: cache di compilazione per gioco, dalla più grande, e per tutti i giochi, con conferma. |
| [Sources/NXLibrary/Views/Settings/SettingsConsoleSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsConsoleSection.swift) | System → Console: apre la console dei log di build e avvio. |
| [Sources/NXLibrary/Views/Settings/SettingsEngineSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsEngineSection.swift) | Porting → Setup and engine: checkout, pin, gate, toolchain, runtime, changelog upstream e Setup. |
| [Sources/NXLibrary/Views/Settings/SettingsKeysSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsKeysSection.swift) | Porting → Keys: stato, importazione, sostituzione e rilevamento di prod.keys. |
| [Sources/NXLibrary/Views/Settings/SettingsAboutSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsAboutSection.swift) | Mostra versione, diagnostica, aggiornamenti, pulsante di sostegno volontario, crediti e il link alla guida online. |
| [Sources/NXLibrary/Views/Settings/LocalePicker.swift](../../Sources/NXLibrary/Views/Settings/LocalePicker.swift) | Scelta diretta della lingua e ricerca dei formati regionali, con focus tastiera/controller e codici stabili. |

## UI · Setup, avvio, ricerca e console

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/Setup/SetupCheckView.swift](../../Sources/NXLibrary/Views/Setup/SetupCheckView.swift) | Disegna schede dei requisiti, dettagli, progressi e pulsanti Install all/Continue. |
| [Sources/NXLibrary/Views/Setup/SetupCheckView+Input.swift](../../Sources/NXLibrary/Views/Setup/SetupCheckView+Input.swift) | Gestisce focus iniziale, navigazione della griglia, attivazione delle schede Setup e B verso `found` durante il primo avvio. |
| [Sources/NXLibrary/Views/Setup/ArcaneWelcomeView.swift](../../Sources/NXLibrary/Views/Setup/ArcaneWelcomeView.swift) | Disegna il benvenuto in Arcane: nome nuovo, novità, offerta Steam dalla cartella scelta, Add / Not now e Open library. |
| [Sources/NXLibrary/Views/Setup/ArcaneWelcomeView+Input.swift](../../Sources/NXLibrary/Views/Setup/ArcaneWelcomeView+Input.swift) | Gestisce focus, mouse, tastiera e controller del benvenuto. |
| [Sources/NXLibrary/Views/Setup/FoundGamesSetupView.swift](../../Sources/NXLibrary/Views/Setup/FoundGamesSetupView.swift) | Prima pagina del Setup: Steam con interruttore o Retry, app portate e card Porting; Open library resta disponibile durante la lettura. |
| [Sources/NXLibrary/Views/Setup/FoundGamesSetupView+Input.swift](../../Sources/NXLibrary/Views/Setup/FoundGamesSetupView+Input.swift) | Focus, mouse, tastiera e controller di found; Retry della lettura Steam e uscita che annulla la richiesta prima di aprire la libreria. |
| [Sources/NXLibrary/Views/Setup/YourGamesSetupView.swift](../../Sources/NXLibrary/Views/Setup/YourGamesSetupView.swift) | Disegna scelta cartella, primo gioco, apertura libreria e Skip; gestisce mouse, tastiera e controller; contiene `SetupCardRow`, la riga condivisa con `found`. |
| [Sources/NXLibrary/Views/Launch/LaunchScreenView.swift](../../Sources/NXLibrary/Views/Launch/LaunchScreenView.swift) | Mostra artwork e logo per nxnative e Steam. Sfuma anche quando la finestra del gioco è già pronta alla comparsa. |
| [Sources/NXLibrary/Views/Launch/LaunchMotion.swift](../../Sources/NXLibrary/Views/Launch/LaunchMotion.swift) | Movimento della schermata di lancio in Core Animation: artwork che si avvicina e logo del gioco che sale una volta. Con Riduci movimento resta la dissolvenza del logo. |
| [Sources/NXLibrary/Views/Launch/LaunchCoverWindow.swift](../../Sources/NXLibrary/Views/Launch/LaunchCoverWindow.swift) | Ordina la finestra d’attesa sopra ogni app e Space e avvisa il coordinatore dopo aver inviato il pannello al server delle finestre. |
| [Sources/NXLibrary/Views/Search/FindGameView.swift](../../Sources/NXLibrary/Views/Search/FindGameView.swift) | Presenta ricerca nella libreria e risultati navigabili e inoltra il gioco scelto alla home. |
| [Sources/NXLibrary/Views/Console/ConsoleView.swift](../../Sources/NXLibrary/Views/Console/ConsoleView.swift) | Mostra log e stato corrente e offre copia di log e diagnostica. |
| [Sources/NXLibrary/Views/ControlsView.swift](../../Sources/NXLibrary/Views/ControlsView.swift) | Guida Selene separata fra Library e In game; stato controller, rilevamento e scorrimento delle righe con tastiera/controller. |

## UI · componenti condivisi

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/Components/WikipediaAbout.swift](../../Sources/NXLibrary/Views/Components/WikipediaAbout.swift) | Richiesta dell'introduzione di Wikipedia per About this game (Spotlight e Details), chiesta solo quando la risposta dello store nella lingua dell'app è definitiva, valida solo per lo stesso gioco e lingua, e credito con link alla voce. |
| [Sources/NXLibrary/Views/Components/GameIconProvider.swift](../../Sources/NXLibrary/Views/Components/GameIconProvider.swift) | Fornisce e conserva l’icona estratta dai bundle dei giochi; ricorda anche quando manca. |
| [Sources/NXLibrary/Views/Components/PortingArtLook.swift](../../Sources/NXLibrary/Views/Components/PortingArtLook.swift) | Applica alla tile desaturazione, riempimento e barra di avanzamento del porting. |
| [Sources/NXLibrary/Views/Components/ScreenshotViewer.swift](../../Sources/NXLibrary/Views/Components/ScreenshotViewer.swift) | Mostra screenshot a schermo pieno e navigazione fra le immagini. |
| [Sources/NXLibrary/Views/Components/SeleneBottomScrim.swift](../../Sources/NXLibrary/Views/Components/SeleneBottomScrim.swift) | Definisce sfumatura inferiore, posizione condivisa dei comandi (32 unità dal fondo) e fascia libera dai contenuti. |
| [Sources/NXLibrary/Views/Components/SeleneConfirmDialog.swift](../../Sources/NXLibrary/Views/Components/SeleneConfirmDialog.swift) | Definisce card e pulsanti delle conferme, scelte multiple e SeleneSuccessNotice. |
| [Sources/NXLibrary/Views/Components/AppUpdateDialog.swift](../../Sources/NXLibrary/Views/Components/AppUpdateDialog.swift) | Presenta controllo aggiornamenti, note di release, errori e progresso nel dialogo dell’app. |
| [Sources/NXLibrary/Views/Components/SeleneHintsBar.swift](../../Sources/NXLibrary/Views/Components/SeleneHintsBar.swift) | Disegna i suggerimenti contestuali alla posizione condivisa, con grandezza dei simboli invariata. |
| [Sources/NXLibrary/Views/Components/SeleneHomeChrome.swift](../../Sources/NXLibrary/Views/Components/SeleneHomeChrome.swift) | Rende elementi condivisi della cornice e dei controlli della home Selene; trattiene gli hint durante l’entrata. |
| [Sources/NXLibrary/Views/Components/SeleneOptionRow.swift](../../Sources/NXLibrary/Views/Components/SeleneOptionRow.swift) | Disegna righe di opzioni con icona, titolo, descrizione, focus e contenuto laterale. |
| [Sources/NXLibrary/Views/Components/SeleneExpandableText.swift](../../Sources/NXLibrary/Views/Components/SeleneExpandableText.swift) | Rivela la descrizione completa animando l'altezza fra due layout di testo stabili; usato solo dalle righe dei metadati. |
| [Sources/NXLibrary/Views/Components/SelenePillButton.swift](../../Sources/NXLibrary/Views/Components/SelenePillButton.swift) | Disegna il pulsante pill condiviso da azioni e dialoghi. |
| [Sources/NXLibrary/Views/Components/SelenePromptBadge.swift](../../Sources/NXLibrary/Views/Components/SelenePromptBadge.swift) | Rende simbolo o etichetta del pulsante del controller o della tastiera. |
| [Sources/NXLibrary/Views/Components/GlideGroup.swift](../../Sources/NXLibrary/Views/Components/GlideGroup.swift) | Fa muovere un blocco come un pezzo unico durante una scivolata (pagina Spotlight, lista Achievements, pannello Mod, pagina gioco, riga Collection): una dissolvenza, un'immagine che arriva o un'altra animazione non fanno più correre i singoli elementi a velocità diversa. Usa `geometryGroup`, quindi richiede macOS 14. |
| [Sources/NXLibrary/Views/Components/SeleneReveal.swift](../../Sources/NXLibrary/Views/Components/SeleneReveal.swift) | Applica l’animazione di comparsa Selene rispettando la preferenza Riduci movimento. |
| [Sources/NXLibrary/Views/Components/SeleneSettingsRow.swift](../../Sources/NXLibrary/Views/Components/SeleneSettingsRow.swift) | Disegna righe delle impostazioni con valore, focus e azione. |
| [Sources/NXLibrary/Views/Components/SeleneStatsRow.swift](../../Sources/NXLibrary/Views/Components/SeleneStatsRow.swift) | Disegna le statistiche compatte del gioco nella libreria. |
| [Sources/NXLibrary/Views/Components/SeleneSwitch.swift](../../Sources/NXLibrary/Views/Components/SeleneSwitch.swift) | Disegna lo switch coerente con il tema. |
| [Sources/NXLibrary/Views/Components/SeleneTileRing.swift](../../Sources/NXLibrary/Views/Components/SeleneTileRing.swift) | Ring e riflesso della tile selezionata; con Reduce motion il ring fermo disegnato da SwiftUI. |
| [Sources/NXLibrary/Views/Components/TileMotionLayers.swift](../../Sources/NXLibrary/Views/Components/TileMotionLayers.swift) | Ring e riflesso come layer Core Animation in loop: nessun ridisegno dell'app tra un frame e l'altro. |
| [Sources/NXLibrary/Views/Components/SeleneValueChip.swift](../../Sources/NXLibrary/Views/Components/SeleneValueChip.swift) | Rende valori e badge compatti nel linguaggio visivo Selene. |
| [Sources/NXLibrary/Views/Components/SpotlightTileArtwork.swift](../../Sources/NXLibrary/Views/Components/SpotlightTileArtwork.swift) | Disegna subito l’icona nxnative già decodificata; cache condivisa `TileArtMemo` con fonte e revisione delle scelte, caricamento annullabile e segnale `TileArtPendingKey`. |
| [Sources/NXLibrary/Views/Components/SwitchBoxArtCover.swift](../../Sources/NXLibrary/Views/Components/SwitchBoxArtCover.swift) | Carica e disegna la copertina Switch mantenendone le proporzioni. |
| [Sources/NXLibrary/Views/Components/SteamGridDBKeyDialog.swift](../../Sources/NXLibrary/Views/Components/SteamGridDBKeyDialog.swift) | Popup per incollare e verificare la chiave SteamGridDB da Settings → Look e da Change artwork. |
| [Sources/NXLibrary/Views/Components/SwitchPlatformIcon.swift](../../Sources/NXLibrary/Views/Components/SwitchPlatformIcon.swift) | Icona vettoriale della console Switch per la riga della piattaforma. |
| [Sources/NXLibrary/Views/Components/SteamPlatformLogo.swift](../../Sources/NXLibrary/Views/Components/SteamPlatformLogo.swift) | Logo ufficiale Steam per la piattaforma dei giochi Steam: da solo, almeno 50 pixel, spazio libero della manovella. |
| [Sources/NXLibrary/Views/Components/GameLogoArea.swift](../../Sources/NXLibrary/Views/Components/GameLogoArea.swift) | Area del logo del gioco con la geometria condivisa da Spotlight e Collection; caricamento e impostazioni restano fuori. |
| [Sources/NXLibrary/Views/Components/GamePrimaryActions.swift](../../Sources/NXLibrary/Views/Components/GamePrimaryActions.swift) | Play, Options e preferito con lo stesso aspetto e gli stessi bersagli di input per ogni fonte; i puntini di «Porting» e «Downloading». |
| [Sources/NXLibrary/Views/Components/SessionCard.swift](../../Sources/NXLibrary/Views/Components/SessionCard.swift) | Card di fine sessione: aspetta che Arcane sia davanti, compare 1,8 s dopo per 8 s; una sessione più recente sostituisce quella in attesa. |

## UI · temi, rendering e sfondi

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/Theme/ThemeStore.swift](../../Sources/NXLibrary/Views/Theme/ThemeStore.swift) | Mantiene palette attiva, wallpaper inclusi e importati e operazioni sulle scelte dell’utente. |
| [Sources/NXLibrary/Views/Theme/SeleneTheme.swift](../../Sources/NXLibrary/Views/Theme/SeleneTheme.swift) | Espone colori, stili, curve di animazione, focus e chiavi dell’ambiente Selene. |
| [Sources/NXLibrary/Views/Theme/SeleneFonts.swift](../../Sources/NXLibrary/Views/Theme/SeleneFonts.swift) | Registra il font incluso e definisce MaterialIconView. |
| [Sources/NXLibrary/Views/Theme/SeleneCanvasEnvironment.swift](../../Sources/NXLibrary/Views/Theme/SeleneCanvasEnvironment.swift) | Pubblica il canvas della finestra e applica unità e font scalati. |
| [Sources/NXLibrary/Views/Theme/SeleneBackdrop.swift](../../Sources/NXLibrary/Views/Theme/SeleneBackdrop.swift) | Nella shell dichiara la richiesta di sfondo condiviso, fuori dalla shell disegna; consuma lo snapshot completo della palette e compone gradiente, wallpaper e Moonlight a particelle morbide; conserva le immagini decodificate e il fallback statico. |
| [Sources/NXLibrary/Views/Theme/MoonlightRenderer.swift](../../Sources/NXLibrary/Views/Theme/MoonlightRenderer.swift) | Gestisce Metal, display link e rendering live/statico; su entrambi i percorsi il primo drawable presentato sblocca `LaunchReveal`. Da macOS 14 disegna solo il `CAMetalDisplayLink`, anche il frame fermo; nella Dev registra creazione e prima presentazione. |
| [Sources/NXLibrary/Views/Theme/MoonlightShaders.swift](../../Sources/NXLibrary/Views/Theme/MoonlightShaders.swift) | Contiene gli shader Metal del Moonlight, superfici analitiche Arcane/Flow, filamenti sottili antialias piegati da onde viaggianti e particelle morbide, compilati a runtime. |
| [Sources/NXLibrary/Views/Theme/LiveBackdrop.swift](../../Sources/NXLibrary/Views/Theme/LiveBackdrop.swift) | Integra video AVFoundation in loop e adatta riproduzione e frame alla visibilità della finestra. |
| [Sources/NXLibrary/Views/Theme/OnlineBrowsePanel.swift](../../Sources/NXLibrary/Views/Theme/OnlineBrowsePanel.swift) | Mantiene stato di ricerca e download e presenta griglia e miniature degli sfondi online. |
| [Sources/NXLibrary/Views/Theme/ThemePickerView.swift](../../Sources/NXLibrary/Views/Theme/ThemePickerView.swift) | Presenta i colori con anteprima viva nel primo passo; sfondi, provider e destinazione nel passo successivo. |
| [Sources/NXLibrary/Views/Theme/ThemePreview.swift](../../Sources/NXLibrary/Views/Theme/ThemePreview.swift) | Disegna un’anteprima della home con palette, sfondo e particelle morbide; il movimento segue le preferenze. |
| [Sources/NXLibrary/Views/Theme/AppLocaleEnvironment.swift](../../Sources/NXLibrary/Views/Theme/AppLocaleEnvironment.swift) | Contesto della lingua reattivo per le viste; conserva identità, selezione e focus. |

## UI · fonti, Steam e libreria mista

| File | Responsabilità |
|---|---|
| [AppViewModel+Catalog.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Catalog.swift) | Rilettura, errori e retry del risultato di build senza libreria di ripiego. |
| [CatalogPersonalizationsEnvironment.swift](../../Sources/NXLibrary/Views/Theme/CatalogPersonalizationsEnvironment.swift) | Dipendenza SwiftUI esplicita per le chiavi personali stabili. |
| [AppViewModel+Sources.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Sources.swift) | Proiezione visibile, selezione comune e modifiche personali tipizzate. |
| [SettingsSourcesSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsSourcesSection.swift) | Attivazione, refresh/cancel, cartella Steam, avvio in background, revisione e recupero dei nascosti. |
| [CatalogNativeArtwork.swift](../../Sources/NXLibrary/Views/Catalog/CatalogNativeArtwork.swift) | Icona nativa in sola lettura e indicatore Steam; nessun artwork Nintendo. |
| [CatalogSteamInfo.swift](../../Sources/NXLibrary/Views/Catalog/CatalogSteamInfo.swift) | Intestazione condivisa nelle due librerie: Play/Riprendi/Annulla/Riprova, Opzioni e preferito, con la nota di stato. |
| [SteamPlayCoordinator.swift](../../Sources/NXLibrary/Services/SteamPlayCoordinator.swift) | Play tramite il client verificato dopo la preparazione della schermata. La schermata copre Steam durante l'attesa. Sessioni dal processo dell’app installata. |
| [SteamPlaytimeCoordinator.swift](../../Sources/NXLibrary/Services/SteamPlaytimeCoordinator.swift) | Una lettura alla volta delle ore di Steam fuori dal thread principale; applica `SteamPlaytimeSync` e passa i totali a `PlaySessionStore`. |
| [SteamOptionsView.swift](../../Sources/NXLibrary/Views/GameOptions/SteamOptionsView.swift) | Opzioni di un gioco Steam con l’aspetto e l’input di Game options: Play, Edit details, Move, preferito, nascosto, Finder. |
| [PersonalizationSubject.swift](../../Sources/NXLibrary/Views/GameOptions/PersonalizationSubject.swift) | Il gioco che Change artwork e Change metadata personalizzano: scelte nxnative o archivio personale Steam, senza icona Mac per Steam. |
| [SteamGamePage.swift](../../Sources/NXLibrary/Views/Catalog/SteamGamePage.swift) | Dati store Steam dei giochi a schermo, una copia condivisa da Spotlight e Collection, per AppID e lingua; una risposta per un gioco o una lingua non più chiesti si scarta; offline mostra il testo di un'altra lingua con l'avviso. |
| [SteamArtwork.swift](../../Sources/NXLibrary/Views/Catalog/SteamArtwork.swift) | Immagini Steam con cache disponibile prima del task, identità di richiesta/build e ripiego già letto; rivalidazione dei file, scelte personali, annullamento e `TileArtPendingKey`. |
| [SteamPersonalizations.swift](../../Sources/NXLibrary/Views/Catalog/SteamPersonalizations.swift) | Archivio delle scelte personali Steam (metadati e artwork), modificate da Change artwork e Change metadata. |

## UI · achievement

| File | Responsabilità |
|---|---|
| [SteamAchievementsStore.swift](../../Sources/NXLibrary/Services/SteamAchievementsStore.swift) | Legge gli achievement fuori dal thread principale (selezione, apertura della schermata e, per il gioco selezionato, fine di una sessione Steam: subito e dopo un minuto), uno per AppID alla volta; tiene gli ultimi 16 giochi e aggiunge la rarità quando arriva. |
| [ArcaneOrbVideo.swift](../../Sources/NXLibrary/Views/Spotlight/ArcaneOrbVideo.swift) | L'Arcane della card come video: grigio e fermo a riposo, a colori e in movimento con hover o focus, si ferma sul suo fotogramma e riparte da lì; colore, luce e scala animati da Core Animation. Usato anche, grande e sempre attivo, in testa alla schermata Achievements quando l'Arcane è conquistato. |
| [DetailsAchievementsCard.swift](../../Sources/NXLibrary/Views/Detail/DetailsAchievementsCard.swift) | Card Achievements in cima alla colonna destra della pagina, sopra il pannello Details; prende il focus e apre la schermata. |
| [AchievementIcon.swift](../../Sources/NXLibrary/Views/Detail/AchievementIcon.swift) | Icona di un achievement dalla cache di `SteamMetadataService`, decodificata fuori dal thread principale e tenuta in memoria (niente lampo quando una riga torna in vista), con un riquadro neutro finché manca; un segreto non sbloccato è sfocato sotto un lucchetto. |
| [AchievementsScreen.swift](../../Sources/NXLibrary/Views/Spotlight/AchievementsScreen.swift) | Schermata Achievements sopra l’arte del gioco, impaginata come Selene: logo e sbloccati di recente a sinistra; a destra i cristalli per tier con sotto percentuale, barra larga quanto i quattro cristalli e conteggio (`TrophyColumn`), oppure, a gioco completato, il medaglione dell’Arcane (video, nome, conteggio e piccoli cristalli Oro/Argento/Bronzo); filtri tra LB e RB (Q/E su tastiera), ordine (Y) in basso a destra accanto a Open, con Q/E e LB/RB compatti ai lati delle categorie e barra alla posizione condivisa; lista e sfumatura lasciano libera la fascia dei comandi e lista in una colonna mossa da un offset proprio (niente ScrollView), disegnando solo le righe in vista. |
| [AchievementDetail.swift](../../Sources/NXLibrary/Views/Spotlight/AchievementDetail.swift) | Dettaglio di un obiettivo come medaglione (A sulla riga o clic sulla riga in focus): icona grande con il cristallo della tier come piccolo distintivo sull’angolo, nome e descrizione interi centrati, percentuale dei giocatori, data di sblocco; le frecce scorrono la lista, A/B o un clic fuori chiudono. |
| [TierCrystal.swift](../../Sources/NXLibrary/Views/Spotlight/TierCrystal.swift) | Il cristallo di una tier dalle risorse del Core, decodificato una volta; non ancora ottenuto, tenue con una traccia del suo colore, così oro, argento e bronzo restano distinguibili. |
| [AchievementsScreenModel.swift](../../Sources/NXLibrary/ViewModels/AchievementsScreenModel.swift) | Schermata Achievements aperta: selezione, filtro, input e scorrimento della lista; un riferimento, così un passo non ridisegna la Spotlight sotto. Dopo la rotella la prima freccia porta il fuoco alla riga in vista più vicina. |
| [ListScroll.swift](../../Sources/NXLibrary/ViewModels/ListScroll.swift) | Offset di una lista (`TextScroll`) con la planata del pannello delle mod: rotella, trackpad e frecce muovono lo stesso valore. |

## Test e fixture

| File | Responsabilità aggiuntiva |
|---|---|
| [Tests/NXLibraryCoreTests/SettingsRowActionTests.swift](../../Tests/NXLibraryCoreTests/SettingsRowActionTests.swift) | Regressioni per giochi omonimi e azioni secondarie della medesima riga. |
| [Tests/NXLibraryCoreTests/ScreenshotFallbackTests.swift](../../Tests/NXLibraryCoreTests/ScreenshotFallbackTests.swift) | Screenshot LaunchBox cercati una volta e conservati, precedenza di quelli propri e dimensione piena della scelta. |
| [Tests/NXLibraryCoreTests/SteamGridDBArtTests.swift](../../Tests/NXLibraryCoreTests/SteamGridDBArtTests.swift) | Chiave privata, richieste con la chiave solo a SteamGridDB, crediti, anteprime e ricerca da Browse online. |
| [Tests/PublicationChecks/test_publication.py](../../Tests/PublicationChecks/test_publication.py) | Esegue il controllo reale in repository temporanee: sorgenti consentiti, file vietati, chiavi sintetiche senza esposizione e runtime non corrispondente al lock. |
| [Tests/PublicationChecks/test_update_archive.py](../../Tests/PublicationChecks/test_update_archive.py) | Verifica il controllo ZIP reale con bundle sintetici, symlink, percorsi non sicuri, collisioni Unicode, header incoerenti e dimensioni eccessive. |

| File | Responsabilità |
|---|---|
| [Tests/NXLibraryCoreTests/ActivitySummaryTests.swift](../../Tests/NXLibraryCoreTests/ActivitySummaryTests.swift) | Totali settimanali, distribuzione giornaliera, sessioni aperte e passaggi di mezzanotte. |
| [Tests/NXLibraryCoreTests/AppBundleRenameTests.swift](../../Tests/NXLibraryCoreTests/AppBundleRenameTests.swift) | Rinomina alla chiusura: nome vecchio, `Arcane.app` già presente, cartella in sola lettura, copia Dev, traslocata o occupata, altri nomi, spostamento fallito. |
| [Tests/NXLibraryCoreTests/AppRouterTests.swift](../../Tests/NXLibraryCoreTests/AppRouterTests.swift) | Route iniziale, ritorno, overlay, richieste Spotlight e precedenza/occlusione delle coperture fullscreen. |
| [Tests/NXLibraryCoreTests/AppSettingsStoreTests.swift](../../Tests/NXLibraryCoreTests/AppSettingsStoreTests.swift) | Default, errori, recupero, compatibilità e ultima selezione persistita in background e alla chiusura, senza invalidare gli osservatori. |
| [Tests/NXLibraryCoreTests/AppSizeCacheTests.swift](../../Tests/NXLibraryCoreTests/AppSizeCacheTests.swift) | Riuso delle dimensioni, invalidazione sui bundle modificati e scansione senza falso stato vuoto. |
| [Tests/NXLibraryCoreTests/AppUpdateTests.swift](../../Tests/NXLibraryCoreTests/AppUpdateTests.swift) | Versioni, asset release, requisiti, digest, identità del bundle, collisioni con copie esistenti e guasti di copia, scambio e Cestino. |
| [Tests/NXLibraryCoreTests/AppUpdatePresentationTests.swift](../../Tests/NXLibraryCoreTests/AppUpdatePresentationTests.swift) | Verifica che i controlli manuali non permettano sostituzioni di copie di sviluppo, in sola lettura o con una versione uguale/più recente. |
| [Tests/NXLibraryCoreTests/ArcaneWelcomeTests.swift](../../Tests/NXLibraryCoreTests/ArcaneWelcomeTests.swift) | Una volta dopo l'aggiornamento, mai dopo un primo Setup né con un recupero in corso, decodifica di un file vecchio, offerta di Steam, focus e uscite. |
| [Tests/NXLibraryCoreTests/ShellOverlayInputTests.swift](../../Tests/NXLibraryCoreTests/ShellOverlayInputTests.swift) | Ogni monitor della tastiera che cede all'offerta di aggiornamento cede anche al benvenuto, così Invio non arriva alla schermata sotto. |
| [Tests/NXLibraryCoreTests/ArcaneNameTests.swift](../../Tests/NXLibraryCoreTests/ArcaneNameTests.swift) | Nessun testo del catalogo, in nessuna lingua, mostra il vecchio nome; User-Agent con il nome Arcane e nessuna sorgente con il vecchio. |
| [Tests/NXLibraryCoreTests/ArtworkPickerFocusTests.swift](../../Tests/NXLibraryCoreTests/ArtworkPickerFocusTests.swift) | Spostamenti nella griglia dei candidati e passaggi fra slot di artwork. |
| [Tests/NXLibraryCoreTests/ArtworkPickerTests.swift](../../Tests/NXLibraryCoreTests/ArtworkPickerTests.swift) | Decodifica Title DB, candidati per slot e scelte manuali. |
| [Tests/NXLibraryCoreTests/AutomaticIconTests.swift](../../Tests/NXLibraryCoreTests/AutomaticIconTests.swift) | Priorità delle fonti, ambiguità, edizioni, cache offline, immagini invalide e opt-out del sito. |
| [Tests/NXLibraryCoreTests/ArtworkStoreTests.swift](../../Tests/NXLibraryCoreTests/ArtworkStoreTests.swift) | Cache, download, immagini trasparenti, ridimensionamento e fallback. |
| [Tests/NXLibraryCoreTests/BoxArtServiceTests.swift](../../Tests/NXLibraryCoreTests/BoxArtServiceTests.swift) | Matching GameTDB, regioni e durata delle ricerche senza risultato. |
| [Tests/NXLibraryCoreTests/BuildCommandBuilderTests.swift](../../Tests/NXLibraryCoreTests/BuildCommandBuilderTests.swift) | Contratto CLI, opzioni runtime/build e propagazione dell’override Metal. |
| [Tests/NXLibraryCoreTests/BuildEventParserTests.swift](../../Tests/NXLibraryCoreTests/BuildEventParserTests.swift) | Eventi JSON, fasi, percentuali e righe ordinarie di log. |
| [Tests/NXLibraryCoreTests/BuildOutputInstallerTests.swift](../../Tests/NXLibraryCoreTests/BuildOutputInstallerTests.swift) | Pubblicazione atomica, interruzioni, tentativi ripetuti, copie fra volumi e conservazione dei bundle in caso di errore. |
| [Tests/NXLibraryCoreTests/BuildScratchTests.swift](../../Tests/NXLibraryCoreTests/BuildScratchTests.swift) | Posto dei file di build per Mac, disco esterno, exFAT e workspaces spostati; workspace gestiti e cartelle temporanee. |
| [Tests/NXLibraryCoreTests/BuildServiceTests.swift](../../Tests/NXLibraryCoreTests/BuildServiceTests.swift) | Processi, eventi, cancellazione, lease e conservazione della build dopo un errore d’installazione, con retry senza nuova esecuzione del motore; un avvio fallito non lascia file aperti. |
| [Tests/NXLibraryCoreTests/GameAppDestinationTests.swift](../../Tests/NXLibraryCoreTests/GameAppDestinationTests.swift) | Installazione e scoperta nella cartella scelta, rebuild dopo il cambio cartella, conflitti di nome, sorgenti protette e cartelle non disponibili o di sola lettura. |
| [Tests/NXLibraryCoreTests/ButtonPromptsTests.swift](../../Tests/NXLibraryCoreTests/ButtonPromptsTests.swift) | Etichette e simboli per tastiera, controller e scelte esplicite dell’utente. |
| [Tests/NXLibraryCoreTests/CheatCopyTests.swift](../../Tests/NXLibraryCoreTests/CheatCopyTests.swift) | Testi di intestazione, rifiuto, conferma e rimozione dei cheats. |
| [Tests/NXLibraryCoreTests/CheatFileTests.swift](../../Tests/NXLibraryCoreTests/CheatFileTests.swift) | Parsing dei codici secondo il motore, sezioni, metadati, nomi duplicati e codici non validi. |
| [Tests/NXLibraryCoreTests/CheatInstallTests.swift](../../Tests/NXLibraryCoreTests/CheatInstallTests.swift) | Build ID, title ID, file senza nome, cartelle e decisioni di installazione. |
| [Tests/NXLibraryCoreTests/CheatLocatorTests.swift](../../Tests/NXLibraryCoreTests/CheatLocatorTests.swift) | Identità nel bundle e precedenza dei percorsi cheats e delle variabili del launcher. |
| [Tests/NXLibraryCoreTests/CheatStatusTests.swift](../../Tests/NXLibraryCoreTests/CheatStatusTests.swift) | Ancestry del motore, necessità di rebuild, valore della riga e indicatore attivo. |
| [Tests/NXLibraryCoreTests/CheatStoreTests.swift](../../Tests/NXLibraryCoreTests/CheatStoreTests.swift) | Installazione, enabled, master switch, sostituzione e metadati dei file cheats. |
| [Tests/NXLibraryCoreTests/ModStoreTests.swift](../../Tests/NXLibraryCoreTests/ModStoreTests.swift) | Ordine, acceso/spento, limite dell'overlay, conflitti, Cestino e righe dell'`env.txt` delle mod. |
| [Tests/NXLibraryCoreTests/ModFolderScannerTests.swift](../../Tests/NXLibraryCoreTests/ModFolderScannerTests.swift) | Voci della cartella mods, layout `romfs`/Atmosphère, symlink, file relativi e file nascosti. |
| [Tests/NXLibraryCoreTests/EnvFileEditorTests.swift](../../Tests/NXLibraryCoreTests/EnvFileEditorTests.swift) | Modifica di una chiave dell'`env.txt`: commenti, duplicati, CRLF, merge al lancio. |
| [Tests/NXLibraryCoreTests/GameBananaAPITests.swift](../../Tests/NXLibraryCoreTests/GameBananaAPITests.swift) | Decodifica tollerante delle risposte, URL, host fidati, contenuto degli archivi e testo dalle descrizioni. |
| [Tests/NXLibraryCoreTests/GameBananaClientTests.swift](../../Tests/NXLibraryCoreTests/GameBananaClientTests.swift) | User-Agent, durata della cache, rete assente, errori del server, limite di richieste e cache immagini. |
| [Tests/NXLibraryCoreTests/GameBananaBandModelTests.swift](../../Tests/NXLibraryCoreTests/GameBananaBandModelTests.swift) | Cambio di gioco, avanzi di installazione, ricerca per nome con controller, mod in due gruppi con l'arte pronta. |
| [Tests/NXLibraryCoreTests/TextScrollTests.swift](../../Tests/NXLibraryCoreTests/TextScrollTests.swift) | Descrizione dopo Read more, limiti dello scorrimento, riga mostrata intera e passo Su/Giù tra le righe. |
| [Tests/NXLibraryCoreTests/GameBananaMatchTests.swift](../../Tests/NXLibraryCoreTests/GameBananaMatchTests.swift) | Abbinamento per nome, voci per piattaforma e memoria della scelta. |
| [Tests/NXLibraryCoreTests/ModSupportTests.swift](../../Tests/NXLibraryCoreTests/ModSupportTests.swift) | Quali archivi funzionano, radice `romfs`, title ID, visibilità e nomi di cartella. |
| [Tests/NXLibraryCoreTests/AvailableModsFinderTests.swift](../../Tests/NXLibraryCoreTests/AvailableModsFinderTests.swift) | Mod che funzionano in ordine, limiti di ricerca, rete assente e aggiornamenti. |
| [Tests/NXLibraryCoreTests/ModInstallerTests.swift](../../Tests/NXLibraryCoreTests/ModInstallerTests.swift) | Installazione con archivi veri: MD5, percorsi pericolosi, mod di codice, errori, gioco aperto, spazio, nomi, aggiornamenti. |
| [Tests/NXLibraryCoreTests/CloudSavesTests.swift](../../Tests/NXLibraryCoreTests/CloudSavesTests.swift) | Cartelle cloud, preferenze per gioco e decodifica delle impostazioni precedenti. |
| [Tests/NXLibraryCoreTests/CompatibilityCheckerTests.swift](../../Tests/NXLibraryCoreTests/CompatibilityCheckerTests.swift) | Commit, modifiche ammesse nel checkout, Metal, CLI e override del gate. |
| [Tests/NXLibraryCoreTests/ConnectivityWatcherTests.swift](../../Tests/NXLibraryCoreTests/ConnectivityWatcherTests.swift) | Solo il passaggio da offline a online conta come ritorno della connessione; la prima lettura no. |
| [Tests/NXLibraryCoreTests/DetailsFocusTests.swift](../../Tests/NXLibraryCoreTests/DetailsFocusTests.swift) | Spostamento nelle bande di Details, limiti e sezioni vuote. |
| [Tests/NXLibraryCoreTests/DirectorySizeTests.swift](../../Tests/NXLibraryCoreTests/DirectorySizeTests.swift) | Somma dei file regolari ignorando nascosti e collegamenti; cartella mancante a zero. |
| [Tests/NXLibraryCoreTests/DiagnosticsReportTests.swift](../../Tests/NXLibraryCoreTests/DiagnosticsReportTests.swift) | Rimozione di percorsi personali e chiavi e contenuto delle sezioni diagnostiche. |
| [Tests/NXLibraryCoreTests/EngineLocationTests.swift](../../Tests/NXLibraryCoreTests/EngineLocationTests.swift) | Percorso predefinito, cartella scelta e fallback quando scompare. |
| [Tests/NXLibraryCoreTests/EngineToolchainTests.swift](../../Tests/NXLibraryCoreTests/EngineToolchainTests.swift) | Rilevamento del runtime incluso e fallback a Python e strumenti del checkout. |
| [Tests/NXLibraryCoreTests/EnvironmentTests.swift](../../Tests/NXLibraryCoreTests/EnvironmentTests.swift) | Parsing di Metal e controlli dell’ambiente mediante runner sintetico. |
| [Tests/NXLibraryCoreTests/FocusIndexTests.swift](../../Tests/NXLibraryCoreTests/FocusIndexTests.swift) | Movimento limitato agli elementi della lista e liste vuote. |
| [Tests/NXLibraryCoreTests/GameDetailPresentationTests.swift](../../Tests/NXLibraryCoreTests/GameDetailPresentationTests.swift) | Disponibilità di build e sorgenti e formattazione di metadati e azioni Details. |
| [Tests/NXLibraryCoreTests/GameResourceStateTests.swift](../../Tests/NXLibraryCoreTests/GameResourceStateTests.swift) | App spostata e ripristinata, input assenti, Play senza sorgenti e conservazione di workspace e build attive durante Refresh. |
| [Tests/NXLibraryCoreTests/GameOptionsPresentationTests.swift](../../Tests/NXLibraryCoreTests/GameOptionsPresentationTests.swift) | Ordine delle righe, focus, visibilità dei controlli e valori runtime. |
| [Tests/NXLibraryCoreTests/GameRuntimeConfigTests.swift](../../Tests/NXLibraryCoreTests/GameRuntimeConfigTests.swift) | Review di giochi nuovi ed esistenti, persistenza, lingua del rebuild e conversione DM_* con merge di env.txt. |
| [Tests/NXLibraryCoreTests/GameTDBTests.swift](../../Tests/NXLibraryCoreTests/GameTDBTests.swift) | Database, normalizzazione dei nomi, regioni e matching delle copertine. |
| [Tests/NXLibraryCoreTests/HoldDetectorTests.swift](../../Tests/NXLibraryCoreTests/HoldDetectorTests.swift) | Soglia temporale e distinzione fra pressione breve e prolungata. |
| [Tests/NXLibraryCoreTests/ImportServiceTests.swift](../../Tests/NXLibraryCoreTests/ImportServiceTests.swift) | Riconoscimento dei bundle nxnative e normalizzazione degli identificativi. |
| [Tests/NXLibraryCoreTests/CursorIdleTests.swift](../../Tests/NXLibraryCoreTests/CursorIdleTests.swift) | Ritardo del cursore, ripristino e ripartenza dopo interruzione o attività del mouse. |
| [Tests/NXLibraryCoreTests/InstallProgressTests.swift](../../Tests/NXLibraryCoreTests/InstallProgressTests.swift) | Fasi Git, percentuali, byte e ricomposizione delle righe parziali. |
| [Tests/NXLibraryCoreTests/KeyCheckTests.swift](../../Tests/NXLibraryCoreTests/KeyCheckTests.swift) | Cifratura e lettura delle intestazioni sintetiche e chiavi richieste dalle sorgenti. |
| [Tests/NXLibraryCoreTests/KeyStoreTests.swift](../../Tests/NXLibraryCoreTests/KeyStoreTests.swift) | Importazione e sostituzione atomica, conservazione della copia precedente in caso di errore, permessi 0600 e riepilogo. |
| [Tests/NXLibraryCoreTests/LaunchServiceTests.swift](../../Tests/NXLibraryCoreTests/LaunchServiceTests.swift) | Scrittura dell’ambiente, avvio del bundle e propagazione degli errori. |
| [Tests/NXLibraryCoreTests/LauncherSettingsTests.swift](../../Tests/NXLibraryCoreTests/LauncherSettingsTests.swift) | Metadati launcher.json e fallback dei controlli per build precedenti. |
| [Tests/NXLibraryCoreTests/LaunchBoxArtTests.swift](../../Tests/NXLibraryCoreTests/LaunchBoxArtTests.swift) | Risultati di ricerca, scelta della voce Switch/Switch 2, payload Nuxt con file pieni e screenshot. |
| [Tests/NXLibraryCoreTests/LibraryPresentationTests.swift](../../Tests/NXLibraryCoreTests/LibraryPresentationTests.swift) | Formattazione dei metadati e delle statistiche della libreria. |
| [Tests/NXLibraryCoreTests/LibraryQueryTests.swift](../../Tests/NXLibraryCoreTests/LibraryQueryTests.swift) | Filtri, ricerca, ordinamento e rapporto con la cronologia di gioco. |
| [Tests/NXLibraryCoreTests/NXNativeCatalogPersistenceTests.swift](../../Tests/NXLibraryCoreTests/NXNativeCatalogPersistenceTests.swift) | Persistenza e merge nxnative attraverso il repository attuale: sorgenti, impostazioni, preferiti, installazioni in attesa e dettagli degli errori. Recupero e conversione legacy sono verificati da CatalogStoreTests. |
| [Tests/NXLibraryCoreTests/MaterialIconTests.swift](../../Tests/NXLibraryCoreTests/MaterialIconTests.swift) | Integrità dei glifi e del font delle icone. |
| [Tests/NXLibraryCoreTests/MetadataPickerTests.swift](../../Tests/NXLibraryCoreTests/MetadataPickerTests.swift) | Alternative per campo, override persistiti e applicazione ai metadati del gioco. |
| [Tests/NXLibraryCoreTests/MoonlightFieldTests.swift](../../Tests/NXLibraryCoreTests/MoonlightFieldTests.swift) | Generazione deterministica e limiti dei dati delle particelle. |
| [MoonlightAppearanceTests.swift](../../Tests/NXLibraryCoreTests/MoonlightAppearanceTests.swift) | Ignora la preferenza storica delle particelle senza perdere altri valori; continuità del ciclo e bordi della griglia colori. |
| [Tests/NXLibraryCoreTests/MoreArtworkSourcesTests.swift](../../Tests/NXLibraryCoreTests/MoreArtworkSourcesTests.swift) | Matching dei titoli e risposte delle sorgenti artwork aggiuntive. |
| [Tests/NXLibraryCoreTests/MoreLikeThisTests.swift](../../Tests/NXLibraryCoreTests/MoreLikeThisTests.swift) | Ranking condiviso, precedenza Steam e ripiego Switch, giochi nascosti e metadati incompleti. |
| [Tests/NXLibraryCoreTests/NintendoStoreMetadataTests.swift](../../Tests/NXLibraryCoreTests/NintendoStoreMetadataTests.swift) | Decodifica store e Title DB, cache, screenshot e risposte incomplete. |
| [Tests/NXLibraryCoreTests/ReleaseNotesLayoutTests.swift](../../Tests/NXLibraryCoreTests/ReleaseNotesLayoutTests.swift) | Titoli, voci e righe vuote delle note di release, una voce per riga. |
| [Tests/NXLibraryCoreTests/NewestEngineTests.swift](../../Tests/NXLibraryCoreTests/NewestEngineTests.swift) | Lock e Metal di main, validità della scelta, comandi git del cambio, gate Newest engine, scheda Setup e frase. |
| [Tests/NXLibraryCoreTests/NUPSourceCatalogTests.swift](../../Tests/NXLibraryCoreTests/NUPSourceCatalogTests.swift) | NUP storici, multiprogramma e soli update; identità DLC, JSON, capacità checkout, programma zero nei vecchi record e argv coerenti. |
| [Tests/NXLibraryCoreTests/NXNativeGameSettingsTests.swift](../../Tests/NXLibraryCoreTests/NXNativeGameSettingsTests.swift) | Build senza adattatore, migrazione da env.txt, scrittura dei soli valori diversi dal default e chiavi fissate. |
| [Tests/NXLibraryCoreTests/OnlineArtworkSourcesTests.swift](../../Tests/NXLibraryCoreTests/OnlineArtworkSourcesTests.swift) | Ricerca Steam e loghi MediaWiki/Commons con risposte sintetiche. |
| [Tests/NXLibraryCoreTests/OnlineBackgroundsTests.swift](../../Tests/NXLibraryCoreTests/OnlineBackgroundsTests.swift) | Parser degli sfondi fissi, risoluzioni, crediti e nomi dei download. |
| [Tests/NXLibraryCoreTests/OnlineLiveSourcesTests.swift](../../Tests/NXLibraryCoreTests/OnlineLiveSourcesTests.swift) | Parser e indirizzi dei provider di sfondi video. |
| [Tests/NXLibraryCoreTests/PendingInstallTests.swift](../../Tests/NXLibraryCoreTests/PendingInstallTests.swift) | Staging, installazione e cartelle da conservare; riapertura e scansione prima di completare un’installazione già pubblicata. |
| [Tests/NXLibraryCoreTests/PlaySessionStoreTests.swift](../../Tests/NXLibraryCoreTests/PlaySessionStoreTests.swift) | Persistenza, durata, heartbeat e riconciliazione delle sessioni. |
| [Tests/NXLibraryCoreTests/PortedGameTests.swift](../../Tests/NXLibraryCoreTests/PortedGameTests.swift) | Modello del gioco, compatibilità dei record e condizioni di disponibilità dell’app. |
| [Tests/NXLibraryCoreTests/PortingFailureReasonTests.swift](../../Tests/NXLibraryCoreTests/PortingFailureReasonTests.swift) | Classificazione dei fallimenti e corrispondenza con i messaggi del pin, anche da un checkout separato scelto con NX_TEST_ENGINE_REPO. |
| [Tests/NXLibraryCoreTests/PortingNoticeTests.swift](../../Tests/NXLibraryCoreTests/PortingNoticeTests.swift) | Condizioni e testi delle notifiche di esito del porting. |
| [Tests/NXLibraryCoreTests/PortingPresentationTests.swift](../../Tests/NXLibraryCoreTests/PortingPresentationTests.swift) | ETA, attività del prewarm senza stime storiche, tile, pill e rappresentazione dei fallimenti del porting. |
| [Tests/NXLibraryCoreTests/AppIconPreferenceTests.swift](../../Tests/NXLibraryCoreTests/AppIconPreferenceTests.swift) | Ambito dell’icona: scelta esplicita, vecchie librerie, scansioni, persistenza e rebuild. |
| [Tests/NXLibraryCoreTests/AppIconProgressTests.swift](../../Tests/NXLibraryCoreTests/AppIconProgressTests.swift) | Verifica che l'esito di un'icona mancante non sovrascriva il log o segnali una build fallita. |
| [Tests/NXLibraryCoreTests/IconLaunchWaitTests.swift](../../Tests/NXLibraryCoreTests/IconLaunchWaitTests.swift) | Attesa Play: successo, errore, annullamento, gioco diverso e nuova firma in coda. |
| [Tests/NXLibraryCoreTests/PipelineArchiveProgressTests.swift](../../Tests/NXLibraryCoreTests/PipelineArchiveProgressTests.swift) | Log obsoleti, righe incomplete, cache riusata, gruppi paralleli e GPU diverse. |
| [Tests/NXLibraryCoreTests/PortingProgressTests.swift](../../Tests/NXLibraryCoreTests/PortingProgressTests.swift) | Aggregazione delle fasi, avanzamento monotono, peso degli shader e avvisi di archivio/prewarm. |
| [Tests/NXLibraryCoreTests/ProdKeysLocationsTests.swift](../../Tests/NXLibraryCoreTests/ProdKeysLocationsTests.swift) | Selezione e validazione dei possibili percorsi delle chiavi. |
| [Tests/NXLibraryCoreTests/RunningGamesTests.swift](../../Tests/NXLibraryCoreTests/RunningGamesTests.swift) | Associazione bundle ID, applicazioni aperte e voci della libreria. |
| [Tests/NXLibraryCoreTests/RyujinxSaveImportTests.swift](../../Tests/NXLibraryCoreTests/RyujinxSaveImportTests.swift) | Contenitori e slot Ryujinx, identità del titolo e importazioni con strutture e destinazioni differenti. |
| [Tests/NXLibraryCoreTests/SaveLocationTests.swift](../../Tests/NXLibraryCoreTests/SaveLocationTests.swift) | Identificativi, percorsi sicuri, precedenze dell’ambiente e cloud effettivo. |
| [Tests/NXLibraryCoreTests/SaveOperationGateTests.swift](../../Tests/NXLibraryCoreTests/SaveOperationGateTests.swift) | Lease per titolo, esclusione globale dell’updater, operazioni concorrenti e recupero bloccato senza I/O attivo. |
| [Tests/NXLibraryCoreTests/SavePresentationTests.swift](../../Tests/NXLibraryCoreTests/SavePresentationTests.swift) | Azioni e messaggi del pannello; distingue backup storico/completo e limite cloud. |
| [Tests/NXLibraryCoreTests/SaveSnapshotStoreTests.swift](../../Tests/NXLibraryCoreTests/SaveSnapshotStoreTests.swift) | Inventari, xattr, integrità dei backup, staging e selezione dei backup datati. |
| [MultiuserSaveTests.swift](../../Tests/NXLibraryCoreTests/MultiuserSaveTests.swift) | Backup e restore utenti/registro, compatibilità storica, import circoscritti, fault injection e conservazione di dati cambiati da fuori. |
| [Tests/NXLibraryCoreTests/SaveTestHome.swift](../../Tests/NXLibraryCoreTests/SaveTestHome.swift) | Fixture condivisa che crea una home e un bundle sintetici in una directory temporanea dedicata. |
| [Tests/NXLibraryCoreTests/SaveTransactionTests.swift](../../Tests/NXLibraryCoreTests/SaveTransactionTests.swift) | Sostituzioni, interruzioni, rollback, modifiche esterne e compatibilità dei journal precedenti. |
| [Tests/NXLibraryCoreTests/ScreenshotViewerStateTests.swift](../../Tests/NXLibraryCoreTests/ScreenshotViewerStateTests.swift) | Indice, avanzamento e limiti del visualizzatore screenshot. |
| [Tests/NXLibraryCoreTests/SeleneCanvasTests.swift](../../Tests/NXLibraryCoreTests/SeleneCanvasTests.swift) | Scala, centratura e conversione delle unità del canvas. |
| [Tests/NXLibraryCoreTests/SeleneImporterTests.swift](../../Tests/NXLibraryCoreTests/SeleneImporterTests.swift) | Copia delle risorse Selene e risoluzione dei cue sonori. |
| [Tests/NXLibraryCoreTests/SelenePaletteTests.swift](../../Tests/NXLibraryCoreTests/SelenePaletteTests.swift) | Lettura delle 25 palette, valori RGB e fallback storici del blu, alternative Crystal/Flow, persistenza ID, ordine e fallback. |
| [Tests/NXLibraryCoreTests/SettingsCatalogTests.swift](../../Tests/NXLibraryCoreTests/SettingsCatalogTests.swift) | Catalogo delle righe, ricerca, valori modificati, identità invariate, sezioni e gruppi in ordine, reset delle righe spostate. |
| [Tests/NXLibraryCoreTests/SetupActionsTests.swift](../../Tests/NXLibraryCoreTests/SetupActionsTests.swift) | Comandi Git del Setup e rispetto delle modifiche locali nel checkout. |
| [Tests/NXLibraryCoreTests/SetupCheckTests.swift](../../Tests/NXLibraryCoreTests/SetupCheckTests.swift) | Stati delle schede, requisiti, override e condizioni di riapertura del Setup. |
| [Tests/NXLibraryCoreTests/SetupGridTests.swift](../../Tests/NXLibraryCoreTests/SetupGridTests.swift) | Bilanciamento delle righe e spostamento del focus fra le schede. |
| [Tests/NXLibraryCoreTests/FirstRunSetupTests.swift](../../Tests/NXLibraryCoreTests/FirstRunSetupTests.swift) | Pagina iniziale, Porting, scelta Steam acceso/spento dopo interruzione, completamento e pulizia della scelta salvata, focus, scansione e ripresa. |
| [Tests/NXLibraryCoreTests/FirstRunFindingsTests.swift](../../Tests/NXLibraryCoreTests/FirstRunFindingsTests.swift) | Steam assente, solo giochi Mac pronti, zero giochi, errore/parziale distinto da assenza, annullamento e app portate contate. |
| [Tests/NXLibraryCoreTests/SmokeTests.swift](../../Tests/NXLibraryCoreTests/SmokeTests.swift) | Importabilità e versione nominale del modulo Core. |
| [Tests/NXLibraryCoreTests/WikipediaDescriptionTests.swift](../../Tests/NXLibraryCoreTests/WikipediaDescriptionTests.swift) | Quando cercare Wikipedia (lingua dal testo, scelta del giocatore, scrittura cinese, testi corti), sitelink dell'entità giusta, introduzione e link, host rifiutati, cache ed errori di rete non salvati. |
| [Tests/NXLibraryCoreTests/CriticRatingTests.swift](../../Tests/NXLibraryCoreTests/CriticRatingTests.swift) | Abbinamenti esatti, metriche e piattaforme, stelle proporzionali, cache offline, richieste seriali/condivise, errori e annullamento delle valutazioni. |
| [Tests/NXLibraryCoreTests/IGDBRatingTests.swift](../../Tests/NXLibraryCoreTests/IGDBRatingTests.swift) | Credenziali 0600 sintetiche, isolamento degli host, voti critica/utenti, rinnovo accesso, annullamento, cache offline e ripiego Wikidata. |
| [Tests/NXLibraryCoreTests/IGDBMetadataTests.swift](../../Tests/NXLibraryCoreTests/IGDBMetadataTests.swift) | Identità, ruoli, date precise per piattaforma, Steam, cache offline, retry, annullamento e token/coda condivisi. |
| [Tests/NXLibraryCoreTests/DatabaseMetadataTests.swift](../../Tests/NXLibraryCoreTests/DatabaseMetadataTests.swift) | Parser pubblici, identità/ambiguità, date, conteggio richieste, letture concorrenti, cache, annullamento, risposte errate e retry. |
| [Tests/NXLibraryCoreTests/SourceCatalogTests.swift](../../Tests/NXLibraryCoreTests/SourceCatalogTests.swift) | Fixture PFS0/CNMT e riconoscimento di base, aggiornamenti e DLC. |
| [Tests/NXLibraryCoreTests/EngineUpgradeSourcesTests.swift](../../Tests/NXLibraryCoreTests/EngineUpgradeSourcesTests.swift) | Copre cartelle estratte, pacchetti multipli, selezione, persistenza, bridge Python, file illeggibili e restaging senza perdita di cache o originali. |
| [Tests/NXLibraryCoreTests/SpotlightPageTests.swift](../../Tests/NXLibraryCoreTests/SpotlightPageTests.swift) | Estratti del testo e stati dello scorrimento della pagina del gioco. |
| [Tests/NXLibraryCoreTests/SpotlightRowTests.swift](../../Tests/NXLibraryCoreTests/SpotlightRowTests.swift) | Ordine, card, riordino delle tile, gioco avviato primo nell’ordine salvato e selezione Surprise. |
| [Tests/NXLibraryCoreTests/SpotlightStateTests.swift](../../Tests/NXLibraryCoreTests/SpotlightStateTests.swift) | Focus, selezione, filtri, azioni e spostamento delle tile Spotlight. |
| [Tests/NXLibraryCoreTests/SpotlightEntranceTests.swift](../../Tests/NXLibraryCoreTests/SpotlightEntranceTests.swift) | Partenze, tempi di volo e dissolvenza, bordi, durata, messaggio vuoto, avanzamento degli effetti e fasi dell’entrata; interruttore e Riduci movimento. |
| [Tests/NXLibraryCoreTests/StorageManagerTests.swift](../../Tests/NXLibraryCoreTests/StorageManagerTests.swift) | Misure per gioco, cache condivise e nascoste, pulizia selettiva, protezione di app/sorgenti/symlink, file incoerenti e volumi/cartelle non disponibili. |
| [Tests/NXLibraryCoreTests/ThemePickerTests.swift](../../Tests/NXLibraryCoreTests/ThemePickerTests.swift) | Navigazione della griglia, tab e selezione degli sfondi. |
| [Tests/NXLibraryCoreTests/ToolchainGateCopyTests.swift](../../Tests/NXLibraryCoreTests/ToolchainGateCopyTests.swift) | Testi del gate per Metal certificato, precedente, successivo e altre cause di blocco. |
| [Tests/NXLibraryCoreTests/ToolchainRequirementsTests.swift](../../Tests/NXLibraryCoreTests/ToolchainRequirementsTests.swift) | Versioni minime e identificativi degli asset Metal da scaricare. |
| [Tests/NXLibraryCoreTests/UpstreamCheckerTests.swift](../../Tests/NXLibraryCoreTests/UpstreamCheckerTests.swift) | Changelog HTTP, cache e gestione degli errori del provider. |
| [Tests/NXLibraryCoreTests/UpstreamCopyTests.swift](../../Tests/NXLibraryCoreTests/UpstreamCopyTests.swift) | Testi della riga upstream e adozione dei commit attraverso gli aggiornamenti dell’app. |
| [Tests/NXLibraryCoreTests/WallpaperBrightnessTests.swift](../../Tests/NXLibraryCoreTests/WallpaperBrightnessTests.swift) | Maschere e livelli di luminosità dello sfondo. |
| [Tests/NXLibraryCoreTests/WallpaperCatalogTests.swift](../../Tests/NXLibraryCoreTests/WallpaperCatalogTests.swift) | Catalogo dei file inclusi/importati, gruppi e tipi immagine/video. |
| [Tests/NXLibraryCoreTests/WallpaperPlacementTests.swift](../../Tests/NXLibraryCoreTests/WallpaperPlacementTests.swift) | Destinazione dello sfondo fra home e impostazioni. |
| [Tests/NXLibraryCoreTests/WorkspaceManagerTests.swift](../../Tests/NXLibraryCoreTests/WorkspaceManagerTests.swift) | Collegamenti simbolici, cache adottate e rilevamento dei link interrotti. |
| [Tests/NXLibraryCoreTests/AppIconWriterTests.swift](../../Tests/NXLibraryCoreTests/AppIconWriterTests.swift) | Icona scelta scritta e ripristinata, originale ricordato anche se assente, ricostruzione dell’app, firma fallita senza modifiche, icona rifilata e opaca. |
| [Tests/NXLibraryCoreTests/BackdropArtTests.swift](../../Tests/NXLibraryCoreTests/BackdropArtTests.swift) | Arte tenuta fra un gioco e l’altro e mai fra card e gioco, dissolvenze sull’orologio come Core Animation, livelli coperti tolti e scorrimento rapido. |
| [Tests/NXLibraryCoreTests/BoundedDownloadTests.swift](../../Tests/NXLibraryCoreTests/BoundedDownloadTests.swift) | Blocchi raccolti fino al limite, corpo o lunghezza dichiarata oltre il limite rifiutati, nessun redirect, annullamento della lettura. |
| [Tests/NXLibraryCoreTests/DetailsFactsTests.swift](../../Tests/NXLibraryCoreTests/DetailsFactsTests.swift) | Righe Details per Switch e Steam: ordine, valori mancanti o vuoti nascosti, mai la versione Steam, solo crediti durante il download, simboli. |
| [Tests/NXLibraryCoreTests/DetailsReviewFixTests.swift](../../Tests/NXLibraryCoreTests/DetailsReviewFixTests.swift) | Play costruisce un gioco non ancora costruito con le sorgenti; nome di cartella o volume letto una volta per URL. |
| [Tests/NXLibraryCoreTests/EngineRuntimeRequirementsTests.swift](../../Tests/NXLibraryCoreTests/EngineRuntimeRequirementsTests.swift) | Il runtime incluso porta ogni pacchetto Python che il motore fissato chiede (riga `pip install` del README e `tools.txt`). |
| [Tests/NXLibraryCoreTests/GameFocusTests.swift](../../Tests/NXLibraryCoreTests/GameFocusTests.swift) | Ritorno della libreria davanti solo per il gioco in primo piano, mai con un altro gioco aperto, uscita contata una volta. |
| [Tests/NXLibraryCoreTests/ModStoreModelTests.swift](../../Tests/NXLibraryCoreTests/ModStoreModelTests.swift) | Store delle mod da copia fresca o vecchia, abbinamenti incerti o sicuri, ordine della libreria, copie di un altro gioco, chiusura senza perdite. |
| [Tests/NXLibraryCoreTests/SessionSummaryTests.swift](../../Tests/NXLibraryCoreTests/SessionSummaryTests.swift) | Card di fine sessione: gioco, sessione e totale, meno di un minuto, sessioni troppo brevi o in corso, altri giochi, giochi Steam. |
| [Tests/NXLibraryCoreTests/SettingsRowButtonsTests.swift](../../Tests/NXLibraryCoreTests/SettingsRowButtonsTests.swift) | Riga con due pulsanti: Sinistra/Destra fra i pulsanti, uscita dalla riga, riga con un solo pulsante, A preme quello in focus. |
| [Tests/NXLibraryCoreTests/SpotlightRowGeometryTests.swift](../../Tests/NXLibraryCoreTests/SpotlightRowGeometryTests.swift) | Posto a schermo = camera più posto nella riga, tessere che restano ferme durante lo scorrimento, distanze costanti e quattro tessere di riserva ai bordi. |
| [Tests/NXLibraryCoreTests/TileMotionTests.swift](../../Tests/NXLibraryCoreTests/TileMotionTests.swift) | Periodi e curve di bagliore, ring e riflesso, campioni che chiudono il loop senza salti, fase nel periodo e simbolo del download. |
| [Tests/NXLibraryCoreTests/AppLocaleTests.swift](../../Tests/NXLibraryCoreTests/AppLocaleTests.swift) | Preferenze, migrazione, formati, ricerca, identità e traduzioni native; avvisi pipeline localizzati senza output tecnico grezzo. |
| [Tests/PublicationChecks/test_localizations.py](../../Tests/PublicationChecks/test_localizations.py) | Rifiuto di cataloghi incompleti e bundle senza risorse. |
| [DevelopmentProfileTests.swift](../../Tests/NXLibraryCoreTests/DevelopmentProfileTests.swift) | Copia, conservazione della sorgente, errori, sessioni, symlink e ripetizione. |
| [DevelopmentProfileEffectTests.swift](../../Tests/NXLibraryCoreTests/DevelopmentProfileEffectTests.swift) | Isolamento Dev, staging e richieste esplicite. Verifica anche che la riconciliazione delle mod conservi record e overlay dopo un errore di lettura. |
| [test_profile_boundaries.py](../../Tests/PublicationChecks/test_profile_boundaries.py) | Guardia contro percorsi/defaults del launcher non centralizzati. |
| [SteamKeyValuesTests.swift](../../Tests/NXLibraryCoreTests/SteamKeyValuesTests.swift) | Formato, escape, Unicode, duplicati, input troncati e limiti del parser. |
| [SteamPlaytimeReaderTests.swift](../../Tests/NXLibraryCoreTests/SteamPlaytimeReaderTests.swift) | Campi letti, ultima partita, scelta dell’account, duplicati e tipi errati di blocchi/scalari, file grandi, malformati o non sicuri. |
| [SteamPlaytimeBaselinesTests.swift](../../Tests/NXLibraryCoreTests/SteamPlaytimeBaselinesTests.swift) | Base mantenuta o ripartita, minuto conservato, cambio account, salvataggio e mappatura sul catalogo. |
| [SteamReturnFocusTests.swift](../../Tests/NXLibraryCoreTests/SteamReturnFocusTests.swift) | Ritorno ad Arcane solo per Play premuto qui, gioco davanti e nessun altro gioco aperto. |
| [SteamLaunchQuestionsTests.swift](../../Tests/NXLibraryCoreTests/SteamLaunchQuestionsTests.swift) | Fase `ShowInterstitials` a freddo, domande aperte o risposte subito, log per righe intere e sostituzione del file. |
| [SteamPlaytimeSyncTests.swift](../../Tests/NXLibraryCoreTests/SteamPlaytimeSyncTests.swift) | Letture con o senza account, file illeggibili, file invariato, regole di pubblicazione e coda delle letture. |
| [NativeMacApplicationTests.swift](../../Tests/NXLibraryCoreTests/NativeMacApplicationTests.swift) | Fixture native, classificazione, traversal/link, metadata non regolari e header invalidi. |
| [SteamLibrarySourceTests.swift](../../Tests/NXLibraryCoreTests/SteamLibrarySourceTests.swift) | Più fonti, dischi assenti, identità, manifest/path con campi duplicati o di tipo errato, file cambiati, limiti e assenza di scritture. |
| [SteamDiscoveryConsistencyTests.swift](../../Tests/NXLibraryCoreTests/SteamDiscoveryConsistencyTests.swift) | Mutazioni reali di inventario e app durante scan, indice inizialmente assente, budget e propagazione dell'annullamento. |
| [SteamTestSupport.swift](../../Tests/NXLibraryCoreTests/SteamTestSupport.swift) | Genera solo metadati e header sintetici nelle directory temporanee dei test. |
| [SteamPlayStateTests.swift](../../Tests/NXLibraryCoreTests/SteamPlayStateTests.swift) | Symlink, passaggio senza sessione, Play doppi e risposte tardive, rifiuti e timeout, giochi già aperti, argomenti silenziosi, pazienza di Steam a freddo e schermata di lancio. |
| [SteamBinaryKeyValuesTests.swift](../../Tests/NXLibraryCoreTests/SteamBinaryKeyValuesTests.swift) | Tipi, annidamento, fine dei dati, input troncati, tipi ignoti e limiti del parser binario. |
| [SteamAchievementReaderTests.swift](../../Tests/NXLibraryCoreTests/SteamAchievementReaderTests.swift) | Percorsi, account e file mancanti/non sicuri, lingue con ripiego anche su stringhe vuote duplicate, primo valore tipizzato, nascosti, icone, ordine numerico e file corrotti. |
| [SteamAchievementRarityTests.swift](../../Tests/NXLibraryCoreTests/SteamAchievementRarityTests.swift) | Percentuali numeriche o testuali (non numeriche scartate), host e percorso ammessi, cache di un giorno, cache vecchia offline, icone in cache, coda oltre sei download con annullamento, errore recente senza attesa e file che non sono immagini. |
| [AchievementSummaryTests.swift](../../Tests/NXLibraryCoreTests/AchievementSummaryTests.swift) | Conteggi, gioco completato, ordini dei filtri, rarità sconosciute in fondo, soglia del raro, maschera dei nascosti e icone recenti (segreti compresi). |
| [AchievementsScreenStateTests.swift](../../Tests/NXLibraryCoreTests/AchievementsScreenStateTests.swift) | Movimento in due colonne, bordi, liste vuote, cambio filtro e liste che si accorciano. |
| [GridListLayoutTests.swift](../../Tests/NXLibraryCoreTests/GridListLayoutTests.swift) | Linee, altezza, posizione delle righe, spazio da mostrare, linee visibili e riga in vista più vicina dopo la rotella. |
| [AchievementTierTests.swift](../../Tests/NXLibraryCoreTests/AchievementTierTests.swift) | Soglie, tier dalla percentuale mostrata, ordine dal più raro, conteggi per tier, Arcane solo al 100% e mai senza achievement, miglior tier ottenuto, rarità sconosciuta. |
| [SteamManifestWatcherTests.swift](../../Tests/NXLibraryCoreTests/SteamManifestWatcherTests.swift) | Filtri e durata dello stream; eventi reali da librerie tornate disponibili, da sole o accanto a una già osservata, inclusa la normalizzazione `/private`. |
| [CatalogModelTests.swift](../../Tests/NXLibraryCoreTests/CatalogModelTests.swift) | Conservazione del record precedente, proprietà comuni e separazione delle azioni per integrazione. |
| [CatalogStoreTests.swift](../../Tests/NXLibraryCoreTests/CatalogStoreTests.swift) | Conversione, backup, corruzione, versioni, input cambiati, scrittori concorrenti e guasti di pubblicazione. |
| [SteamCatalogReconcilerTests.swift](../../Tests/NXLibraryCoreTests/SteamCatalogReconcilerTests.swift) | Identità, aggiornamenti, installazioni ambigue, fonti assenti e scansioni obsolete/parziali. |
| [CatalogTestSupport.swift](../../Tests/NXLibraryCoreTests/CatalogTestSupport.swift) | Record legacy sintetico completo e scrittura di fixture; nessun contenuto di gioco. |
| [CatalogRepositoryTests.swift](../../Tests/NXLibraryCoreTests/CatalogRepositoryTests.swift) | Modifiche concorrenti, confini per integrazione, campi build e conservazione di Steam/legacy. |
| [CatalogRecoveryTests.swift](../../Tests/NXLibraryCoreTests/CatalogRecoveryTests.swift) | Recupero esplicito, conflitto legacy senza fusione, archivi, offerte obsolete, guasti di pubblicazione, restore point e importazione Dev. |
| [CatalogPersonalizationTests.swift](../../Tests/NXLibraryCoreTests/CatalogPersonalizationTests.swift) | Rinomina senza perdita del lookup e isolamento di chiavi uguali tra fonti. |
| [CatalogBuildRecoveryTests.swift](../../Tests/NXLibraryCoreTests/CatalogBuildRecoveryTests.swift) | Vecchia build persistita e nuova conservata, sospensione automatica e conferme obsolete. |
| [run_notices.py](../../Tests/CatalogAppChecks/run_notices.py) | Esegue i metodi reali degli avvisi e del ponte legacy senza finestre, dopo swift test. |
| [run_review.py](../../Tests/CatalogAppChecks/run_review.py) | Verifica achievement, loghi, focus, navigazione, lettura Mods e priorità dei dialoghi. Prova Steam che riappare durante Play e aspetta il completamento del task che gestisce il ripiego del pannello. Dati sintetici, senza finestre. |
| [run_startup_recovery.py](../../Tests/CatalogAppChecks/run_startup_recovery.py) | Coordinatore di avvio reale su profili sintetici: conflitto, scelta esplicita, offerta obsoleta, Retry e fallimento della preparazione; nessuna finestra. |
| [run_source_access.py](../../Tests/CatalogAppChecks/run_source_access.py) | Esegue il ripristino di avvio, l'observer e i selettori reali: nessuna scansione automatica dei sorgenti, cartella ricordata, annullamento e lettura dei soli file scelti; nessuna finestra o dato personale. |
| [run_onboarding.py](../../Tests/CatalogAppChecks/run_onboarding.py) | Esegue observer e ripristino del Setup, uscita durante lettura pendente con annullamento, input sotto modali, scelte acceso/spento/nil, radice della fonte, focus dopo Retry e richiesta notifiche su dati sintetici; nessuna finestra. |
| [run_artwork_return.py](../../Tests/CatalogAppChecks/run_artwork_return.py) | Viste, task e host Mods reali su fixture: primo body con arte warm, scelte personali, aggiornamenti Steam nello stesso percorso, badge dopo rimozione, cambi abbinamento e snapshot completato fuori ordine; nessuna finestra o rendering. |
| [run_nested_bundles.py](../../Tests/CatalogAppChecks/run_nested_bundles.py) | App sintetiche con bundle dati annidati e firme reali: installazione, icona, rollback, copia forzata, ripresa e rifiuto di dati alterati; nessuna UI. |
| [run_nup_programs.py](../../Tests/CatalogAppChecks/run_nup_programs.py) | Esegue il probe NUP opzionale su snapshot sintetico, convertitori UI reali, persistenza e argv del rebuild. |
| [run_save_restart.py](../../Tests/CatalogAppChecks/run_save_restart.py) | Arresti reali e nuovi processi nei checkpoint di transazione, recovery e pulizia; verifica tutti gli utenti, registro e integrità dei backup su fixture temporanee. |
| [run_entrance.py](../../Tests/CatalogAppChecks/run_entrance.py) | Esegue i metodi reali di input e readiness: nessun comando agisce o salta l’entrata prima dell’atterraggio, precedenza delle coperture, drawable mancante e presentazione su entrambi i percorsi. Nessuna finestra o GPU reale. |
| [run_icon_cache.py](../../Tests/CatalogAppChecks/run_icon_cache.py) | Esegue il vero `GameIconProvider`: un gioco senza icona non si rilegge dal disco a ogni disegno; dopo `forget` o la build si legge di nuovo. |
| [run_theme.py](../../Tests/CatalogAppChecks/run_theme.py) | Regressioni delle richieste condivise (precedenza, frame mantenuto e pausa) e del cambio palette a wallpaper/card invariati con snapshot e apply reali, ordine Look e input del selettore; shader Metal fuori schermo, colori locali GPU/Core, profilo sottile, deformazione delle onde, superfici distinte, frame fermo e uniform Mods. |
| [run_achievement_scroll.py](../../Tests/CatalogAppChecks/run_achievement_scroll.py) | Verifica fuori schermo la vera lista e i modelli durante riaperture rapide, dettagli della prima riga, ridimensionamento e Riduci movimento; nessuna finestra o automazione UI. |
| [run_game_header.py](../../Tests/CatalogAppChecks/run_game_header.py) | Esegue i corpi reali di logo e azioni condivisi senza finestra né store applicativi, per entrambi i layout. |
| [NoticeHost.swift](../../Tests/CatalogAppChecks/NoticeHost.swift) | Host minimo per i controlli applicativi, con storage reale e dati sintetici temporanei. |
| [SharedGamePresentationTests.swift](../../Tests/NXLibraryCoreTests/SharedGamePresentationTests.swift) | Presentazione Steam con identità, personalizzazioni e cronologia; prima installazione disponibile coerente per artwork e dettagli, con Play bloccato se ambiguo; confine nxnative e opzioni comuni. |
| [CatalogSourcesRepositoryTests.swift](../../Tests/NXLibraryCoreTests/CatalogSourcesRepositoryTests.swift) | Compatibilità generazioni, cambi fonte, preferenze concorrenti e adozione NX esplicita. |
| [CatalogSourcesModelTests.swift](../../Tests/NXLibraryCoreTests/CatalogSourcesModelTests.swift) | Opt-in, annullamento, cambio radice, recupero errori e intervallo tra riscansioni, misurato dagli avvii pubblicati dal modello. |
| [CatalogLibraryQueryTests.swift](../../Tests/NXLibraryCoreTests/CatalogLibraryQueryTests.swift) | Visibilità, ricerca/filtri misti e selezione per UUID senza sessioni simulate. |
| [SteamOptionsTests.swift](../../Tests/NXLibraryCoreTests/SteamOptionsTests.swift) | Righe delle opzioni Steam come quelle comuni nxnative, niente di nxnative, Play e Finder spenti senza installazione, artwork e impostazione «Keep Steam in the background». |
| [SteamMetadataTests.swift](../../Tests/NXLibraryCoreTests/SteamMetadataTests.swift) | Identità, lingue, offline, URL, concorrenza, tratti correlati in cache ed esito del salvataggio. |
| [SteamArtworkRequestTests.swift](../../Tests/NXLibraryCoreTests/SteamArtworkRequestTests.swift) | Quadrato dall’icona originale e mai dalla copertina, scelta personale prima, link che escono dal bundle ignorati, icona automatica solo senza app. |
| [SteamAutomaticIconTests.swift](../../Tests/NXLibraryCoreTests/SteamAutomaticIconTests.swift) | Quadrato LaunchBox della voce PC preso intero, scaricato una volta e conservato; nessun quadrato non si richiede di nuovo nella sessione. |
| [SteamBackdropChoiceTests.swift](../../Tests/NXLibraryCoreTests/SteamBackdropChoiceTests.swift) | Solo arte in formato schermo, ordine store → screenshot → banner, fan art LaunchBox fra store e screenshot, ripiego sulla prima immagine che si carica. |
| [test_app_bundle.py](../../Tests/PublicationChecks/test_app_bundle.py) | Verifica che il bundle del launcher rinunci a Game Mode. |

## Script di sviluppo e packaging

| File | Responsabilità |
|---|---|
| [scripts/build_app.sh](../../scripts/build_app.sh) | Compila in staging, prepara plist, runtime e risorse, verifica la firma e pubblica il bundle con sostituzione atomica. |
| [scripts/install_built_app.swift](../../scripts/install_built_app.swift) | Piccolo ingresso CLI che riusa BuildOutputInstaller per installare Arcane dopo il packaging. |
| [scripts/check_publication.py](../../scripts/check_publication.py) | Rifiuta contenuti personali o di gioco versionati e formati di segreto riconoscibili; verifica il runtime rispetto al lock prima del packaging. |
| [scripts/build_dmg.sh](../../scripts/build_dmg.sh) | Confeziona un bundle già costruito in un’immagine DMG di sviluppo. |
| [scripts/bundle_runtime.sh](../../scripts/bundle_runtime.sh) | Prepara Python e strumenti dalle versioni bloccate, verifica gli hash e firma il runtime incluso. |
| [scripts/release.sh](../../scripts/release.sh) | Controlla prerequisiti, suite Swift e tutti gli script headless delle regressioni app; produce ZIP e DMG di release, con pubblicazione esplicita opzionale. |
| [scripts/validate_update.py](../../scripts/validate_update.py) | Verifica struttura, percorsi e limiti degli archivi prima dell'estrazione, sia nel bundle sia durante il packaging delle release. |
| [scripts/relink_macho.py](../../scripts/relink_macho.py) | Riscrive riferimenti Mach-O dei binari e delle librerie affinché il runtime incluso sia rilocabile. |
| [scripts/make_icons.swift](../../scripts/make_icons.swift) | Genera le risorse dell’icona dell’app nelle varianti usate dal bundle. |
| [scripts/import_selene_palettes.py](../../scripts/import_selene_palettes.py) | Converte le palette Selene nel catalogo JSON usato dall’app. |
| [scripts/check_localizations.py](../../scripts/check_localizations.py) | Verifica copertura, placeholder, plurali e risorse nel bundle installato. |
| [scripts/check_metadata_text_layout.swift](../../scripts/check_metadata_text_layout.swift) | Verifica fuori schermo il layout delle descrizioni e la destinazione dello scroll dopo cambi di focus, anche rapidi e con Riduci movimento. |
| [check_app_profile.swift](../../scripts/check_app_profile.swift) | Prova senza UI di identità, accesso reale alle preferenze e percorsi nel pacchetto prodotto dalla build; non importa né scrive dati. |

## Risorse incluse

| File | Responsabilità aggiuntiva |
|---|---|
| [Resources/IconArtwork.png](../../Resources/IconArtwork.png) | Master quadrato originale dell’icona (cristallo nella sfera di vetro), fornito dall’utente e creato con AI. |
| [Resources/IconArtwork.md](../../Resources/IconArtwork.md) | Provenienza dichiarata, brief e riproduzione delle varianti tramite il generatore. |
| [crystal-arcane.png](../../Sources/NXLibraryCore/Resources/crystal-arcane.png) | Immagine ferma del trofeo Arcane, anche come ripiego del video. |
| [crystal-arcane.mov](../../Sources/NXLibraryCore/Resources/crystal-arcane.mov) | Animazione con alpha del trofeo Arcane. |
| [crystal-gold.png](../../Sources/NXLibraryCore/Resources/crystal-gold.png) | Immagine del trofeo Oro. |
| [crystal-silver.png](../../Sources/NXLibraryCore/Resources/crystal-silver.png) | Immagine del trofeo Argento. |
| [crystal-bronze.png](../../Sources/NXLibraryCore/Resources/crystal-bronze.png) | Immagine del trofeo Bronzo. |

| File | Responsabilità |
|---|---|
| [Resources/AppIcon.icns](../../Resources/AppIcon.icns) | Icona macOS del bundle Arcane. |
| [Resources/AppIcon-Dark.png](../../Resources/AppIcon-Dark.png) | Variante scura dell’icona dell’app. |
| [Resources/AppIcon-Light.png](../../Resources/AppIcon-Light.png) | Variante chiara dell’icona dell’app. |
| [Resources/AppIcon-Mono.png](../../Resources/AppIcon-Mono.png) | Variante monocromatica dell’icona dell’app. |
| [Resources/Selene/palettes.json](../../Resources/Selene/palettes.json) | Catalogo delle 25 palette: blu classico predefinito, Arcane Crystal e Arcane Flow come superfici opzionali. |
| [Resources/Selene/Fonts/MaterialIcons-Regular.ttf](../../Resources/Selene/Fonts/MaterialIcons-Regular.ttf) | Font dei glifi Material Icons disegnati dalla UI. |
| [Resources/Selene/Fonts/MaterialIcons-LICENSE.txt](../../Resources/Selene/Fonts/MaterialIcons-LICENSE.txt) | Licenza del font Material Icons incluso. |
| [Resources/Selene/NOTICE.txt](../../Resources/Selene/NOTICE.txt) | Attribuzioni delle risorse Selene incluse. |
| [Resources/Brands/SteamLogo.png](../../Resources/Brands/SteamLogo.png) | Logo Steam inverso dalle linee guida Valve, inalterato; attribuzione in `NOTICE`. |
| [Resources/Brands/BuyMeACoffee.png](../../Resources/Brands/BuyMeACoffee.png) | Icona gialla dal kit ufficiale Buy Me a Coffee per il pulsante di sostegno; attribuzione in `NOTICE`. |
| [Resources/Selene/NOTICE-palettes.txt](../../Resources/Selene/NOTICE-palettes.txt) | Attribuzioni delle palette incluse con esse. |
| [Resources/Selene/Sounds/Boot.wav](../../Resources/Selene/Sounds/Boot.wav) | Cue sonoro incluso per l’avvio. |
| [Resources/Selene/Sounds/Key.wav](../../Resources/Selene/Sounds/Key.wav) | Cue sonoro incluso per la pressione dei tasti. |
| [Resources/Selene/Sounds/Success.wav](../../Resources/Selene/Sounds/Success.wav) | Cue sonoro incluso per il completamento di un’azione. |
| [Resources/Selene/Sounds/navigation.wav](../../Resources/Selene/Sounds/navigation.wav) | Cue sonoro incluso per la navigazione. |

## Screenshot e demo

| File | Responsabilità |
|---|---|
| [docs/media/README.md](../media/README.md) | Registra i media del README e la loro posizione. |
| [docs/media/spotlight.webp](../media/spotlight.webp) | Presenta Spotlight e la libreria nell'apertura del README. |
| [docs/media/game-details.webp](../media/game-details.webp) | Mostra dettagli, attività e informazioni di build di un gioco. |
| [docs/media/mod-store.webp](../media/mod-store.webp) | Presenta lo store delle mod nel README. |
| [docs/media/quick-menu.webp](../media/quick-menu.webp) | Illustra il menu rapido sopra la libreria. |
| [docs/media/porting-progress.webp](../media/porting-progress.webp) | Mostra l'avanzamento di un porting dalla schermata Spotlight. |
| [docs/media/settings.webp](../media/settings.webp) | Cattura storica di Settings in NX Library. |
| [docs/media/color-themes.webp](../media/color-themes.webp) | Mostra la scelta delle palette con anteprima della libreria. |
| [docs/media/static-wallpapers.webp](../media/static-wallpapers.webp) | Illustra il browser degli sfondi statici e la relativa anteprima. |
| [docs/media/live-wallpapers.webp](../media/live-wallpapers.webp) | Mostra il selettore degli sfondi animati e l'importazione di video personali. |

## Documentazione tecnica e registri datati

| File | Responsabilità |
|---|---|
| [docs/README.md](../README.md) | Indice della documentazione: cosa c'è in ogni cartella, per chi è e da dove partire. |
| [docs/how-it-works/architecture.md](../how-it-works/architecture.md) | Come funziona oggi ogni area: confini dei componenti, regole, dati su disco e verifiche; niente storia né stati di validazione. |
| [docs/how-it-works/flows.md](../how-it-works/flows.md) | Schemi dei flussi completi: avvio, libreria, Play Switch e Steam, Add Game, salvataggi, mod, impostazioni, aggiornamento dell’app. |
| [docs/how-it-works/steam.md](../how-it-works/steam.md) | Riferimento unico dell’integrazione Steam: file letti, stati, osservazione, libreria, Play, ore, achievement, scelte e limiti. |
| [docs/working-on-it/conventions.md](conventions.md) | Come si costruisce una cosa nuova: dove va il codice, ricette per fonte, schermata Selene, impostazione, file su disco, rete, testi, lavoro in background, test e documentazione. |
| [docs/working-on-it/development.md](development.md) | Documenta prerequisiti, runtime, build, debug, verifiche, CI e preparazione delle release. |
| [docs/working-on-it/file-map.md](file-map.md) | Catalogo corrente delle responsabilità di tutti i file versionati, suddiviso per area. |
| [docs/working-on-it/validation.md](validation.md) | Elenco unico di ciò che il maintainer ha validato o deve ancora provare, compresi i pin dell’engine. |
| [docs/history/engine-upgrades/README.md](../history/engine-upgrades/README.md) | Checklist obbligatoria e indice delle revisioni del pin upstream. |
| [docs/history/engine-upgrades/2026-10-27-06b7b3e-4f24ce6.md](../history/engine-upgrades/2026-10-27-06b7b3e-4f24ce6.md) | Registro della revisione del delta, scelte di adozione e verifiche per questo upgrade del motore. |
| [docs/history/engine-upgrades/2026-10-27-4f24ce6-1963fab.md](../history/engine-upgrades/2026-10-27-4f24ce6-1963fab.md) | Registro della revisione del delta, scelte di adozione e verifiche per questo upgrade del motore. |
| [docs/history/engine-upgrades/2026-10-29-1963fab-ee369f0.md](../history/engine-upgrades/2026-10-29-1963fab-ee369f0.md) | Registro della revisione del delta, scelte di adozione e verifiche per questo upgrade del motore. |
| [docs/history/engine-upgrades/2026-10-31-ee369f0-2716f78.md](../history/engine-upgrades/2026-10-31-ee369f0-2716f78.md) | Registro della revisione del delta, scelte di adozione e verifiche per questo upgrade del motore. |
| [docs/history/engine-upgrades/2026-11-02-163a9905-65501fbb-review.md](../history/engine-upgrades/2026-11-02-163a9905-65501fbb-review.md) | Registra l’adozione di 65501fbb, le decisioni UI/backend, i test, la build certificata e l’avvio manuale. |
| [docs/history/engine-upgrades/2026-11-02-2716f78-163a9905-review.md](../history/engine-upgrades/2026-11-02-2716f78-163a9905-review.md) | Registra revisione e adozione del pin: toolchain certificata, nuove sorgenti, interventi UI, prove sintetiche e conferma manuale di build e avvio. |
| [docs/history/engine-upgrades/2026-11-03-65501fbb-b64a5ff0-review.md](../history/engine-upgrades/2026-11-03-65501fbb-b64a5ff0-review.md) | Registra l’adozione di b64a5ff0, le scelte UI/backend, la build certificata e la conferma manuale di avvio. |
| [docs/history/engine-upgrades/2026-11-05-b64a5ff0-4a0551e4-review.md](../history/engine-upgrades/2026-11-05-b64a5ff0-4a0551e4-review.md) | Registra l’adozione di 4a0551e4: righe Front-ends, profili provvisori, avviso dell’archivio pipeline, uscita con Home, build Wonder certificata e avvio confermato. |
| [docs/history/engine-upgrades/2026-11-06-04df08d4-b2d46b86-review.md](../history/engine-upgrades/2026-11-06-04df08d4-b2d46b86-review.md) | Revisione del delta engine del 6 novembre e compatibilità della toolchain. |
| [docs/history/engine-upgrades/2026-11-06-4a0551e4-04df08d4-review.md](../history/engine-upgrades/2026-11-06-4a0551e4-04df08d4-review.md) | Revisione del candidato 04df08d4: tre righe Front-ends, cache e librerie shader in un file, etichetta **Updating shader cache**, pacchetti solo di sviluppo in tools.txt; in attesa di build certificato e avvio confermato. |
| [docs/history/engine-upgrades/2026-11-07-7fe9fc4d-e5f03403-review.md](../history/engine-upgrades/2026-11-07-7fe9fc4d-e5f03403-review.md) | Revisione engine del 7 novembre, eventi di progresso e prompt dei controller. |
| [docs/history/engine-upgrades/2026-11-07-b2d46b86-7fe9fc4d-review.md](../history/engine-upgrades/2026-11-07-b2d46b86-7fe9fc4d-review.md) | Revisione engine del 7 novembre, shader e requisiti. |
| [docs/history/engine-upgrades/2026-11-08-e5f03403-bd979ced-review.md](../history/engine-upgrades/2026-11-08-e5f03403-bd979ced-review.md) | Revisione engine dell’8 novembre e nuova catena di traduzione shader. |
| [docs/history/engine-upgrades/2026-11-09-bd979ced-79741184-review.md](../history/engine-upgrades/2026-11-09-bd979ced-79741184-review.md) | Adozione engine per 0.1.4.2 e limiti della validazione registrata. |
| [docs/history/engine-upgrades/2026-11-12-79741184-8a5c5e7e-review.md](../history/engine-upgrades/2026-11-12-79741184-8a5c5e7e-review.md) | Adozione engine per 0.1.4.3 e limiti della validazione registrata. |
| [docs/history/engine-upgrades/2026-11-18-8a5c5e7e-461a5f9f-review.md](../history/engine-upgrades/2026-11-18-8a5c5e7e-461a5f9f-review.md) | Revisione engine per 0.2.0, confronto con il commit già provato, scelte d'integrazione e prove del gate. |
| [docs/history/reviews/2026-11-09-hotfix-0.1.4.2.md](../history/reviews/2026-11-09-hotfix-0.1.4.2.md) | Ambito della release 0.1.4.2, autorizzazione del maintainer e verifiche ancora non confermate. |
| [docs/history/reviews/2026-11-16-ratings-metadata-evidence.md](../history/reviews/2026-11-16-ratings-metadata-evidence.md) | Prove e misure dietro le scelte di voti e metadati: abbinamenti Wikidata, console Switch 2 in IGDB, download a blocchi, movimento del selettore, sonde LaunchBox/TheGamesDB. |
| [docs/history/reviews/2026-11-17-arcane-moonlight.md](../history/reviews/2026-11-17-arcane-moonlight.md) | Contratti provati fuori schermo e tempi GPU del Moonlight prima/dopo, con limiti delle misure. |
| [docs/history/reviews/2026-11-17-dock-rename-probe.md](../history/reviews/2026-11-17-dock-rename-probe.md) | Sonda: il Dock apre ancora un'app rinominata nella stessa cartella. |
| [docs/history/reviews/2026-11-17-entrance-frames.md](../history/reviews/2026-11-17-entrance-frames.md) | Metodo, campioni e limiti delle misure temporanee dell’entrata e del passaggio al fullscreen. |
| [docs/history/reviews/2026-11-18-spotlight-glide.md](../history/reviews/2026-11-18-spotlight-glide.md) | Campioni dei primi cambi gioco e costo di mod e salvataggio selezione. |
| [docs/history/reviews/2026-11-18-steam-launch-spaces.md](../history/reviews/2026-11-18-steam-launch-spaces.md) | Riscontro video e log dei cambi rapidi di Space durante Play Steam, causa e regressione. |

## Aggiornare questo catalogo

Quando si aggiunge, rinomina o rimuove un file versionato, aggiornare la sua riga nella sezione della sua area e il totale iniziale; una funzione nuova non apre una sezione in fondo al catalogo. Le regole complete sono in [conventions.md](conventions.md#10-documentazione). Quando cambia un flusso o una responsabilità, aggiornare anche la sezione corrispondente della guida tecnica. Le descrizioni dei test indicano l’ambito dei controlli, mentre l’esito di esecuzione appartiene ai rapporti di verifica.
