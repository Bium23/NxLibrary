# Moonlight Arcane — prove e misure del 17 novembre 2026

Il tema Arcane mantiene l’identità `selene` e usa un campo cromatico continuo
nei passaggi Metal già esistenti. Le misure sotto documentano anche la prima
prova di Crystal dust, successivamente rimossa; immagini e video mantengono
il proprio aspetto.

## Contratti verificati

`MoonlightAppearanceTests` prova compatibilità dei file vecchi e dei valori
sconosciuti, salvataggio, Changed/Reset, continuità e periodicità dei colori,
e accesso alla riga delle particelle prima della scelta dello sfondo.

`run_theme.py` esegue i veri metodi di input con `AppSettingsStore` su una
cartella sintetica: movimento dal bordo della griglia alla riga, scelta
sinistra/destra, ritorno alle palette, mouse e A verso il passo sfondo.
Confronta anche l’ordine delle righe visibili di Look con quello delle azioni
di tastiera e controller. Questa regressione falliva prima della correzione
dell’ordine fra Background motion e Particles.

Con Metal disponibile, lo stesso script compila gli shader reali e confronta
il campionamento GPU dello spettro con quello del Core. Verifica le uniform
dei due effetti e di Mods, la differenza dei frame delle particelle e
l’identità di due immagini renderizzate allo stesso istante. Non apre
finestre, non cattura lo schermo e non legge profili del giocatore. Senza
device Metal salta soltanto la parte GPU; con un device e shader non
compilabili fallisce.

## Semplificazione delle particelle, 17 novembre

Il maintainer chiede di mantenere soltanto le particelle morbide: le faccette
sono poco distinguibili e non giustificano un’opzione. Il selettore esce da
Theme e Look, dal catalogo Search/Changed/Reset e dal renderer. Il campo
storico `particleStyle` è ignorato alla lettura e non viene più salvato.

I test di compatibilità e focus falliscono prima della rimozione e passano
dopo; la suite Swift esegue 1790 test senza errori. `run_theme.py` verifica
i metodi reali della griglia, il passaggio allo sfondo, l’ordine delle righe
Look e gli shader Metal reali: particelle morbide, campionamento GPU/Core,
frame fermo e uniform distinti per Mods. Questi controlli non sostituiscono
la prova visiva del maintainer. La tabella seguente resta la misura storica
della prima versione e non misura la rimozione delle faccette.

## Tempo dei passaggi GPU, fuori schermo

Misura locale con il renderer precedente e quello nuovo, stesso campo
deterministico e texture BGRA8 privata. Ogni riga ha 32 campioni dopo
10 frame di riscaldamento. Il tempo viene da `MTLCommandBuffer.gpuStartTime`
e `gpuEndTime`; include luce e particelle, non composizione della finestra,
SwiftUI, acquisizione del drawable o presentazione sul display.

| Profilo | Dimensione | Mediana GPU | P95 GPU |
|---|---|---|---|
| Precedente | 1920 × 1080 | 0,373 ms | 1,406 ms |
| Classico nel renderer nuovo | 1920 × 1080 | 0,395 ms | 2,280 ms |
| Arcane + Crystal dust | 1920 × 1080 | 0,238 ms | 1,541 ms |
| Precedente | 3840 × 2160 | 0,751 ms | 2,414 ms |
| Classico nel renderer nuovo | 3840 × 2160 | 0,711 ms | 2,298 ms |
| Arcane + Crystal dust | 3840 × 2160 | 0,894 ms | 2,554 ms |

L’ordine delle misure, il carico del desktop e la frequenza dinamica della GPU
non sono controllati. Le differenze non dimostrano un miglioramento di
prestazioni né garantiscono un frame rate nell’app. Servono a rilevare costi
evidenti nei soli passaggi aggiunti; fluidità, contrasto e integrazione si
verificano nella Dev. Lo stato delle prove umane è in
[validation.md](../validation.md).

## Superfici Arcane e Arcane Flow

Le due superfici usano filamenti analitici e piani generati nello shader.
Il colore resta locale (rosa a sinistra, ciano a destra), con variazioni
minime su180s. Nessun asset grafico esterno alimenta il movimento.
La variante è un metadato facoltativo della palette; la preferenza resta
`colorThemeID`. Le regole di pausa, Riduci movimento, copertura da artwork
ed entrata restano quelle del renderer e delle viste condivise.

La suite esegue1792test senza errori. Il controllo Metal confronta colori
GPU/Core, superfici distinte, fotogrammi identici a tempo fermo, movimento
a tempi diversi, uniform della variante Flow e oro Mods indipendente.
I fotogrammi sintetici delle due superfici sono stati ispezionati fuori
schermo; non sono screenshot dell’app e non provano la fluidità interattiva.

Una sonda a1920×1080 registra il tempo completo di `snapshot`, inclusi
allocazione, rendering, attesa e lettura CPU:12campioni dopo3di riscaldamento.
Mediane classico10,68ms, Arcane12,55ms, Flow12,41ms; massimi rispettivamente
11,86/13,08/13,08ms. Questi valori non sono tempi GPU né frame rate della
finestra e non sono confrontabili con la tabella GPU precedente. La prova
umana nella Dev resta necessaria per fluidità, leggibilità e ritmo.

La revisione individua valutazioni inutili: variante nascosta e fascio classico
anche con superficie Arcane pienamente visibile. I rami uniformi ora evitano
quei percorsi a regime; durante le dissolvenze restano entrambi. Le misure
sopra precedono questa correzione e non ne quantificano il beneficio. Il
controllo finale include anche blend intermedi e trasparenza a presenza zero.

Il blu classico resta il default `selene` e il fallback. Le superfici nuove
sono alternative esplicite: `arcane-crystal` (Arcane Crystal) e `arcane-flow`
(Arcane Flow). I controlli verificano anche questa separazione, l’ordine
predefinito e la persistenza degli ID; nessuna preferenza è riscritta.
Il ripristino del blu confronta esattamente i valori della palette storica;
il metadato delle nuove superfici è assente sia dal default sia dal fallback.
La suite completa passa ancora1792test, con una regressione inizialmente
rossa per default, fallback, ordine e numero delle alternative.

## Ripristino effettivo della luminosità originale

Il primo ripristino usava ancora i colori scuriti nell’esperimento5eb9862.
Il riferimento corretto è f427937: default radiale0x102A5C/0x03081A e fallback
lineare0x17244A/0x0C142C/0x05080F. Test inizialmente rossi ora proteggono
questi valori. Gli shader classici attuali sono confrontati fuori schermo con
quelli di f427937, stesso campo e uniform: differenza massima per canale
0/255 a320px,1/255 a640px,0/255 a960px. Il controllo del pacchetto Dev
conferma l’esatta palette storica, escluso il nome visibile. Non è una prova
della finestra o della composizione dello schermo.

## Fili sottili e onde viaggianti

La correzione mantiene intatto il percorso classico. Nei due temi opzionali
il profilo usa un nucleo gaussiano da0,5pixel sigma e dispersione molto
debole; il footprint è calcolato dalle derivate spaziali per mantenere il
tratto sottile anche sulle diagonali. Due onde sovrapposte deformano le curve
lungo la loro lunghezza, con fili secondari più deboli ed estremi sfumati.
I bokeh grandi sono attenuati soltanto nelle alternative.

La regressione GPU inizialmente rossa prova le funzioni Metal effettive:
luce a un pixel dal nucleo inferiore al20% del picco, escursione limitata,
spostamenti continui e deformazioni diverse in due punti del filo. Restano
le prove di colori locali, trasparenza a presenza zero, blend e Mods.
Fotogrammi sintetici e una sequenza reale di18secondi a30fps sono generati
fuori schermo, senza finestre o catture; questi dati non verificano la
fluidità dell’app e la qualità visiva resta da confermare dal maintainer.

## Cambio palette con selezione invariata

La prova dei metodi reali della shell e di ThemeStore riproduce la regressione:
il valore di SeleneBackdropStyle restava identico quando cambiava soltanto la
palette. SwiftUI non riceveva un cambiamento dell’ambiente; il successivo
spostamento della card ridisegnava il contenuto e rileggeva i colori globali.
Ora lo snapshot comprende la palette e i consumer di sfondo/maschere usano
quel valore. La prova inizialmente rossa passa per blu → Crystal → Flow → blu
senza cambiare il wallpaper né la card. Non si ricrea la pagina con un ID.

Su richiesta del maintainer, le alternative conservano solo filamenti e
luce ambientale molto tenue: rimossi i piani e ridotti i campi diffusi.
Il percorso classico del default resta invariato. Lo scatto/intervallo nero
nell’apertura immediata delle impostazioni resta distinto: log locali nella
sola Dev misurano renderer creato/presentato e apertura pagina, senza dati
del giocatore. I test d’ingresso verificano i contratti di readiness, non
la fluidità della finestra.

## Continuità home → Settings

La prova umana conferma lo scatto/nero. I log mostrano windowSettling=false
e un renderer nuovo ad ogni ingresso/ritorno, con21–57ms al primo drawable
presentato; la discontinuità non dipende soltanto dal fullscreen iniziale.
La shell conserva ora la superficie persistente. Le pagine dichiarano i
parametri tramite SeleneBackdropRequest e mantengono artwork/maschere,
senza creare un secondo sfondo. Il frame e il clock restano nella stessa
istanza; una richiesta assente conserva i parametri e mette in pausa.

I controlli headless coprono ordine delle richieste sovrapposte, mantenimento
del frame, pausa, ritorno agli stessi parametri, cambio palette e Mods.
Passano anche ingresso, onboarding e routing reali senza finestre. La prova
finale nella Dev deve confermare continuità visiva e stesso ID del renderer
attraverso home/Settings; i test di codice non sostituiscono questa verifica.

La revisione rileva che condividere la superficie richiede anche di coprire
i contenuti dei livelli inferiori. ShellBackdropCover definisce nel Core
la precedenza Setup2,5 → benvenuto2,4 → scelta tema1: ogni strato inferiore
resta montato/caldo ma quasi trasparente e senza input; dialoghi superiori
restano visibili. Controls applica la stessa separazione al contenuto locale
di Settings. Il blur esistente copre anche lo sfondo persistente. I test
verificano la precedenza dei tre schermi e i livelli0/0,5/0,8/1/2/2,4/2,5/3/4.
