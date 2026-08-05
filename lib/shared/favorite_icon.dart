import 'package:flutter/material.dart';

/// Icona dei PREFERITI: una luna, non una stella (scelta esplicita — la luna è
/// anche il simbolo che Bruma usa nelle notifiche anonime).
///
/// Definita qui in un punto solo: era sparsa in sei file, e cambiarla a mano
/// significava dimenticarsene da qualche parte.
const IconData favoriteIconOn = Icons.bedtime;
const IconData favoriteIconOff = Icons.bedtime_outlined;

/// Colore della luna quando il contenuto è salvato.
const Color favoriteColor = Color(0xFFF2C744);
