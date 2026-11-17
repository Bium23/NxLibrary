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
