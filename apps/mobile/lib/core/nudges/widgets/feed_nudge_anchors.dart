import 'package:flutter/widgets.dart';

/// GlobalKeys partagées entre `FeedCard` (attache au 1er article) et
/// `NudgeHost` (cible le spotlight). Déclarées au niveau module pour que les
/// deux widgets utilisent la MÊME instance (sinon le coachmark ne trouve pas).
///
/// - `feedFirstBadgeKey` : 1ʳᵉ balise long-pressable du 1er article (topic chip
///   si dispo, sinon source badge). Cible de `feed_badge_longpress`.
/// - `feedFirstCardKey` : conteneur du 1er article entier. Cible de
///   `feed_preview_longpress`.
final GlobalKey feedFirstBadgeKey =
    GlobalKey(debugLabel: 'feedFirstBadgeKey');
final GlobalKey feedFirstCardKey =
    GlobalKey(debugLabel: 'feedFirstCardKey');
