# Dock e app rinominata — sonda del 17 novembre 2026

**Domanda:** se un'app nel Dock viene rinominata mentre è chiusa, il Dock la apre ancora?

**Sonda** (macOS 27.2, Mac del maintainer):
1. Un'app minima `NX Probe.app` in `~/Applications`, firmata ad-hoc, bundle ID `local.nxlibrary.dockprobe`, tenuta nel Dock dal maintainer e chiusa.
2. Rinominata in `Arcane Probe.app` con `mv`, nella stessa cartella.
3. Dopo la rinomina, `defaults read com.apple.dock persistent-apps` mostra ancora `_CFURLString` = `file:///Users/<utente>/Applications/NX%20Probe.app/` e `file-label` = "NX Probe".
4. Il maintainer ha cliccato l'icona nel Dock: l'app si è aperta e la sua finestra mostrava il percorso nuovo.

**Esito:** il Dock segue una rinomina nella stessa cartella. Il percorso salvato non serve a ritrovare l'app: per inferenza, il Dock la risolve dal segnalibro o dal bundle ID. L'app di prova è stata messa nel Cestino.
