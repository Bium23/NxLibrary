# Arcane — i flussi principali

Ogni flusso segue un'azione dall'input all'effetto, nominando i tipi che se ne occupano. I dettagli e le regole di ogni passo sono nella sezione dell'area in [architecture.md](architecture.md); come costruire un pezzo nuovo è in [conventions.md](../working-on-it/conventions.md). Se un flusso cambia, il suo schema si aggiorna nello stesso commit.

- [1. Avvio dell'app](#1-avvio-dellapp)
- [2. Dal disco alla libreria](#2-dal-disco-alla-libreria)
- [3. Play di un gioco Switch (nxnative)](#3-play-di-un-gioco-switch-nxnative)
- [4. Play di un gioco Steam](#4-play-di-un-gioco-steam)
- [5. Costruire un gioco Switch (Add Game)](#5-costruire-un-gioco-switch-add-game)
- [6. Importare o ripristinare un salvataggio](#6-importare-o-ripristinare-un-salvataggio)
- [7. Installare una mod](#7-installare-una-mod)
- [8. Cambiare un'impostazione](#8-cambiare-unimpostazione)
- [9. Aggiornare l'app](#9-aggiornare-lapp)

## 1. Avvio dell'app

```mermaid
flowchart TD
    A["NXLibraryApp (@main)"] --> B["DevelopmentStartupView<br/>AppData.prepare: profilo release o Dev"]
    B --> C["AppSettingsStore · lingua (AppLocalization)<br/>LaunchReveal: finestra pronta, poi fullscreen"]
    C --> D["CatalogStore legge catalog.json<br/>(conversione da library.json se serve)"]
    D -->|"archivio danneggiato"| R["Recupero esplicito: Retry / ripristino backup"]
    D -->|"catalogo valido, legacy modificato"| L["Scelta Keep Arcane’s library"]
    L --> LA["Rivalida impronte → archivia catalogo, backup e legacy<br/>Mantieni i giochi Arcane e riconosci la base legacy"]
    LA --> D
    D --> E["AppShellState prepara coordinatore, router, tema"]
    E --> F["AppShellView: AppViewModel, store, monitor, updater"]
    F --> G{"Primo avvio completato?<br/>(FirstRunSetup)"}
    G -->|"no"| H["Setup: found (Steam, app portate) → Open library<br/>oppure Porting → Get ready → Your games"]
    G -->|"sì"| I["Benvenuto in Arcane una volta, per chi aggiorna<br/>altrimenti home scelta"]
    H --> K["Prima home Spotlight: moonlight condiviso → entrata<br/>Entrance animation; niente volo con Riduci movimento"]
    I --> K
    F --> J["In background: recuperi dei salvataggi, installazioni in attesa,<br/>scansione Steam se attivo, controllo engine se attivo, aggiornamenti;<br/>avviso se la copia è temporanea (App Translocation)"]
```

Punti fissi:
- Gli store si costruiscono una volta sola, prima della shell.
- Un archivio illeggibile non diventa mai una libreria vuota.
- La Dev legge e scrive solo nel suo profilo.
- La scelta Steam del primo Setup resta salvata anche alla chiusura; lettura e attivazione usano la cartella scelta nella fonte. Una lettura incompleta offre Retry, senza dichiarare la libreria vuota.
- La cartella Game files ricordata resta una preferenza del selettore: l'avvio non ne enumera i sorgenti.
- Menu e dialoghi nativi hanno precedenza sul routing della shell: `nativeDialogOwnsInput` ferma i comandi del controller anche se un benvenuto, Setup o dialogo dell'app è già aperto sotto.

## 2. Dal disco alla libreria

```mermaid
flowchart TD
    subgraph NX["Switch (nxnative)"]
        N1["Cartella Game apps"] --> N2["ImportService<br/>DMTitleID o org.nxnative.*"]
        N2 --> N3["NXNativeLibraryMerge<br/>conserva impostazioni, preferiti, build"]
    end
    subgraph ST["Steam"]
        S1["libraryfolders.vdf + manifest"] --> S2["SteamLibrarySource<br/>(worker annullabile, limiti)"]
        S2 --> S3["SteamCatalogReconciler<br/>ticket di revisione e radice"]
        S4["SteamManifestWatcher (FSEvents)"] --> S2
    end
    N3 --> W["CatalogRepository<br/>unico writer di catalog.json"]
    S3 --> W
    W --> P["CatalogLibraryProjection<br/>solo fonti attive"]
    P --> V["Spotlight · Collection · Ricerca<br/>(stessi UUID, filtri, ordine)"]
```

Punti fissi:
- Una scansione aggiorna solo ciò che ha osservato; un'assenza non cancella nulla.
- Un risultato superato da un cambio di cartella o di fonte non si applica.

## 3. Play di un gioco Switch (nxnative)

```mermaid
flowchart TD
    A["Play (GamePrimaryActions)"] --> B["AppViewModel.launchGame"]
    B --> C{"Possibile ora?"}
    C -->|"operazione sui salvataggi o recupero"| X["Attesa / spiegazione"]
    C -->|"icona in firma"| Y["Dialogo Preparing (IconLaunchWait)"]
    C -->|"sì"| D["SaveOperationGate: lease del titolo"]
    D --> E["LauncherSettings migra launcher.json<br/>oppure LaunchService aggiorna env.txt"]
    E --> F["CloudSavesPreferences applica la scelta cloud"]
    F --> M["ModStore riconcilia le cartelle prima di Play"]
    M --> G["LaunchService apre l'app (NSWorkspace)"]
    G --> H["LaunchCoverWindow + LaunchMotion<br/>finché LaunchReadinessProbe vede una finestra"]
    H --> I["RunningGameMonitor · PlaySessionStore (heartbeat)"]
    I --> J["Fine: sessione salvata → SessionCard<br/>GameFocus/LibraryWindow riportano la libreria davanti"]
    J --> K["Dopo la chiusura: icone, installazioni in attesa"]
```

## 4. Play di un gioco Steam

```mermaid
flowchart TD
    A["Play (GamePrimaryActions)"] --> B["SteamPlayCoordinator"]
    B --> K["LaunchCoverWindow<br/>ripiego entro 1 s se il pannello manca"]
    K --> C["steam://run/AppID al client di Valve"]
    C --> D["SteamPlayState / SteamBackgroundLaunch<br/>attesa del processo del gioco"]
    D -->|"Domanda effettiva o scadenza"| Q["La schermata lascia spazio a Steam"]
    D --> E["LaunchCoverWindow finché il gioco disegna"]
    E --> F["PlaySessionStore registra la sessione reale"]
    F --> G["Fine: SessionCard · SteamReturnFocus"]
    G --> H["SteamPlaytimeSync rilegge le ore da localconfig.vdf"]
```

Arcane legge le domande dal log di Steam. Durante `ShowInterstitials` l'attesa prosegue e il client può aprire le sue finestre dietro la schermata. Arcane non scrive mai i file di Steam e non apre l'app del gioco direttamente. Dettagli in [steam.md](steam.md).

Nella pagina Spotlight di un titolo Steam, Giù porta anche a **More like this** quando la fascia è presente. Invio, A o doppio clic selezionano la copertina sulla riga della libreria. Se il filtro la esclude, la libreria passa a **All games** come per Switch.

## 5. Costruire un gioco Switch (Add Game)

```mermaid
flowchart TD
    A["AddGameView: scelta esplicita di file o cartelle<br/>il selettore ricorda Game files"] --> B["SourceCatalog · ExtractedSourceCatalog · NUPSourceCatalog<br/>base, update, DLC"]
    B --> C["SourceSelection: titolo e versioni scelte"]
    C --> D["KeyCheck (se le sorgenti sono cifrate)<br/>NUP: identità programma e capacità del checkout"]
    D --> E["Review: GameAppDestination, GameRuntimeConfig.forReview"]
    E --> F{"Gate: CompatibilityChecker<br/>Metal certificato o override"}
    F -->|"bloccato"| Z["Spiegazione (ToolchainGateCopy)<br/>Play delle app esistenti resta attivo"]
    F -->|"ok"| G["WorkspaceManager + BuildScratch"]
    G --> N["Porting accettato: richiesta permesso notifiche"]
    N --> H["BuildCommandBuilder → BuildService<br/>processo dell'engine nxnative"]
    H --> I["BuildEventParser → PortingProgress<br/>tile, percentuale, ETA<br/>prewarm senza conteggio: attività e tempo trascorso"]
    I --> J["BuildOutputInstaller: scambio atomico"]
    J -->|"gioco aperto o installazione fallita"| K["PendingInstall: Retry più tardi"]
    J --> L["CatalogRepository: BuildRecord, toolchain"]
    L --> M["AppIconWriter (se c'è un'icona scelta) · notifica"]
```

## 6. Importare o ripristinare un salvataggio

```mermaid
flowchart TD
    A["SavesPanel"] --> B["SavePanelModel"]
    B --> C["AppViewModel+Saves: SaveLocation, identità, cloud"]
    C -->|"cloud attivo o gioco aperto"| X["Rifiuto con motivo (SaveFailure)"]
    C --> D["SaveOperationGate: lease"]
    D --> E["SaveSnapshotStore.stageImport / SaveRestorePreview<br/>copia accanto, hash, anteprima From → To"]
    E --> F["Conferma: sorgente, staging e salvataggio attuale<br/>schema 1: due slot · schema 2: tutti gli utenti + registro"]
    F --> G["SaveTransaction: backup completo → journal → soli pezzi da modificare<br/>verifica originali; registro per ultimo"]
    G --> H["SeleneSuccessNotice"]
    G -.->|"interruzione"| I["Al prossimo avvio: rollback o verifica dal journal<br/>Play attende"]
```

## 7. Installare una mod

```mermaid
flowchart TD
    A["Fascia Mods o card Mods (store)"] --> B["GameBananaMatch: pagina del gioco"]
    B --> C["AvailableModsFinder + ModSupport<br/>solo mod RomFS che funzionano"]
    C --> D["ModDetailPanel: Install"]
    D --> E["ModDownload (host GameBanana) · dimensione e MD5"]
    E --> F["ModInstaller: bsdtar, niente .. / link"]
    F --> G["ModStore.adopt: ordine e stato in mods/TID.json"]
    G --> H["EnvFileEditor scrive DM_ROMFS_OVERLAY in env.txt"]
    H --> I["L'engine legge le mod al prossimo avvio del gioco"]
```

## 8. Cambiare un'impostazione

```mermaid
flowchart TD
    A["Riga in Settings (SettingsCatalog)"] --> B["AppSettings modificato"]
    B --> C["AppSettingsStore.save: file temporaneo e sostituzione"]
    C -->|"errore"| X["Dialogo Selene con Retry"]
    C --> D["Pubblicazione: le viste si aggiornano"]
    A --> E["Search e Changed leggono lo stesso catalogo"]
    F["Reset group (X)"] --> G["SettingsReset.reset: i valori della sezione tornano ai default"]
    G --> B
```

Nel menu rapido, Theme apre prima i colori con anteprima viva; A applica la palette e passa alla selezione dello sfondo. Il tema Arcane conserva il blu classico e l’identità predefinita `selene`; le alternative Arcane Crystal e Arcane Flow salvano `arcane-crystal` e `arcane-flow` nello stesso `colorThemeID`. La shell conserva un backdrop persistente; le pagine ne dichiarano stile, pausa e Mods con `SeleneBackdropRequest`, mantenendo artwork e maschere locali. La shell passa la palette completa in `SeleneBackdropStyle`: cambia il valore dell’ambiente e aggiorna sfondo e maschere anche senza spostare la selezione. La superficie usa lo stesso renderer, con orologio e regole di pausa condivisi. Le particelle sono sempre morbide, senza una scelta aggiuntiva. La scelta dello sfondo mantiene il dialogo di destinazione esistente.

La barra laterale segue `SettingsSidebarGroup`: General, Library, Porting e System. Ogni sezione mostra solo le righe di `SettingsCatalog` che le appartengono.

In System → About, il pulsante Support Arcane compare tra il riepilogo dell’app e i crediti. `SettingsAboutSection` apre la pagina Buy Me a Coffee nel browser predefinito tramite clic, Invio o conferma del controller.

Tornando alla home, le viste delle tessere ricreate leggono subito le immagini decodificate in `TileArtMemo`; i task caricano quelle mancanti e rivalidano i file Steam. La cover della card Mods resta nel `ModStoreHost` posseduto dalla shell ed è rivalidata in background rispetto agli abbinamenti correnti.

## 9. Aggiornare l'app

```mermaid
flowchart TD
    A["AppUpdater: release su GitHub"] --> B{"AppUpdate.mayInstall<br/>versione più nuova e copia installabile"}
    B -->|"no (copia Dev o sola lettura)"| X["Solo note di rilascio"]
    B --> C["AppUpdateDownload: dimensione dichiarata, host GitHub"]
    C --> D["validate_update.py: struttura e percorsi"]
    D --> E["SaveOperationGate: esclusione globale"]
    E --> F["Controllo di versione, identità e firma"]
    F --> G["Copia in cartella esclusiva sul volume corrente"]
    G --> H["Scambio atomico"]
    H --> I["Vecchia app nel Cestino; se fallisce, conservarla nella cartella esclusiva"]
    I --> J["Riavvio allo stesso percorso"]
```

Alla chiusura successiva, una copia release che si chiama ancora `NX Library.app` diventa `Arcane.app` (`AppBundleRename`, chiamato da `AppDelegate.applicationWillTerminate`). Non succede se un riavvio è in programma, perché l'aiuto che riapre l'app usa il percorso attuale.
