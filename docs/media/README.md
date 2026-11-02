# Immagini e video del README

Il README apre con logo, nome, descrizione e pochi badge. Spotlight introduce l'app; gli altri screenshot accompagnano la funzione descritta nella guida. Il video avrà posto subito sotto la presentazione, prima di Spotlight. Il blocco legale rimane in fondo.

## Screenshot inclusi

Le otto catture fornite dall'utente il 2 novembre 2026 sono state rinominate nelle copie del repository. Gli originali sul Desktop restano invariati. Gli agenti non hanno aperto né automatizzato l'app.

| Nome originale | File nel repository | Posizione nel README |
|---|---|---|
| `Spotlight View.png` | [spotlight.webp](spotlight.webp) | Apertura, prima di Overview. |
| `Details Games.png` | [game-details.webp](game-details.webp) | Your library: dettagli e attività del gioco. |
| `Rapid Menu.png` | [quick-menu.webp](quick-menu.webp) | Your library: accesso al menu rapido. |
| `Porting State home .png` | [porting-progress.webp](porting-progress.webp) | Add or rebuild a game: avanzamento in Spotlight. |
| `Setting View.png` | [settings.webp](settings.webp) | Know which settings apply: categorie e Start-up. |
| `Color theme.png` | [color-themes.webp](color-themes.webp) | Artwork, themes and sound: scelta della palette. |
| `Background Static Wallpaper.png` | [static-wallpapers.webp](static-wallpapers.webp) | Artwork, themes and sound: sfondi statici. |
| `Background Wallpaper Live .png` | [live-wallpapers.webp](live-wallpapers.webp) | Artwork, themes and sound: sfondi animati. |

Le copie WebP sono larghe 1920 pixel, mantengono proporzioni e contenuto delle catture e usano il profilo colore sRGB. Occupano complessivamente circa 2,3 MB, rispetto ai circa 73 MB degli originali. I metadati personali non vengono trasferiti. Le didascalie e i testi alternativi sono in inglese; ciascuna immagine ha una propria riga per preservare la leggibilità.

La cattura di Settings mostra ancora il precedente pin `2716f78`; il pin corrente e i requisiti sono quelli del README. Aggiornare questa foto alla prossima sessione di cattura. Anche lo stato delle sorgenti e della toolchain nei dettagli di un gioco descrive soltanto il gioco fotografato.

Le immagini illustrano la libreria dell'utente. Copertine, loghi e wallpaper visibili restano soggetti ai diritti e ai termini dei rispettivi proprietari; la licenza MIT del codice non ne modifica i termini.

## Aggiornare le immagini

Conservare le catture complete, senza modificare lo stato mostrato o ricreare l'interfaccia. Preparare copie ottimizzate in questa cartella e collegarle alla sezione pertinente del README con testo alternativo e una didascalia breve. Controllare che non siano visibili chiavi, percorsi privati o notifiche personali. Non aggiungere file di gioco o asset separati.

Gli screenshot del setup in due passaggi e dell'anteprima dei salvataggi potranno essere aggiunti quando disponibili; non ci sono segnaposto visibili. Il commento `NX-SCREENSHOTS` delimita l'immagine d'apertura e `NX-DEMO` riserva il posto al video. Aggiornare anche il [catalogo dei file](../file-map.md) quando si aggiungono o rinominano immagini.

## Video subito dopo la presentazione

Una registrazione breve, circa 45–90 secondi, può mostrare Spotlight, Collection, le opzioni di un gioco, un'anteprima dei salvataggi e Settings. I tempi di una build vanno abbreviati dichiarandolo; non presentare una sequenza tagliata come una compilazione istantanea.

Preferire un MP4 con H.264 per un'ampia compatibilità. Quando l'utente fornirà il video, caricarlo come allegato GitHub e mettere il suo URL su una riga autonoma al posto del commento `NX-DEMO`, subito dopo la presentazione. Non aggiungere un file video pesante alla cronologia Git. Verificare la riproduzione e l'accessibilità dell'allegato anche nel contesto di pubblicazione previsto.

La resa degli allegati dipende dal contesto e dal browser. Se il lettore non viene mostrato nel README, usare un fermo immagine cliccabile che apra il video, conservandolo nella stessa posizione. Non inserire pulsanti Play che portano a un video ancora inesistente. Riferimenti: [allegati GitHub](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/attaching-files) e [allegati tramite GitHub CLI](https://docs.github.com/en/github-cli/github-cli/attaching-files-with-github-cli).

Quando uscirà una release, aggiornare immagini o filmato se l'interfaccia è cambiata. Il video e gli screenshot illustrano la versione mostrata e non certificano il supporto di ogni gioco.
