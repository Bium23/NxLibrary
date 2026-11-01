# Immagini e video del README

Il README apre con logo, nome, descrizione e pochi badge. Il video andrà subito sotto questa presentazione, seguito dalle immagini delle funzioni. La guida d'uso continua più sotto; il blocco legale rimane in fondo.

Al momento non sono state inserite immagini dell'app né un video: gli screenshot ricevuti durante lo sviluppo mostravano anche stati ormai corretti. Le due posizioni sono riservate con commenti invisibili nel README, senza collegamenti vuoti o anteprime inventate. L'utente registra e fotografa la versione attuale; gli agenti non aprono né automatizzano l'app.

## Quattro immagini utili

| File da fornire | Schermata | Cosa racconta | Didascalia proposta |
|---|---|---|---|
| `spotlight.png` | Spotlight con una libreria ordinata. | La prima impressione: giochi, artwork e navigazione. | **Your library, together.** Browse games, artwork and activity in Spotlight. |
| `porting.png` | Add game, Review oppure porting in corso. | Il percorso guidato dalla selezione delle sorgenti alla build locale. | **From your files to a Mac app.** Review sources and follow each build stage. |
| `save-import.png` | Anteprima di importazione con From, percorsi e freccia. | Il passaggio fra origine e destinazione prima della conferma. | **Keep your progress.** Back up local saves and preview imports before replacing them. |
| `settings.png` | Settings con un gruppo leggibile, oppure Next launch di un gioco. | La distinzione fra libreria, nuovi giochi e scelte per titolo. | **Make it yours.** Keep library preferences and each game's launch options clear. |

Una quinta immagine di Collection può essere utile se mostra qualcosa di diverso. Evitare una galleria lunga di schermate quasi uguali.

Usare finestre della stessa proporzione, idealmente 16:10 o 16:9, con testo leggibile e una larghezza indicativa di 1600–1920 pixel. PNG è adatto agli screenshot dell'interfaccia. Le immagini devono mostrare il comportamento reale; eventuali oscuramenti di dati personali non devono cambiare lo stato rappresentato.

Prima di includerle, controllare nomi utente, percorsi, notifiche e informazioni personali. Non aggiungere asset Nintendo, chiavi, file di gioco o loro contenuti al repository. Per artwork e immagini visibili usare materiale originale o con diritti di redistribuzione adeguati, rispettando questo vincolo: le immagini caricate da servizi esterni non diventano automaticamente risorse del progetto.

## Inserimento delle immagini

Quando i file sono disponibili, conservarli in questa cartella e sostituire il commento `NX-SCREENSHOTS` nel README con immagini e didascalie. Usare percorsi relativi al README, ad esempio:

~~~html
<p align="center">
  <img src="docs/media/spotlight.png" alt="NX Library Spotlight showing the game library" width="100%">
</p>
<p align="center"><strong>Your library, together.</strong><br>Browse games, artwork and activity in Spotlight.</p>
~~~

L'immagine principale può occupare tutta la larghezza. Le altre funzionano meglio una per riga se contengono testo: una griglia riduce troppo i dettagli. Aggiungere al [catalogo dei file](../file-map.md) ogni immagine effettivamente inclusa.

## Video subito dopo la presentazione

Una registrazione breve, circa 45–90 secondi, può mostrare Spotlight, Collection, le opzioni di un gioco, un'anteprima dei salvataggi e Settings. I tempi di una build vanno abbreviati dichiarandolo; non presentare una sequenza tagliata come una compilazione istantanea.

Preferire un MP4 con H.264 per un'ampia compatibilità. Quando l'utente fornirà il video, caricarlo come allegato GitHub e mettere il suo URL su una riga autonoma al posto del commento `NX-DEMO`, subito dopo la presentazione. Non aggiungere un file video pesante alla cronologia Git. Verificare la riproduzione e l'accessibilità dell'allegato anche nel contesto di pubblicazione previsto.

La resa degli allegati dipende dal contesto e dal browser. Se il lettore non viene mostrato nel README, usare un fermo immagine cliccabile che apra il video, conservandolo nella stessa posizione. Non inserire pulsanti Play che portano a un video ancora inesistente. Riferimenti: [allegati GitHub](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/attaching-files) e [allegati tramite GitHub CLI](https://docs.github.com/en/github-cli/github-cli/attaching-files-with-github-cli).

Quando uscirà una release, aggiornare immagini o filmato se l'interfaccia è cambiata. Il video e gli screenshot illustrano la versione mostrata e non certificano il supporto di ogni gioco.
