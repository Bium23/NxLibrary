# Voti e metadati: prove e verifiche (16 nov 2026)

Nota datata. Raccoglie le verifiche reali e le misure che hanno motivato scelte descritte in [architecture.md](../architecture.md#artwork-metadati-e-voti). Il testo è quello che stava nella guida tecnica prima del riordino del 17 novembre 2026; qui resta come prova, la guida descrive solo il comportamento attuale.

## Wikidata: difetti trovati nella libreria reale

La verifica nella libreria reale ha individuato due difetti di ricerca: i simboli ™/®/©
nei nomi dello store davano risultati vuoti, e un nome Steam personalizzato non identificava
il titolo. Le query ora tolgono soltanto quei simboli, conservando sequel/edizioni; Steam
prova prima P1733 (ID pubblico esatto), verificato di nuovo nelle dichiarazioni dell'entità.
Il ripiego per nome usa anche il campo `match` degli alias. Le assenze salvate dal vecchio
resolver vengono ricontrollate, senza eliminare voti validi o modificare la libreria.

## IGDB: console Switch 2 (Ocarina of Time)

La verifica di Ocarina of Time (2026-11-16) ha individuato un filtro errato: entrambe
le pagine passavano sempre Switch (IGDB 130), scartando la scheda Switch 2. La query ora
deriva la console da `PortedGame.isSwitch2`, come Details, e distingue `switch` da
`switch2` (IGDB 508; Wikidata Q122761124). Nome/alias esatti e unicità rimangono obbligatori:
non si allarga il filtro alle due console insieme, evitando di mescolare edizioni omonime.
La console fa parte della chiave di entrambe le cache: Switch 2 riprova subito senza
riutilizzare l'assenza salvata come Switch, mentre voti validi e cache esistenti restano
intatti. Nessuna cancellazione di dati o modifica alle credenziali. Test con dati sintetici
coprono edizioni omonime, query dai giochi, compatibilità della vecchia identità Switch,
ripiego Wikidata e un'assenza preesistente. Restano da validare in Dev Ocarina/Switch 2,
un titolo Switch e uno Steam; la disponibilità effettiva del dato è stata poi verificata
con la richiesta autorizzata descritta sotto. La nuova presentazione del ripiego utenti
rimane in attesa di validazione umana.

## IGDB: verifica diretta autorizzata

Verifica diretta autorizzata dal maintainer il 16 novembre 2026: la stessa ricerca
dell'app restituisce la scheda Ocarina Switch 2 (405460, piattaforma 508), confermata
anche per ID. La risposta non contiene `aggregated_rating` né `aggregated_rating_count`:
ha solo `rating` (circa 99,7) e `rating_count` (35), cioè voti utenti al momento della
verifica. L'assenza nella riga della critica è quindi attesa anche dopo la correzione
della console. Non sostituire silenziosamente il voto utenti o quello di un'altra
edizione. Il maintainer ha poi approvato il ripiego utenti esplicitamente distinto.
Nessuna credenziale o token è stata registrata.

## Download a blocchi: misura

Correzioni del 16 novembre 2026 (in attesa di validazione umana). Una media della critica IGDB
vale solo con almeno 3 recensioni (`IGDBRatings.minimumCriticReviews`): con meno, la riga usa
Wikidata o, in sua assenza, la media utenti IGDB esplicita. `CriticRating.isValid` applica lo
stesso minimo, così le vecchie cache con 1–2 recensioni vengono richieste di nuovo. Salvare le
credenziali riporta anche una cartella `credentials` già esistente al modo 0700. I download di
Wikidata, IGDB, LaunchBox/TheGamesDB e Steam passano per `BoundedDownload`, che conserva i
blocchi ricevuti da URLSession: leggere `AsyncBytes` un byte alla volta costava circa 6 µs per
byte (pagina LaunchBox da 640 KB: 5,4 s e 3,9 s di CPU, ora 2,0 s e circa 10–30 ms di CPU).
Limiti di dimensione, rifiuto dei redirect e annullamento restano invariati.

## Selettore dei metadati: correzione del movimento

Correzione del movimento nel selettore: il cambio di focus sostituiva istantaneamente
l'estratto (240 caratteri) con il testo completo e avviava separatamente uno scroll
centrato, anche per righe più alte della finestra. `SeleneExpandableText` conserva i
due layout alla stessa larghezza: `Layout` risolve subito la geometria finale,
mentre SwiftUI anima i frame e la dissolvenza tra estratto e testo completo
([contratto SwiftUI](https://developer.apple.com/documentation/swiftui/layout)).
Interpolare le misure dentro `Layout` sposterebbe il bersaglio di `scrollTo`
durante la chiusura della riga precedente; la sonda fuori schermo ha riprodotto
questo errore e verificato l'allineamento con misure finali stabili.
Il selettore usa la stessa curva per espansione e scroll, con allineamento iniziale
per leggere il titolo delle descrizioni lunghe. Riduci movimento disattiva entrambi.
L'opzione è locale ai metadati: gli altri `SeleneOptionRow` restano invariati. Nessuna
modifica a richieste, cache, testi salvati o selezione delle fonti.

`scripts/check_metadata_text_layout.swift` verifica fuori schermo le altezze a tre
larghezze, il cambio di contenuto e le destinazioni dello scroll durante cambi
di focus ripetuti, anche con Riduci movimento; non misura frame rate o fluidità reale.
Da verificare nella Dev: su/giù ripetuti fra descrizioni corte e molto lunghe, scroll
manuale fino alla fine, Q/E, scelta/salvataggio e Riduci movimento. Correzione del
movimento **in attesa di validazione umana**.

## LaunchBox e TheGamesDB: sonde reali

Scelta: leggere su richiesta una ricerca e una scheda pubblica per database, con
parser separati e cache di sole proposte; non scaricare l'intero Metadata.zip né
duplicare un catalogo immagini. Le sonde delle pagine pubbliche hanno misurato circa
74 KB per una scheda LaunchBox e 15 KB per una TheGamesDB, senza scaricare immagini.
Il formato corrente LaunchBox espone gameKey/name/platform e campi indicizzati nel
payload Nuxt; TheGamesDB espone titolo, piattaforma e campi etichettati. I parser
devono verificare anche la scheda finale, rifiutare ambiguità e non eliminare parole
di edizione. Mac è preferito a PC/Windows; una proposta alternativa PC è dichiarata
e non fornisce una falsa data Mac. Le righe delle fonti restano visibili e stabili,
con stati assente/uguale ad Automatico/errore e retry accessibile, senza scrivere
scelte personali durante il caricamento. Cache, dimensioni, durata, annullamento e
numero di richieste sono verificati con test e sonde: nessuna promessa di massima
prestazione deriva dalla sola compilazione. Implementato; controlli automatici e confezionamento Dev descritti sotto.
Validazione umana ancora necessaria.

La sonda reale ha individuato un redirect LaunchBox da ricerca con maiuscole al
percorso minuscolo: `LaunchBoxArt.searchURL` ora genera direttamente la forma canonica,
evita il 301 e permette il client vincolato anche per i metadati. La prova, con cache
isolata e titoli pubblici di fixture, ha restituito cinque campi per Donkey Kong
Bananza (Switch 2) e quattro per Hollow Knight (PC come alternativa Mac, senza data
PC). In quella singola esecuzione la prima lettura ha impiegato circa 1,595 s e
0,510 s; le riletture locali circa 0,420 ms e 0,275 ms. Non sono misure di frame rate
né garanzie sulla latenza dei servizi. Il probe temporaneo non è incluso nei test
normali; i test riproducibili verificano invece due richieste per una ricerca
LaunchBox, zero richieste cambiando campo/rileggendo una cache fresca, coalescenza,
annullamento, retry e risposte sovradimensionate o di destinazione inattesa.

