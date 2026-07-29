-- ============================================================================
-- Richieste di riapertura mostrate IN CHAT come messaggi di sistema.
-- Due nuovi tipi di messaggio (senza contenuto: né ciphertext né blob):
--   * reopen_request → la richiesta di riaprire una foto (cita la foto via
--     reply_to). La vedono entrambi; il proprietario ci trova Accetta/Rifiuta.
--   * reopened       → segnaposto "foto riaperta" inserito in fondo alla chat
--     quando il proprietario accetta (rinnova la STESSA foto, nessun reinvio).
-- Non serve message_access (nessuna chiave da consegnare) e non si duplicano
-- contenuti né statistiche: la foto originale resta l'unica, riabilitata da
-- renew_access.
-- ============================================================================

alter table public.messages drop constraint if exists messages_type_check;
alter table public.messages add constraint messages_type_check
  check (type in ('text', 'photo', 'reopen_request', 'reopened'));
