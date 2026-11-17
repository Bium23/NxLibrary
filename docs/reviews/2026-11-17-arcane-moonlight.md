# Moonlight Arcane — prove e misure del 17 novembre 2026

Il tema Arcane mantiene l’identità `selene` e usa un campo cromatico continuo
nei passaggi Metal già esistenti. La preferenza delle particelle è indipendente
dal tema; le immagini e i video mantengono il proprio aspetto.

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
