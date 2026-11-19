# Traduzione delle descrizioni: prova sul Mac

19 novembre 2026, macOS 27.2.1, Xcode 27.2. Prova temporanea (uno script Swift fuori dal repository) per scegliere tra il framework Translation di Apple e il modello di Apple Intelligence (Foundation Models) per Translate in About this game.

## Campioni

Tre descrizioni inglesi reali dalla cache dei metadati (Pokémon Brilliant Diamond, 1565 caratteri; Super Mario Bros. Wonder, 1942; The Legend of Zelda: Tears of the Kingdom, 513) e un testo di 152 caratteri con violenza esplicita, come quelli dei giochi horror. Destinazioni: cinese semplificato e italiano. Su questo Mac le due lingue erano già scaricate e Apple Intelligence era attiva.

## Risultati

| Testo | Translation, zh-Hans | Modello, zh-Hans | Translation, it | Modello, it |
|---|---|---|---|---|
| Pokémon (1565) | 4,9 s | 8,1 s | 5,1 s | 8,0 s |
| Mario Wonder (1942) | 7,0 s | 11,6 s | 7,3 s | 13,1 s |
| Zelda (513) | 1,8 s | 3,1 s, **mescola il cinese tradizionale** | 1,6 s | 2,9 s |
| Violento (152) | 0,7 s | 1,3 s | 0,9 s | **rifiutato** ("unsafe content") |

- Translation tiene sempre il cinese semplificato. Lascia in inglese alcuni nomi propri (Sinnoh, Team Galactic).
- Il modello rende meglio alcuni nomi (新奥地区), ma nel testo di Zelda passa al cinese tradizionale a metà, e rifiuta il testo violento in italiano.
- NaturalLanguage riconosce l'inglese in tutti e quattro i campioni.

## Scelta

Solo il framework Translation: è circa due volte più veloce, tiene la scrittura giusta e non rifiuta i testi. Un solo percorso è anche più semplice da mantenere.

## Limiti

Un solo Mac, quattro testi, lingue già scaricate. Non misurati: il primo download di una lingua, la memoria, Mac senza Apple Intelligence o con macOS 15.
