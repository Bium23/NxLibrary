# Primi cambi gioco in Spotlight — misure del 18 novembre 2026

Lo scatto compariva con destra e sinistra nei primi movimenti dopo l'entrata.
La prova manuale confronta più avvii della Dev. Una sonda temporanea campiona il
valore animato della camera della riga sul thread principale, unisce le letture
a meno di 2 ms e riporta l'intervallo più lungo e il lavoro sincrono misurato.

| Campione | Primo aggiornamento | Intervallo massimo | Mod sul thread principale | Salvataggio selezione |
|---|---:|---:|---:|---:|
| Prima, primo cambio | 24 ms | 35 ms | 9 ms | 2 ms |
| Prima, secondo cambio | 9 ms | 15 ms | 5 ms | 1 ms |
| Dopo, primo cambio | 19 ms | 28 ms | < 0,5 ms | 9 ms |
| Dopo, secondo cambio | 15 ms | 16 ms | < 0,5 ms | 7 ms |
| Scrittura in background, primo cambio (avvio 1) | 28 ms | 52 ms | — | in background |
| Scrittura in background, secondo cambio (avvio 1) | 17 ms | 18 ms | — | in background |
| Scrittura in background, primo cambio (avvio 2) | 29 ms | 53 ms | — | in background |
| Scrittura in background, secondo cambio (avvio 2) | 14 ms | 15 ms | — | in background |

Spotlight legge le mod all'apertura della pagina e Play riconcilia le cartelle
prima dell'avvio del gioco. Il controllo senza finestre usa la funzione di
Spotlight con un sostituto di `ModsBandHost` e verifica che la riga non legga
la fascia del gioco successivo, mentre la pagina la carica.

Il salvataggio sincrono della selezione arriva a 7–9 ms dopo il primo intervento.
`AppSettingsStore` passa quella scrittura alla coda seriale in background e
completa la scelta alla chiusura. I test esercitano la scrittura fuori dal
thread principale e la precedenza del valore più recente al salvataggio.

Entrambi i primi cambi nel passaggio con scrittura in background hanno 27
aggiornamenti in circa mezzo secondo. I secondi ne hanno 58 e 59. Nei due
campioni freddi l'artwork successivo entra 45 ms dopo la fine del
campionamento della riga. La differenza di cadenza richiede una misura
dedicata e non stabilisce da sola la causa.

Un campionamento CPU di 12 s rallenta anche i movimenti successivi, con
intervalli di 112–172 ms. Questi tempi sono esclusi dal confronto. Nelle pile
del thread principale si osserva `rememberLastSelectedGame` → setter
`@Published` → invalidazione e aggiornamento sincrono della pagina Spotlight.
La scelta diventa stato di navigazione osservato solo dalla logica di
ripristino. Lo stesso store conserva il campo nel JSON. Un test conta le
notifiche dello store e richiede zero per un cambio di selezione riuscito.

Senza la notifica delle impostazioni, i primi cambi dei tre avvii danno
55, 51 e 27 aggiornamenti, con intervalli massimi di 25, 33 e 51 ms.
Il secondo cambio singolo dell'ultimo avvio dà 59 aggiornamenti e 22 ms.
In quest'ultimo avvio la nuova immagine sfuma dopo il campionamento.
Una prova con `CADisplayLink` chiede 120 Hz durante lo scorrimento. Core
Animation indica un obiettivo di circa 8 ms, ma la riga registra 26
aggiornamenti e un intervallo massimo di 53 ms. La prova non risolve lo
scatto e la richiesta viene rimossa.

Il percorso delle frecce costruiva il modello Dettagli prima di spostare
la riga, anche se non lo usava. SwiftUI impaginava la parte inferiore della
pagina anche durante la navigazione tra tessere. La riga usa ora solo la
lista filtrata. Dettagli, descrizione e giochi correlati si costruiscono
quando la pagina sale. Il controllo senza finestre verifica il cambio di
tessera, il bordo della riga e la precedenza della navigazione nella pagina.

### Esito della riga separata

| Avvio | Primo aggiornamento | Intervallo massimo | Aggiornamenti nel primo cambio |
|---|---:|---:|---:|
| 1 | 19 ms | 11 ms | 59 |
| 2 | 9 ms | 14 ms | 60 |
| 3 | 12 ms | 15 ms | 59 |

Il primo cambio nella prova precedente registrava 26 aggiornamenti e un
intervallo massimo di 53 ms. La curva, la geometria della riga e l'entrata
rimangono identiche nel codice. La parte inferiore della pagina si monta
alla sua apertura, quindi i suoi caricamenti possono iniziare più tardi.
Il controllo dei file prima di Play conserva record e overlay se la lettura
fallisce. Le fixture coprono cartella illeggibile, JSON corrotto e singola
mod assente in una cartella leggibile.

I valori provengono da singoli avvii. Indicano i tempi degli aggiornamenti di
SwiftUI, non i frame presentati dal compositor. La sonda è rimossa dalla Dev.
Lo stato delle prove manuali è in [validation.md](../../working-on-it/validation.md).
