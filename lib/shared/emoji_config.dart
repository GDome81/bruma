import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

/// Config del picker emoji allineata al tema di Bruma: sfondo e testi seguono
/// il `ColorScheme` invece del bianco fisso di default (che in tema scuro
/// rendeva la barra di ricerca praticamente illeggibile).
Config brumaEmojiConfig(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Config(
    emojiViewConfig: EmojiViewConfig(
      backgroundColor: cs.surface,
      columns: 8,
      emojiSizeMax: 28,
    ),
    categoryViewConfig: CategoryViewConfig(
      backgroundColor: cs.surfaceContainerHighest,
      indicatorColor: cs.primary,
      iconColor: cs.onSurfaceVariant,
      iconColorSelected: cs.primary,
      backspaceColor: cs.primary,
      dividerColor: cs.outlineVariant,
    ),
    bottomActionBarConfig: BottomActionBarConfig(
      backgroundColor: cs.surfaceContainerHighest,
      buttonColor: cs.surfaceContainerHighest,
      buttonIconColor: cs.onSurfaceVariant,
    ),
    searchViewConfig: SearchViewConfig(
      backgroundColor: cs.surfaceContainerHighest,
      buttonIconColor: cs.onSurfaceVariant,
      hintText: 'Cerca',
      inputTextStyle: TextStyle(color: cs.onSurface),
      hintTextStyle: TextStyle(color: cs.onSurfaceVariant),
    ),
  );
}
