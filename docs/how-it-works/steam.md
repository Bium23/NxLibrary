# Steam in Arcane

Riferimento unico dell’integrazione Steam: cosa legge, come decide e cosa mostra. È il
documento da leggere prima di toccare qualunque parte Steam. `architecture.md` ne tiene solo un riassunto;
`file-map.md` elenca i file uno per uno. Lo stato delle prove manuali sta solo in [validation.md](../working-on-it/validation.md).

## Indice

- [Principi](#principi)
- [File di Steam letti](#file-di-steam-letti)
- [Rilevamento e catalogo](#rilevamento-e-catalogo)
- [Stati di un gioco Steam](#stati-di-un-gioco-steam)
- [Osservazione dei file di Steam](#osservazione-dei-file-di-steam)
- [Libreria: tile, ordine, pagina](#libreria-tile-ordine-pagina)
- [Play, sessioni e primo piano](#play-sessioni-e-primo-piano)
- [Ore di gioco](#ore-di-gioco)
- [Achievement](#achievement)
- [Metadati, arte e personalizzazioni](#metadati-arte-e-personalizzazioni)
- [Dati su disco di Arcane](#dati-su-disco-di-arcane)
- [Scelte del maintainer](#scelte-del-maintainer)
- [Limiti noti e punti rimandati](#limiti-noti-e-punti-rimandati)
- [Cambiare l’integrazione](#cambiare-lintegrazione)

## Principi

- **Steam non viene mai scritto.** Arcane legge file di Steam e invia solo URL `steam://` al client di Valve
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
- **Nessun gioco nxnative finto.** `CatalogGame` porta il record reale (`SteamCatalogGame`); i comandi Switch
  (build, salvataggi, mod) ricevono solo `PortedGame` e non possono partire da un gioco Steam.
- **Fonte opzionale.** Con la fonte Steam spenta non partono scansioni o watcher del catalogo. La scoperta del primo avvio e l’offerta del benvenuto leggono soltanto per proporre la scelta, senza attivare la fonte; usano la cartella Steam salvata oppure quella standard. Una lettura incompleta nel primo avvio offre Retry, senza indicare che i giochi sono assenti.

## File di Steam letti

`<Steam>` è la cartella scelta in Settings → Sources (di solito `~/Library/Application Support/Steam`).
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

I lookup senza distinzione maiuscole/minuscole sono condivisi nell’estensione di `[KeyValuesEntry]` in
`SteamKeyValues.swift`. Le regole restano esplicite e distinte:

| Lookup | Regola | Uso |
|---|---|---|
| `firstValue` | prima chiave, anche se il suo valore ha un tipo inatteso | blocchi del percorso in `localconfig.vdf` |
| `firstString` / `firstObject` | primo valore del tipo richiesto; copie di altro tipo vengono saltate | schema e statistiche achievement |
| `uniqueValue` / `uniqueString` | duplicati di qualsiasi tipo rifiutati; `uniqueString` rifiuta anche un valore non stringa | manifest, indice librerie e campi delle ore/account |

I lettori decidono l’esito al proprio confine: i campi scalari non utilizzabili delle ore mantengono i ripieghi
esistenti, mentre manifest e indici non validi producono una scansione parziale con un problema segnalato.
Una prima stringa localizzata vuota negli achievement mantiene il ripiego inglese, senza scegliere un duplicato
successivo. Sette prove sui lettori reali fissano questi esiti.

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
| `requiresReview` | più app, problemi di lettura, stesso AppID in due librerie | da controllare | Settings → Sources, «to review» |

- Un gioco mai riconosciuto non entra nella riga, salvo mentre scarica. Play esiste solo con un’unica installazione
  disponibile e niente da controllare.
- `needsReview` è falso per un gioco in download: non compare fra quelli da controllare.
- Un aggiornamento in coda su un gioco installato (`StateFlags` 6 o 1030: bit 4 presente) resta giocabile; Steam
  aggiorna al lancio.
- `StateFlags` mancante o illeggibile: si guarda solo la cartella, come prima del supporto ai download.
- Il catalogo resta leggibile da una versione più vecchia di Arcane: `isDownloading` si decodifica con `decodeIfPresent` e la
  disponibilità usa casi già esistenti.

## Osservazione dei file di Steam

`SteamManifestWatcher` apre un solo `FSEventStream` (eventi per file, latenza 2 s) sulle cartelle `steamapps` di
tutte le librerie disponibili dell’ultima scansione. Ogni scansione ricontrolla anche i percorsi invariati: una
cartella tornata disponibile entra nello stream, anche se le altre erano già osservate. Un avvio dello stream
fallito si può ritentare. I percorsi degli eventi e delle cartelle usano la stessa normalizzazione (anche sotto
`/var` e `/tmp`). Contano solo
`appmanifest_<cifre>.acf` e il `libraryfolders.vdf` della radice; un evento «rileggi le sottocartelle» del sistema
conta solo se riguarda `steamapps` o una cartella sopra. Tutto il resto (`downloading/`, `common/`) viene scartato nel
callback.

`CatalogSourcesModel.steamFilesChanged` decide quando riscansionare: 3 s dopo l’ultimo evento utile, al massimo ogni
15 s, mai sopra una scansione in corso (quella successiva la segue). Il watcher parte con la fonte e si ferma quando la
fonte si spegne o l’app esce. Nessun polling.

Il test dell’intervallo minimo confronta gli avvii delle scansioni pubblicati dal modello.

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
`SeleneHeroArt`), poi screenshot, About, la card Achievements e il pannello Details condiviso (`DetailsPanel`: Developer, Publisher,
Size on disk, Installed in «Steam · <volume>»; in download solo Developer e Publisher; mai il build ID). La piattaforma è il logo
ufficiale Valve (`SteamPlatformLogo`), con l’attribuzione in Settings › About e in `NOTICE`.

**More like this** sta sotto About e Details. Usa la fascia e il focus condivisi con Switch, con fino a sei titoli correlati della libreria. I titoli Steam hanno precedenza; quando nessuno corrisponde, la fascia usa le corrispondenze Switch. Lo store legge i tratti per il punteggio dalla cache Steam all'apertura, e le scelte personali prevalgono. Doppio clic, Invio o A selezionano il gioco sulla riga di Spotlight.

| Situazione | Primo pulsante | Nota sopra i pulsanti |
|---|---|---|
| installato | Play | — |
| in download | «Downloading» con i puntini, come «Porting»; apre `steam://open/downloads` | — |
| in download, senza client Steam | «Downloading», spento | «Steam is not installed on this Mac.» |
| in avvio, in gioco, errore | Cancel, Resume, Try again | il motivo |

Opzioni (`SteamOptionsView`): Play, Edit details (Change artwork, Change metadata, Store page), Move (solo Spotlight),
Favorite, Hidden, Show in Finder.

## Play, sessioni e primo piano

- Play invia `steam://run/<AppID>` (`SteamPlayCoordinator`) solo al client di Valve registrato. La richiesta aspetta che Arcane ordini e invii la finestra d'attesa al server delle finestre, così la copertura precede il passaggio di Space. Se il pannello non si prepara, la richiesta parte entro un secondo.
  Il controllo senza finestre attende il completamento del task di ripiego, così il carico del runner non anticipa l'asserzione rispetto all'invio.
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
  nulla, per nessun gioco. Un clic la chiude (Arcane torna davanti se il gioco non è arrivato, salvo un gioco in
  primo piano); se ne va comunque dopo 120 s. Un gioco avviato da Steam non la mostra.
- `ShowInterstitials` è un passaggio di avvio che può restare in attesa oltre un secondo.
  La schermata rimane visibile durante quel passaggio, con il normale limite di 15 s o 45 s.
- Il log si legge fuori dal thread principale ogni 0,5 s durante l’attesa, per righe intere; la prima lettura prende
  l’ultimo megabyte (conta anche una domanda rimasta aperta da un Play precedente), un file nuovo (Steam riavviato)
  azzera tutto. Esempio di domanda: `KickingOtherSession`, il gioco è aperto su un altro dispositivo. Se Valve cambia
  il formato, resta l’attesa a tempo.
- **Keep Steam in the background** (`SteamBackgroundLaunch`): Steam avviato da Play parte con `-silent -nofriendsui`.
  Durante l'attesa la schermata copre il client, che può finire di aprire le sue finestre. Nasconderlo in risposta
  a ogni riapertura fa oscillare macOS fra lo Space fullscreen e la scrivania.
  All'uscita di un gioco rimasto in primo piano, Steam torna fuori vista se lo era prima del Play.
  [Analisi dello sfarfallio](../history/reviews/2026-11-18-steam-launch-spaces.md)
- All’uscita del gioco Arcane torna davanti se Play era partito da qui, il gioco era in primo piano e nessun
  altro gioco della libreria è aperto (`SteamReturnFocus`). Una sessione finita mostra la card di fine sessione dei
  giochi Switch, con il totale che include le ore di Steam.

## Ore di gioco

Le ore sono quelle di Steam (`Playtime`, tutti i computer) più le sessioni di Arcane successive all’ultimo valore
visto, così nulla si conta due volte anche se Steam aggiorna il file in ritardo (`SteamPlaytimeBaselines`,
`PlaySessionStore`). Un valore più basso o un altro account ripartono da capo; il totale non torna mai indietro per
un minuto. Le letture (`SteamPlaytimeCoordinator`, una alla volta, fuori dal thread principale) avvengono quando
cambiano catalogo o fonti, quando Arcane torna attiva e a fine sessione Steam (subito e dopo un minuto), solo se
la data del file è cambiata; la regola di ogni lettura è il tipo puro `SteamPlaytimeSync`. Un file illeggibile
conserva gli ultimi totali buoni dello stesso account; solo l’assenza di un account li azzera. Le sessioni uscite
dall’elenco recente restano contate (`CarriedPlaytime.afterExternal`) finché Steam non aggiorna il valore; mentre i
totali Steam sono nascosti, `PlaySessionStore.trimReferences` conserva il momento dell’ultimo valore di ogni gioco.

## Achievement

Dai file locali di `appcache/stats`, per l’account delle ore. Senza schema, account o file delle statistiche non c’è
la card; un file malformato la nasconde (un file vuoto o troncato non è «nessuno sbloccato»). In rete vanno solo la
rarità pubblica (`GetGlobalAchievementPercentagesForApp`, senza chiave, in cache un giorno, usata anche scaduta
offline; una percentuale non numerica si scarta) e le icone dall’host community-assets del CDN di Steam (il vecchio
percorso `steamcommunity/public/images` risponde 404 per le icone recenti). `SteamAchievementsStore` legge alla
selezione del gioco, all’apertura della schermata e a fine sessione; tiene in memoria gli ultimi 16 giochi.

Tier come i trofei PS5 (`AchievementTier`): Oro, Argento e Bronzo per rarità (sotto il 10%, sotto il 30%, il resto);
Arcane, al posto del Platino, quando tutto è sbloccato. I cristalli sono arte del maintainer; l’Arcane è un video in
loop (`ArcaneOrbVideo`, 1,5×) che a riposo resta fermo e grigio. Una tier non ottenuta tiene una traccia del suo
colore. Un achievement segreto non ancora sbloccato mostra il nome mascherato e l’icona sfocata sotto un lucchetto.

In cima alla colonna a destra di About, in un pannello chiaro quasi trasparente (sfocatura leggera dell’immagine)
con il contorno sottile dei pulsanti
(`DetailsAchievementsCard`: il miglior cristallo ottenuto a sinistra, «17/50» o, a gioco completato, il nome
dell’Arcane, le ultime tre icone a ventaglio con hover o focus; selezionato, l’anello Selene sta sul bordo del
pannello); A apre `AchievementsScreen` (filtri con LB/RB, ordine con Y, raro sotto il 10%: regole in
`AchievementSummary`), B torna alla card. In testa alla schermata, a destra, i quattro cristalli con sotto la
percentuale, la barra e il conteggio; a gioco completato il medaglione dell’Arcane. A su una riga apre il dettaglio
come medaglione (`AchievementDetail`): icona grande con il cristallo sull’angolo, nome, descrizione, rarità e data. La card prende il focus fra gli screenshot e il pannello della fonte, accanto a Read more
(Sinistra/Destra). «Your activity» non c’è: ore e ultima partita sono già nella testata. Schema: nomi e descrizioni
nella lingua dell’app, poi inglese. Nessuna chiave Web API di Steam: non serve per questi dati.

Riaprire rapidamente la schermata durante la sua transizione può riusare la vista della lista con un nuovo
`AchievementsScreenModel`, senza richiamare `onAppear` né cambiare altezza. Per questo la lista riporta le misure
con un `task(id:)` legato all’istanza corrente del modello
([contratto SwiftUI](https://developer.apple.com/documentation/swiftui/view/task%28id%3Aname%3Apriority%3Afile%3Aline%3A_%3A%29)),
conservando i controlli per altezza, scala e Riduci movimento. Nessun reset dell’identità della vista o dello stato.
La sonda fuori schermo `run_achievement_scroll.py` verifica con 41 righe sintetiche riaperture rapide e dopo la
transizione, dettagli della prima riga, ridimensionamento e Riduci movimento.

`SteamCatalogGame.firstAvailableInstallation` è il lookup condiviso
per artwork, pagina, Opzioni, volume e osservazione dei processi. Restituisce la prima installazione con stato
`available` nell’ordine del catalogo; non effettua I/O, non modifica i record e non decide se Play sia consentito.
`CatalogGamePresentation` conserva i controlli di fonte, riconoscimento, review e unicità prima del lancio.
I test di artwork e dettagli coprono anche Play bloccato con più installazioni e l'assenza di app e dati
d'installazione negli stati non disponibili.

## Metadati, arte e personalizzazioni

- `SteamMetadataService`: dati pubblici dello store per AppID e lingua, separati da installazioni e scelte personali.
  Solo HTTPS, niente redirect, al massimo sei trasferimenti insieme (gli altri aspettano in coda e si annullano se
  la loro vista sparisce), 20 s per richiesta, ripiego sui dati validi già in cache.
- Sfondo automatico (`SteamBackdropChoice`): immagini in formato schermo (Xbox, GOG, TheGamesDB, poi la fan art
  LaunchBox), poi il primo screenshot, per ultimo il banner della libreria Steam ritagliato. La scelta del giocatore
  vince sempre; svuotare la cache artwork ricalcola la scelta automatica.
- Le immagini si decodificano fuori dal thread principale (`GameArtLoader.decode`) alle misure dei giochi Switch
  (sfondo 2560 px, logo 1600, copertina 900, icona 512): un `NSImage(contentsOf:)` si decodificava al primo disegno e
  costava a quel frame 40–60 ms.
- `SteamGameFacts` condivide i dati store per AppID e lingua fra testata, pagina e input; un’assenza si richiede di
  nuovo dopo un minuto. Offline in una lingua nuova la pagina mostra il testo in cache di un'altra lingua
  (`SteamMetadataService.cachedInAnyLanguage`) con l'avviso "Description in …", e lo sostituisce appena Steam risponde.
- `SteamPersonalizationStore`: testo e immagini scelte in un solo manifest atomico; un errore conserva le scelte
  precedenti. SteamGridDB usa la chiave del giocatore, in `steamgriddb-api-key` con permessi `0600`, mai nei log.

## Dati su disco di Arcane

Sotto `Application Support/NXLibrary` (Dev: `NXLibrary-Development`):

| Percorso | Contenuto |
|---|---|
| catalogo (`CatalogDocument`) | giochi Steam con installazioni, preferiti, nascosti, `isDownloading` |
| `integrations/steam/enrichment/<AppID>/` | metadati store, icone degli achievement, rarità |
| `integrations/steam/artwork-picks/` | immagini scelte dal giocatore |
| `integrations/steam/metadata-picks.json` | testi scelti dal giocatore |
| `integrations/steam/playtime-baselines.json` | ultimo totale di Steam visto per gioco, con l’ora |

## Scelte del maintainer

- Lucchetto solo per i fallimenti Switch; un download ha il suo aspetto.
- Riquadri: solo icone vere, mai arte ritagliata; ordine scelta → icona dell’app → Square LaunchBox → neutro.
- Download: bianco e nero pieno (non colori sbiaditi), simbolo che pulsa senza alone, cerchio sottile, pulsante
  «Downloading» come «Porting», nessuna nota sopra i pulsanti, gioco in testa alla riga fino all’uscita.
- Nessuna etichetta «Steam» sulle tile.
- Pagina: «Your activity» tolta, Achievements in cima alla colonna destra, in un pannello chiaro quasi trasparente
  con contorno sottile.
- Logo Steam inalterato al posto del valore sotto PLATFORM, con lo spazio libero ridotto sopra.
- Ore: base di Steam più le sessioni successive.
- Achievement: Arcane al posto del Platino, cristalli e video dell’Arcane fatti dal maintainer, video a
  1,5×, medaglione al 100% e nel dettaglio, percentuale e barra larga sotto i cristalli, lucchetto sfocato sui segreti.

## Limiti noti e punti rimandati

Decisi consapevolmente:
- Un download in pausa, in coda o abbandonato ha lo stesso aspetto di uno attivo (i flag non li distinguono); i
  puntini si muovono comunque. Steam → Download dice quale.
- `StateFlags` senza il bit 4 per altri motivi (file mancanti, disinstallato a metà) mostra «Downloading»: anche lì
  Steam deve scaricare.
- Un manifest rimasto a 1026 dopo un download annullato continua a mostrare «Downloading».
- Un’assenza su LaunchBox (anche per rete assente) non si ricerca fino al prossimo avvio.

Punti minori rimandati dalle revisioni:
- Watcher: se la scrittura della configurazione fallisce, resta fermo fino alla scansione successiva;
  il callback usa `unsafeBitCast` a `NSArray`. Il solo collegamento di un volume non avvia una scansione:
  serve Refresh o una modifica rilevante ai file Steam già osservati.
- Un Refresh manuale non annulla una riscansione in attesa (una scansione in più).
- `openDownloads` ignora gli errori di apertura.
- Achievement: la freccia Su sparisce col focus sulla card; riepilogo ricalcolato a ogni disegno.
- Il focus dei link Details non viene limitato quando una disinstallazione Steam ne riduce il numero.
- Un errore Wikidata sospende per 60 s anche le richieste degli altri giochi.
- In Change metadata, il nome canonico arrivato da IGDB riavvia le ricerche LaunchBox/TheGamesDB.
- Ore Steam: dopo «nessun account», un errore senza account può ripubblicare le ore precedenti.
- Un catalogo occupato da un’altra istanza viene presentato come installazione fallita.
- La prima conversione scrive il backup prima del principale: un errore del secondo può offrire «Restore backup»
  per il catalogo appena convertito, con dati corretti ma un messaggio poco chiaro.

I lettori di statistiche, schema, account e ore usano `InstallationFileSnapshot`, con limite durante la lettura,
rifiuto dei symlink finali e verifica della stabilità del file. Test Core e controlli delle vere funzioni dell’app
con dati sintetici coprono le regressioni senza aprire finestre.

## Cambiare l’integrazione

- Un nuovo file di Steam da leggere: un lettore in `Sources/NXLibraryCore/Steam/` che estrae solo i campi
  necessari, con limiti di dimensione, test con fixture sintetiche (`SteamTestSupport`) e una riga nella tabella
  [File di Steam letti](#file-di-steam-letti).
- Un nuovo stato o campo nel catalogo: decodifica tollerante (`decodeIfPresent`) e nessun nuovo caso persistito che una
  versione più vecchia di Arcane non sappia leggere.
- Una nuova animazione su una tile: Core Animation fuori dal `drawingGroup`, ferma con Riduci movimento.
- Testi: sette lingue in `Localizable.xcstrings`.
- Aggiornare questo documento, il riassunto in `architecture.md` e `file-map.md` nello stesso commit.
