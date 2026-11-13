# NX Library — catalogo dei file

Aggiornato il 3 novembre 2026. Copertura di **398 file** del progetto, compresi i controlli di pubblicazione, la CI, il master dell’icona, le guide per sviluppo e media, gli screenshot del README, l'integrazione di nxnative, il canale di aggiornamento e il setup in due passaggi con cartella unica per scoperta e installazione dei giochi. Le cartelle personali, gli output generati e gli appunti non versionati sono esclusi.

La [guida tecnica](architecture.md) spiega come collaborano i componenti. Qui ogni riga identifica un file e la sua responsabilità. Le sezioni Core seguono le funzionalità, quelle UI seguono schermate e componenti. Le viste usano i modelli e i servizi del Core attraverso il coordinamento applicativo.

Le cartelle generate `.build/`, `work/` e `dist/` e i dati personali in Application Support sono descritti nella guida. Per i piani datati, leggere anche le note finali di esecuzione e la specifica della funzionalità interessata.

## Indice

- [Progetto e configurazione](#progetto-e-configurazione)
- [Ingresso e shell dell’app](#ingresso-e-shell-dellapp)
- [Coordinamento applicativo](#coordinamento-applicativo)
- [Modelli dello stato applicativo](#modelli-dello-stato-applicativo)
- [Integrazione con macOS e servizi applicativi](#integrazione-con-macos-e-servizi-applicativi)
- [Core · libreria, stato e sessioni](#core--libreria-stato-e-sessioni)
- [Core · Setup, motore e chiavi](#core--setup-motore-e-chiavi)
- [Core · sorgenti, porting, installazione e lancio](#core--sorgenti-porting-installazione-e-lancio)
- [Core · cheats](#core--cheats)
- [Core · salvataggi e cloud](#core--salvataggi-e-cloud)
- [Core · artwork, metadati e sfondi online](#core--artwork-metadati-e-sfondi-online)
- [Core · presentazione Selene, focus e impostazioni](#core--presentazione-selene-focus-e-impostazioni)
- [UI · Add Game e porting](#ui--add-game-e-porting)
- [UI · Spotlight](#ui--spotlight)
- [UI · Collection e Details](#ui--collection-e-details)
- [UI · Game Options, cheats e salvataggi](#ui--game-options-cheats-e-salvataggi)
- [UI · Settings](#ui--settings)
- [UI · Setup, avvio, ricerca e console](#ui--setup-avvio-ricerca-e-console)
- [UI · componenti condivisi](#ui--componenti-condivisi)
- [UI · temi, rendering e sfondi](#ui--temi-rendering-e-sfondi)
- [Test e fixture](#test-e-fixture)
- [Script di sviluppo e packaging](#script-di-sviluppo-e-packaging)
- [Risorse incluse](#risorse-incluse)
- [Screenshot e demo](#screenshot-e-demo)
- [Documentazione tecnica e registri datati](#documentazione-tecnica-e-registri-datati)

## Progetto e configurazione

La pubblicazione comprende anche [CONTRIBUTING.md](../CONTRIBUTING.md), [SECURITY.md](../SECURITY.md), [la CI](../.github/workflows/ci.yml) e [il modello di segnalazione](../.github/ISSUE_TEMPLATE/bug_report.yml): istruzioni di contribuzione e aggiornamento del changelog, canale per vulnerabilità, controlli automatici su codice e contenuti e richieste di riproduzione senza allegati privati.

| File | Responsabilità |
|---|---|
| [.gitignore](../.gitignore) | Esclude output di build, bundle, cache, work e file personali dell’IDE dal versionamento. |
| [AGENTS.md](../AGENTS.md) | Definisce vincoli per gli agenti, procedura di upgrade del motore e verifiche assegnate all’utente. |
| [CHANGELOG.md](../CHANGELOG.md) | Registra le modifiche visibili all'utente per release; Unreleased raccoglie il lavoro non ancora pubblicato. |
| [LICENSE](../LICENSE) | Contiene la licenza MIT di NX Library. |
| [NOTICE](../NOTICE) | Conserva attribuzioni e provenienza dei componenti e dei riferimenti riutilizzati. |
| [Package.swift](../Package.swift) | Dichiara i target SwiftPM, le loro dipendenze e il deployment macOS minimo. |
| [README.md](../README.md) | Presenta l'app con logo e badge, guida d'uso, requisiti, risoluzione dei problemi, crediti e note legali. |
| [runtime.lock](../runtime.lock) | Fissa versioni, download e hash del runtime Python e degli strumenti inclusi nel bundle. |

## Ingresso e shell dell’app

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/NXLibraryApp.swift](../Sources/NXLibrary/NXLibraryApp.swift) | Punto @main, finestra SwiftUI, notifiche interne e comandi della barra menu. |
| [Sources/NXLibrary/AppDelegate.swift](../Sources/NXLibrary/AppDelegate.swift) | Registra Material Icons e gestisce il ciclo di chiusura e riapertura della finestra. |
| [Sources/NXLibrary/Views/MainView.swift](../Sources/NXLibrary/Views/MainView.swift) | Presenta AppShellView come contenuto della finestra principale. |
| [Sources/NXLibrary/Views/Shell/AppShellView.swift](../Sources/NXLibrary/Views/Shell/AppShellView.swift) | Possiede lo stato condiviso, compone schermate e overlay e assegna priorità all’input. |
| [Sources/NXLibrary/Views/Shell/FullscreenCursorView.swift](../Sources/NXLibrary/Views/Shell/FullscreenCursorView.swift) | Gestisce il cursore inattivo nella sola finestra fullscreen del launcher, sospendendolo per pannelli e menu e ripristinando gli eventi al distacco. |
| [Sources/NXLibrary/Views/Shell/StartupWindowView.swift](../Sources/NXLibrary/Views/Shell/StartupWindowView.swift) | Applica una sola volta alla finestra pronta la preferenza fullscreen letta al lancio. |
| [Sources/NXLibrary/Views/Shell/MenuOverlayView.swift](../Sources/NXLibrary/Views/Shell/MenuOverlayView.swift) | Disegna il control center con azioni, focus e sottomenu Power. |
| [Sources/NXLibraryCore/NXLibraryCore.swift](../Sources/NXLibraryCore/NXLibraryCore.swift) | Espone la versione nominale del modulo Core. |

## Coordinamento applicativo

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/ViewModels/AppViewModel.swift](../Sources/NXLibrary/ViewModels/AppViewModel.swift) | Coordina libreria, sorgenti, ambiente, porting, log, impostazioni dei giochi e lancio. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Cheats.swift](../Sources/NXLibrary/ViewModels/AppViewModel+Cheats.swift) | Adatta Core e bundle installato al pannello Cheats, alla riga di stato e alla diagnostica. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Mods.swift](../Sources/NXLibrary/ViewModels/AppViewModel+Mods.swift) | Crea lo `ModStore` di un gioco, il valore della riga Mods e le frasi per ogni errore. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Controller.swift](../Sources/NXLibrary/ViewModels/AppViewModel+Controller.swift) | Conserva il contesto di gioco per i comandi e offre il collegamento alla cartella dei save. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Diagnostics.swift](../Sources/NXLibrary/ViewModels/AppViewModel+Diagnostics.swift) | Raccoglie ambiente, toolchain e ultimo build per il rapporto diagnostico ripulito. |
| [Sources/NXLibrary/ViewModels/AppViewModel+KeyCheck.swift](../Sources/NXLibrary/ViewModels/AppViewModel+KeyCheck.swift) | Rilancia il controllo delle chiavi al variare delle sorgenti e scarta risultati superati. |
| [Sources/NXLibrary/ViewModels/AppViewModel+AppIcon.swift](../Sources/NXLibrary/ViewModels/AppViewModel+AppIcon.swift) | Applica o ripristina l’icona dell’app del gioco dopo build, avvio e chiusura del gioco, senza toccare giochi in esecuzione o in build. |
| [Sources/NXLibrary/ViewModels/AppViewModel+PendingInstall.swift](../Sources/NXLibrary/ViewModels/AppViewModel+PendingInstall.swift) | Riprende le installazioni differite e gestisce errore e nuovo tentativo sul bundle pronto, rispettando i lease. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Porting.swift](../Sources/NXLibrary/ViewModels/AppViewModel+Porting.swift) | Prepara tile, pill e stime del porting e coordina notifiche e azioni sugli errori riconosciuti. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Saves.swift](../Sources/NXLibrary/ViewModels/AppViewModel+Saves.swift) | Risolve contesto e identità dei save, coordina i lease e avvia i recuperi pendenti. |
| [Sources/NXLibrary/ViewModels/AppViewModel+SteamGridDB.swift](../Sources/NXLibrary/ViewModels/AppViewModel+SteamGridDB.swift) | Verifica, salva e rimuove la chiave SteamGridDB dell’utente senza registrarne il valore. |
| [Sources/NXLibrary/ViewModels/AppViewModel+NewestEngine.swift](../Sources/NXLibrary/ViewModels/AppViewModel+NewestEngine.swift) | Usa l’engine più nuovo o torna a quello testato, accende l’override e controlla se main è utilizzabile. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Toolchain.swift](../Sources/NXLibrary/ViewModels/AppViewModel+Toolchain.swift) | Espone il riepilogo del gate della toolchain per l’interfaccia. |
| [Sources/NXLibrary/ViewModels/SavePanelModel.swift](../Sources/NXLibrary/ViewModels/SavePanelModel.swift) | Gestisce refresh, anteprime, backup, importazione, ripristino, errori e conferma temporanea di successo. |
| [Sources/NXLibrary/ViewModels/SetupCheckModel.swift](../Sources/NXLibrary/ViewModels/SetupCheckModel.swift) | Esegue probe e installazioni del Setup in background, con avanzamento e ricontrollo periodico. |

## Modelli dello stato applicativo

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Models/AppIconAppearanceMode.swift](../Sources/NXLibrary/Models/AppIconAppearanceMode.swift) | Enumera le varianti dell’icona dell’app selezionabili dall’utente. |
| [Sources/NXLibrary/Models/BuildStageItem.swift](../Sources/NXLibrary/Models/BuildStageItem.swift) | Rappresenta una fase del porting nella lista di avanzamento. |
| [Sources/NXLibrary/Models/BuildState.swift](../Sources/NXLibrary/Models/BuildState.swift) | Enumera gli esiti e lo stato operativo del porting nella UI. |
| [Sources/NXLibrary/Models/GameDetailsInfo.swift](../Sources/NXLibrary/Models/GameDetailsInfo.swift) | Ispeziona DLC e salvataggi del bundle e prepara dimensioni e dettagli del gioco. |
| [Sources/NXLibrary/Models/GamepadType.swift](../Sources/NXLibrary/Models/GamepadType.swift) | Definisce brand dei controller e azioni astratte GamepadAction. |
| [Sources/NXLibrary/Models/LogEntry.swift](../Sources/NXLibrary/Models/LogEntry.swift) | Rappresenta messaggi, livelli e identità delle righe di log mostrate dall’app. |
| [Sources/NXLibrary/Models/NXLibraryError.swift](../Sources/NXLibrary/Models/NXLibraryError.swift) | Raggruppa errori applicativi e relative spiegazioni, compresi i rifiuti prima del porting. |
| [Sources/NXLibrary/Models/SelectableGame.swift](../Sources/NXLibrary/Models/SelectableGame.swift) | Rappresenta le sorgenti selezionabili e l’ordinamento delle versioni nel wizard. |
| [Sources/NXLibrary/Models/UpstreamCheckState.swift](../Sources/NXLibrary/Models/UpstreamCheckState.swift) | Rappresenta gli stati del controllo del changelog upstream. |

## Integrazione con macOS e servizi applicativi

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Services/AppUpdater.swift](../Sources/NXLibrary/Services/AppUpdater.swift) | Coordina controllo release, download, verifica, installazione e riavvio di NX Library. |
| [Sources/NXLibrary/Services/NativeMenuCommands.swift](../Sources/NXLibrary/Services/NativeMenuCommands.swift) | Coordina tracking, disponibilità nella scena e passaggio differito dai menu macOS alle azioni del launcher. |
| [Sources/NXLibrary/Services/GameControllerService.swift](../Sources/NXLibrary/Services/GameControllerService.swift) | Rileva controller e rimappature, gestisce tap e hold e produce azioni e simboli dei pulsanti. |
| [Sources/NXLibrary/Services/LaunchReadinessProbe.swift](../Sources/NXLibrary/Services/LaunchReadinessProbe.swift) | Attende una finestra visibile del gioco per terminare la schermata di lancio. |
| [Sources/NXLibrary/Services/NotificationService.swift](../Sources/NXLibrary/Services/NotificationService.swift) | Invia notifiche dei porting e instrada i clic verso il titolo o l’errore interessato. |
| [Sources/NXLibrary/Services/OnlineBackgroundService.swift](../Sources/NXLibrary/Services/OnlineBackgroundService.swift) | Carica pagine e miniature e scarica wallpaper o video conservando progressi e crediti. |
| [Sources/NXLibrary/Services/RunningGameMonitor.swift](../Sources/NXLibrary/Services/RunningGameMonitor.swift) | Riconcilia applicazioni in esecuzione e libreria e offre Resume e chiusura del gioco. |
| [Sources/NXLibrary/Services/SoundEffectService.swift](../Sources/NXLibrary/Services/SoundEffectService.swift) | Riproduce i cue Selene e applica attivazione, volume e file importati. |
| [Sources/NXLibrary/Services/SystemDetector.swift](../Sources/NXLibrary/Services/SystemDetector.swift) | Individua checkout nxnative, root personale e possibili percorsi delle chiavi. |

## Core · libreria, stato e sessioni

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Models/PortedGame.swift](../Sources/NXLibraryCore/Models/PortedGame.swift) | Modello persistente del gioco con bundle, sorgenti, impostazioni, build e installazione in attesa. |
| [Sources/NXLibraryCore/Models/GameStorageUsage.swift](../Sources/NXLibraryCore/Models/GameStorageUsage.swift) | Dimensioni per gioco e totali: distingue assenza e indisponibilità, segnala cache condivise e conserva identità stabili per il focus. |
| [Sources/NXLibraryCore/Models/LibraryFile.swift](../Sources/NXLibraryCore/Models/LibraryFile.swift) | Contenitore versionato del catalogo della libreria. |
| [Sources/NXLibraryCore/Models/GameStatus.swift](../Sources/NXLibraryCore/Models/GameStatus.swift) | Enumera disponibilità e stato del gioco rispetto ad app, sorgenti e porting. |
| [Sources/NXLibraryCore/Models/GameResourceState.swift](../Sources/NXLibraryCore/Models/GameResourceState.swift) | Distingue app mancanti, sorgenti assenti e workspace non compilati, riconcilia gli stati e conserva Play per una build esistente. |
| [Sources/NXLibraryCore/Models/BackdropArt.swift](../Sources/NXLibraryCore/Models/BackdropArt.swift) | Regola che tiene l’arte del gioco precedente sullo sfondo Spotlight (`BackdropArtRule`) dissolvenza di un layer calcolata sull’orologio (`OpacityFade`) e livelli ormai coperti da togliere (`ArtStack`). |
| [Sources/NXLibraryCore/Models/TileMotion.swift](../Sources/NXLibraryCore/Models/TileMotion.swift) | Curve e campioni dei loop di ring, bagliore e riflesso della tile selezionata, sull'orologio condiviso. |
| [Sources/NXLibraryCore/Models/TextScroll.swift](../Sources/NXLibraryCore/Models/TextScroll.swift) | Scorrimento della colonna del pannello della mod: altezza della descrizione dopo Read more, limiti, riga a fuoco mostrata intera e passo Su/Giù che legge prima della riga seguente. |
| [Sources/NXLibraryCore/Models/AppSettings.swift](../Sources/NXLibraryCore/Models/AppSettings.swift) | Definisce impostazioni globali, default e decodifica compatibile dei campi aggiunti nel tempo. |
| [Sources/NXLibraryCore/Models/LibraryFilter.swift](../Sources/NXLibraryCore/Models/LibraryFilter.swift) | Definisce filtri, PlayHistory e query condivisa per ricerca/ordine del catalogo misto, conservando l’API nxnative. |
| [Sources/NXLibraryCore/Models/LibrarySelectionState.swift](../Sources/NXLibraryCore/Models/LibrarySelectionState.swift) | Mantiene selezione e spostamento nel risultato filtrato della Collection. |
| [Sources/NXLibraryCore/Models/LibraryPresentation.swift](../Sources/NXLibraryCore/Models/LibraryPresentation.swift) | Formatta metadati e statistiche temporali per le schermate della libreria. |
| [Sources/NXLibraryCore/Models/GameDetailPresentation.swift](../Sources/NXLibraryCore/Models/GameDetailPresentation.swift) | Prepara badge, disponibilità delle azioni, date e dati della pagina Details. |
| [Sources/NXLibraryCore/Models/PlaySession.swift](../Sources/NXLibraryCore/Models/PlaySession.swift) | Descrive una sessione persistibile con gioco e riferimenti temporali. |
| [Sources/NXLibraryCore/Models/ActivitySummary.swift](../Sources/NXLibraryCore/Models/ActivitySummary.swift) | Aggrega sessioni, giorni e tempi della settimana per la scheda Activity. |
| [Sources/NXLibraryCore/Models/MoreLikeThis.swift](../Sources/NXLibraryCore/Models/MoreLikeThis.swift) | Ordina i giochi correlati usando generi, sviluppatore e publisher. |
| [Sources/NXLibraryCore/Services/LibraryStore.swift](../Sources/NXLibraryCore/Services/LibraryStore.swift) | Salva il catalogo con recupero; conserva lo stato nelle scansioni e sostituisce le sorgenti solo per una selezione esplicita. |
| [Sources/NXLibraryCore/Services/ImportService.swift](../Sources/NXLibraryCore/Services/ImportService.swift) | Scansiona bundle nxnative e ne ricava identità, versione, percorso e dimensioni. |
| [Sources/NXLibraryCore/Models/CursorIdleState.swift](../Sources/NXLibraryCore/Models/CursorIdleState.swift) | Politica del ritardo di visibilità del puntatore e reset su mouse o perdita di eleggibilità. |
| [Sources/NXLibraryCore/Services/AppSizeCache.swift](../Sources/NXLibraryCore/Services/AppSizeCache.swift) | Conserva dimensioni per percorso e data del bundle e decide lo stato vuoto della libreria. |
| [Sources/NXLibraryCore/Services/AppSettingsStore.swift](../Sources/NXLibraryCore/Services/AppSettingsStore.swift) | Pubblica impostazioni ed errori, preserva i file illeggibili e salva settings.json tramite file temporaneo. |
| [Sources/NXLibraryCore/Services/PlaySessionStore.swift](../Sources/NXLibraryCore/Services/PlaySessionStore.swift) | Registra avvio, heartbeat, fine e riconciliazione delle sessioni di gioco. |
| [Sources/NXLibraryCore/Navigation/AppRouter.swift](../Sources/NXLibraryCore/Navigation/AppRouter.swift) | Gestisce route, ritorno, menu, ricerca e richieste di selezione o spostamento su Spotlight. |

## Core · Setup, motore e chiavi

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Models/ToolchainRequirements.swift](../Sources/NXLibraryCore/Models/ToolchainRequirements.swift) | Centralizza requisiti Xcode e asset Metal e confronta versioni numeriche. |
| [Sources/NXLibraryCore/Models/ToolchainInfo.swift](../Sources/NXLibraryCore/Models/ToolchainInfo.swift) | Registra provenienza e verifica della toolchain associata a un build. |
| [Sources/NXLibraryCore/Models/ToolchainGateCopy.swift](../Sources/NXLibraryCore/Models/ToolchainGateCopy.swift) | Traduce il gate in testi distinguendo Metal certificato, precedente e successivo. |
| [Sources/NXLibraryCore/Models/SetupCheck.swift](../Sources/NXLibraryCore/Models/SetupCheck.swift) | Converte fatti e override del Setup in schede, stati, azioni e condizioni di riapertura. |
| [Sources/NXLibraryCore/Models/FirstRunSetup.swift](../Sources/NXLibraryCore/Models/FirstRunSetup.swift) | Coordina pagine, completamento, ripresa del primo avvio, stato della scansione, focus e consumo unico delle selezioni avviate da Your games. |
| [Sources/NXLibraryCore/Models/GameFoldersCopy.swift](../Sources/NXLibraryCore/Models/GameFoldersCopy.swift) | Condivide nomi delle cartelle, formati e descrizioni tra Setup, Settings e selettori dei percorsi. |
| [Sources/NXLibraryCore/Models/SetupGrid.swift](../Sources/NXLibraryCore/Models/SetupGrid.swift) | Calcola disposizione, centratura e navigazione del focus nella griglia del Setup. |
| [Sources/NXLibraryCore/Models/UpstreamCopy.swift](../Sources/NXLibraryCore/Models/UpstreamCopy.swift) | Prepara i testi del changelog upstream e dell’adozione degli aggiornamenti tramite NX Library. |
| [Sources/NXLibraryCore/Services/NXNativeEnvironment.swift](../Sources/NXLibraryCore/Services/NXNativeEnvironment.swift) | Ispeziona strumenti, Python, Xcode e Metal e restituisce uno stato dell’ambiente. |
| [Sources/NXLibraryCore/Services/EngineLocation.swift](../Sources/NXLibraryCore/Services/EngineLocation.swift) | Risolve checkout predefinito o scelto e produce i candidati per prod.keys. |
| [Sources/NXLibraryCore/Services/EngineToolchain.swift](../Sources/NXLibraryCore/Services/EngineToolchain.swift) | Individua runtime incluso o venv del checkout e prepara ambiente e PATH dei processi. |
| [Sources/NXLibraryCore/Services/EnginePackageReader.swift](../Sources/NXLibraryCore/Services/EnginePackageReader.swift) | Legge capacità delle sorgenti e content meta di tutti i pacchetti in un solo passaggio del lettore upstream (`package_reader`, o `package_title_reader` sugli engine precedenti a 5c4dc18f), validando identità e tipi senza esporre chiavi. |
| [Sources/NXLibraryCore/Models/BuildWarningCopy.swift](../Sources/NXLibraryCore/Models/BuildWarningCopy.swift) | Testo mostrato a fine build per una fase terminata con `warn` dell’engine (archivio delle pipeline mancante). |
| [Sources/NXLibraryCore/Models/ReleaseNotesLayout.swift](../Sources/NXLibraryCore/Models/ReleaseNotesLayout.swift) | Divide le note di release in titoli, voci e testo, una riga per volta, per il dialogo degli aggiornamenti. |
| [Sources/NXLibraryCore/Services/NewestEngine.swift](../Sources/NXLibraryCore/Services/NewestEngine.swift) | Scelta dell’engine più nuovo: testi condivisi, lettura del Metal dal lock di main, cambio di commit con git senza toccare file modificati. |
| [Sources/NXLibraryCore/Services/NUPSourceCatalog.swift](../Sources/NXLibraryCore/Services/NUPSourceCatalog.swift) | Riconosce i file NUP Switch 2 e ne elenca base, update e DLC tramite il lettore pack_nup dell’engine; accetta anche un NUP senza base (solo update). |
| [Sources/NXLibraryCore/Services/DirectorySize.swift](../Sources/NXLibraryCore/Services/DirectorySize.swift) | Misura le cartelle con fts come du, così il refresh non resta bloccato su app grandi in dischi esterni (issue #2). |
| [Sources/NXLibraryCore/Services/NXNativeGameSettings.swift](../Sources/NXLibraryCore/Services/NXNativeGameSettings.swift) | Legge l’elenco impostazioni del build, i valori attuali e le chiavi fissate da env.txt. |
| [Sources/NXLibraryCore/Services/SavedChoicesStore.swift](../Sources/NXLibraryCore/Services/SavedChoicesStore.swift) | Legge e scrive le scelte salvate launcher.<env> nel dominio preferenze dell’app gioco. |
| [Sources/NXLibraryCore/Services/CompatibilityChecker.swift](../Sources/NXLibraryCore/Services/CompatibilityChecker.swift) | Controlla commit, modifiche del checkout, Metal e opzioni CLI richieste dal frontend. |
| [Sources/NXLibraryCore/Services/SetupProbe.swift](../Sources/NXLibraryCore/Services/SetupProbe.swift) | Raccoglie i fatti mostrati dal Setup usando comandi e controlli mirati. |
| [Sources/NXLibraryCore/Services/SetupActions.swift](../Sources/NXLibraryCore/Services/SetupActions.swift) | Costruisce le operazioni Git ammesse per installare o allineare il motore al pin. |
| [Sources/NXLibraryCore/Services/InstallProgress.swift](../Sources/NXLibraryCore/Services/InstallProgress.swift) | Interpreta avanzamento Git, percentuali, byte e righe parziali per le installazioni. |
| [Sources/NXLibraryCore/Services/KeyStore.swift](../Sources/NXLibraryCore/Services/KeyStore.swift) | Valida le chiavi, espone solo il riepilogo e pubblica atomicamente la copia gestita con permessi 0600. |
| [Sources/NXLibraryCore/Services/KeyCheck.swift](../Sources/NXLibraryCore/Services/KeyCheck.swift) | Legge intestazioni NCA e ticket e verifica se le chiavi possono aprire le sorgenti selezionate. |
| [Sources/NXLibraryCore/Services/CommandRunner.swift](../Sources/NXLibraryCore/Services/CommandRunner.swift) | Confine sostituibile per comandi e output, con esecuzione sincrona o streaming delle righe. |
| [Sources/NXLibraryCore/Services/UpstreamChecker.swift](../Sources/NXLibraryCore/Services/UpstreamChecker.swift) | Consulta i commit upstream tramite HTTP e produce stato e collegamento di confronto. |

## Core · sorgenti, porting, installazione e lancio

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Models/GameFileItem.swift](../Sources/NXLibraryCore/Models/GameFileItem.swift) | Descrive sorgenti, tipo base/update/DLC, percorso, dimensione e metadati rilevati. |
| [Sources/NXLibraryCore/Models/SourceSelection.swift](../Sources/NXLibraryCore/Models/SourceSelection.swift) | Gestisce scelta esplicita dei titoli, selezione e ripristino logico dei contenuti, DLC incorporati, dimensioni uniche, versione di build e requisiti del motore. |
| [Sources/NXLibraryCore/Models/BuildRecord.swift](../Sources/NXLibraryCore/Models/BuildRecord.swift) | Conserva esito, tempi, log e provenienza di un porting. |
| [Sources/NXLibraryCore/Models/TargetPlatform.swift](../Sources/NXLibraryCore/Models/TargetPlatform.swift) | Definisce il target mac-app e le sue etichette per l’interfaccia. |
| [Sources/NXLibraryCore/Models/GameRuntimeConfig.swift](../Sources/NXLibraryCore/Models/GameRuntimeConfig.swift) | Persiste opzioni per titolo, prepara Review e lingua del rebuild, mappa DM_* e unisce env.txt. |
| [Sources/NXLibraryCore/Models/LauncherSettings.swift](../Sources/NXLibraryCore/Models/LauncherSettings.swift) | Legge launcher.json e verifica i controlli supportati, con fallback per le build precedenti. |
| [Sources/NXLibraryCore/Models/AppIconProgress.swift](../Sources/NXLibraryCore/Models/AppIconProgress.swift) | Stati e testi della preparazione icona, con esito informativo aggiunto al log della build conclusa. |
| [Sources/NXLibraryCore/Models/IconLaunchWait.swift](../Sources/NXLibraryCore/Models/IconLaunchWait.swift) | Conserva una richiesta Play durante la firma dell'icona e la revoca su annullamento, errore o chiusura del dialogo. |
| [Sources/NXLibraryCore/Services/PipelineArchiveProgress.swift](../Sources/NXLibraryCore/Services/PipelineArchiveProgress.swift) | Legge il log pipeline della build corrente e conta solo i gruppi confermati pronti dal motore. |
| [Sources/NXLibraryCore/Models/PortingProgress.swift](../Sources/NXLibraryCore/Models/PortingProgress.swift) | Aggrega eventi del motore in fasi e percentuale complessiva per la UI. |
| [Sources/NXLibraryCore/Models/PortingPresentation.swift](../Sources/NXLibraryCore/Models/PortingPresentation.swift) | Definisce fallimento persistito, ETA, aspetto della tile e pill del porting. |
| [Sources/NXLibraryCore/Models/PortingFailureReason.swift](../Sources/NXLibraryCore/Models/PortingFailureReason.swift) | Classifica messaggi del motore e rifiuti preliminari in motivazioni e azioni spiegabili. |
| [Sources/NXLibraryCore/Models/PortingNotice.swift](../Sources/NXLibraryCore/Models/PortingNotice.swift) | Decide quando notificare l’esito di un porting e prepara il relativo messaggio. |
| [Sources/NXLibraryCore/Models/PendingInstall.swift](../Sources/NXLibraryCore/Models/PendingInstall.swift) | Conserva un bundle pronto in attesa e ne gestisce installazione, scarto e aggiornamento del record, anche dopo una pubblicazione interrotta. |
| [Sources/NXLibraryCore/Models/RunningGames.swift](../Sources/NXLibraryCore/Models/RunningGames.swift) | Confronta bundle ID e mantiene uno snapshot delle applicazioni in esecuzione. |
| [Sources/NXLibraryCore/Services/SourceCatalog.swift](../Sources/NXLibraryCore/Services/SourceCatalog.swift) | Riconosce sorgenti NSP/XCI/NSZ/XCZ e raggruppa titoli, aggiornamenti e DLC. |
| [Sources/NXLibraryCore/Services/ExtractedSourceCatalog.swift](../Sources/NXLibraryCore/Services/ExtractedSourceCatalog.swift) | Verifica il layout di un gioco estratto, legge NPDM e profilo registrato e rileva update e DLC. |
| [Sources/NXLibraryCore/Services/WorkspaceManager.swift](../Sources/NXLibraryCore/Services/WorkspaceManager.swift) | Prepara collegamenti simbolici, verifica link interrotti e adotta workspace e cache esistenti. |
| [Sources/NXLibraryCore/Services/BuildScratch.swift](../Sources/NXLibraryCore/Services/BuildScratch.swift) | Sceglie dove stanno workspace e app temporanea (sul volume dell'app quando può ospitarli), riconosce i workspace gestiti e le cartelle temporanee da pulire. |
| [Sources/NXLibraryCore/Services/BuildCommand.swift](../Sources/NXLibraryCore/Services/BuildCommand.swift) | Valore con eseguibile, argomenti, ambiente e directory di lavoro del processo di porting. |
| [Sources/NXLibraryCore/Services/BuildCommandBuilder.swift](../Sources/NXLibraryCore/Services/BuildCommandBuilder.swift) | Costruisce il contratto CLI nxnative, comprese destinazione Mac, JSON e override toolchain. |
| [Sources/NXLibraryCore/Services/BuildEvent.swift](../Sources/NXLibraryCore/Services/BuildEvent.swift) | Definisce gli eventi di fase, step, avanzamento e log ricevuti dal motore. |
| [Sources/NXLibraryCore/Services/BuildEventParser.swift](../Sources/NXLibraryCore/Services/BuildEventParser.swift) | Decodifica eventi JSON e tratta le altre righe come log. |
| [Sources/NXLibraryCore/Services/BuildService.swift](../Sources/NXLibraryCore/Services/BuildService.swift) | Avvia il porting, gestisce processi, cancellazione, log ed eventi; conserva il bundle valido quando fallisce solo l’installazione. |
| [Sources/NXLibraryCore/Services/BuildOutputInstaller.swift](../Sources/NXLibraryCore/Services/BuildOutputInstaller.swift) | Pubblica il bundle con rinomina o scambio atomico, prepara copie fra volumi e riconosce i tentativi già completati tramite ricevuta. |
| [Sources/NXLibraryCore/Services/GameAppDestination.swift](../Sources/NXLibraryCore/Services/GameAppDestination.swift) | Risolve la destinazione condivisa da review e porting, conserva i percorsi dei rebuild, evita conflitti di nome e verifica la cartella di destinazione. |
| [Sources/NXLibraryCore/Services/LaunchService.swift](../Sources/NXLibraryCore/Services/LaunchService.swift) | Scrive l’ambiente runtime e avvia il bundle del gioco tramite NSWorkspace. |
| [Sources/NXLibraryCore/Services/StorageManager.swift](../Sources/NXLibraryCore/Services/StorageManager.swift) | Misura app, cache e log per gioco e totali senza duplicare percorsi condivisi; verifica cartelle e sorgenti prima della pulizia selettiva. I backup appartengono al flusso Saves. |
| [Sources/NXLibraryCore/Services/DiagnosticsReport.swift](../Sources/NXLibraryCore/Services/DiagnosticsReport.swift) | Genera il rapporto diagnostico e rimuove percorso home e valori riconosciuti come chiavi. |
| [Sources/NXLibraryCore/Services/AppUpdate.swift](../Sources/NXLibraryCore/Services/AppUpdate.swift) | Definisce repository, versioni, requisiti, limiti di download, digest, firma e regole di verifica e sostituzione dell’app NX Library. |
| [Sources/NXLibraryCore/Models/AppUpdatePresentation.swift](../Sources/NXLibraryCore/Models/AppUpdatePresentation.swift) | Definisce gli stati dell’updater e il gate di installazione per versione e tipo di copia. |
| [Sources/NXLibraryCore/Services/AppUpdateDownload.swift](../Sources/NXLibraryCore/Services/AppUpdateDownload.swift) | Scarica gli aggiornamenti con limiti di dimensione, redirect HTTPS vincolati a GitHub e gestione del file temporaneo. |

## Core · cheats

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Models/CheatFile.swift](../Sources/NXLibraryCore/Models/CheatFile.swift) | Decodifica cheats, sezioni, metadati e collegamenti dei codici secondo il parser del motore. |
| [Sources/NXLibraryCore/Models/CheatInstall.swift](../Sources/NXLibraryCore/Models/CheatInstall.swift) | Valuta file e cartelle in ingresso rispetto a title ID, build ID e necessità di conferma. |
| [Sources/NXLibraryCore/Models/CheatLocator.swift](../Sources/NXLibraryCore/Models/CheatLocator.swift) | Risolve build ID, title ID e cartella cheats seguendo i file e l’ambiente del launcher. |
| [Sources/NXLibraryCore/Models/CheatStatus.swift](../Sources/NXLibraryCore/Models/CheatStatus.swift) | Valuta il supporto del motore tramite ancestry e prepara stato della riga e indicatore attivo. |
| [Sources/NXLibraryCore/Models/CheatCopy.swift](../Sources/NXLibraryCore/Models/CheatCopy.swift) | Centralizza testi di stato, rifiuto, importazione, sostituzione e rimozione dei cheats. |
| [Sources/NXLibraryCore/Services/CheatStore.swift](../Sources/NXLibraryCore/Services/CheatStore.swift) | Legge e modifica cheats, file enabled, master switch e metadati della build corrente. |
| [Sources/NXLibraryCore/Services/ModStore.swift](../Sources/NXLibraryCore/Services/ModStore.swift) | Ordine, stato acceso/spento, conflitti, Cestino e riga `DM_ROMFS_OVERLAY` delle mod RomFS di un gioco. |
| [Sources/NXLibraryCore/Services/ModFolderScanner.swift](../Sources/NXLibraryCore/Services/ModFolderScanner.swift) | Trova le voci della cartella mods (cartelle e file sparsi), il loro `romfs` e i file che contengono (senza quelli nascosti). |
| [Sources/NXLibraryCore/Services/GameBanana/GameBananaAPI.swift](../Sources/NXLibraryCore/Services/GameBanana/GameBananaAPI.swift) | URL, host fidati, modelli delle risposte di GameBanana e testo semplice dalle descrizioni HTML. |
| [Sources/NXLibraryCore/Services/GameBanana/GameBananaClient.swift](../Sources/NXLibraryCore/Services/GameBanana/GameBananaClient.swift) | Richieste a GameBanana con User-Agent, limite di 4 alla volta e cache su disco. |
| [Sources/NXLibraryCore/Services/GameBanana/GameBananaImageCache.swift](../Sources/NXLibraryCore/Services/GameBanana/GameBananaImageCache.swift) | Cache su disco delle immagini delle mod dal CDN di GameBanana. |
| [Sources/NXLibraryCore/Services/GameBanana/GameBananaMatch.swift](../Sources/NXLibraryCore/Services/GameBanana/GameBananaMatch.swift) | Abbina un gioco alla sua pagina GameBanana per nome e ricorda la scelta. |
| [Sources/NXLibraryCore/Services/GameBanana/ModSupport.swift](../Sources/NXLibraryCore/Services/GameBanana/ModSupport.swift) | Quali file di mod funzionano (solo RomFS), dov'è la loro cartella `romfs`, nomi di cartella sicuri. |
| [Sources/NXLibraryCore/Services/GameBanana/AvailableModsFinder.swift](../Sources/NXLibraryCore/Services/GameBanana/AvailableModsFinder.swift) | Cerca le mod di un gioco che funzionano e capisce quando una mod installata ha un aggiornamento. |
| [Sources/NXLibraryCore/Services/GameBanana/ModInstaller.swift](../Sources/NXLibraryCore/Services/GameBanana/ModInstaller.swift) | Controlla, estrae con `bsdtar` e installa una mod scaricata nella cartella del gioco. |
| [Sources/NXLibraryCore/Services/GameBanana/GameBananaBandModel.swift](../Sources/NXLibraryCore/Services/GameBanana/GameBananaBandModel.swift) | Stato della fascia Mods di un gioco: abbinamento, mod che funzionano, installazioni. |
| [Sources/NXLibraryCore/Services/GameBanana/ModCatalog.swift](../Sources/NXLibraryCore/Services/GameBanana/ModCatalog.swift) | Categorie nostre, ordinamenti e sezioni della pagina dello store (altezze fisse). |
| [Sources/NXLibraryCore/Services/GameBanana/ModCatalogSnapshots.swift](../Sources/NXLibraryCore/Services/GameBanana/ModCatalogSnapshots.swift) | Le mod di ogni gioco salvate su disco, per aprire lo store subito; solo link GameBanana. |
| [Sources/NXLibraryCore/Services/GameBanana/ModStoreModel.swift](../Sources/NXLibraryCore/Services/GameBanana/ModStoreModel.swift) | Dati dello store: apre dalle copie su disco, aggiorna in background due giochi alla volta, abbina solo se sicuro. |
| [Sources/NXLibraryCore/Models/ModStoreFocus.swift](../Sources/NXLibraryCore/Models/ModStoreFocus.swift) | Focus nella pagina dello store, ancorato al tipo di sezione; ogni sezione ricorda la sua tessera. |
| [Sources/NXLibraryCore/Services/GameBanana/GameBananaFindModel.swift](../Sources/NXLibraryCore/Services/GameBanana/GameBananaFindModel.swift) | Stato della ricerca per nome: campo, risultati, None of these. |
| [Sources/NXLibraryCore/Services/GameBanana/ModDownload.swift](../Sources/NXLibraryCore/Services/GameBanana/ModDownload.swift) | Scarica un file di GameBanana con avanzamento e Cancel, solo da host fidati. |
| [Sources/NXLibraryCore/Models/ModsBandLayout.swift](../Sources/NXLibraryCore/Models/ModsBandLayout.swift) | Ordine delle tessere della fascia Mods e movimento nella sua griglia (sei per riga). |
| [Sources/NXLibraryCore/Services/EnvFileEditor.swift](../Sources/NXLibraryCore/Services/EnvFileEditor.swift) | Cambia una sola variabile di un `env.txt` lasciando intatte le altre righe. |
| [Sources/NXLibraryCore/Models/LocalMod.swift](../Sources/NXLibraryCore/Models/LocalMod.swift) | Una cartella della cartella mods di un gioco, con il suo `romfs` e lo stato. |

## Core · salvataggi e cloud

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Models/SaveLocation.swift](../Sources/NXLibraryCore/Models/SaveLocation.swift) | Valida percorsi e identità, risolve cloud effettivo e definisce slot ed errori dei salvataggi. |
| [Sources/NXLibraryCore/Models/SaveSnapshot.swift](../Sources/NXLibraryCore/Models/SaveSnapshot.swift) | Definisce identità, inventario, manifest e anteprime di importazione o ripristino. |
| [Sources/NXLibraryCore/Models/SavePresentation.swift](../Sources/NXLibraryCore/Models/SavePresentation.swift) | Prepara riepiloghi, date, dimensioni, nomi degli slot e disponibilità dell’importazione. |
| [Sources/NXLibraryCore/Models/CloudSaves.swift](../Sources/NXLibraryCore/Models/CloudSaves.swift) | Descrive scelta cloud, cartelle iCloud o personalizzate e passaggi fra le opzioni. |
| [Sources/NXLibraryCore/Services/CloudSavesPreferences.swift](../Sources/NXLibraryCore/Services/CloudSavesPreferences.swift) | Prepara la cartella e riapplica la scelta cloud ai domini dei giochi prima di ogni avvio, anche Off. |
| [Sources/NXLibraryCore/Services/RyujinxSaveFolder.swift](../Sources/NXLibraryCore/Services/RyujinxSaveFolder.swift) | Riconosce contenitori Ryujinx, controlla il title ID e seleziona l’intero albero committed 0. |
| [Sources/NXLibraryCore/Services/SaveFileIO.swift](../Sources/NXLibraryCore/Services/SaveFileIO.swift) | Centralizza copie, hash, xattr portabili, controlli dei percorsi, spazio e scritture durevoli. |
| [Sources/NXLibraryCore/Services/SaveSnapshotStore.swift](../Sources/NXLibraryCore/Services/SaveSnapshotStore.swift) | Crea e verifica backup e prepara importazioni da esportazioni o backup datati. |
| [Sources/NXLibraryCore/Services/SaveRestorePreview.swift](../Sources/NXLibraryCore/Services/SaveRestorePreview.swift) | Estende lo store con staging, validazione e rilascio delle anteprime di ripristino. |
| [Sources/NXLibraryCore/Services/SaveTransaction.swift](../Sources/NXLibraryCore/Services/SaveTransaction.swift) | Esegue sostituzioni con copia protettiva e journal e recupera o ripulisce transazioni interrotte. |
| [Sources/NXLibraryCore/Services/SaveOperationGate.swift](../Sources/NXLibraryCore/Services/SaveOperationGate.swift) | Assegna lease per titolo e un’esclusione globale per l’updater; coordina salvataggi, Play, installazioni e recuperi. |

## Core · artwork, metadati e sfondi online

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Models/OnlineBackgrounds.swift](../Sources/NXLibraryCore/Models/OnlineBackgrounds.swift) | Modella sorgenti e risultati e interpreta le risposte dei provider di sfondi fissi e video. |
| [Sources/NXLibraryCore/Services/AutomaticIconResolver.swift](../Sources/NXLibraryCore/Services/AutomaticIconResolver.swift) | Risolve icone automatiche con cache, abbinamento prudente e rispetto delle restrizioni del provider. |
| [Sources/NXLibraryCore/Services/ArtworkStore.swift](../Sources/NXLibraryCore/Services/ArtworkStore.swift) | Scarica, ridimensiona e conserva immagini e screenshot nella cache per titolo e tipo. |
| [Sources/NXLibraryCore/Services/AppIconWriter.swift](../Sources/NXLibraryCore/Services/AppIconWriter.swift) | Scrive l’icona scelta nell’app del gioco, conserva l’originale, rifirma e verifica, e annulla tutto in caso di errore. |
| [Sources/NXLibraryCore/Services/ArtworkPicker.swift](../Sources/NXLibraryCore/Services/ArtworkPicker.swift) | Aggrega candidati per cover, sfondo, icona e logo e conserva le scelte manuali. |
| [Sources/NXLibraryCore/Services/MetadataPicker.swift](../Sources/NXLibraryCore/Services/MetadataPicker.swift) | Aggrega valori alternativi dei metadati e conserva gli override dell’utente per campo. |
| [Sources/NXLibraryCore/Services/BoxArtService.swift](../Sources/NXLibraryCore/Services/BoxArtService.swift) | Trova copertine Switch in GameTDB e ricorda copertine e ricerche senza risultato. |
| [Sources/NXLibraryCore/Services/GameTDB.swift](../Sources/NXLibraryCore/Services/GameTDB.swift) | Decodifica il database GameTDB, abbina nomi e regioni e conserva l’indice locale. |
| [Sources/NXLibraryCore/Services/NintendoStoreMetadata.swift](../Sources/NXLibraryCore/Services/NintendoStoreMetadata.swift) | Consulta i cataloghi pubblici dello store e Title DB e conserva descrizioni, immagini e screenshot. |
| [Sources/NXLibraryCore/Services/OnlineArtworkSources.swift](../Sources/NXLibraryCore/Services/OnlineArtworkSources.swift) | Ricava artwork Steam e loghi da MediaWiki e Wikimedia Commons. |
| [Sources/NXLibraryCore/Services/SeleneImporter.swift](../Sources/NXLibraryCore/Services/SeleneImporter.swift) | Importa suoni e wallpaper dalla cartella Selene dell’utente e risolve cue e fallback. |
| [Sources/NXLibraryCore/Services/MoreArtworkSources.swift](../Sources/NXLibraryCore/Services/MoreArtworkSources.swift) | Aggiunge matching dei nomi e sorgenti Xbox, GOG, Nintendo Europe, wiki e altri cataloghi. |
| [Sources/NXLibraryCore/Services/ArtworkBrowse.swift](../Sources/NXLibraryCore/Services/ArtworkBrowse.swift) | Sorgenti sfogliabili da Change artwork (LaunchBox, SteamGridDB): nomi cercati e risultati per tutti gli slot. |
| [Sources/NXLibraryCore/Services/LaunchBoxArt.swift](../Sources/NXLibraryCore/Services/LaunchBoxArt.swift) | Legge ricerca e pagina gioco di LaunchBox; dal payload Nuxt ricava anteprime, file pieni, tipo, regione e dimensioni; screenshot Gameplay. |
| [Sources/NXLibraryCore/Services/SteamGridDBArt.swift](../Sources/NXLibraryCore/Services/SteamGridDBArt.swift) | Conserva la chiave SteamGridDB in un file 0600 e interroga l’API v2 per griglie, hero, loghi e icone statiche accreditate. |
| [Sources/NXLibraryCore/Services/ScreenshotFallback.swift](../Sources/NXLibraryCore/Services/ScreenshotFallback.swift) | Conserva per 30 giorni gli screenshot LaunchBox dei giochi senza screenshot Title DB e li sovrappone ai metadati. |

## Core · presentazione Selene, focus e impostazioni

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Models/ButtonPrompts.swift](../Sources/NXLibraryCore/Models/ButtonPrompts.swift) | Traduce azioni in simboli o etichette per tastiera e controller Switch, Xbox e PlayStation. |
| [Sources/NXLibraryCore/Models/CollectionRow.swift](../Sources/NXLibraryCore/Models/CollectionRow.swift) | Definisce proporzioni delle copertine e geometria della riga Collection. |
| [Sources/NXLibraryCore/Models/DetailsFocus.swift](../Sources/NXLibraryCore/Models/DetailsFocus.swift) | Gestisce zone e spostamenti del focus nelle azioni e nelle bande di Details. |
| [Sources/NXLibraryCore/Models/FocusIndex.swift](../Sources/NXLibraryCore/Models/FocusIndex.swift) | Mantiene un indice di focus entro i limiti di una lista. |
| [Sources/NXLibraryCore/Models/SettingsRowAction.swift](../Sources/NXLibraryCore/Models/SettingsRowAction.swift) | Identifica azioni e righe Settings, mantenendo una sola azione primaria per riga senza accorpare giochi omonimi. |
| [Sources/NXLibraryCore/Models/GameOptionsPresentation.swift](../Sources/NXLibraryCore/Models/GameOptionsPresentation.swift) | Definisce righe, livelli, etichette, scelte runtime e focus di Game Options. |
| [Sources/NXLibraryCore/Models/HoldDetector.swift](../Sources/NXLibraryCore/Models/HoldDetector.swift) | Distingue pressione breve e prolungata usando un tempo fornito dal chiamante. |
| [Sources/NXLibraryCore/Models/MaterialIcon.swift](../Sources/NXLibraryCore/Models/MaterialIcon.swift) | Elenca i glifi del font Material Icons incluso nel bundle. |
| [Sources/NXLibraryCore/Models/MenuSelectionModel.swift](../Sources/NXLibraryCore/Models/MenuSelectionModel.swift) | Gestisce azioni selezionate nel control center e nelle scelte Power. |
| [Sources/NXLibraryCore/Models/MoonlightField.swift](../Sources/NXLibraryCore/Models/MoonlightField.swift) | Genera in modo deterministico i dati delle particelle per lo sfondo Metal. |
| [Sources/NXLibraryCore/Models/ScreenshotViewerState.swift](../Sources/NXLibraryCore/Models/ScreenshotViewerState.swift) | Mantiene indice e limiti della navigazione nel visualizzatore screenshot. |
| [Sources/NXLibraryCore/Models/SeleneCanvas.swift](../Sources/NXLibraryCore/Models/SeleneCanvas.swift) | Calcola scala uniforme, stage centrato e conversione delle unità del canvas 1920×1080. |
| [Sources/NXLibraryCore/Models/SelenePalette.swift](../Sources/NXLibraryCore/Models/SelenePalette.swift) | Decodifica palette, ordine del selettore e fallback della palette predefinita. |
| [Sources/NXLibraryCore/Models/SettingsCatalog.swift](../Sources/NXLibraryCore/Models/SettingsCatalog.swift) | Descrive righe, ricerca e valori modificati, distinguendo i default dei nuovi giochi dalla vibrazione in Controllers. |
| [Sources/NXLibraryCore/Models/SettingsSection.swift](../Sources/NXLibraryCore/Models/SettingsSection.swift) | Enumera gruppi, titoli e icone della schermata Settings. |
| [Sources/NXLibraryCore/Models/SpotlightPage.swift](../Sources/NXLibraryCore/Models/SpotlightPage.swift) | Calcola estratti delle descrizioni e stati dello scorrimento della pagina Spotlight. |
| [Sources/NXLibraryCore/Models/SpotlightRow.swift](../Sources/NXLibraryCore/Models/SpotlightRow.swift) | Costruisce la sequenza per UUID e salva riordini conservando giochi/fonti/card temporaneamente nascosti; Surprise mantiene il proprio contratto nxnative. |
| [Sources/NXLibraryCore/Models/SpotlightRowGeometry.swift](../Sources/NXLibraryCore/Models/SpotlightRowGeometry.swift) | Posti delle tessere nella riga, camera unica che la fa scorrere e finestra delle tessere create; posto, scala e camera lungo lo scorrimento dalla posizione continua della selezione. |
| [Sources/NXLibraryCore/Models/SpotlightState.swift](../Sources/NXLibraryCore/Models/SpotlightState.swift) | Gestisce selezione, focus, azioni e spostamento delle tile su Spotlight. |
| [Sources/NXLibraryCore/Models/ThemePicker.swift](../Sources/NXLibraryCore/Models/ThemePicker.swift) | Gestisce griglia, tab Wallpapers/Live e scelte di sfondo nel selettore temi. |
| [Sources/NXLibraryCore/Models/WallpaperCatalog.swift](../Sources/NXLibraryCore/Models/WallpaperCatalog.swift) | Elenca wallpaper e video, gruppi, nomi e file delle risorse incluse o importate. |
| [Sources/NXLibraryCore/Models/WallpaperPlacement.swift](../Sources/NXLibraryCore/Models/WallpaperPlacement.swift) | Decide dove applicare uno sfondo scelto fra schermi principali e Settings. |

## UI · Add Game e porting

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/AddGame/AddGameView.swift](../Sources/NXLibrary/Views/AddGame/AddGameView.swift) | Compone il wizard Choose/Review/Porting e gestisce ingresso, chiusura e navigazione. |
| [Sources/NXLibrary/Views/AddGame/AddGameView+Rows.swift](../Sources/NXLibrary/Views/AddGame/AddGameView+Rows.swift) | Definisce righe, focus, conferme e input dei passaggi del wizard. |
| [Sources/NXLibrary/Views/AddGame/AddGameRows.swift](../Sources/NXLibrary/Views/AddGame/AddGameRows.swift) | Rende le righe riutilizzabili per sorgenti e azioni di Add Game. |
| [Sources/NXLibrary/Views/AddGame/AddGameAction.swift](../Sources/NXLibrary/Views/AddGame/AddGameAction.swift) | Identifica le azioni navigabili dei passaggi del wizard. |
| [Sources/NXLibrary/Views/AddGame/AddGameStepThreeView.swift](../Sources/NXLibrary/Views/AddGame/AddGameStepThreeView.swift) | Mostra progresso, log, cancellazione ed esito del porting, con nuovo tentativo d’installazione per una build già pronta. |

## UI · Spotlight

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/Spotlight/SpotlightView.swift](../Sources/NXLibrary/Views/Spotlight/SpotlightView.swift) | Compone home, selezione, filtri, pagina del gioco e stato delle tile. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightView+Input.swift](../Sources/NXLibrary/Views/Spotlight/SpotlightView+Input.swift) | Traduce input, card, azioni, screenshot e riordino nel modello Spotlight. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightRowView.swift](../Sources/NXLibrary/Views/Spotlight/SpotlightRowView.swift) | Disegna la riga di tile con finestra visibile, focus e titoli; la faccia della card Mods (`ModsCardCover`). |
| [Sources/NXLibrary/Views/Spotlight/SpotlightTopBar.swift](../Sources/NXLibrary/Views/Spotlight/SpotlightTopBar.swift) | Disegna filtri, prompt dei dorsali e orologio condivisi con Collection. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightInfoView.swift](../Sources/NXLibrary/Views/Spotlight/SpotlightInfoView.swift) | Mostra logo, Play/Options/Favorite, statistiche e stato di porting del gioco selezionato. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightCardInfoView.swift](../Sources/NXLibrary/Views/Spotlight/SpotlightCardInfoView.swift) | Mostra informazioni e azioni delle card Collection, Surprise, Activity e Add Game. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightPageSections.swift](../Sources/NXLibrary/Views/Spotlight/SpotlightPageSections.swift) | Prepara generi, descrizione, Build & Sources e giochi correlati della pagina inferiore. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightScreenshotStrip.swift](../Sources/NXLibrary/Views/Spotlight/SpotlightScreenshotStrip.swift) | Disegna la striscia di screenshot con focus e stile adattabile alle schermate. |
| [Sources/NXLibrary/Views/Spotlight/SeleneArtBackground.swift](../Sources/NXLibrary/Views/Spotlight/SeleneArtBackground.swift) | Compone wallpaper, sfondo del gioco, transizioni e maschere Selene; l'arte è un `CALayer` che dissolve nel render server (`SeleneArtLayer`). |
| [Sources/NXLibrary/Views/Spotlight/SeleneHeroArt.swift](../Sources/NXLibrary/Views/Spotlight/SeleneHeroArt.swift) | Coordina il caricamento differito di hero e logo del gioco selezionato. |
| [Sources/NXLibrary/Views/Spotlight/GameArtLoader.swift](../Sources/NXLibrary/Views/Spotlight/GameArtLoader.swift) | Carica e memorizza hero e loghi attraverso ArtworkStore e decoder immagini dedicati. |

## UI · Collection e Details

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/Collection/CollectionView.swift](../Sources/NXLibrary/Views/Collection/CollectionView.swift) | Compone la libreria a copertine, filtri e informazioni del gioco selezionato. |
| [Sources/NXLibrary/Views/Collection/CollectionView+Input.swift](../Sources/NXLibrary/Views/Collection/CollectionView+Input.swift) | Gestisce navigazione, azioni e selezione nella Collection. |
| [Sources/NXLibrary/Views/Collection/CollectionCoverRow.swift](../Sources/NXLibrary/Views/Collection/CollectionCoverRow.swift) | Disegna copertine e scorrimento della riga Collection. |
| [Sources/NXLibrary/Views/Detail/GameDetailView.swift](../Sources/NXLibrary/Views/Detail/GameDetailView.swift) | Compone la pagina Details e coordina bande, modello corrente e focus. |
| [Sources/NXLibrary/Views/Detail/GameDetailView+Input.swift](../Sources/NXLibrary/Views/Detail/GameDetailView+Input.swift) | Gestisce azioni, screenshot, navigazione e passaggio ai giochi correlati da Details. |
| [Sources/NXLibrary/Views/Detail/DetailsBackground.swift](../Sources/NXLibrary/Views/Detail/DetailsBackground.swift) | Compone hero e maschere dello sfondo dedicato alla pagina Details. |
| [Sources/NXLibrary/Views/Detail/DetailsTopBlock.swift](../Sources/NXLibrary/Views/Detail/DetailsTopBlock.swift) | Mostra logo, crediti, azioni, statistiche, generi e descrizione del gioco. |
| [Sources/NXLibrary/Views/Detail/DetailsBands.swift](../Sources/NXLibrary/Views/Detail/DetailsBands.swift) | Disegna bande screenshot, mod, attività e giochi correlati con i relativi titoli. |
| [Sources/NXLibrary/Views/Detail/BuildSourcesPanel.swift](../Sources/NXLibrary/Views/Detail/BuildSourcesPanel.swift) | Prepara e disegna le azioni di app, sorgenti, rebuild, log e cartelle. |

## UI · Game Options, cheats e salvataggi

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/GameOptions/GameOptionsView.swift](../Sources/NXLibrary/Views/GameOptions/GameOptionsView.swift) | Presenta opzioni del gioco, Edit details, impostazioni runtime e conferme delle azioni. |
| [Sources/NXLibrary/Views/GameOptions/ChangeArtworkView.swift](../Sources/NXLibrary/Views/GameOptions/ChangeArtworkView.swift) | Seleziona artwork per titolo da rete o file e indica dove viene usato, con stato ad altezza stabile. |
| [Sources/NXLibrary/Views/GameOptions/ChangeMetadataView.swift](../Sources/NXLibrary/Views/GameOptions/ChangeMetadataView.swift) | Offre alternative o testo personalizzato per descrizione, generi, crediti e data. |
| [Sources/NXLibrary/Views/GameOptions/CheatsPanel.swift](../Sources/NXLibrary/Views/GameOptions/CheatsPanel.swift) | Presenta file, master switch, codici, importazione, rimozione e stato di scrittura dei cheats. |
| [Sources/NXLibrary/Views/GameOptions/ModsPanel.swift](../Sources/NXLibrary/Views/GameOptions/ModsPanel.swift) | Game options → Mods: accende, ordina e sposta nel Cestino le mod RomFS, apre la cartella mods. |
| [Sources/NXLibrary/Views/Detail/ModDetailPanel.swift](../Sources/NXLibrary/Views/Detail/ModDetailPanel.swift) | Dettaglio di una mod GameBanana: immagini, autore, versione, descrizione, Install/Update e link. |
| [Sources/NXLibrary/Views/Detail/GameBananaFindPanel.swift](../Sources/NXLibrary/Views/Detail/GameBananaFindPanel.swift) | Cerca su GameBanana la pagina del gioco quando l'abbinamento automatico non basta. |
| [Sources/NXLibrary/ViewModels/ModStoreHost.swift](../Sources/NXLibrary/ViewModels/ModStoreHost.swift) | Store della card Mods: catalogo, ordinamento, focus, chip Installed/Update e pannello della mod. |
| [Sources/NXLibrary/Views/Store/ModStorePage.swift](../Sources/NXLibrary/Views/Store/ModStorePage.swift) | Pagina dello store: barra di ordinamento, banner Featured, righe di tessere; disegna solo le sezioni vicine al focus. |
| [Sources/NXLibrary/Views/Store/GameBananaBlur.swift](../Sources/NXLibrary/Views/Store/GameBananaBlur.swift) | Arte di una mod rimpicciolita e sfocata una volta, fuori dal main thread, e tenuta in memoria: sfondo del Featured. |
| [Sources/NXLibrary/ViewModels/ModsBandHost.swift](../Sources/NXLibrary/ViewModels/ModsBandHost.swift) | Fascia Mods condivisa da Spotlight e Details: mod installate, GameBanana, pannelli di dettaglio e ricerca. |
| [Sources/NXLibrary/ViewModels/GameBananaServices.swift](../Sources/NXLibrary/ViewModels/GameBananaServices.swift) | Client, cache delle immagini e abbinamenti GameBanana condivisi da tutta l'app. |
| [Sources/NXLibrary/Views/GameOptions/SavesPanel.swift](../Sources/NXLibrary/Views/GameOptions/SavesPanel.swift) | Presenta azioni sui save, anteprime, errori e popup di successo a scomparsa automatica. |
| [Sources/NXLibrary/Views/GameOptions/MoreSettingsPanel.swift](../Sources/NXLibrary/Views/GameOptions/MoreSettingsPanel.swift) | Mostra le impostazioni del launcher.json senza riga dedicata: interruttori, scelte e intervalli; le righe fissate da env.txt restano attenuate. |
| [Sources/NXLibrary/Views/GameOptions/SaveImportDetails.swift](../Sources/NXLibrary/Views/GameOptions/SaveImportDetails.swift) | Disegna percorsi From/To centrati, riquadri leggeri e freccia con riflesso direzionale. |

## UI · Settings

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/Settings/SettingsView.swift](../Sources/NXLibrary/Views/Settings/SettingsView.swift) | Compone sidebar e gruppo attivo e coordina focus, input e reset delle impostazioni. |
| [Sources/NXLibrary/Views/Settings/SettingsSidebar.swift](../Sources/NXLibrary/Views/Settings/SettingsSidebar.swift) | Disegna intestazione e lista dei gruppi della schermata Settings. |
| [Sources/NXLibrary/Views/Settings/SettingsSectionContent.swift](../Sources/NXLibrary/Views/Settings/SettingsSectionContent.swift) | Instrada il gruppo selezionato e fornisce sottotitoli e formattazioni condivise. |
| [Sources/NXLibrary/Views/Settings/SettingsSearchSection.swift](../Sources/NXLibrary/Views/Settings/SettingsSearchSection.swift) | Presenta ricerca e Changed, con apertura del gruppo della riga selezionata. |
| [Sources/NXLibrary/Views/Settings/SettingsStartUpSection.swift](../Sources/NXLibrary/Views/Settings/SettingsStartUpSection.swift) | Espone schermata iniziale, intro, Setup e controlli degli aggiornamenti all’avvio. |
| [Sources/NXLibrary/Views/Settings/SettingsNavigationSection.swift](../Sources/NXLibrary/Views/Settings/SettingsNavigationSection.swift) | Espone le preferenze di navigazione e dei suggerimenti dei tasti. |
| [Sources/NXLibrary/Views/Settings/SettingsSpotlightSection.swift](../Sources/NXLibrary/Views/Settings/SettingsSpotlightSection.swift) | Espone card, ordine e preferenze della home Spotlight. |
| [Sources/NXLibrary/Views/Settings/SettingsSoundSection.swift](../Sources/NXLibrary/Views/Settings/SettingsSoundSection.swift) | Espone volume e suoni e importa risorse da una cartella Selene. |
| [Sources/NXLibrary/Views/Settings/SettingsLookSection.swift](../Sources/NXLibrary/Views/Settings/SettingsLookSection.swift) | Espone palette, wallpaper, luminosità, adattamento, animazione e aspetto dell’icona. |
| [Sources/NXLibrary/Views/Settings/SettingsGamesSection.swift](../Sources/NXLibrary/Views/Settings/SettingsGamesSection.swift) | Espone default runtime, cloud saves e gestione dei giochi nascosti. |
| [Sources/NXLibrary/Views/Settings/SettingsControllersSection.swift](../Sources/NXLibrary/Views/Settings/SettingsControllersSection.swift) | Espone preferenze dei controller e relative azioni di gruppo. |
| [Sources/NXLibrary/Views/Settings/SettingsLibrarySection.swift](../Sources/NXLibrary/Views/Settings/SettingsLibrarySection.swift) | Espone cartella della libreria, scansione e notifiche dei porting. |
| [Sources/NXLibrary/Views/Settings/SettingsStorageSection.swift](../Sources/NXLibrary/Views/Settings/SettingsStorageSection.swift) | Mostra spazio occupato, azioni su cache/log e accesso alla cartella comune dei backup verificati. |
| [Sources/NXLibrary/Views/Settings/SettingsEngineSection.swift](../Sources/NXLibrary/Views/Settings/SettingsEngineSection.swift) | Mostra checkout, pin, gate, toolchain, runtime, chiavi e changelog upstream. |
| [Sources/NXLibrary/Views/Settings/SettingsAboutSection.swift](../Sources/NXLibrary/Views/Settings/SettingsAboutSection.swift) | Mostra versione, attribuzioni, diagnostica, documentazione e aggiornamenti dell’app. |

## UI · Setup, avvio, ricerca e console

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/Setup/SetupCheckView.swift](../Sources/NXLibrary/Views/Setup/SetupCheckView.swift) | Disegna schede dei requisiti, dettagli, progressi e pulsanti Install all/Continue. |
| [Sources/NXLibrary/Views/Setup/SetupCheckView+Input.swift](../Sources/NXLibrary/Views/Setup/SetupCheckView+Input.swift) | Gestisce focus iniziale, navigazione della griglia e attivazione delle schede Setup. |
| [Sources/NXLibrary/Views/Setup/YourGamesSetupView.swift](../Sources/NXLibrary/Views/Setup/YourGamesSetupView.swift) | Disegna scelta cartella, primo gioco, apertura libreria e Skip; condivide l'indicatore dei due passaggi e gestisce mouse, tastiera e controller. |
| [Sources/NXLibrary/Views/Launch/IntroView.swift](../Sources/NXLibrary/Views/Launch/IntroView.swift) | Mostra l’intro a freddo (solo lo sfondo animato, senza icona né scritta) e gestisce il salto tramite input. |
| [Sources/NXLibrary/Views/Launch/LaunchScreenView.swift](../Sources/NXLibrary/Views/Launch/LaunchScreenView.swift) | Mostra artwork e logo durante l’avvio del gioco e chiude l’overlay a finestra visibile. |
| [Sources/NXLibrary/Views/Search/FindGameView.swift](../Sources/NXLibrary/Views/Search/FindGameView.swift) | Presenta ricerca nella libreria e risultati navigabili e inoltra il gioco scelto alla home. |
| [Sources/NXLibrary/Views/Console/ConsoleView.swift](../Sources/NXLibrary/Views/Console/ConsoleView.swift) | Mostra log e stato corrente e offre copia di log e diagnostica. |
| [Sources/NXLibrary/Views/ControlsView.swift](../Sources/NXLibrary/Views/ControlsView.swift) | Guida Selene separata fra Library e In game; stato controller, rilevamento e scorrimento delle righe con tastiera/controller. |

## UI · componenti condivisi

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/Components/BuildLiveLogsDrawer.swift](../Sources/NXLibrary/Views/Components/BuildLiveLogsDrawer.swift) | Mostra il log del porting con livelli, scroll sul nuovo contenuto e apertura o chiusura. |
| [Sources/NXLibrary/Views/Components/BuildStageStepperView.swift](../Sources/NXLibrary/Views/Components/BuildStageStepperView.swift) | Disegna elenco delle fasi e relativo stato di completamento. |
| [Sources/NXLibrary/Views/Components/DropZoneView.swift](../Sources/NXLibrary/Views/Components/DropZoneView.swift) | Presenta la zona di trascinamento per scegliere le sorgenti del gioco. |
| [Sources/NXLibrary/Views/Components/GameIconProvider.swift](../Sources/NXLibrary/Views/Components/GameIconProvider.swift) | Fornisce e conserva l’icona estratta dai bundle dei giochi. |
| [Sources/NXLibrary/Views/Components/PortingArtLook.swift](../Sources/NXLibrary/Views/Components/PortingArtLook.swift) | Applica alla tile desaturazione, riempimento e barra di avanzamento del porting. |
| [Sources/NXLibrary/Views/Components/ScreenshotViewer.swift](../Sources/NXLibrary/Views/Components/ScreenshotViewer.swift) | Mostra screenshot a schermo pieno e navigazione fra le immagini. |
| [Sources/NXLibrary/Views/Components/SeleneBottomScrim.swift](../Sources/NXLibrary/Views/Components/SeleneBottomScrim.swift) | Definisce maschera inferiore e spazi riservati ai suggerimenti dei tasti. |
| [Sources/NXLibrary/Views/Components/SeleneConfirmDialog.swift](../Sources/NXLibrary/Views/Components/SeleneConfirmDialog.swift) | Definisce card e pulsanti delle conferme, scelte multiple e SeleneSuccessNotice. |
| [Sources/NXLibrary/Views/Components/AppUpdateDialog.swift](../Sources/NXLibrary/Views/Components/AppUpdateDialog.swift) | Presenta controllo aggiornamenti, note di release, errori e progresso nel dialogo dell’app. |
| [Sources/NXLibrary/Views/Components/SeleneHintsBar.swift](../Sources/NXLibrary/Views/Components/SeleneHintsBar.swift) | Disegna i suggerimenti contestuali allineati ai bordi inferiori della schermata. |
| [Sources/NXLibrary/Views/Components/SeleneHomeChrome.swift](../Sources/NXLibrary/Views/Components/SeleneHomeChrome.swift) | Rende elementi condivisi della cornice e dei controlli della home Selene. |
| [Sources/NXLibrary/Views/Components/SeleneOptionRow.swift](../Sources/NXLibrary/Views/Components/SeleneOptionRow.swift) | Disegna righe di opzioni con icona, titolo, descrizione, focus e contenuto laterale. |
| [Sources/NXLibrary/Views/Components/SelenePillButton.swift](../Sources/NXLibrary/Views/Components/SelenePillButton.swift) | Disegna il pulsante pill condiviso da azioni e dialoghi. |
| [Sources/NXLibrary/Views/Components/SelenePromptBadge.swift](../Sources/NXLibrary/Views/Components/SelenePromptBadge.swift) | Rende simbolo o etichetta del pulsante del controller o della tastiera. |
| [Sources/NXLibrary/Views/Components/SeleneReveal.swift](../Sources/NXLibrary/Views/Components/SeleneReveal.swift) | Applica l’animazione di comparsa Selene rispettando la preferenza Riduci movimento. |
| [Sources/NXLibrary/Views/Components/SeleneSettingsRow.swift](../Sources/NXLibrary/Views/Components/SeleneSettingsRow.swift) | Disegna righe delle impostazioni con valore, focus e azione. |
| [Sources/NXLibrary/Views/Components/SeleneStatsRow.swift](../Sources/NXLibrary/Views/Components/SeleneStatsRow.swift) | Disegna le statistiche compatte del gioco nella libreria. |
| [Sources/NXLibrary/Views/Components/SeleneSwitch.swift](../Sources/NXLibrary/Views/Components/SeleneSwitch.swift) | Disegna lo switch coerente con il tema. |
| [Sources/NXLibrary/Views/Components/SeleneTileRing.swift](../Sources/NXLibrary/Views/Components/SeleneTileRing.swift) | Ring e riflesso della tile selezionata; con Reduce motion il ring fermo disegnato da SwiftUI. |
| [Sources/NXLibrary/Views/Components/TileMotionLayers.swift](../Sources/NXLibrary/Views/Components/TileMotionLayers.swift) | Ring e riflesso come layer Core Animation in loop: nessun ridisegno dell'app tra un frame e l'altro. |
| [Sources/NXLibrary/Views/Components/SeleneValueChip.swift](../Sources/NXLibrary/Views/Components/SeleneValueChip.swift) | Rende valori e badge compatti nel linguaggio visivo Selene. |
| [Sources/NXLibrary/Views/Components/SpotlightTileArtwork.swift](../Sources/NXLibrary/Views/Components/SpotlightTileArtwork.swift) | Carica e disegna l’artwork quadrato usato dalle tile Spotlight. |
| [Sources/NXLibrary/Views/Components/SwitchBoxArtCover.swift](../Sources/NXLibrary/Views/Components/SwitchBoxArtCover.swift) | Carica e disegna la copertina Switch mantenendone le proporzioni. |
| [Sources/NXLibrary/Views/Components/SteamGridDBKeyDialog.swift](../Sources/NXLibrary/Views/Components/SteamGridDBKeyDialog.swift) | Popup per incollare e verificare la chiave SteamGridDB da Settings → Look e da Change artwork. |
| [Sources/NXLibrary/Views/Components/SwitchPlatformIcon.swift](../Sources/NXLibrary/Views/Components/SwitchPlatformIcon.swift) | Icona vettoriale della console Switch per la riga della piattaforma. |

## UI · temi, rendering e sfondi

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/Theme/ThemeStore.swift](../Sources/NXLibrary/Views/Theme/ThemeStore.swift) | Mantiene palette attiva, wallpaper inclusi e importati e operazioni sulle scelte dell’utente. |
| [Sources/NXLibrary/Views/Theme/SeleneTheme.swift](../Sources/NXLibrary/Views/Theme/SeleneTheme.swift) | Espone colori, stili, curve di animazione, focus e chiavi dell’ambiente Selene. |
| [Sources/NXLibrary/Views/Theme/SeleneFonts.swift](../Sources/NXLibrary/Views/Theme/SeleneFonts.swift) | Registra il font incluso e definisce MaterialIconView. |
| [Sources/NXLibrary/Views/Theme/SeleneCanvasEnvironment.swift](../Sources/NXLibrary/Views/Theme/SeleneCanvasEnvironment.swift) | Pubblica il canvas della finestra e applica unità e font scalati. |
| [Sources/NXLibrary/Views/Theme/SeleneBackdrop.swift](../Sources/NXLibrary/Views/Theme/SeleneBackdrop.swift) | Compone gradiente, wallpaper e Moonlight e conserva le immagini già decodificate. |
| [Sources/NXLibrary/Views/Theme/MoonlightRenderer.swift](../Sources/NXLibrary/Views/Theme/MoonlightRenderer.swift) | Gestisce device Metal, pipeline, display link, particelle e rendering live o statico del backdrop. |
| [Sources/NXLibrary/Views/Theme/MoonlightShaders.swift](../Sources/NXLibrary/Views/Theme/MoonlightShaders.swift) | Contiene le sorgenti shader Metal dello sfondo compilate a runtime. |
| [Sources/NXLibrary/Views/Theme/LiveBackdrop.swift](../Sources/NXLibrary/Views/Theme/LiveBackdrop.swift) | Integra video AVFoundation in loop e adatta riproduzione e frame alla visibilità della finestra. |
| [Sources/NXLibrary/Views/Theme/OnlineBrowsePanel.swift](../Sources/NXLibrary/Views/Theme/OnlineBrowsePanel.swift) | Mantiene stato di ricerca e download e presenta griglia e miniature degli sfondi online. |
| [Sources/NXLibrary/Views/Theme/ThemePickerView.swift](../Sources/NXLibrary/Views/Theme/ThemePickerView.swift) | Presenta palette, tab Wallpapers/Live, provider e scelta della destinazione dello sfondo. |
| [Sources/NXLibrary/Views/Theme/ThemePreview.swift](../Sources/NXLibrary/Views/Theme/ThemePreview.swift) | Disegna un’anteprima della home con palette e sfondo in valutazione. |

## Test e fixture

| File | Responsabilità aggiuntiva |
|---|---|
| [Tests/NXLibraryCoreTests/SettingsRowActionTests.swift](../Tests/NXLibraryCoreTests/SettingsRowActionTests.swift) | Regressioni per giochi omonimi e azioni secondarie della medesima riga. |
| [Tests/NXLibraryCoreTests/ScreenshotFallbackTests.swift](../Tests/NXLibraryCoreTests/ScreenshotFallbackTests.swift) | Screenshot LaunchBox cercati una volta e conservati, precedenza di quelli propri e dimensione piena della scelta. |
| [Tests/NXLibraryCoreTests/SteamGridDBArtTests.swift](../Tests/NXLibraryCoreTests/SteamGridDBArtTests.swift) | Chiave privata, richieste con la chiave solo a SteamGridDB, crediti, anteprime e ricerca da Browse online. |
| [Tests/PublicationChecks/test_publication.py](../Tests/PublicationChecks/test_publication.py) | Esegue il controllo reale in repository temporanee: sorgenti consentiti, file vietati, chiavi sintetiche senza esposizione e runtime non corrispondente al lock. |
| [Tests/PublicationChecks/test_update_archive.py](../Tests/PublicationChecks/test_update_archive.py) | Verifica il controllo ZIP reale con bundle sintetici, symlink, percorsi non sicuri, collisioni Unicode, header incoerenti e dimensioni eccessive. |

| File | Responsabilità |
|---|---|
| [Tests/NXLibraryCoreTests/ActivitySummaryTests.swift](../Tests/NXLibraryCoreTests/ActivitySummaryTests.swift) | Totali settimanali, distribuzione giornaliera, sessioni aperte e passaggi di mezzanotte. |
| [Tests/NXLibraryCoreTests/AppRouterTests.swift](../Tests/NXLibraryCoreTests/AppRouterTests.swift) | Route iniziale, ritorno, overlay e richieste di selezione o spostamento. |
| [Tests/NXLibraryCoreTests/AppSettingsStoreTests.swift](../Tests/NXLibraryCoreTests/AppSettingsStoreTests.swift) | Default, persistenza, errori osservabili, conservazione dei file illeggibili e compatibilità dei campi mancanti. |
| [Tests/NXLibraryCoreTests/AppSizeCacheTests.swift](../Tests/NXLibraryCoreTests/AppSizeCacheTests.swift) | Riuso delle dimensioni, invalidazione sui bundle modificati e scansione senza falso stato vuoto. |
| [Tests/NXLibraryCoreTests/AppUpdateTests.swift](../Tests/NXLibraryCoreTests/AppUpdateTests.swift) | Versioni, asset release, requisiti, digest, identità del bundle e sostituzione dell’app. |
| [Tests/NXLibraryCoreTests/AppUpdatePresentationTests.swift](../Tests/NXLibraryCoreTests/AppUpdatePresentationTests.swift) | Verifica che i controlli manuali non permettano sostituzioni di copie di sviluppo, in sola lettura o con una versione uguale/più recente. |
| [Tests/NXLibraryCoreTests/ArtworkPickerFocusTests.swift](../Tests/NXLibraryCoreTests/ArtworkPickerFocusTests.swift) | Spostamenti nella griglia dei candidati e passaggi fra slot di artwork. |
| [Tests/NXLibraryCoreTests/ArtworkPickerTests.swift](../Tests/NXLibraryCoreTests/ArtworkPickerTests.swift) | Decodifica Title DB, candidati per slot e scelte manuali. |
| [Tests/NXLibraryCoreTests/AutomaticIconTests.swift](../Tests/NXLibraryCoreTests/AutomaticIconTests.swift) | Priorità delle fonti, ambiguità, edizioni, cache offline, immagini invalide e opt-out del sito. |
| [Tests/NXLibraryCoreTests/ArtworkStoreTests.swift](../Tests/NXLibraryCoreTests/ArtworkStoreTests.swift) | Cache, download, immagini trasparenti, ridimensionamento e fallback. |
| [Tests/NXLibraryCoreTests/BoxArtServiceTests.swift](../Tests/NXLibraryCoreTests/BoxArtServiceTests.swift) | Matching GameTDB, regioni e durata delle ricerche senza risultato. |
| [Tests/NXLibraryCoreTests/BuildCommandBuilderTests.swift](../Tests/NXLibraryCoreTests/BuildCommandBuilderTests.swift) | Contratto CLI, opzioni runtime/build e propagazione dell’override Metal. |
| [Tests/NXLibraryCoreTests/BuildEventParserTests.swift](../Tests/NXLibraryCoreTests/BuildEventParserTests.swift) | Eventi JSON, fasi, percentuali e righe ordinarie di log. |
| [Tests/NXLibraryCoreTests/BuildOutputInstallerTests.swift](../Tests/NXLibraryCoreTests/BuildOutputInstallerTests.swift) | Pubblicazione atomica, interruzioni, tentativi ripetuti, copie fra volumi e conservazione dei bundle in caso di errore. |
| [Tests/NXLibraryCoreTests/BuildScratchTests.swift](../Tests/NXLibraryCoreTests/BuildScratchTests.swift) | Posto dei file di build per Mac, disco esterno, exFAT e workspaces spostati; workspace gestiti e cartelle temporanee. |
| [Tests/NXLibraryCoreTests/BuildServiceTests.swift](../Tests/NXLibraryCoreTests/BuildServiceTests.swift) | Processi, eventi, cancellazione, lease e conservazione della build dopo un errore d’installazione, con retry senza nuova esecuzione del motore. |
| [Tests/NXLibraryCoreTests/GameAppDestinationTests.swift](../Tests/NXLibraryCoreTests/GameAppDestinationTests.swift) | Installazione e scoperta nella cartella scelta, rebuild dopo il cambio cartella, conflitti di nome, sorgenti protette e cartelle non disponibili o di sola lettura. |
| [Tests/NXLibraryCoreTests/ButtonPromptsTests.swift](../Tests/NXLibraryCoreTests/ButtonPromptsTests.swift) | Etichette e simboli per tastiera, controller e scelte esplicite dell’utente. |
| [Tests/NXLibraryCoreTests/CheatCopyTests.swift](../Tests/NXLibraryCoreTests/CheatCopyTests.swift) | Testi di intestazione, rifiuto, conferma e rimozione dei cheats. |
| [Tests/NXLibraryCoreTests/CheatFileTests.swift](../Tests/NXLibraryCoreTests/CheatFileTests.swift) | Parsing dei codici secondo il motore, sezioni, metadati, nomi duplicati e codici non validi. |
| [Tests/NXLibraryCoreTests/CheatInstallTests.swift](../Tests/NXLibraryCoreTests/CheatInstallTests.swift) | Build ID, title ID, file senza nome, cartelle e decisioni di installazione. |
| [Tests/NXLibraryCoreTests/CheatLocatorTests.swift](../Tests/NXLibraryCoreTests/CheatLocatorTests.swift) | Identità nel bundle e precedenza dei percorsi cheats e delle variabili del launcher. |
| [Tests/NXLibraryCoreTests/CheatStatusTests.swift](../Tests/NXLibraryCoreTests/CheatStatusTests.swift) | Ancestry del motore, necessità di rebuild, valore della riga e indicatore attivo. |
| [Tests/NXLibraryCoreTests/CheatStoreTests.swift](../Tests/NXLibraryCoreTests/CheatStoreTests.swift) | Installazione, enabled, master switch, sostituzione e metadati dei file cheats. |
| [Tests/NXLibraryCoreTests/ModStoreTests.swift](../Tests/NXLibraryCoreTests/ModStoreTests.swift) | Ordine, acceso/spento, limite dell'overlay, conflitti, Cestino e righe dell'`env.txt` delle mod. |
| [Tests/NXLibraryCoreTests/ModFolderScannerTests.swift](../Tests/NXLibraryCoreTests/ModFolderScannerTests.swift) | Voci della cartella mods, layout `romfs`/Atmosphère, symlink, file relativi e file nascosti. |
| [Tests/NXLibraryCoreTests/EnvFileEditorTests.swift](../Tests/NXLibraryCoreTests/EnvFileEditorTests.swift) | Modifica di una chiave dell'`env.txt`: commenti, duplicati, CRLF, merge al lancio. |
| [Tests/NXLibraryCoreTests/GameBananaAPITests.swift](../Tests/NXLibraryCoreTests/GameBananaAPITests.swift) | Decodifica tollerante delle risposte, URL, host fidati, contenuto degli archivi e testo dalle descrizioni. |
| [Tests/NXLibraryCoreTests/GameBananaClientTests.swift](../Tests/NXLibraryCoreTests/GameBananaClientTests.swift) | User-Agent, durata della cache, rete assente, errori del server, limite di richieste e cache immagini. |
| [Tests/NXLibraryCoreTests/GameBananaBandModelTests.swift](../Tests/NXLibraryCoreTests/GameBananaBandModelTests.swift) | Cambio di gioco, avanzi di installazione, ricerca per nome con controller, mod in due gruppi con l'arte pronta. |
| [Tests/NXLibraryCoreTests/TextScrollTests.swift](../Tests/NXLibraryCoreTests/TextScrollTests.swift) | Descrizione dopo Read more, limiti dello scorrimento, riga mostrata intera e passo Su/Giù tra le righe. |
| [Tests/NXLibraryCoreTests/GameBananaMatchTests.swift](../Tests/NXLibraryCoreTests/GameBananaMatchTests.swift) | Abbinamento per nome, voci per piattaforma e memoria della scelta. |
| [Tests/NXLibraryCoreTests/ModSupportTests.swift](../Tests/NXLibraryCoreTests/ModSupportTests.swift) | Quali archivi funzionano, radice `romfs`, title ID, visibilità e nomi di cartella. |
| [Tests/NXLibraryCoreTests/AvailableModsFinderTests.swift](../Tests/NXLibraryCoreTests/AvailableModsFinderTests.swift) | Mod che funzionano in ordine, limiti di ricerca, rete assente e aggiornamenti. |
| [Tests/NXLibraryCoreTests/ModInstallerTests.swift](../Tests/NXLibraryCoreTests/ModInstallerTests.swift) | Installazione con archivi veri: MD5, percorsi pericolosi, mod di codice, errori, gioco aperto, spazio, nomi, aggiornamenti. |
| [Tests/NXLibraryCoreTests/CloudSavesTests.swift](../Tests/NXLibraryCoreTests/CloudSavesTests.swift) | Cartelle cloud, preferenze per gioco e decodifica delle impostazioni precedenti. |
| [Tests/NXLibraryCoreTests/CompatibilityCheckerTests.swift](../Tests/NXLibraryCoreTests/CompatibilityCheckerTests.swift) | Commit, modifiche ammesse nel checkout, Metal, CLI e override del gate. |
| [Tests/NXLibraryCoreTests/DetailsFocusTests.swift](../Tests/NXLibraryCoreTests/DetailsFocusTests.swift) | Spostamento nelle bande di Details, limiti e sezioni vuote. |
| [Tests/NXLibraryCoreTests/DirectorySizeTests.swift](../Tests/NXLibraryCoreTests/DirectorySizeTests.swift) | Somma dei file regolari ignorando nascosti e collegamenti; cartella mancante a zero. |
| [Tests/NXLibraryCoreTests/DiagnosticsReportTests.swift](../Tests/NXLibraryCoreTests/DiagnosticsReportTests.swift) | Rimozione di percorsi personali e chiavi e contenuto delle sezioni diagnostiche. |
| [Tests/NXLibraryCoreTests/EngineLocationTests.swift](../Tests/NXLibraryCoreTests/EngineLocationTests.swift) | Percorso predefinito, cartella scelta e fallback quando scompare. |
| [Tests/NXLibraryCoreTests/EngineToolchainTests.swift](../Tests/NXLibraryCoreTests/EngineToolchainTests.swift) | Rilevamento del runtime incluso e fallback a Python e strumenti del checkout. |
| [Tests/NXLibraryCoreTests/EnvironmentTests.swift](../Tests/NXLibraryCoreTests/EnvironmentTests.swift) | Parsing di Metal e controlli dell’ambiente mediante runner sintetico. |
| [Tests/NXLibraryCoreTests/FocusIndexTests.swift](../Tests/NXLibraryCoreTests/FocusIndexTests.swift) | Movimento limitato agli elementi della lista e liste vuote. |
| [Tests/NXLibraryCoreTests/GameDetailPresentationTests.swift](../Tests/NXLibraryCoreTests/GameDetailPresentationTests.swift) | Disponibilità di build e sorgenti e formattazione di metadati e azioni Details. |
| [Tests/NXLibraryCoreTests/GameResourceStateTests.swift](../Tests/NXLibraryCoreTests/GameResourceStateTests.swift) | App spostata e ripristinata, input assenti, Play senza sorgenti e conservazione di workspace e build attive durante Refresh. |
| [Tests/NXLibraryCoreTests/GameOptionsPresentationTests.swift](../Tests/NXLibraryCoreTests/GameOptionsPresentationTests.swift) | Ordine delle righe, focus, visibilità dei controlli e valori runtime. |
| [Tests/NXLibraryCoreTests/GameRuntimeConfigTests.swift](../Tests/NXLibraryCoreTests/GameRuntimeConfigTests.swift) | Review di giochi nuovi ed esistenti, persistenza, lingua del rebuild e conversione DM_* con merge di env.txt. |
| [Tests/NXLibraryCoreTests/GameTDBTests.swift](../Tests/NXLibraryCoreTests/GameTDBTests.swift) | Database, normalizzazione dei nomi, regioni e matching delle copertine. |
| [Tests/NXLibraryCoreTests/HoldDetectorTests.swift](../Tests/NXLibraryCoreTests/HoldDetectorTests.swift) | Soglia temporale e distinzione fra pressione breve e prolungata. |
| [Tests/NXLibraryCoreTests/ImportServiceTests.swift](../Tests/NXLibraryCoreTests/ImportServiceTests.swift) | Riconoscimento dei bundle nxnative e normalizzazione degli identificativi. |
| [Tests/NXLibraryCoreTests/CursorIdleTests.swift](../Tests/NXLibraryCoreTests/CursorIdleTests.swift) | Ritardo del cursore, ripristino e ripartenza dopo interruzione o attività del mouse. |
| [Tests/NXLibraryCoreTests/InstallProgressTests.swift](../Tests/NXLibraryCoreTests/InstallProgressTests.swift) | Fasi Git, percentuali, byte e ricomposizione delle righe parziali. |
| [Tests/NXLibraryCoreTests/KeyCheckTests.swift](../Tests/NXLibraryCoreTests/KeyCheckTests.swift) | Cifratura e lettura delle intestazioni sintetiche e chiavi richieste dalle sorgenti. |
| [Tests/NXLibraryCoreTests/KeyStoreTests.swift](../Tests/NXLibraryCoreTests/KeyStoreTests.swift) | Importazione e sostituzione atomica, conservazione della copia precedente in caso di errore, permessi 0600 e riepilogo. |
| [Tests/NXLibraryCoreTests/LaunchServiceTests.swift](../Tests/NXLibraryCoreTests/LaunchServiceTests.swift) | Scrittura dell’ambiente, avvio del bundle e propagazione degli errori. |
| [Tests/NXLibraryCoreTests/LauncherSettingsTests.swift](../Tests/NXLibraryCoreTests/LauncherSettingsTests.swift) | Metadati launcher.json e fallback dei controlli per build precedenti. |
| [Tests/NXLibraryCoreTests/LaunchBoxArtTests.swift](../Tests/NXLibraryCoreTests/LaunchBoxArtTests.swift) | Risultati di ricerca, scelta della voce Switch/Switch 2, payload Nuxt con file pieni e screenshot. |
| [Tests/NXLibraryCoreTests/LibraryPresentationTests.swift](../Tests/NXLibraryCoreTests/LibraryPresentationTests.swift) | Formattazione dei metadati e delle statistiche della libreria. |
| [Tests/NXLibraryCoreTests/LibraryQueryTests.swift](../Tests/NXLibraryCoreTests/LibraryQueryTests.swift) | Filtri, ricerca, ordinamento e rapporto con la cronologia di gioco. |
| [Tests/NXLibraryCoreTests/LibraryStoreTests.swift](../Tests/NXLibraryCoreTests/LibraryStoreTests.swift) | Persistenza, merge, recupero e conservazione di installazioni in attesa ed errori dopo scansioni ripetute. |
| [Tests/NXLibraryCoreTests/MaterialIconTests.swift](../Tests/NXLibraryCoreTests/MaterialIconTests.swift) | Integrità dei glifi e del font delle icone. |
| [Tests/NXLibraryCoreTests/MetadataPickerTests.swift](../Tests/NXLibraryCoreTests/MetadataPickerTests.swift) | Alternative per campo, override persistiti e applicazione ai metadati del gioco. |
| [Tests/NXLibraryCoreTests/MoonlightFieldTests.swift](../Tests/NXLibraryCoreTests/MoonlightFieldTests.swift) | Generazione deterministica e limiti dei dati delle particelle. |
| [Tests/NXLibraryCoreTests/MoreArtworkSourcesTests.swift](../Tests/NXLibraryCoreTests/MoreArtworkSourcesTests.swift) | Matching dei titoli e risposte delle sorgenti artwork aggiuntive. |
| [Tests/NXLibraryCoreTests/MoreLikeThisTests.swift](../Tests/NXLibraryCoreTests/MoreLikeThisTests.swift) | Ranking dei giochi correlati e gestione di metadati incompleti. |
| [Tests/NXLibraryCoreTests/NintendoStoreMetadataTests.swift](../Tests/NXLibraryCoreTests/NintendoStoreMetadataTests.swift) | Decodifica store e Title DB, cache, screenshot e risposte incomplete. |
| [Tests/NXLibraryCoreTests/ReleaseNotesLayoutTests.swift](../Tests/NXLibraryCoreTests/ReleaseNotesLayoutTests.swift) | Titoli, voci e righe vuote delle note di release, una voce per riga. |
| [Tests/NXLibraryCoreTests/NewestEngineTests.swift](../Tests/NXLibraryCoreTests/NewestEngineTests.swift) | Lock e Metal di main, validità della scelta, comandi git del cambio, gate Newest engine, scheda Setup e frase. |
| [Tests/NXLibraryCoreTests/NUPSourceCatalogTests.swift](../Tests/NXLibraryCoreTests/NUPSourceCatalogTests.swift) | Magic NUP, cartelle, lettura tramite engine, nomi NACP, profili mancanti, selezione e NUP senza base. |
| [Tests/NXLibraryCoreTests/NXNativeGameSettingsTests.swift](../Tests/NXLibraryCoreTests/NXNativeGameSettingsTests.swift) | Build senza adattatore, migrazione da env.txt, scrittura dei soli valori diversi dal default e chiavi fissate. |
| [Tests/NXLibraryCoreTests/OnlineArtworkSourcesTests.swift](../Tests/NXLibraryCoreTests/OnlineArtworkSourcesTests.swift) | Ricerca Steam e loghi MediaWiki/Commons con risposte sintetiche. |
| [Tests/NXLibraryCoreTests/OnlineBackgroundsTests.swift](../Tests/NXLibraryCoreTests/OnlineBackgroundsTests.swift) | Parser degli sfondi fissi, risoluzioni, crediti e nomi dei download. |
| [Tests/NXLibraryCoreTests/OnlineLiveSourcesTests.swift](../Tests/NXLibraryCoreTests/OnlineLiveSourcesTests.swift) | Parser e indirizzi dei provider di sfondi video. |
| [Tests/NXLibraryCoreTests/PendingInstallTests.swift](../Tests/NXLibraryCoreTests/PendingInstallTests.swift) | Staging, installazione e cartelle da conservare; riapertura e scansione prima di completare un’installazione già pubblicata. |
| [Tests/NXLibraryCoreTests/PlaySessionStoreTests.swift](../Tests/NXLibraryCoreTests/PlaySessionStoreTests.swift) | Persistenza, durata, heartbeat e riconciliazione delle sessioni. |
| [Tests/NXLibraryCoreTests/PortedGameTests.swift](../Tests/NXLibraryCoreTests/PortedGameTests.swift) | Modello del gioco, compatibilità dei record e condizioni di disponibilità dell’app. |
| [Tests/NXLibraryCoreTests/PortingFailureReasonTests.swift](../Tests/NXLibraryCoreTests/PortingFailureReasonTests.swift) | Classificazione dei fallimenti e corrispondenza con i messaggi del pin, anche da un checkout separato scelto con NX_TEST_ENGINE_REPO. |
| [Tests/NXLibraryCoreTests/PortingNoticeTests.swift](../Tests/NXLibraryCoreTests/PortingNoticeTests.swift) | Condizioni e testi delle notifiche di esito del porting. |
| [Tests/NXLibraryCoreTests/PortingPresentationTests.swift](../Tests/NXLibraryCoreTests/PortingPresentationTests.swift) | ETA, tile, pill e rappresentazione dei fallimenti del porting. |
| [Tests/NXLibraryCoreTests/AppIconPreferenceTests.swift](../Tests/NXLibraryCoreTests/AppIconPreferenceTests.swift) | Ambito dell’icona: scelta esplicita, vecchie librerie, scansioni, persistenza e rebuild. |
| [Tests/NXLibraryCoreTests/AppIconProgressTests.swift](../Tests/NXLibraryCoreTests/AppIconProgressTests.swift) | Verifica che l'esito di un'icona mancante non sovrascriva il log o segnali una build fallita. |
| [Tests/NXLibraryCoreTests/IconLaunchWaitTests.swift](../Tests/NXLibraryCoreTests/IconLaunchWaitTests.swift) | Attesa Play: successo, errore, annullamento, gioco diverso e nuova firma in coda. |
| [Tests/NXLibraryCoreTests/PipelineArchiveProgressTests.swift](../Tests/NXLibraryCoreTests/PipelineArchiveProgressTests.swift) | Log obsoleti, righe incomplete, cache riusata, gruppi paralleli e GPU diverse. |
| [Tests/NXLibraryCoreTests/PortingProgressTests.swift](../Tests/NXLibraryCoreTests/PortingProgressTests.swift) | Aggregazione delle fasi, avanzamento monotono e peso degli shader. |
| [Tests/NXLibraryCoreTests/ProdKeysLocationsTests.swift](../Tests/NXLibraryCoreTests/ProdKeysLocationsTests.swift) | Selezione e validazione dei possibili percorsi delle chiavi. |
| [Tests/NXLibraryCoreTests/RunningGamesTests.swift](../Tests/NXLibraryCoreTests/RunningGamesTests.swift) | Associazione bundle ID, applicazioni aperte e voci della libreria. |
| [Tests/NXLibraryCoreTests/RyujinxSaveImportTests.swift](../Tests/NXLibraryCoreTests/RyujinxSaveImportTests.swift) | Contenitori e slot Ryujinx, identità del titolo e importazioni con strutture e destinazioni differenti. |
| [Tests/NXLibraryCoreTests/SaveLocationTests.swift](../Tests/NXLibraryCoreTests/SaveLocationTests.swift) | Identificativi, percorsi sicuri, precedenze dell’ambiente e cloud effettivo. |
| [Tests/NXLibraryCoreTests/SaveOperationGateTests.swift](../Tests/NXLibraryCoreTests/SaveOperationGateTests.swift) | Lease per titolo, esclusione globale dell’updater, operazioni concorrenti e recupero bloccato senza I/O attivo. |
| [Tests/NXLibraryCoreTests/SavePresentationTests.swift](../Tests/NXLibraryCoreTests/SavePresentationTests.swift) | Riepiloghi, date, nomi degli slot e accessibilità dell’azione di importazione. |
| [Tests/NXLibraryCoreTests/SaveSnapshotStoreTests.swift](../Tests/NXLibraryCoreTests/SaveSnapshotStoreTests.swift) | Inventari, xattr, integrità dei backup, staging e selezione dei backup datati. |
| [Tests/NXLibraryCoreTests/SaveTestHome.swift](../Tests/NXLibraryCoreTests/SaveTestHome.swift) | Fixture condivisa che crea una home e un bundle sintetici in una directory temporanea dedicata. |
| [Tests/NXLibraryCoreTests/SaveTransactionTests.swift](../Tests/NXLibraryCoreTests/SaveTransactionTests.swift) | Sostituzioni, interruzioni, rollback, modifiche esterne e compatibilità dei journal precedenti. |
| [Tests/NXLibraryCoreTests/ScreenshotViewerStateTests.swift](../Tests/NXLibraryCoreTests/ScreenshotViewerStateTests.swift) | Indice, avanzamento e limiti del visualizzatore screenshot. |
| [Tests/NXLibraryCoreTests/SeleneCanvasTests.swift](../Tests/NXLibraryCoreTests/SeleneCanvasTests.swift) | Scala, centratura e conversione delle unità del canvas. |
| [Tests/NXLibraryCoreTests/SeleneImporterTests.swift](../Tests/NXLibraryCoreTests/SeleneImporterTests.swift) | Copia delle risorse Selene e risoluzione dei cue sonori. |
| [Tests/NXLibraryCoreTests/SelenePaletteTests.swift](../Tests/NXLibraryCoreTests/SelenePaletteTests.swift) | Lettura delle palette, ordine e fallback. |
| [Tests/NXLibraryCoreTests/SettingsCatalogTests.swift](../Tests/NXLibraryCoreTests/SettingsCatalogTests.swift) | Catalogo delle righe, ricerca e identificazione dei valori modificati. |
| [Tests/NXLibraryCoreTests/SetupActionsTests.swift](../Tests/NXLibraryCoreTests/SetupActionsTests.swift) | Comandi Git del Setup e rispetto delle modifiche locali nel checkout. |
| [Tests/NXLibraryCoreTests/SetupCheckTests.swift](../Tests/NXLibraryCoreTests/SetupCheckTests.swift) | Stati delle schede, requisiti, override e condizioni di riapertura del Setup. |
| [Tests/NXLibraryCoreTests/SetupGridTests.swift](../Tests/NXLibraryCoreTests/SetupGridTests.swift) | Bilanciamento delle righe e spostamento del focus fra le schede. |
| [Tests/NXLibraryCoreTests/FirstRunSetupTests.swift](../Tests/NXLibraryCoreTests/FirstRunSetupTests.swift) | Skip persistente, ripresa, riapertura manuale senza reset, attesa della scansione, separazione dei requisiti e navigazione del primo gioco. |
| [Tests/NXLibraryCoreTests/SmokeTests.swift](../Tests/NXLibraryCoreTests/SmokeTests.swift) | Importabilità e versione nominale del modulo Core. |
| [Tests/NXLibraryCoreTests/SourceCatalogTests.swift](../Tests/NXLibraryCoreTests/SourceCatalogTests.swift) | Fixture PFS0/CNMT e riconoscimento di base, aggiornamenti e DLC. |
| [Tests/NXLibraryCoreTests/EngineUpgradeSourcesTests.swift](../Tests/NXLibraryCoreTests/EngineUpgradeSourcesTests.swift) | Copre cartelle estratte, pacchetti multipli, selezione, persistenza, bridge Python, file illeggibili e restaging senza perdita di cache o originali. |
| [Tests/NXLibraryCoreTests/SpotlightPageTests.swift](../Tests/NXLibraryCoreTests/SpotlightPageTests.swift) | Estratti del testo e stati dello scorrimento della pagina del gioco. |
| [Tests/NXLibraryCoreTests/SpotlightRowTests.swift](../Tests/NXLibraryCoreTests/SpotlightRowTests.swift) | Ordine, card, riordino delle tile e selezione Surprise. |
| [Tests/NXLibraryCoreTests/SpotlightStateTests.swift](../Tests/NXLibraryCoreTests/SpotlightStateTests.swift) | Focus, selezione, filtri, azioni e spostamento delle tile Spotlight. |
| [Tests/NXLibraryCoreTests/StorageManagerTests.swift](../Tests/NXLibraryCoreTests/StorageManagerTests.swift) | Misure per gioco, cache condivise e nascoste, pulizia selettiva, protezione di app/sorgenti/symlink, file incoerenti e volumi/cartelle non disponibili. |
| [Tests/NXLibraryCoreTests/ThemePickerTests.swift](../Tests/NXLibraryCoreTests/ThemePickerTests.swift) | Navigazione della griglia, tab e selezione degli sfondi. |
| [Tests/NXLibraryCoreTests/ToolchainGateCopyTests.swift](../Tests/NXLibraryCoreTests/ToolchainGateCopyTests.swift) | Testi del gate per Metal certificato, precedente, successivo e altre cause di blocco. |
| [Tests/NXLibraryCoreTests/ToolchainRequirementsTests.swift](../Tests/NXLibraryCoreTests/ToolchainRequirementsTests.swift) | Versioni minime e identificativi degli asset Metal da scaricare. |
| [Tests/NXLibraryCoreTests/UpstreamCheckerTests.swift](../Tests/NXLibraryCoreTests/UpstreamCheckerTests.swift) | Changelog HTTP, cache e gestione degli errori del provider. |
| [Tests/NXLibraryCoreTests/UpstreamCopyTests.swift](../Tests/NXLibraryCoreTests/UpstreamCopyTests.swift) | Testi della riga upstream e adozione dei commit attraverso gli aggiornamenti dell’app. |
| [Tests/NXLibraryCoreTests/WallpaperBrightnessTests.swift](../Tests/NXLibraryCoreTests/WallpaperBrightnessTests.swift) | Maschere e livelli di luminosità dello sfondo. |
| [Tests/NXLibraryCoreTests/WallpaperCatalogTests.swift](../Tests/NXLibraryCoreTests/WallpaperCatalogTests.swift) | Catalogo dei file inclusi/importati, gruppi e tipi immagine/video. |
| [Tests/NXLibraryCoreTests/WallpaperPlacementTests.swift](../Tests/NXLibraryCoreTests/WallpaperPlacementTests.swift) | Destinazione dello sfondo fra home e impostazioni. |
| [Tests/NXLibraryCoreTests/WorkspaceManagerTests.swift](../Tests/NXLibraryCoreTests/WorkspaceManagerTests.swift) | Collegamenti simbolici, cache adottate e rilevamento dei link interrotti. |

## Script di sviluppo e packaging

| File | Responsabilità |
|---|---|
| [scripts/build_app.sh](../scripts/build_app.sh) | Compila in staging, prepara plist, runtime e risorse, verifica la firma e pubblica il bundle con sostituzione atomica. |
| [scripts/install_built_app.swift](../scripts/install_built_app.swift) | Piccolo ingresso CLI che riusa BuildOutputInstaller per installare NX Library dopo il packaging. |
| [scripts/check_publication.py](../scripts/check_publication.py) | Rifiuta contenuti personali o di gioco versionati e formati di segreto riconoscibili; verifica il runtime rispetto al lock prima del packaging. |
| [scripts/build_dmg.sh](../scripts/build_dmg.sh) | Confeziona un bundle già costruito in un’immagine DMG di sviluppo. |
| [scripts/bundle_runtime.sh](../scripts/bundle_runtime.sh) | Prepara Python e strumenti dalle versioni bloccate, verifica gli hash e firma il runtime incluso. |
| [scripts/release.sh](../scripts/release.sh) | Controlla i prerequisiti e produce ZIP e DMG di release, con pubblicazione esplicita opzionale. |
| [scripts/validate_update.py](../scripts/validate_update.py) | Verifica struttura, percorsi e limiti degli archivi prima dell'estrazione, sia nel bundle sia durante il packaging delle release. |
| [scripts/relink_macho.py](../scripts/relink_macho.py) | Riscrive riferimenti Mach-O dei binari e delle librerie affinché il runtime incluso sia rilocabile. |
| [scripts/make_icons.swift](../scripts/make_icons.swift) | Genera le risorse dell’icona dell’app nelle varianti usate dal bundle. |
| [scripts/import_selene_palettes.py](../scripts/import_selene_palettes.py) | Converte le palette Selene nel catalogo JSON usato dall’app. |

## Risorse incluse

| File | Responsabilità aggiuntiva |
|---|---|
| [Resources/IconArtwork.png](../Resources/IconArtwork.png) | Master quadrato originale dell’icona, fornito dall’utente e creato con AI. |
| [Resources/IconArtwork.md](../Resources/IconArtwork.md) | Provenienza dichiarata, brief e riproduzione delle varianti tramite il generatore. |

| File | Responsabilità |
|---|---|
| [Resources/AppIcon.icns](../Resources/AppIcon.icns) | Icona macOS del bundle NX Library. |
| [Resources/AppIcon-Dark.png](../Resources/AppIcon-Dark.png) | Variante scura dell’icona dell’app. |
| [Resources/AppIcon-Light.png](../Resources/AppIcon-Light.png) | Variante chiara dell’icona dell’app. |
| [Resources/AppIcon-Mono.png](../Resources/AppIcon-Mono.png) | Variante monocromatica dell’icona dell’app. |
| [Resources/Selene/palettes.json](../Resources/Selene/palettes.json) | Catalogo serializzato delle palette disponibili. |
| [Resources/Selene/Fonts/MaterialIcons-Regular.ttf](../Resources/Selene/Fonts/MaterialIcons-Regular.ttf) | Font dei glifi Material Icons disegnati dalla UI. |
| [Resources/Selene/Fonts/MaterialIcons-LICENSE.txt](../Resources/Selene/Fonts/MaterialIcons-LICENSE.txt) | Licenza del font Material Icons incluso. |
| [Resources/Selene/NOTICE.txt](../Resources/Selene/NOTICE.txt) | Attribuzioni delle risorse Selene incluse. |
| [Resources/Selene/NOTICE-palettes.txt](../Resources/Selene/NOTICE-palettes.txt) | Attribuzioni delle palette incluse con esse. |
| [Resources/Selene/Sounds/Boot.wav](../Resources/Selene/Sounds/Boot.wav) | Cue sonoro incluso per l’avvio. |
| [Resources/Selene/Sounds/Key.wav](../Resources/Selene/Sounds/Key.wav) | Cue sonoro incluso per la pressione dei tasti. |
| [Resources/Selene/Sounds/Success.wav](../Resources/Selene/Sounds/Success.wav) | Cue sonoro incluso per il completamento di un’azione. |
| [Resources/Selene/Sounds/navigation.wav](../Resources/Selene/Sounds/navigation.wav) | Cue sonoro incluso per la navigazione. |

## Screenshot e demo

| File | Responsabilità |
|---|---|
| [docs/media/README.md](../docs/media/README.md) | Registra provenienza e posizione degli screenshot, ottimizzazione delle copie e inserimento del video futuro. |
| [docs/media/spotlight.webp](../docs/media/spotlight.webp) | Presenta Spotlight e la libreria nell'apertura del README. |
| [docs/media/game-details.webp](../docs/media/game-details.webp) | Mostra dettagli, attività e informazioni di build di un gioco. |
| [docs/media/quick-menu.webp](../docs/media/quick-menu.webp) | Illustra il menu rapido sopra la libreria. |
| [docs/media/porting-progress.webp](../docs/media/porting-progress.webp) | Mostra l'avanzamento di un porting dalla schermata Spotlight. |
| [docs/media/settings.webp](../docs/media/settings.webp) | Illustra le categorie di Settings e il pannello Start-up. |
| [docs/media/color-themes.webp](../docs/media/color-themes.webp) | Mostra la scelta delle palette con anteprima della libreria. |
| [docs/media/static-wallpapers.webp](../docs/media/static-wallpapers.webp) | Illustra il browser degli sfondi statici e la relativa anteprima. |
| [docs/media/live-wallpapers.webp](../docs/media/live-wallpapers.webp) | Mostra il selettore degli sfondi animati e l'importazione di video personali. |

## Documentazione tecnica e registri datati

| File | Responsabilità |
|---|---|
| [docs/architecture.md](../docs/architecture.md) | Spiega architettura corrente, confini dei componenti, flussi, dati su disco e verifiche. |
| [docs/development.md](../docs/development.md) | Documenta prerequisiti, runtime, build, debug, verifiche, CI e preparazione delle release. |
| [docs/file-map.md](../docs/file-map.md) | Catalogo corrente delle responsabilità di tutti i file versionati, suddiviso per area. |
| [docs/upstream-upgrades/2026-10-27-06b7b3e-4f24ce6.md](../docs/upstream-upgrades/2026-10-27-06b7b3e-4f24ce6.md) | Registro della revisione del delta, scelte di adozione e verifiche per questo upgrade del motore. |
| [docs/upstream-upgrades/2026-10-27-4f24ce6-1963fab.md](../docs/upstream-upgrades/2026-10-27-4f24ce6-1963fab.md) | Registro della revisione del delta, scelte di adozione e verifiche per questo upgrade del motore. |
| [docs/upstream-upgrades/2026-10-29-1963fab-ee369f0.md](../docs/upstream-upgrades/2026-10-29-1963fab-ee369f0.md) | Registro della revisione del delta, scelte di adozione e verifiche per questo upgrade del motore. |
| [docs/upstream-upgrades/2026-10-31-ee369f0-2716f78.md](../docs/upstream-upgrades/2026-10-31-ee369f0-2716f78.md) | Registro della revisione del delta, scelte di adozione e verifiche per questo upgrade del motore. |
| [docs/upstream-upgrades/2026-11-02-2716f78-163a9905-review.md](../docs/upstream-upgrades/2026-11-02-2716f78-163a9905-review.md) | Registra revisione e adozione del pin: toolchain certificata, nuove sorgenti, interventi UI, prove sintetiche e conferma manuale di build e avvio. |
| [docs/upstream-upgrades/2026-11-02-163a9905-65501fbb-review.md](../docs/upstream-upgrades/2026-11-02-163a9905-65501fbb-review.md) | Registra l’adozione di 65501fbb, le decisioni UI/backend, i test, la build certificata e l’avvio manuale. |
| [docs/upstream-upgrades/2026-11-03-65501fbb-b64a5ff0-review.md](../docs/upstream-upgrades/2026-11-03-65501fbb-b64a5ff0-review.md) | Registra l’adozione di b64a5ff0, le scelte UI/backend, la build certificata e la conferma manuale di avvio. |
| [docs/upstream-upgrades/2026-11-06-4a0551e4-04df08d4-review.md](../docs/upstream-upgrades/2026-11-06-4a0551e4-04df08d4-review.md) | Revisione del candidato 04df08d4: tre righe Front-ends, cache e librerie shader in un file, etichetta **Updating shader cache**, pacchetti solo di sviluppo in tools.txt; in attesa di build certificato e avvio confermato. |
| [docs/upstream-upgrades/2026-11-05-b64a5ff0-4a0551e4-review.md](../docs/upstream-upgrades/2026-11-05-b64a5ff0-4a0551e4-review.md) | Registra l’adozione di 4a0551e4: righe Front-ends, profili provvisori, avviso dell’archivio pipeline, uscita con Home, build Wonder certificata e avvio confermato. |
| [docs/upstream-upgrades/README.md](../docs/upstream-upgrades/README.md) | Checklist obbligatoria e indice delle revisioni del pin upstream. |

## Aggiornare questo catalogo

Quando si aggiunge, rinomina o rimuove un file versionato, aggiornare la sua riga e il totale iniziale. Quando cambia un flusso o una responsabilità, aggiornare anche la sezione corrispondente della guida tecnica. Le descrizioni dei test indicano l’ambito dei controlli, mentre l’esito di esecuzione appartiene ai rapporti di verifica.

## Localizzazione (hotfix non pubblicato)

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Models/AppLocale.swift](../Sources/NXLibraryCore/Models/AppLocale.swift) | Sei lingue, risoluzione delle preferenze e regione indipendente; nomi e ricerca delle regioni. |
| [Sources/NXLibraryCore/Models/GameGenre.swift](../Sources/NXLibraryCore/Models/GameGenre.swift) | Generi noti tradotti alla presentazione; dati originali e generi personali conservati. |
| [Sources/NXLibrary/Views/Theme/AppLocaleEnvironment.swift](../Sources/NXLibrary/Views/Theme/AppLocaleEnvironment.swift) | Contesto della lingua reattivo per le viste; conserva identità, selezione e focus. |
| [Sources/NXLibraryCore/Services/AppLocalization.swift](../Sources/NXLibraryCore/Services/AppLocalization.swift) | Contesto osservabile, lookup portabile delle risorse e interpolazioni/plurali. |
| [Sources/NXLibraryCore/Resources/Localizable.xcstrings](../Sources/NXLibraryCore/Resources/Localizable.xcstrings) | Testi condivisi e traduzioni en/it/fr/de/es/pt-BR. |
| [Sources/NXLibrary/Views/Settings/LocalePicker.swift](../Sources/NXLibrary/Views/Settings/LocalePicker.swift) | Scelta diretta della lingua e ricerca dei formati regionali, con focus tastiera/controller e codici stabili. |
| [Tests/NXLibraryCoreTests/AppLocaleTests.swift](../Tests/NXLibraryCoreTests/AppLocaleTests.swift) | Preferenze, migrazione, formati, ricerca, identità e traduzioni native. |
| [scripts/check_localizations.py](../scripts/check_localizations.py) | Verifica copertura, placeholder, plurali e risorse nel bundle installato. |
| [Tests/PublicationChecks/test_localizations.py](../Tests/PublicationChecks/test_localizations.py) | Rifiuto di cataloghi incompleti e bundle senza risorse. |

### Profilo di sviluppo del launcher

| File | Responsabilità |
|---|---|
| [AppDataProfile.swift](../Sources/NXLibraryCore/Services/AppDataProfile.swift) | Policy di percorsi, cache, preferenze e staging del profilo. |
| [DevelopmentProfileImporter.swift](../Sources/NXLibraryCore/Services/DevelopmentProfileImporter.swift) | Copia iniziale selettiva, hash, validazione e ripresa senza modificare la sorgente. |
| [DevelopmentOperationStore.swift](../Sources/NXLibraryCore/Services/DevelopmentOperationStore.swift) | Autorizzazioni persistenti per le operazioni richieste nella Dev, distinte da quelle importate. |
| [DevelopmentStartupView.swift](../Sources/NXLibrary/Views/Launch/DevelopmentStartupView.swift) | Avvio asincrono, errore recuperabile e costruzione della shell dopo l'importazione. |
| [AppShellState.swift](../Sources/NXLibrary/Views/Shell/AppShellState.swift) | Prepara coordinatore, router, fonti, lingua e tema prima dell’inserimento della libreria nel grafo SwiftUI. |
| [DevelopmentProfileTests.swift](../Tests/NXLibraryCoreTests/DevelopmentProfileTests.swift) | Copia, conservazione della sorgente, errori, sessioni, symlink e ripetizione. |
| [DevelopmentProfileEffectTests.swift](../Tests/NXLibraryCoreTests/DevelopmentProfileEffectTests.swift) | Mod, staging e persistenza delle richieste esplicite. |
| [test_profile_boundaries.py](../Tests/PublicationChecks/test_profile_boundaries.py) | Guardia contro percorsi/defaults del launcher non centralizzati. |
| [check_app_profile.swift](../scripts/check_app_profile.swift) | Prova senza UI di identità, accesso reale alle preferenze e percorsi nel pacchetto prodotto dalla build; non importa né scrive dati. |

### Rilevamento Steam — modulo in sviluppo

| File | Responsabilità |
|---|---|
| [SteamKeyValues.swift](../Sources/NXLibraryCore/Services/Steam/SteamKeyValues.swift) | Lettura limitata del formato testuale con campi duplicati conservati e accesso non ambiguo; nessuna direttiva eseguita. |
| [InstallationFileSnapshot.swift](../Sources/NXLibraryCore/Services/Steam/InstallationFileSnapshot.swift) | Letture limitate e non bloccanti di file regolari; verifica dell'identità prima della pubblicazione. |
| [InstallationDirectorySnapshot.swift](../Sources/NXLibraryCore/Services/Steam/InstallationDirectorySnapshot.swift) | Lettura incrementale delle cartelle, budget anche sulle voci nascoste e annullamento durante l'enumerazione. |
| [NativeMacApplication.swift](../Sources/NXLibraryCore/Services/Steam/NativeMacApplication.swift) | Evidenze del bundle Mac e degli header eseguibili, architetture e categoria dichiarata, senza avvio. |
| [SteamLibrarySource.swift](../Sources/NXLibraryCore/Services/Steam/SteamLibrarySource.swift) | Snapshot delle librerie/manifest dichiarati, disponibilità, ambiguità, limiti e annullamento; non modifica il catalogo. |
| [SteamKeyValuesTests.swift](../Tests/NXLibraryCoreTests/SteamKeyValuesTests.swift) | Formato, escape, Unicode, duplicati, input troncati e limiti del parser. |
| [NativeMacApplicationTests.swift](../Tests/NXLibraryCoreTests/NativeMacApplicationTests.swift) | Fixture native, classificazione, traversal/link, metadata non regolari e header invalidi. |
| [SteamLibrarySourceTests.swift](../Tests/NXLibraryCoreTests/SteamLibrarySourceTests.swift) | Più fonti, dischi assenti, identità, file cambiati, limiti e assenza di scritture. |
| [SteamDiscoveryConsistencyTests.swift](../Tests/NXLibraryCoreTests/SteamDiscoveryConsistencyTests.swift) | Mutazioni reali di inventario e app durante scan, indice inizialmente assente, budget e propagazione dell'annullamento. |
| [SteamTestSupport.swift](../Tests/NXLibraryCoreTests/SteamTestSupport.swift) | Genera solo metadati e header sintetici nelle directory temporanee dei test. |

## Catalogo comune (attivazione nella Dev in attesa di validazione)

| File | Responsabilità |
|---|---|
| [CatalogGame.swift](../Sources/NXLibraryCore/Models/CatalogGame.swift) | Record tipizzato nxnative/Steam, identità e personalizzazioni con namespace, osservazioni delle installazioni. |
| [CatalogDocument.swift](../Sources/NXLibraryCore/Models/CatalogDocument.swift) | Schema, revisione, provenienza legacy, configurazione delle fonti e validazione delle identità. |
| [CatalogGamePresentation.swift](../Sources/NXLibraryCore/Models/CatalogGamePresentation.swift) | Contratto comune per presentazione, operazioni supportate e target di avvio; nessuna operazione I/O. |
| [CatalogStore.swift](../Sources/NXLibraryCore/Services/Catalog/CatalogStore.swift) | Conversione conservativa, letture limitate, revisioni attese e serializzazione degli scrittori. |
| [CatalogPublication.swift](../Sources/NXLibraryCore/Services/Catalog/CatalogPublication.swift) | Staging verificato, creazione esclusiva e sostituzione atomica, con confine di errore controllabile. |
| [SteamCatalogReconciler.swift](../Sources/NXLibraryCore/Services/Catalog/SteamCatalogReconciler.swift) | Ticket e fusione pura degli snapshot Steam, identità conservate e assenza trattata secondo completezza. |
| [CatalogModelTests.swift](../Tests/NXLibraryCoreTests/CatalogModelTests.swift) | Conservazione del record precedente, proprietà comuni e separazione delle azioni per integrazione. |
| [CatalogStoreTests.swift](../Tests/NXLibraryCoreTests/CatalogStoreTests.swift) | Conversione, backup, corruzione, versioni, input cambiati, scrittori concorrenti e guasti di pubblicazione. |
| [SteamCatalogReconcilerTests.swift](../Tests/NXLibraryCoreTests/SteamCatalogReconcilerTests.swift) | Identità, aggiornamenti, installazioni ambigue, fonti assenti e scansioni obsolete/parziali. |
| [CatalogTestSupport.swift](../Tests/NXLibraryCoreTests/CatalogTestSupport.swift) | Record legacy sintetico completo e scrittura di fixture; nessun contenuto di gioco. |

| File | Responsabilità aggiunta per l'attivazione |
|---|---|
| [CatalogRepository.swift](../Sources/NXLibraryCore/Services/Catalog/CatalogRepository.swift) | Modifiche tipizzate sull'ultimo catalogo, senza replay di effetti esterni; risultati build limitati ai propri campi. |
| [NXNativeLibraryMerge.swift](../Sources/NXLibraryCore/Services/NXNativeLibraryMerge.swift) | Unico merge nxnative condiviso tra archivio precedente e catalogo comune. |
| [CatalogRecovery.swift](../Sources/NXLibraryCore/Models/CatalogRecovery.swift) | Offerta di recupero con impronte del principale/backup, rivalidata all'accettazione. |
| [CatalogPersonalizations.swift](../Sources/NXLibraryCore/Models/CatalogPersonalizations.swift) | Lookup personali immutabili per identità e radici distinte per integrazione. |
| [CatalogErrorCopy.swift](../Sources/NXLibraryCore/Services/Catalog/CatalogErrorCopy.swift) | Errori recuperabili del catalogo nelle sei lingue. |
| [AppViewModel+Catalog.swift](../Sources/NXLibrary/ViewModels/AppViewModel+Catalog.swift) | Rilettura, errori e retry del risultato di build senza libreria di ripiego. |
| [CatalogPersonalizationsEnvironment.swift](../Sources/NXLibrary/Views/Theme/CatalogPersonalizationsEnvironment.swift) | Dipendenza SwiftUI esplicita per le chiavi personali stabili. |
| [CatalogRepositoryTests.swift](../Tests/NXLibraryCoreTests/CatalogRepositoryTests.swift) | Modifiche concorrenti, confini per integrazione, campi build e conservazione di Steam/legacy. |
| [CatalogRecoveryTests.swift](../Tests/NXLibraryCoreTests/CatalogRecoveryTests.swift) | Recupero esplicito, offerte obsolete, file conservati e importazione del catalogo Dev. |
| [CatalogPersonalizationTests.swift](../Tests/NXLibraryCoreTests/CatalogPersonalizationTests.swift) | Rinomina senza perdita del lookup e isolamento di chiavi uguali tra fonti. |

| [CatalogBuildRecoveries.swift](../Sources/NXLibraryCore/Models/CatalogBuildRecoveries.swift) | Generazioni di build non ancora salvate, selezione del retry e conferma della sola generazione persistita. |
| [CatalogBuildRecoveryTests.swift](../Tests/NXLibraryCoreTests/CatalogBuildRecoveryTests.swift) | Vecchia build persistita e nuova conservata, sospensione automatica e conferme obsolete. |
| [run_notices.py](../Tests/CatalogAppChecks/run_notices.py) | Esegue i metodi reali degli avvisi e del ponte legacy senza finestre, dopo swift test. |
| [NoticeHost.swift](../Tests/CatalogAppChecks/NoticeHost.swift) | Host minimo per i controlli applicativi, con storage reale e dati sintetici temporanei. |


## Fonti e libreria mista (Dev, in attesa di validazione)

| File | Responsabilità |
|---|---|
| [CatalogSourcesModel.swift](../Sources/NXLibraryCore/Services/Catalog/CatalogSourcesModel.swift) | Opt-in, worker annullabile e stato Steam; pubblica solo documenti salvati dal repository. |
| [CatalogLibraryProjection.swift](../Sources/NXLibraryCore/Models/CatalogLibraryProjection.swift) | Visibilità comune per fonti attive e giochi riconosciuti; nessuna scansione. |
| [AppViewModel+Sources.swift](../Sources/NXLibrary/ViewModels/AppViewModel+Sources.swift) | Proiezione visibile, selezione comune e modifiche personali tipizzate. |
| [SettingsSourcesSection.swift](../Sources/NXLibrary/Views/Settings/SettingsSourcesSection.swift) | Attivazione, refresh/cancel, cartella Steam, revisione e recupero dei nascosti. |
| [CatalogNativeArtwork.swift](../Sources/NXLibrary/Views/Catalog/CatalogNativeArtwork.swift) | Icona nativa in sola lettura e indicatore Steam; nessun artwork Nintendo. |
| [CatalogSteamInfo.swift](../Sources/NXLibrary/Views/Catalog/CatalogSteamInfo.swift) | Intestazione condivisa nelle due librerie: Play/Riprendi/Annulla/Riprova, Opzioni e preferito, con la nota di stato. |
| [SteamPlayCoordinator.swift](../Sources/NXLibrary/Services/SteamPlayCoordinator.swift) | Play tramite il client Steam verificato e sessioni reali dal processo dell’app installata. |
| [SteamOptionsView.swift](../Sources/NXLibrary/Views/GameOptions/SteamOptionsView.swift) | Opzioni di un gioco Steam con l’aspetto e l’input di Game options: Play, Edit details, Move, preferito, nascosto, Finder. |
| [PersonalizationSubject.swift](../Sources/NXLibrary/Views/GameOptions/PersonalizationSubject.swift) | Il gioco che Change artwork e Change metadata personalizzano: scelte nxnative o archivio personale Steam, senza icona Mac per Steam. |
| [CatalogSourcesRepositoryTests.swift](../Tests/NXLibraryCoreTests/CatalogSourcesRepositoryTests.swift) | Compatibilità generazioni, cambi fonte, preferenze concorrenti e adozione NX esplicita. |
| [CatalogSourcesModelTests.swift](../Tests/NXLibraryCoreTests/CatalogSourcesModelTests.swift) | Opt-in, annullamento, risultati vecchi, cambio radice e recupero errori. |
| [CatalogLibraryQueryTests.swift](../Tests/NXLibraryCoreTests/CatalogLibraryQueryTests.swift) | Visibilità, ricerca/filtri misti e selezione per UUID senza sessioni simulate. |


## Metadati Steam (Dev, in attesa di validazione)

| File | Responsabilità |
|---|---|
| [SteamMetadata.swift](../Sources/NXLibraryCore/Services/Steam/SteamMetadata.swift) | Dati store Steam tipizzati, lingua e URL immagini verificati. |
| [SteamMetadataService.swift](../Sources/NXLibraryCore/Services/Steam/SteamMetadataService.swift) | Richieste limitate/coalescenti, cache per lingua, ripiego offline e immagini ridimensionate. |
| [SteamArtwork.swift](../Sources/NXLibrary/Views/Catalog/SteamArtwork.swift) | Immagini e sfondi Steam, con precedenza alle scelte personali e annullamento dei risultati UI obsoleti. |
| [SteamPersonalizations.swift](../Sources/NXLibrary/Views/Catalog/SteamPersonalizations.swift) | Archivio delle scelte personali Steam (metadati e artwork), modificate da Change artwork e Change metadata. |
| [SteamMetadataTests.swift](../Tests/NXLibraryCoreTests/SteamMetadataTests.swift) | Identità, lingue, offline, URL, concorrenza e pubblicazione dopo salvataggio riuscito. |

| [SteamPersonalizationStore.swift](../Sources/NXLibraryCore/Services/Steam/SteamPersonalizationStore.swift) | Pubblicazione unica di metadati e riferimenti artwork; fallimenti e Automatic conservano le scelte coerenti. |

| [run_backdrop.py](../Tests/CatalogAppChecks/run_backdrop.py) | Esegue il corpo reale di SteamBackdrop senza finestra né impostazioni implicite; regressione del crash all’avvio. |
