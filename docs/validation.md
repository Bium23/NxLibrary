# Arcane — stato della validazione

Questo è l'unico elenco di ciò che il maintainer ha provato nell'app. Una cosa è **validata** solo quando il maintainer conferma di averla provata nell'app (Arcane Dev per il lavoro non pubblicato). Test automatici, compilazione e revisioni degli agenti la sostengono, ma non la sostituiscono (AGENTS.md).

Come si aggiorna:
- Quando il maintainer conferma, la riga passa a **validato**, con la data e le sue parole se utili.
- Ogni lavoro nuovo aggiunge la sua riga **in attesa**, con le prove manuali da fare.
- Le guide ([architecture.md](architecture.md), [steam.md](steam.md)) descrivono come funziona; lo stato sta solo qui.

## Lavoro non pubblicato (ramo `bium/library-manager`)

| Parte | Stato | Prove ancora da fare |
|---|---|---|
| Nome Arcane in ciò che si vede (finestra, menu, Settings, About, testi nelle sei lingue; copia Dev `Arcane Dev.app`) | in attesa | Aprire `~/Applications/Arcane Dev.app` e ritrovare libreria e impostazioni della vecchia Dev; nessun "NX Library" visibile nelle sei lingue |
| Rinomina del file alla chiusura (`NX Library.app` → `Arcane.app`) | in attesa | Con la prova del ponte A → B: dopo l'aggiornamento, chiudere; il file diventa `Arcane.app` e il Dock lo apre. Restart app non rinomina |
| Impostazioni in General, Library, Porting e System (sezioni nuove Games, Keys, Cloud saves, Storage di Porting, Console; Rumble in New games) | gruppi, navigazione con controller, Search e conservazione dei valori confermati il 17 nov 2026 («ho fatto tutte le verifiche e mi sembra che non ci sia niente di sbagliato»); altre varianti in attesa | Changed mostra "Porting · …"; Reset group in Library → Games non tocca Rumble; i link "Settings → …" degli errori aprono la sezione giusta |
| Primo avvio da ciò che è già sul Mac (pagina `found`) | percorso base con profilo vuoto e riavvio validato il 17 nov 2026 («fatto»); interruttore spento e Setup interrotto confermati il 17 nov; altre varianti in attesa | Conteggi e scelte Steam nei diversi casi; interruttore spento → nessuna fonte Steam; card Porting → Get ready, B torna indietro; con l'interruttore acceso e il percorso Porting fino a Your games o Skip, Steam è acceso; caso vuoto con "No games found"; Open library durante la lettura prosegue e le fonti restano aggiungibili dopo; verifiche complete con frecce, mouse e controller |
| Benvenuto in Arcane, una volta, per chi aggiorna | percorso Add Steam → Open library → riavvio validato nella Dev il 17 nov 2026 («fatto»), con flag del benvenuto e fonte Steam salvati; caso Steam già attivo confermato il 17 nov; altre varianti in attesa | Not now; chiusura con B/Esc e diverse modalità di input; gioco già aperto con Play/Resume; Riduci movimento e precedenza del Setup. Il percorso di installazione tramite updater resta nella prova A → B |
| Rifinitura del primo avvio: scelta Steam persistente, cartella personalizzata, Retry e notifiche contestuali | in attesa | Chiudere e riaprire durante Porting con scelta Steam accesa/spenta; nessuna scelta residua dopo il completamento; radice Steam personalizzata sia in scoperta sia dopo Add; lettura incompleta → Retry o continua; nessuna richiesta notifiche all’avvio, richiesta soltanto al primo porting accettato |
| Tema Arcane iridescente e scelta Particles nella pagina colori | in attesa | Menu rapido → Theme: Arcane è il primo tema; Particles sotto l’anteprima, raggiungibile con mouse, frecce e controller; Morbide/Polvere di cristallo, A continua allo sfondo. Riavvio, Look/Search/Changed/Reset; wallpaper/video conservati; Riduci movimento e Background motion fermano colori e moti; card Mods mantiene l’oro; ritorno alla home e primo avvio senza lampi |
| Particellare e ritmo dell'entrata della libreria | aspetto validato il 17 nov 2026 («abbiamo risolto la questione particellare») | Riduci movimento prima e durante il volo; avvio con wallpaper e recupero di un errore di preparazione; primo input durante fullscreen/attesa/volo (anche con entrata spenta), filtri vuoti e righe corte; avvio su macOS 13. Le prove dei dialoghi nativi hanno una riga separata |
| Immagini Spotlight al ritorno da Settings | in attesa | Ripetere Settings → home con icone nxnative automatiche e personali, Steam e card Mods già caricata; nessun passaggio al ripiego. Cambiare/rimuovere un'immagine personale e tornare ad Automatic; aggiornamento Steam nello stesso percorso; badge e cover Mods dopo rimozioni o cambio abbinamento da Collection. Il controllo automatico costruisce i valori delle viste senza finestre, non sostituisce la prova visiva |
| Cartella Game files ricordata senza scansione dei sorgenti all'avvio | avvio e scelta cartella validati il 17 nov 2026 («funziona») | Annullare il selettore senza perdere la bozza; scegliere singoli file da un'altra cartella senza cambiare Game files; rebuild di un gioco dalle sue sorgenti registrate |
| Priorità dei dialoghi nativi su controller, tastiera e menu | selettore cartella, isolamento del controller e ripresa dopo Esc validati il 17 nov 2026 («si funziona») | Invio nel selettore; ripetere con un alert nativo e con un dialogo interno (per esempio il controllo aggiornamenti), che deve continuare a ricevere i suoi comandi quando è in primo piano |
| NUP: programma selezionato, base DLC e rebuild coerenti | in attesa | Con un engine capace: importare un NUP multiprogramma, scegliere update e ricostruire lo stesso programma; record storico mantiene programma zero; checkout precedente blocca selezioni non supportate senza impedire Play |
| Newest engine: build, Play, controller, salvataggio e riapertura | validato il 17 nov 2026 su `a2c731e32ea5124055553aac62ccb10fab34805d` («funziona benissimo tutto»), con record di build riuscita sullo stesso hash | Conferma del percorso provato, non di tutti i giochi o del giroscopio; il pin ufficiale resta distinto. La scelta esplicita Newest engine registra `toolchainVerified=false` |
| Prewarm: attività del primo avvio, tempi e avvisi | build e primo avvio confermati il 17 nov 2026 su `a2c731e3`; il log registra Prewarm pipelines concluso con successo. Altre varianti in attesa | Attività localizzata senza ETA ricavata dal vecchio porting, tempo trascorso aggiornato, Stop e ripresa; warning non fatale → app pronta e spiegazione del primo avvio più lungo; spazio sul volume di destinazione |
| App con bundle dati firmati annidati | build reale e Play confermati il 17 nov 2026 su `a2c731e3`; altre varianti in attesa | Cambio/ripristino icona e relativo Play; ripetere su un volume esterno. Le fixture automatiche con firme reali provano il ramo di copia forzato, non un filesystem esterno |
| Backup locali multiutente e compatibilità dei vecchi backup | creazione del backup con Back up now e apertura di Backup folder confermate il 17 nov 2026 («ho fatto tutte le verifiche»); casi multiutente e restore in attesa | Con gioco chiuso: backup completo e restore di utenti/registro; vecchio backup conserva gli utenti aggiuntivi; import cartella modifica solo User/Device; testi del limite cloud e conferme; fonti/app reali costruite altrove incluse |
| Catalogo comune nella Dev (`CatalogRepository`, conversione da `library.json`, recupero) | in attesa | Prima apertura della Dev con libreria reale, recupero esplicito |
| Updater: copie accanto all’app e guasti di sostituzione | in attesa | Prova A → B isolata: conservare eventuali copie `(new)` / `(old)`, nome dell’app e riavvio; Cestino non disponibile conserva la vecchia app. Le regressioni automatiche usano bundle sintetici, mai la copia pubblicata |
| Conflitto con modifiche della vecchia libreria | in attesa | Su profilo di prova isolato: errore → Mantieni la libreria di Arcane; giochi e fonti invariati, archivio separato e riavvio. Retry dopo una modifica successiva ai file; nessuna fusione automatica. Non alterare il profilo pubblicato per provocare il caso |
| Fonti e libreria mista (Steam + Switch, Manage sources) | in attesa | Attivazione e disattivazione delle fonti, persistenza delle scelte, conservazione delle voci e librerie su disco esterno |
| Steam: metadati store e arte | in attesa | — |
| Steam: pagina condivisa, Opzioni, personalizzazioni | in attesa | — |
| Steam: Play, schermata di lancio, domande di Steam, Steam in background | Play/Resume validati il 17 nov 2026 («funziona»); altre varianti in attesa | Domande di Steam, Steam chiuso/in background, annullamento del lancio |
| Steam: ore di gioco | validato il 17 nov 2026 («le ore di Steam funzionano») | — |
| Steam: giochi in download, osservazione dei manifest, ordine della riga | aspetto validato il 15 nov 2026 | Fine del download e controlli di accettazione |
| Achievement Steam: lista, rarità, tier a cristallo, card Details | presenza e consultazione confermate il 17 nov 2026 («gli achievement ci sono»); dettagli in attesa | Rarità, tier e casi privati/offline o senza statistiche |
| Achievement: la lista segue la riga scelta dopo chiusura e riapertura rapide | validato il 16 nov 2026 | — |
| Achievement: video Arcane, medaglioni del dettaglio, lucchetto dei segreti, scorrimenti (`GlideGroup`) | in attesa | — |
| Achievement: intestazione senza 100% (percentuale, barra larga e conteggio sotto i quattro trofei, 44 pt / 4) | in attesa | — |
| Correzioni della revisione di sviluppo (CHANGELOG "Unreleased": focus della card, nuovi tentativi, piattaforma dei loghi, osservazione delle librerie Steam, lettori protetti) | in attesa | — |
| Posizione condivisa dei comandi: `SeleneHintsBar` a 32 unità dal fondo | in attesa | La posizione dei Settings (`7adc0ad`) è validata; la via di mezzo a 32 no |
| Pannello Details uguale per ogni fonte | validato il 16 nov 2026 | — |
| Voto della critica con Wikidata | validato il 16 nov 2026, abbinamenti compresi | — |
| IGDB facoltativo: credenziali, voti, minimo di 3 recensioni, media utenti come ripiego | in attesa (il ripiego utenti è approvato come scelta) | Ocarina con voto utenti, un gioco con voto della critica, cambio rapido di gioco, rimozione di IGDB |
| Sezione Online services (IGDB e SteamGridDB) | in attesa | — |
| IGDB in Change metadata | in attesa | Un gioco nxnative e uno Steam, scelta, Q/E e controller, Automatic, testo personale, persistenza, offline/retry, chiusura durante il caricamento |
| LaunchBox e TheGamesDB in Change metadata (ambito approvato il 16 nov 2026) | in attesa | Source picker su Switch 2 e Steam, persistenza, righe uguali/assenti, controller, offline/retry, immagini TheGamesDB per Mac/PC |
| Movimento del selettore dei metadati (`SeleneExpandableText`) | in attesa | Su/giù ripetuti fra descrizioni corte e lunghe, scroll fino alla fine, Q/E, Riduci movimento |
| Lingua e regione (sei lingue) | validato nella Dev, compreso il cambio immediato e la sidebar senza spostare il focus | Le traduzioni sono bozze, non revisioni madrelingua; issue #10 aperta |
| Spazio per gioco in Settings → Storage | validato il 9 nov 2026 | — |
| Profilo Dev isolato | avvio e libreria Dev validati il 9 nov 2026 | Non copre ogni azione su giochi, mod o salvataggi reali |

## Versioni pubblicate

| Parte | Stato | Note |
|---|---|---|
| 0.1.2: scansione e cursore (revisione 2), menu nativi, dialogo aggiornamenti, avvio a schermo intero, riga di scansione, gate certificato | validato | — |
| 0.1.4.2: tempo della fase e durate oltre i 60 minuti | in attesa | — |
| 0.1.4.2: Play durante la firma dell'icona (Preparing / Cancel) | in attesa | — |
| 0.1.4.2: icona sul Mac, Only here / Use on the Mac | in attesa | — |
| 0.1.4.2: icone automatiche (`AutomaticIconResolver`) | in attesa | Switch Icon Showdown esclude `/images/` ai crawler (9 nov 2026): la fonte non è operativa e la issue #12 non è risolta |
| Prova di aggiornamento A → B con l'app installata | in attesa | Vedi [development.md](development.md#first-installation-and-a--b-update-test) |

## Pin dell'engine

Il dettaglio di ogni revisione è in [upstream-upgrades](upstream-upgrades/README.md).

| Pin | Versione | Stato |
|---|---|---|
| `8a5c5e7e` (Metal 32023.922, Xcode 27.2) | 0.1.4.3, attuale | adottato su richiesta del maintainer; build e avvio sull'esatto hash da confermare |
| `79741184` | 0.1.4.2 | gate e test superati; build e avvio sull'esatto hash non confermati |
| `bd979ced` | 0.1.4.1 | — |
| `e5f03403`, `7fe9fc4d` | precedenti | confermati con un rebuild di Ocarina of Time |
| `04df08d4` | precedente | confermato con un build di Ocarina of Time |
| `4a0551e4` | precedente | gate certificato, build di Wonder con archivio pipeline e avvio confermati |
