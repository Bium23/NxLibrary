# Entrata della libreria — misure del 17 novembre 2026

## Metodo

Una sonda temporanea nella Dev registrava `CACurrentMediaTime()` durante le
valutazioni di `EntranceFlight.effectValue`, unendo campioni distanti meno di
2 ms. Il log `entrance` riportava attesa dopo la copertura, durata, intervallo
massimo e numero di intervalli oltre 1,5 volte il periodo ricavato da
`NSScreen.maximumFramesPerSecond`. Il conteggio escludeva i primi 100 ms.

Le aperture erano eseguite dal maintainer, con e senza benvenuto e con avvio
fullscreen. Non sono state usate automazione UI o catture dello schermo.

## Campioni

I campioni seguenti provengono dal log della Dev durante le iterazioni della
stessa giornata. Le versioni avevano tempi diversi: la durata non è un confronto
diretto di velocità fra prima e dopo.

| Campione | Frequenza dichiarata | Attesa | Durata campionata | Intervallo massimo | Intervalli oltre soglia |
|---|---:|---:|---:|---:|---:|
| 10:16:33, benvenuto, prima del disegno anticipato delle tessere | 120 Hz | 0 ms | 1.471 ms | 28 ms | 3 / 160 |
| 11:08:57, benvenuto, disegno anticipato e pausa di 0,5 s | 120 Hz | 512 ms | 2.124 ms | 9 ms | 0 / 243 |
| 11:39:06, fullscreen, arte ancora in lettura alla scadenza | 120 Hz | 1.562 ms | 2.184 ms | 10 ms | 0 / 251 |
| 11:57:18, fullscreen, senza benvenuto | 120 Hz | 523 ms | 2.188 ms | 9 ms | 0 / 251 |

Nel primo campione i tre intervalli lunghi cadevano a 523, 610 e 798 ms,
vicino alle prime apparizioni di tessere. Il disegno anticipato usa opacità
0,001 per la riga e il contenuto dell'effetto prima della comparsa: negli
ultimi campioni non si osservano intervalli oltre soglia dopo i primi 100 ms.
Resta la riga reale animata in SwiftUI; il livello dell'arte sfuma in Core Animation.

Per l'avvio fullscreen delle 11:57, il log registra il primo frame del moonlight
a 388 ms, l'inizio della transizione a 702 ms e la fine a 1.547 ms dalla prima
apparizione della finestra. `LaunchReveal` attende il primo frame con un limite
di 1 s prima di mostrare la finestra e consentire il fullscreen.

## Limiti e conservazione

- I campioni misurano valutazioni dell'animazione SwiftUI sul thread principale,
  non i frame presentati dalla GPU o dal compositor.
- La frequenza usata è il massimo dichiarato dallo schermo, non una misura del
  refresh effettivo. La soglia è quindi un indicatore diagnostico.
- I primi 100 ms non partecipano al conteggio degli intervalli lunghi.
- Hardware, cache, libreria e tempi sono quelli delle singole aperture; questi
  numeri non garantiscono lo stesso risultato su altri Mac o dati.

La sonda e le sue chiamate sono rimosse dal codice applicativo; questa nota
conserva metodo e risultati. Lo stato delle prove manuali resta soltanto in
[validation.md](../validation.md).
