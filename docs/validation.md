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
| Impostazioni in General, Library, Porting e System (sezioni nuove Games, Keys, Cloud saves, Storage di Porting, Console; Rumble in New games) | in attesa | Percorrere la barra con frecce e controller; Search e Changed mostrano "Porting · …"; Reset group in Library → Games non tocca Rumble; i link "Settings → …" degli errori aprono la sezione giusta |
| Primo avvio da ciò che è già sul Mac (pagina `found`) | in attesa | Con una Dev senza Setup completato: righe Steam e app portate con i numeri giusti; interruttore Steam spento → nessuna fonte Steam; card Porting → Get ready, B torna indietro; Open library apre la libreria; caso vuoto con "No games found"; frecce, mouse e controller |
| Benvenuto in Arcane, una volta, per chi aggiorna | in attesa | Aprire Arcane Dev con i dati della vecchia Dev: compare dopo l'intro; con Steam spento offre Add / Not now (Add accende la fonte); B, Esc e Open library lo chiudono e non torna al riavvio; con un gioco aperto, Play e Resume restano normali; con Riduci movimento nessuna dissolvenza |
| Catalogo comune nella Dev (`CatalogRepository`, conversione da `library.json`, recupero) | in attesa | Prima apertura della Dev con libreria reale, recupero esplicito |
| Fonti e libreria mista (Steam + Switch, Manage sources) | in attesa | La scelta iniziale Mac/Switch/entrambi non esiste ancora |
| Steam: metadati store e arte | in attesa | — |
| Steam: pagina condivisa, Opzioni, personalizzazioni | in attesa | — |
| Steam: Play, schermata di lancio, domande di Steam, Steam in background | in attesa | — |
| Steam: ore di gioco | in attesa | — |
| Steam: giochi in download, osservazione dei manifest, ordine della riga | aspetto validato il 15 nov 2026 | Fine del download e controlli di accettazione |
| Achievement Steam: lista, rarità, tier a cristallo, card Details | in attesa | — |
| Achievement: la lista segue la riga scelta dopo chiusura e riapertura rapide | validato il 16 nov 2026 | — |
| Achievement: video Arcane, medaglioni del dettaglio, lucchetto dei segreti, scorrimenti (`GlideGroup`) | in attesa | — |
| Achievement: intestazione senza 100% (percentuale, barra larga e conteggio sotto i quattro trofei, 44 pt / 4) | in attesa | — |
| Correzioni della revisione di sviluppo (CHANGELOG "Unreleased": focus della card, nuovi tentativi, piattaforma dei loghi, osservazione delle librerie Steam, lettori protetti) | in attesa | — |
| Posizione condivisa dei comandi: `SeleneHintsBar` a 32 unità dal fondo | in attesa | La posizione dei Settings (`7adc0ad`) è validata; la via di mezzo a 32 no |
| Pannello Details uguale per ogni fonte | validato il 16 nov 2026 | — |
| Voto della critica con Wikidata | validato il 16 nov 2026, abbinamenti compresi | — |
| IGDB facoltativo: credenziali, voti, minimo di 3 recensioni, media utenti come ripiego | in attesa (il ripiego utenti è approvato come scelta) | Ocarina con voto utenti, un gioco con voto della critica, cambio rapido di gioco, rimozione di IGDB |
| Sezione API services (IGDB e SteamGridDB) | in attesa | — |
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
