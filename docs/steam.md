# Steam in NX Library

Riferimento unico dell’integrazione Steam: cosa legge, come decide, cosa mostra, e cosa resta da validare. È il
documento da leggere prima di toccare qualunque parte Steam. `architecture.md` ne tiene solo un riassunto;
`file-map.md` elenca i file uno per uno.

Ramo: `bium/library-manager` (rilascio grande, non pubblicato). Aggiornato al 15 novembre 2026.

## Indice

- [Principi](#principi)
- [Stato di validazione](#stato-di-validazione)
- [File di Steam letti](#file-di-steam-letti)
- [Rilevamento e catalogo](#rilevamento-e-catalogo)
- [Stati di un gioco Steam](#stati-di-un-gioco-steam)
- [Osservazione dei file di Steam](#osservazione-dei-file-di-steam)
- [Libreria: tile, ordine, pagina](#libreria-tile-ordine-pagina)
- [Play, sessioni e primo piano](#play-sessioni-e-primo-piano)
- [Ore di gioco](#ore-di-gioco)
- [Achievement](#achievement)
- [Metadati, arte e personalizzazioni](#metadati-arte-e-personalizzazioni)
- [Dati su disco di NX Library](#dati-su-disco-di-nx-library)
- [Scelte del maintainer](#scelte-del-maintainer)
- [Limiti noti e punti rimandati](#limiti-noti-e-punti-rimandati)
- [Cambiare l’integrazione](#cambiare-lintegrazione)

## Principi

- **Steam non viene mai scritto.** NX Library legge file di Steam e invia solo URL `steam://` al client di Valve
  (bundle `com.valvesoftware.steam`); non apre mai l’app di un gioco direttamente.
- **Dati privati fuori dal tipo.** `localconfig.vdf`, `loginusers.vdf` e i file delle statistiche contengono ticket,
  amici e altro: ogni lettore estrae solo i campi che servono, non li registra nei log e non li conserva oltre il
  necessario. Nessun dato privato va in rete.
- **Meglio niente che un numero sbagliato.** Un file illeggibile, un formato cambiato o un account diverso nascondono
  il dato (ore, achievement) invece di indovinarlo.
- **Formati di Valve non documentati.** Manifest, VDF, KeyValues binario e `console_log.txt` non hanno contratto. Ogni
  lettore ha limiti di dimensione, rifiuta l’input malformato e degrada a un comportamento sicuro.
- **Solo giochi Mac nativi.** Un gioco conta se nella sua cartella c’è esattamente un’app Mac che si dichiara gioco.
  Niente Windows, CrossOver o Proton.
- **Nessun gioco nxnative finto.** `CatalogGame` porta il payload reale (`SteamCatalogGame`); i comandi Switch
  (build, salvataggi, mod) ricevono solo `PortedGame` e non possono partire da un gioco Steam.
- **Fonte opzionale.** Con la fonte Steam spenta non si legge nulla di Steam e tutto si comporta come prima.

## Stato di validazione

Ogni parte è implementata e provata automaticamente (1566 test). Conta come validata solo dopo la prova del
maintainer in NX Library Dev.

| Parte | Stato |
|---|---|
| Catalogo comune, fonti, libreria mista | in attesa di validazione umana |
| Metadati store e arte | in attesa di validazione umana |
| Pagina condivisa, Opzioni, personalizzazioni | in attesa di validazione umana |
| Play, schermata di lancio, domande di Steam, Steam in background | in attesa di validazione umana |
| Ore di gioco | in attesa di validazione umana |
| Achievement | in attesa di validazione umana; aspetto della pagina da rivedere (richiesta del maintainer) |
| Giochi in download, osservazione dei manifest, ordine della riga | aspetto approvato dal maintainer il 15 nov 2026; fine download e controlli di accettazione ancora da provare |

## File di Steam letti

`<Steam>` è la cartella scelta in Settings → Steam · Library (di solito `~/Library/Application Support/Steam`).
`<lib>` è ogni libreria: `<Steam>` e quelle elencate in `libraryfolders.vdf`.

| File | Lettore | Cosa ne esce |
|---|---|---|
| `<Steam>/steamapps/libraryfolders.vdf` | `SteamLibrarySource` | percorsi delle librerie |
| `<lib>/steamapps/appmanifest_<AppID>.acf` | `SteamLibrarySource` | AppID, nome, `installdir`, `SizeOnDisk`, `buildid`, `StateFlags` |
| `<lib>/steamapps/common/<installdir>/…` | `NativeMacApplication` | bundle Mac, header Mach-O (architetture), categoria dichiarata; mai eseguito |
| `<Steam>/config/loginusers.vdf` | `SteamPlaytimeReader` | l’account `MostRecent` |
| `<Steam>/userdata/<account>/config/localconfig.vdf` | `SteamPlaytimeReader` | per gioco solo `Playtime` (minuti) e `LastPlayed` |
| `<Steam>/appcache/stats/UserGameStatsSchema_<AppID>.bin` | `SteamAchievementReader` | nomi, descrizioni, nascosti, icone degli achievement |
| `<Steam>/appcache/stats/UserGameStats_<account>_<AppID>.bin` | `SteamAchievementReader` | solo `AchievementTimes` |
| `<Steam>/logs/console_log.txt` | `SteamLaunchQuestionWatch` | solo righe `GameAction [AppID …]`, durante un Play |

Formati: `SteamKeyValues` (testo, campi duplicati conservati, nessuna direttiva eseguita), `SteamBinaryKeyValues`
(binario). Le letture di file e cartelle hanno limiti di dimensione e di voci (`InstallationFileSnapshot`,
`InstallationDirectorySnapshot`) e si possono annullare.

## Rilevamento e catalogo

1. `CatalogSourcesModel` avvia una scansione: all’avvio se Steam è abilitato, su Refresh, quando si attiva la fonte o
   si cambia cartella, e quando cambiano i file di Steam (vedi sotto). Una scansione alla volta, su un worker
   annullabile; disattivare, cambiare cartella o chiederne un’altra invalida il risultato precedente.
2. `SteamLibrarySource` produce uno `SteamLibrarySnapshot`: librerie lette, un’osservazione per manifest, problemi
   trovati. Lo snapshot è completo solo senza problemi; uno parziale non autorizza mai a dimenticare giochi o librerie
   non visti.
3. `SteamCatalogReconciler` fonde lo snapshot nel catalogo: conserva UUID, preferiti, nascosti, scelte personali e le
   installazioni già note. Un gioco non visto diventa «non rilevato» solo con uno snapshot completo.
4. `CatalogRepository` è l’unico che scrive il catalogo (`CatalogDocument`, revisioni, lock); `CatalogLibraryProjection`
   sceglie cosa mostrare in Spotlight, Collection e ricerca, con gli stessi UUID, filtri e ordine salvato dei giochi
   Switch.

## Stati di un gioco Steam

Lo stato nasce dall’osservazione (`SteamGameObservation.State`) e arriva alla vista come `CatalogGamePresentation`.

| Osservazione | Quando | Nel catalogo | Nella libreria |
|---|---|---|---|
| `nativeReady` | un’unica app Mac che si dichiara gioco, nessun problema | `.available`, riconosciuto | tile a colori, Play |
| `downloading` | `StateFlags` senza il bit 4 (FullyInstalled); la cartella non viene letta | `.unavailable` + `isDownloading` | tile in download, pulsante «Downloading» |
| `unavailable` | nessuna app nella cartella (es. disco scollegato) | `.unavailable` | resta nella riga senza Play se era già stato riconosciuto, altrimenti non entra |
| `requiresReview` | più app, problemi di lettura, stesso AppID in due librerie | da controllare | Settings → Steam · Library, «to review» |

- Un gioco mai riconosciuto non entra nella riga, salvo mentre scarica. Play esiste solo con un’unica installazione
  disponibile e niente da controllare.
- `needsReview` è falso per un gioco in download: non compare fra quelli da controllare.
- Un aggiornamento in coda su un gioco installato (`StateFlags` 6 o 1030: bit 4 presente) resta giocabile; Steam
  aggiorna al lancio.
- `StateFlags` mancante o illeggibile: si guarda solo la cartella, come prima del supporto ai download.
- Il catalogo resta leggibile da un NX Library più vecchio: `isDownloading` si decodifica con `decodeIfPresent` e la
  disponibilità usa casi già esistenti.

## Osservazione dei file di Steam

`SteamManifestWatcher` apre un solo `FSEventStream` (eventi per file, latenza 2 s) sulle cartelle `steamapps` di
tutte le librerie dell’ultima scansione, e lo ricrea quando quell’insieme cambia. Contano solo
`appmanifest_<cifre>.acf` e il `libraryfolders.vdf` della radice; un evento «rileggi le sottocartelle» del sistema
conta solo se riguarda `steamapps` o una cartella sopra. Tutto il resto (`downloading/`, `common/`) viene scartato nel
callback.

`CatalogSourcesModel.steamFilesChanged` decide quando riscansionare: 3 s dopo l’ultimo evento utile, al massimo ogni
15 s, mai sopra una scansione in corso (quella successiva la segue). Il watcher parte con la fonte e si ferma quando la
fonte si spegne o l’app esce. Nessun polling.

Effetto: a fine download la tile passa da sola a colori con Play; un gioco installato o rimosso in Steam appare o
sparisce senza Refresh.

## Libreria: tile, ordine, pagina

**Tile.** Il riquadro quadrato mostra sempre un’icona vera, mai una copertina ritagliata. Ordine: scelta del
giocatore → icona dell’app installata → «Square» di LaunchBox della voce Mac o Windows, cercata per nome
(`ArtworkStore.automaticSteamIcon`; un’assenza non si ricerca fino al prossimo avvio) → riquadro neutro. Nessuna
etichetta «Steam» sulla tile: la piattaforma è nella pagina.

**Tile in download** (`PortingTileLook.downloading`). Bianco e nero, la stessa leggera sfocatura del lucchetto Switch,
«Downloading» sotto una freccia sottile in un cerchio (SF Symbol `arrow.down.circle`, peso light). Il simbolo pulsa
piano in luminosità (`TileMotion.downloadMarkOpacity`, 0,4 ↔ 1 in 2,8 s; fermo con Riduci movimento). È un livello
Core Animation (`DownloadMarkLayers`) posato fuori dal `drawingGroup` della tile: dentro, SwiftUI mostrerebbe un
segnaposto giallo. Niente percentuale: Steam scrive il manifest troppo di rado (misurato: fermo 8 minuti durante un
download).

**Ordine della riga.** Ogni gioco che parte, anche da Steam, diventa il primo gioco della riga. Un gioco visto
scaricare in questa sessione la guida come un gioco in porting: subito dopo la scheda Aggiungi gioco, dopo il porting,
sopra l’ordine salvato con Move, e ci resta fino all’uscita anche a download finito (`SessionDownloads`,
`SpotlightRow.leaders`). Al riavvio torna all’ordine normale.

**Pagina.** Gli stessi pezzi Selene dei giochi nxnative (`GameLogoArea`, `GamePrimaryActions`, `SeleneStatsRow`,
`SeleneHeroArt`), poi screenshot, About, la card Achievements e `SteamInstallationPanel`. La piattaforma è il logo
ufficiale Valve (`SteamPlatformLogo`), con l’attribuzione in Settings › About e in `NOTICE`.

| Situazione | Primo pulsante | Nota sopra i pulsanti |
|---|---|---|
| installato | Play | — |
| in download | «Downloading» con i puntini, come «Porting»; apre `steam://open/downloads` | — |
| in download, senza client Steam | «Downloading», spento | «Steam is not installed on this Mac.» |
| in avvio, in gioco, errore | Cancel, Resume, Try again | il motivo |

Opzioni (`SteamOptionsView`): Play, Edit details (Change artwork, Change metadata, Store page), Move (solo Spotlight),
Favorite, Hidden, Show in Finder.

## Play, sessioni e primo piano

- Play invia `steam://run/<AppID>` (`SteamPlayCoordinator`) solo se il gestore registrato è il client di Valve.
- La sessione inizia quando compare il processo dell’app installata (stesso bundle ed eseguibile) e finisce quando
  esce. Steam aperto non conta; un gioco avviato da Steam viene seguito allo stesso modo. Attesa massima 300 s; un pid
  riusato non è il gioco. Una sessione in corso segue il processo che ha visto partire (pid e bundle) anche se il
  catalogo nel frattempo cambia; le risposte tardive si scartano per generazione. Il coordinatore non osserva nulla
  prima di Play: `RunningGameMonitor` chiude le sessioni rimaste aperte all’ultimo heartbeat e un gioco ancora in
  esecuzione ne apre una nuova. I percorsi di ogni pid si risolvono una volta finché vive.
- La schermata di lancio dei giochi Switch copre l’attesa in una finestra propria. Se ne va quando la finestra del
  gioco è visibile, quando Play finisce o fallisce, quando il log dice che Steam aspetta una risposta del giocatore
  (`SteamLaunchQuestions`: una riga `LaunchApp waiting for user response…` non seguita entro 1 s), o passata la
  pazienza (15 s con Steam aperto, 45 s se Play deve avviarlo). Negli ultimi due casi Steam viene mostrato e la
  testata invita a controllarlo. Perché una finestra propria: riprendersi il primo piano mentre Steam si portava davanti
  faceva alternare a macOS schermo intero e scrivania per tutta l’attesa. Mentre la schermata è aperta Play non fa
  nulla, per nessun gioco. Un clic la chiude (NX Library torna davanti se il gioco non è arrivato, salvo un gioco in
  primo piano); se ne va comunque dopo 120 s. Un gioco avviato da Steam non la mostra.
- Il log si legge fuori dal thread principale ogni 0,5 s durante l’attesa, per righe intere; la prima lettura prende
  l’ultimo megabyte (conta anche una domanda rimasta aperta da un Play precedente), un file nuovo (Steam riavviato)
  azzera tutto. Esempio di domanda: `KickingOtherSession`, il gioco è aperto su un altro dispositivo. Se Valve cambia
  il formato, resta l’attesa a tempo.
- **Keep Steam in the background** (`SteamBackgroundLaunch`): Steam avviato da Play parte con `-silent -nofriendsui`;
  uno Steam già aperto viene nascosto durante l’attesa. Finito Play, Steam torna visibile solo se lo era prima, e uno
  Steam fuori vista viene nascosto di nuovo quando il gioco esce (subito e dopo 2 s, perché Steam riapre la sua
  finestra). Valve non offre un modo ufficiale: nascondere è un ripiego e può non riuscire con alcune versioni.
- All’uscita del gioco NX Library torna davanti se Play era partito da qui, il gioco era in primo piano e nessun
  altro gioco della libreria è aperto (`SteamReturnFocus`). Una sessione finita mostra la card di fine sessione dei
  giochi Switch, con il totale che include le ore di Steam.

## Ore di gioco

Le ore sono quelle di Steam (`Playtime`, tutti i computer) più le sessioni di NX Library successive all’ultimo valore
visto, così nulla si conta due volte anche se Steam aggiorna il file in ritardo (`SteamPlaytimeBaselines`,
`PlaySessionStore`). Un valore più basso o un altro account ripartono da capo; il totale non torna mai indietro per
un minuto. Le letture (`SteamPlaytimeCoordinator`, una alla volta, fuori dal thread principale) avvengono quando
cambiano catalogo o fonti, quando NX Library torna attiva e a fine sessione Steam (subito e dopo un minuto), solo se
la data del file è cambiata; la regola di ogni lettura è il tipo puro `SteamPlaytimeSync`. Un file illeggibile
conserva gli ultimi totali buoni dello stesso account; solo l’assenza di un account li azzera. Le sessioni uscite
dall’elenco recente restano contate (`CarriedPlaytime.afterExternal`) finché Steam non aggiorna il valore; mentre i
totali Steam sono nascosti, `PlaySessionStore.trimReferences` conserva il momento dell’ultimo valore di ogni gioco.

## Achievement

Dai file locali di `appcache/stats`, per l’account delle ore. Senza schema, account o file delle statistiche non c’è
la card; un file malformato la nasconde (un file vuoto o troncato non è «nessuno sbloccato»). In rete vanno solo la
rarità pubblica (`GetGlobalAchievementPercentagesForApp`, senza chiave, in cache un giorno, usata anche scaduta
offline) e le icone dal CDN di Steam. `SteamAchievementsStore` legge alla selezione del gioco, all’apertura della
schermata e a fine sessione; tiene in memoria gli ultimi 16 giochi.

Card nella colonna a destra di About (`DetailsAchievementsCard`: «17/50», percentuale, barra, ultime icone); A apre
`AchievementsScreen` (filtri con LB/RB, nascosti mascherati, raro sotto il 10%: regole in `AchievementSummary`), B
torna alla card. La card prende il focus fra gli screenshot e il pannello della fonte, accanto a Read more
(Sinistra/Destra). «Your activity» non c’è: ore e ultima partita sono già nella testata. Schema: nomi e descrizioni
nella lingua dell’app, poi inglese. Nessuna chiave Web API di Steam: non serve per questi dati.

## Metadati, arte e personalizzazioni

- `SteamMetadataService`: dati pubblici dello store per AppID e lingua, separati da installazioni e scelte personali.
  Solo HTTPS, niente redirect, al massimo sei trasferimenti, 20 s per richiesta, ripiego sui dati validi già in cache.
- Sfondo automatico (`SteamBackdropChoice`): immagini in formato schermo (Xbox, GOG, TheGamesDB, poi la fan art
  LaunchBox), poi il primo screenshot, per ultimo il banner della libreria Steam ritagliato. La scelta del giocatore
  vince sempre; svuotare la cache artwork ricalcola la scelta automatica.
- Le immagini si decodificano fuori dal thread principale (`GameArtLoader.decode`) alle misure dei giochi Switch
  (sfondo 2560 px, logo 1600, copertina 900, icona 512): un `NSImage(contentsOf:)` si decodificava al primo disegno e
  costava a quel frame 40–60 ms.
- `SteamGameFacts` condivide i dati store per AppID e lingua fra testata, pagina e input; un’assenza si richiede di
  nuovo dopo un minuto.
- `SteamPersonalizationStore`: testo e immagini scelte in un solo manifest atomico; un errore conserva le scelte
  precedenti. SteamGridDB usa la chiave del giocatore, in `steamgriddb-api-key` con permessi `0600`, mai nei log.

## Dati su disco di NX Library

Sotto `Application Support/NXLibrary` (Dev: `NXLibrary-Development`):

| Percorso | Contenuto |
|---|---|
| catalogo (`CatalogDocument`) | giochi Steam con installazioni, preferiti, nascosti, `isDownloading` |
| `integrations/steam/enrichment/<AppID>/` | metadati store, icone degli achievement, rarità |
| `integrations/steam/artwork-picks/` | immagini scelte dal giocatore |
| `integrations/steam/metadata-picks.json` | testi scelti dal giocatore |
| `integrations/steam/playtime-baselines.json` | ultimo totale di Steam visto per gioco, con l’ora |

## Scelte del maintainer

- Lucchetto solo per i fallimenti Switch; un download ha il suo aspetto (15 nov 2026).
- Riquadri: solo icone vere, mai arte ritagliata; ordine scelta → icona dell’app → Square LaunchBox → neutro.
- Download: bianco e nero pieno (non colori sbiaditi), simbolo che pulsa senza alone, cerchio sottile, pulsante
  «Downloading» come «Porting», nessuna nota sopra i pulsanti, gioco in testa alla riga fino all’uscita.
- Nessuna etichetta «Steam» sulle tile.
- Pagina: «Your activity» tolta, card Achievements in cima alla colonna destra.
- Logo Steam inalterato al posto del valore sotto PLATFORM, con lo spazio libero ridotto sopra.
- Ore: base di Steam più le sessioni successive.

## Limiti noti e punti rimandati

Decisi consapevolmente:
- Un download in pausa, in coda o abbandonato ha lo stesso aspetto di uno attivo (i flag non li distinguono); i
  puntini si muovono comunque. Steam → Download dice quale.
- `StateFlags` senza il bit 4 per altri motivi (file mancanti, disinstallato a metà) mostra «Downloading»: anche lì
  Steam deve scaricare.
- Un manifest rimasto a 1026 dopo un download annullato continua a mostrare «Downloading».
- Un’assenza su LaunchBox (anche per rete assente) non si ricerca fino al prossimo avvio.

Punti minori rimandati dalle revisioni, da decidere prima del rilascio:
- Watcher: se `FSEventStreamStart` fallisce, un `watch()` identico non riprova; se la scrittura della configurazione
  fallisce, il watcher resta fermo fino alla scansione successiva; librerie sotto `/tmp` o `/var` non verrebbero mai
  riconosciute (`/private`); il callback usa `unsafeBitCast` a `NSArray`.
- Un Refresh manuale non annulla una riscansione in attesa (una scansione in più).
- `openDownloads` ignora gli errori di apertura.
- I test del ritmo delle riscansioni hanno margini di 60–80 ms.
- Achievement: ordine «più rari» instabile a parità di percentuale; una rarità `nan` verrebbe mostrata; la freccia Su
  sparisce col focus sulla card; breve lampo dell’icona allo scorrimento; riepilogo ricalcolato a ogni disegno.

## Cambiare l’integrazione

- Un nuovo file di Steam da leggere: un lettore in `Sources/NXLibraryCore/Services/Steam/` che estrae solo i campi
  necessari, con limiti di dimensione, test con fixture sintetiche (`SteamTestSupport`) e una riga nella tabella
  [File di Steam letti](#file-di-steam-letti).
- Un nuovo stato o campo nel catalogo: decodifica tollerante (`decodeIfPresent`) e nessun nuovo caso persistito che un
  NX Library più vecchio non sappia leggere.
- Una nuova animazione su una tile: Core Animation fuori dal `drawingGroup`, ferma con Riduci movimento.
- Testi: sei lingue in `Localizable.xcstrings`.
- Aggiornare questo documento, il riassunto in `architecture.md` e `file-map.md` nello stesso commit.
