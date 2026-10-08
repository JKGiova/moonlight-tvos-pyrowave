# Piano v3 — Tutte le Apple TV con tvOS attuale, decode veloce e Auto

Stato: sviluppo autorizzato e iniziato il 7 ottobre 2026. Baseline Moonlight e PyroWave importati come submodule; parser, test CPU e harness video offline implementati. Il primo percorso live sperimentale complete-frame è collegato tramite patch selettive a RTSP/SDP e al renderer Metal, con coda limitata e richiesta sperimentale esplicita. Lo shader Apple5 per A12, la factory decoder con controlli sui pipeline e la scelta manuale persistente PyroWave sono implementati sperimentalmente. Selettore Auto qualificato, monitor rete e recupero parziale restano da realizzare. Vedere [stato sviluppo](development-status.md). PyroWave è una scelta manuale sperimentale e sarà il candidato preferito in modalità Auto dopo la qualificazione; copertura di tutti i modelli compatibili con tvOS stabile e monitoraggio host ogni 5 secondi.

## Obiettivo

Integrare nel client Moonlight standard per tvOS il protocollo Nonary e il decoder Metal PyroWave, concentrandosi sul tempo di decoding e sulla latenza fino al frame pronto. L'encoder è sul PC host: il client negozia codec/profilo e sceglie il proprio decoder. Non implementiamo un encoder sulla Apple TV.

Il supporto PyroWave non è ancora qualificato su nessun modello. Per A12: il backend Metal ispezionato richiede Apple7, mentre A12 è Apple5. Il percorso portabile implementato sostituisce le operazioni SIMD non supportate con scan di threadgroup; deve ancora essere verificato sulla TV fisica. L'identità iniziale del bitstream è `186f0393`; sorgenti fissate in [upstreams.lock.json](../configs/upstreams.lock.json).

## Copertura dispositivi

Il target comprende tutte le Apple TV compatibili con l’ultima versione stabile di tvOS. Al 7 ottobre 2026, tvOS 27 include Apple TV 4K 2ª gen A2169 (A12), 3ª gen Wi-Fi A2737 e 3ª gen Wi-Fi + Ethernet A2843 (A15). La [matrice dispositivi](device-support.md) contiene fonti Apple, confini e controlli di rilascio; il [manifest](../configs/devices.json) è solo una specifica.

Una sola app tvOS: percorso portabile Apple5 per A12 e percorso nativo Apple7+ candidato per A15/Apple8. Il backend viene scelto dalle capability effettive e dalla creazione dei pipeline, poi qualificato per modello, build OS e profilo. La compatibilità con tvOS non prova la velocità del decoder. Deployment target minimo e toolchain saranno decisi in D0; il criterio sui modelli non impone automaticamente di alzare il minimo OS.

## Priorità

1. Correttezza del decoder su dispositivi fisici A12 e A15, con copertura di tutti i modelli in matrice.
2. Bassa latenza misurata: parsing, upload, dequantizzazione, iDWT, conversione e scheduling.
3. Throughput sostenuto con margine, nessuna crescita delle code.
4. Selezione Auto che preferisce PyroWave quando è idoneo e non peggiora la pipeline client rispetto al decoder hardware.
5. Compatibilità Nonary, resilienza di rete, fallback e diagnostica.
6. 4K60, 4:4:4 e HDR qualificati separatamente.

## Milestone

| Fase | Risultato | Criterio di uscita |
| --- | --- | --- |
| S0 — Scaffold | Documenti, manifest, template e confini dei componenti | Nessuna implementazione, nessun risultato GPU inventato |
| D0 — Import e baseline | Moonlight standard, build e misure H.264/HEVC | Avvio e streaming H.264/HEVC su ogni modello in matrice; revisioni riproducibili |
| D1 — Harness offline | Decoder Metal e frame salvati | Output corretto su A12 portabile e A15 nativo; geometrie e dati corrotti verificati |
| D2 — Qualificazione prestazioni | Shader Apple5 portabile e Apple7+ nativo, pipeline GPU ottimizzata | Percentili e throughput reali per modello/backend/profilo, memory/thermal soak |
| P0 — Protocollo | Patch selettive common-c e framing Nonary | Handshake, record/length-prefixed e buffer persi corretti |
| R0 — Renderer | Output texture e presentazione Metal | Stream 1080p60 SDR stabile, audio/input/stop/reconnect |
| N0 — Monitor host | RTT e telemetria rete aggiornati ogni 5 s; stima banda distinta | Più host, timeout, dati scaduti, budget sonde e assenza di disturbo allo streaming verificati |
| A0 — Selettore Auto | PyroWave manuale + preferenza automatica | Capability, benchmark, rete, profilo e fallback verificati su ogni modello |
| Q0 — Qualificazione 4K | Stesso percorso a 4K60 | Prova fisica di almeno 30 minuti per modello/profilo ammesso, coda limitata e margine |
| H0 — Profili aggiuntivi | 4:4:4, 10-bit, HDR | Misure e colorimetria corrette per ciascun profilo |

D0 è iniziato con l’autorizzazione dell’utente: sorgenti veri, bootstrap e comando di build disponibili. Le prove fisiche della baseline restano richieste prima di qualificare la release. D1 dispone di harness offline Metal e generazione/encoding video compilati in CI; il round trip GPU richiede ancora un dispositivo ammesso dal backend. P0/R0 dispongono del primo percorso complete-frame sperimentale, descritto in [test client sperimentale](experimental-client.md). Il primo smoke test standard su A12/tvOS 27 è riferito dall’utente il 2026-10-08, senza misure e senza prova PyroWave. Le milestone restano aperte fino alle prove fisiche complete.

## D1/D2 — Lavoro sul decoding

- Separare parsing CPU, upload GPU, dequantizzazione e iDWT; conservare un confronto FP32 prima di ottimizzare.
- Implementare scan/prefix e shuffle portabili per Apple5 con memoria di threadgroup e barriere. Conservare e misurare il percorso Apple7+ nativo su A15; non forzare tutti i chip sul percorso portabile. Verificare anche l’equivalenza fra i due percorsi su A15, dove eseguibili.
- Verificare limiti effettivi dei pipeline, texture e memoria locale; non basta rimuovere `supportsFamily:Apple7`.
- Il percorso Apple5 usa `native/apple/PyroWaveApple5Source.h`, generato dallo shader effettivo e verificato in CI; i sorgenti incorporati nativi `pyrowave_msl.h` restano intatti. Entrambi sono compilati con `newLibraryWithSource`.
- Partire da gruppi dequant 128 e iDWT 64 come riferimento; cambiare dimensioni soltanto con equivalenza verificata e benchmark.
- Provare FP32 math/FP16 storage (precisione 1) contro FP32 (precisione 2). Tolleranze su coefficienti interi e output floating point sono distinte.
- Tenere texture private e output GPU; niente readback di immagini nella pipeline normale. Un upload del bitstream resta necessario.
- Riutilizzare texture, buffer, pipeline e pool; evitare allocazioni per frame e attese bloccanti sul main thread.
- Confrontare compute iDWT con pass di rendering solo se il profiling mostra che serve. Il backend Metal ispezionato non offre già un percorso fragment selezionabile.
- Separare riscaldamento/compilazione iniziale da steady state e dal primo frame della sessione.
- Benchmark offline e streaming live sono complementari. La velocità desktop pubblicizzata non è una misura Apple TV.

Obiettivi aspirazionali GPU decode p95: 2 ms a 1080p60, 4 ms a 4K60. Non sono misure né promesse. I gate iniziali usano il budget del frame e sono definiti nella [specifica prestazioni](decoding-performance.md).

## P0/R0 — Integrazione nei sorgenti veri

| File upstream | Modifica pianificata |
| --- | --- |
| `Limelight/ViewControllers/MainFrameViewController.m` | Sostituire la decisione statica con una policy client verificabile |
| Definizione `CODEC_PREF_*`, `TemporarySettings.*`, `DataManager.*` | Nuovo valore PyroWave senza reinterpretare preferenze esistenti |
| `Moonlight TV/Settings.bundle/Root.plist` | Scelta Auto/PyroWave e bitrate; nessuna voce finta nello scaffold |
| `Limelight/Stream/StreamConfiguration.*` | Decisione, capability e profilo negoziato |
| `Limelight/Stream/Connection.m` | Dispatch per formato negoziato, ownership, contatori e errori |
| `Limelight/Stream/VideoDecoderRenderer.m` | Preservare il percorso Apple H.264/HEVC; adattare interfaccia comune |
| `Limelight/Stream/StreamManager.m` | Statistiche separate per decode, rete e presentazione |
| `Moonlight.xcodeproj/project.pbxproj` | Target, Objective-C++, shader e framework |
| common-c `Limelight.h`, `RtspConnection.c`, `SdpGenerator.c` | Capability/maschere PyroWave e selezione negoziata |
| common-c `Video.h`, `VideoDepacketizer.c`, `RtpVideoQueue.*`, `VideoStream.c`, `PlatformSockets.*` | Frame parziali, metadati e ricezione UDP Darwin |

`PyroWaveVideoRenderer` è ora implementato in `native/apple`, includendo inizialmente il presenter Metal nella stessa classe. Altri componenti pianificati: `CodecSelectionPolicy`, `DecoderCapabilityProbe`, `DecoderBenchmarkStore`, `HostNetworkMonitor`, `HostNetworkSampleStore`, `VideoRenderer` e una futura separazione `PyroWaveMetalPresenter`. I nomi restanti definiscono responsabilità future.

Deviare le DECODE_UNIT PyroWave prima del trattamento dei NAL: il codice attuale tratta i buffer non-PICDATA come parameter set. Conservare `BUFFER_TYPE_LOST`, `BUFFER_TYPE_RECORD_START` e `pyrowaveCriticalPackets`. Trasferire i dati in memoria posseduta prima di completare il frame common-c.

Parser: riusare `pyrowaveframing.cpp/.h` Nonary. Codec: `clear → push_packet → readiness → decode_gpu_buffer`. Output: tre texture Y/Cb/Cr → conversione colore → CAMetalLayer. Pool massimo iniziale: due frame GPU in volo e uno in attesa; sostituire il pending con il più recente.

## N0 — Latenza e banda host ogni 5 secondi

Aggiungere `HostNetworkMonitor` e un archivio di campioni per host/percorso, con aggiornamento nominale ogni 5 secondi in foreground. In streaming leggere il RTT stimato ENet tramite `LiGetEstimatedRttInfo` quando disponibile e misurare il goodput su finestre di 5 secondi; fuori sessione usare richieste leggere a un endpoint host esistente e verificato, etichettando il tempo di risposta del servizio. Non richiedere ICMP o un endpoint echo che il server non offre.

Il ping misura RTT, non banda. Mostrare goodput corrente e capacità utile stimata come valori distinti, con direzione, metodo, età e confidenza. Una stima di capacità richiede un trasferimento/protocollo supportato dall’host: prevedere un test limitato prima della sessione o su richiesta. Durante lo streaming evitare speed test saturanti; se non ci sono dati sufficienti, mostrare banda disponibile sconosciuta o precedente con età, aggiornando comunque RTT e goodput ogni 5 secondi.

La [specifica del monitor](host-network-monitor.md) definisce budget, cancellazione, timeout, UI e integrazione Auto. Le misure di banda devono attraversare la stessa rotta e, per qualificare PyroWave, essere accompagnate da convalida UDP live. N0 alimenta A0; lo stato rete non cambia codec a ogni tick.

## A0 — Auto preferisce PyroWave

La modalità Auto farà parte del prodotto, non sarà uno script shell separato. Il selettore client costruirà candidati da capability locali/host e profilo richiesto, poi applicherà i gate e la preferenza descritti in [codec-selection.md](codec-selection.md).

Se PyroWave è eleggibile e il suo client-ready p95 non regredisce oltre 0,5 ms rispetto al migliore fallback hardware misurabile, Auto lo preferisce. Se manca una misura valida, prima calibra oppure usa temporaneamente il codec hardware supportato; non annuncia PyroWave come verificato sulla sola base del nome del chip.

Le misure H.264/HEVC devono essere confrontabili: il percorso AVSampleBufferDisplayLayer può non esporre il tempo esatto del decoder. Distinguere misure complete da proxy e non usare il solo tempo di enqueue come baseline di decode. In assenza di confronto equivalente, il lancio richiede una qualificazione fisica documentata del profilo e della presentazione, non un confronto numerico inventato.

Il codec resta fisso durante la sessione. Il fallback effettua una nuova negoziazione; cooldown e cache dell'errore evitano reconnessioni ripetute. Prima versione Auto SDR 4:2:0; con richiesta HDR/4:4:4 non qualificata, scegliere un candidato del profilo corretto senza abbassarlo silenziosamente.

## Ambiente di test — PC Vibeshine e Apple TV

Il PC dell’utente con Vibeshine diventa l’host primario. Fissiamo come riferimento Vibeshine 2.0.0 (`0689b2e0`), che documenta PyroWave `186f0393`; la versione effettivamente installata verrà verificata durante il setup, senza presumere che coincida.

Ciclo pianificato: modifica sorgenti → build/firma con Mac/Xcode → installazione e avvio sulla Apple TV fisica → connessione al PC già associato → avvio dell’app di test scelta → misure e report. Si può scrivere codice e coordinare test dal PC, ma il client tvOS e le misure GPU girano sulla Apple TV. Servirà un runner raggiungibile dal Mac e dal dispositivo: il repository/cloud da solo non si collega automaticamente alla LAN dell’utente.

Prevedere un profilo locale di test con identità host, app ID, profilo video e durata; pairing PIN iniziale manuale, poi riuso dell’identità salvata dal client. Autoconnessione esplicita solo per i run di sviluppo, timeout e tentativi limitati; nessun cambio automatico delle preferenze normali e nessuna sessione esistente interrotta. Confrontare PyroWave/HEVC/H.264 a parità di contenuto e condizioni, separando encode host, rete e decode client. La [specifica dei test Vibeshine](vibeshine-testing.md) descrive il setup e gli esiti; non è ancora uno script operativo.

Per la banda, Vibeshine offre già HTTPS autenticato `/pyrowave-bandwidth-probe` da 32 MiB e i metadati `/serverinfo`. Riutilizzarli per la calibrazione prima del run, rispettando quota e budget; non fare download da 32 MiB ogni 5 secondi durante il gioco. Vedere [monitor host](host-network-monitor.md).

## Verifica e distribuzione future

- Parser: record troncati, overflow, geometria, indice blocco, padding e perdita header.
- Decoder: frame reali e sintetici, colori/range, geometrie non allineate e riferimento Vulkan.
- Policy: cache separate per modello/backend/build OS, capability assenti, misura scaduta, rete insufficiente, profilo incompatibile, PyroWave idoneo, overload e fallback.
- Monitor host: refresh 5 s, RTT separato da banda, host offline/timeout, endpoint non supportato, rete cambiata, campioni scaduti, budget sonde, impatto sulle code GPU e sui drop.
- Sessione: frame persi/duplicati/riordinati, stop, reconnect e perdita drawable.
- Prestazioni: benchmark in ordine alternato dei codec, stesso profilo/workload, p50/p95/p99 e raw timestamp.
- Soak: almeno 30 minuti per profilo dichiarato; thermal throttling e crescita memoria/code.
- Build: Mac/Xcode, device arm64 e simulator; firma separata. CI app solo dopo l'import reale.

Il rilascio deve avviarsi e offrire un fallback hardware verificato su tutti i modelli in matrice. Per ciascun profilo dichiarato, PyroWave è qualificato con prove fisiche oppure esplicitamente non ammesso con motivazione; non si estende un risultato A15 ad A12 o fra varianti. I dispositivi non misurati restano non qualificati per Auto.

Rivedere la matrice a ogni nuova major stabile tvOS e a ogni nuovo modello Apple TV; l’ampliamento richiede capability e prove reali. Un aggiornamento di matrice non elimina automaticamente il supporto già rilasciato né cambia il deployment target. La prima versione installabile arriva dopo D/P/R/N/A, non da questo scaffold.
