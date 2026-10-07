# Piano v2 — Decode veloce e Auto con preferenza PyroWave

Stato: scaffold e specifica, 6 ottobre 2026. Nessun decoder o selettore è implementato. Questo piano aggiorna la precedente proposta a selezione solo manuale: PyroWave sarà una scelta manuale e il candidato preferito in modalità Auto dopo la qualificazione.

## Obiettivo

Integrare nel client Moonlight standard per tvOS il protocollo Nonary e il decoder Metal PyroWave, concentrandosi sul tempo di decoding e sulla latenza fino al frame pronto. L'encoder è sul PC host: il client negozia codec/profilo e sceglie il proprio decoder. Non implementiamo un encoder sulla Apple TV.

Il supporto A12 non è acquisito: il backend Metal ispezionato richiede Apple7, mentre A12 è Apple5. Il percorso portabile deve sostituire le operazioni SIMD non supportate. L'identità iniziale del bitstream è `186f0393`; sorgenti fissate in [upstreams.lock.json](../configs/upstreams.lock.json).

## Priorità

1. Correttezza del decoder fisico A12.
2. Bassa latenza misurata: parsing, upload, dequantizzazione, iDWT, conversione e scheduling.
3. Throughput sostenuto con margine, nessuna crescita delle code.
4. Selezione Auto che preferisce PyroWave quando è idoneo e non peggiora la pipeline client rispetto al decoder hardware.
5. Compatibilità Nonary, resilienza di rete, fallback e diagnostica.
6. 4K60, 4:4:4 e HDR qualificati separatamente.

## Milestone

| Fase | Risultato | Criterio di uscita |
| --- | --- | --- |
| S0 — Scaffold | Documenti, manifest, template e confini dei componenti | Nessuna implementazione, nessun risultato GPU inventato |
| D0 — Import e baseline | Moonlight standard, build e misure H.264/HEVC | Avvio e streaming sul dispositivo; revisioni riproducibili |
| D1 — Harness offline | Decoder Metal e frame salvati | Output corretto su A12; geometrie e dati corrotti verificati |
| D2 — Qualificazione prestazioni | Shader Apple5 e pipeline GPU ottimizzata | Percentili e throughput reali, memory/thermal soak |
| P0 — Protocollo | Patch selettive common-c e framing Nonary | Handshake, record/length-prefixed e buffer persi corretti |
| R0 — Renderer | Output texture e presentazione Metal | Stream 1080p60 SDR stabile, audio/input/stop/reconnect |
| A0 — Selettore Auto | PyroWave manuale + preferenza automatica | Capability, benchmark, rete, profilo e fallback verificati |
| Q0 — Qualificazione 4K | Stesso percorso a 4K60 | Prova fisica di almeno 30 minuti, coda limitata e margine |
| H0 — Profili aggiuntivi | 4:4:4, 10-bit, HDR | Misure e colorimetria corrette per ciascun profilo |

Lo sviluppo inizierà da D0 soltanto dopo una nuova istruzione dell'utente.

## D1/D2 — Lavoro sul decoding

- Separare parsing CPU, upload GPU, dequantizzazione e iDWT; conservare un confronto FP32 prima di ottimizzare.
- Implementare scan/prefix e shuffle portabili per Apple5 con memoria di threadgroup e barriere. Conservare il percorso Apple7 veloce.
- Verificare limiti effettivi dei pipeline, texture e memoria locale; non basta rimuovere `supportsFamily:Apple7`.
- Rigenerare anche `metal/shaders/pyrowave_msl.h`, perché il backend originale compila sorgenti incorporate con `newLibraryWithSource`.
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

Nuovi componenti pianificati: `CodecSelectionPolicy`, `DecoderCapabilityProbe`, `DecoderBenchmarkStore`, `VideoRenderer`, `PyroWaveVideoRenderer`, `PyroWaveMetalPresenter`. I nomi definiscono responsabilità future, non sorgenti esistenti.

Deviare le DECODE_UNIT PyroWave prima del trattamento dei NAL: il codice attuale tratta i buffer non-PICDATA come parameter set. Conservare `BUFFER_TYPE_LOST`, `BUFFER_TYPE_RECORD_START` e `pyrowaveCriticalPackets`. Trasferire i dati in memoria posseduta prima di completare il frame common-c.

Parser: riusare `pyrowaveframing.cpp/.h` Nonary. Codec: `clear → push_packet → readiness → decode_gpu_buffer`. Output: tre texture Y/Cb/Cr → conversione colore → CAMetalLayer. Pool massimo iniziale: due frame GPU in volo e uno in attesa; sostituire il pending con il più recente.

## A0 — Auto preferisce PyroWave

La modalità Auto farà parte del prodotto, non sarà uno script shell separato. Il selettore client costruirà candidati da capability locali/host e profilo richiesto, poi applicherà i gate e la preferenza descritti in [codec-selection.md](codec-selection.md).

Se PyroWave è eleggibile e il suo client-ready p95 non regredisce oltre 0,5 ms rispetto al migliore fallback hardware misurabile, Auto lo preferisce. Se manca una misura valida, prima calibra oppure usa temporaneamente il codec hardware supportato; non annuncia PyroWave come verificato sulla sola base del nome del chip.

Le misure H.264/HEVC devono essere confrontabili: il percorso AVSampleBufferDisplayLayer può non esporre il tempo esatto del decoder. Distinguere misure complete da proxy e non usare il solo tempo di enqueue come baseline di decode. In assenza di confronto equivalente, il lancio richiede una qualificazione fisica documentata del profilo e della presentazione, non un confronto numerico inventato.

Il codec resta fisso durante la sessione. Il fallback effettua una nuova negoziazione; cooldown e cache dell'errore evitano reconnessioni ripetute. Prima versione Auto SDR 4:2:0; con richiesta HDR/4:4:4 non qualificata, scegliere un candidato del profilo corretto senza abbassarlo silenziosamente.

## Verifica e distribuzione future

- Parser: record troncati, overflow, geometria, indice blocco, padding e perdita header.
- Decoder: frame reali e sintetici, colori/range, geometrie non allineate e riferimento Vulkan.
- Policy: capability assenti, misura scaduta, rete insufficiente, profilo incompatibile, PyroWave idoneo, overload e fallback.
- Sessione: frame persi/duplicati/riordinati, stop, reconnect e perdita drawable.
- Prestazioni: benchmark in ordine alternato dei codec, stesso profilo/workload, p50/p95/p99 e raw timestamp.
- Soak: almeno 30 minuti per profilo dichiarato; thermal throttling e crescita memoria/code.
- Build: Mac/Xcode, device arm64 e simulator; firma separata. CI app solo dopo l'import reale.

La prima versione installabile arriva dopo D/P/R/A, non da questo scaffold.
