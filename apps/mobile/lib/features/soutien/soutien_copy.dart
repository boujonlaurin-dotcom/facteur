/// Copy de la feature Soutien / paywalls « Fact·eur·isse ».
///
/// Verbatim de la maquette « Paywalls Premium », avec les em-dashes « — »
/// remplacés par `,` / `·` / `:` conformément à la règle projet (pas d'em-dash
/// dans la copy user-facing).
class SoutienCopy {
  SoutienCopy._();

  // ─── Réglages ───
  static const premiumStamp = 'FACT·EUR·ISSE';
  static const premiumSincePrefix = 'depuis'; // « depuis juillet 2026 »
  static const soutienTileFreeTitle = 'Nous soutenir';
  static const soutienTileFreeSubtitle = 'Deviens Fact·eur·isse · 3 €/mois';
  static const soutienTilePremiumTitle = 'Ton soutien';
  static const soutienTilePremiumSubtitle = '3 €/mois · gérer mon abonnement';
  static const sereinCustomizeLabel = 'Personnaliser mes bonnes nouvelles';
  static const sereinCustomizeComingSoon = 'Bientôt disponible';
  static const veillePremiumStamp = 'PREMIUM';

  // ─── Écran Soutien (porte 1) ───
  static const soutienEyebrow = 'UNE LETTRE DE DJANGO & LAURIN';
  static const soutienHeadline =
      'Une info qui ne te manipule pas, ça se finance autrement.';
  static const soutienLetterP1 =
      "On a construit Facteur parce qu'on en avait marre d'une info qui "
      'déforme, qui angoisse, qui te vole ton attention. On voulait un média '
      "qui filtre l'essentiel, honnêtement, sans te manipuler.";
  static const soutienLetterP2 =
      'Ça ne peut pas exister avec de la pub, ni avec un actionnaire qui '
      'décide à ta place. Ça ne tient que si celles et ceux qui y croient '
      'le financent.';
  static const soutienSignature = 'Django & Laurin, tes facteurs';
  static const soutienBonusIntro =
      'Si tu nous rejoins, tu deviens Fact·eur·isse. Et en bonus, tu '
      'débloques :';
  static const bonusVeilleTitle =
      'Ne rate plus rien sur les sujets qui comptent pour toi';
  static const bonusVeilleBody = 'crée autant de veilles que tu veux.';
  static const bonusAnalysesTitle =
      'Comprends comment chaque sujet est vraiment couvert';
  static const bonusAnalysesBody = 'analyses de couverture sans compter.';
  static const bonusSereinTitle = 'Un mode serein à ton image';
  static const bonusSereinBody =
      'choisis ce qui reste dans tes bonnes nouvelles.';
  static const bientotStamp = 'BIENTÔT';
  static const bonusSoonAlertes = 'Alertes intelligentes personnalisables';
  static const bonusSoonResumes = 'Résumés sur tes thématiques préférées';
  static const reassurance1 = 'Résiliable en un geste, sans engagement.';
  static const reassurance2 =
      "Pas de pub, pas d'actionnaire : tes 3 € financent le média, rien "
      "d'autre.";
  static const reassurance3 =
      "On publie où va l'argent, chaque année, en clair.";
  static const priceAmount = '3 €';
  static const priceSuffix = '/mois';
  static const soutienPriceNote = 'moins qu\'un café. Le même prix pour '
      'tou·te·s.';
  static const soutienCta = 'Reçois ton lien pour nous rejoindre';
  static const soutienDisclaimer =
      "Le Facteur t'envoie une enveloppe par email, règles des stores "
      "obligent : rien ne se paie dans l'app.";

  // ─── Murs de feature (porte 2) ───
  static const wallCta = 'Reçois ton lien pour débloquer';
  static const wallDisclaimer =
      "On t'envoie le lien par email : rien ne se paie dans l'app.";
  static const wallPriceNote = 'sans engagement, résiliable en un geste';
  static const missionLinkLabel = 'Notre histoire →';

  // Mur veille (écran dédié)
  static const veilleWallEyebrow = 'Veille thématique';
  static const veilleWallHeadline =
      'Ne rate plus rien sur les sujets qui comptent pour toi';
  static const veilleWallBenefit1 =
      'Un condensé régulier des meilleurs articles, sur des sujets aussi '
      'précis que tu veux';
  static const veilleWallBenefit2 =
      "Tes angles, tes mots-clés : pas ceux d'un algorithme";
  static const veilleWallBenefit3 =
      'Livré dans ton flux, au rythme que tu choisis';
  static const veilleWallMission =
      "Facteur n'a ni pub ni actionnaire. En débloquant la veille, tu fais "
      'aussi vivre une info indépendante.';
  static const veilleWallPriceNote = 'résiliable en un geste';

  // Murs en sheet
  static const analysesWallEyebrow = 'Analyse Facteur · 1/1 aujourd\'hui';
  static const analysesWallHeadline =
      'Comprends comment chaque sujet est vraiment couvert';
  static const analysesWallBody =
      'Tu as utilisé ton analyse offerte du jour. En passant Fact·eur·isse, '
      "lance autant d'analyses que tu veux, quand tu veux, sur chaque sujet "
      "qui t'intrigue.";
  static const sereinWallEyebrow = 'Mode serein';
  static const sereinWallHeadline = 'Un mode serein à ton image';
  static const sereinWallBody =
      'Choisis précisément ce qui reste dans tes bonnes nouvelles, sujet par '
      'sujet. En passant Fact·eur·isse, le calme se règle à ta main.';
  static const wallMissionLine =
      "Débloquer, c'est aussi financer une info sans pub ni actionnaire.";

  // ─── Gates aux touchpoints ───
  static const veilleGateStamp = 'RÉSERVÉ AUX FACT·EUR·ISSES';
  static const veilleGateCta = 'Créer ma première veille';
  static const analysesQuotaBanner =
      'Chaque analyse Facteur a un coût réel de génération. On te la laisse '
      'quand tu en as besoin. Si tu veux nous aider à financer une info sans '
      'pub ni actionnaire, on te raconte tout.';
  static const analysesPillPremium = 'Analyses illimitées · Fact·eur·isse';

  // ─── Confirmation « lien envoyé » ───
  static const linkSentStamp = 'ENVOYÉ';
  static const linkSentHeadline = 'Ton lien est en route.';
  static const linkSentBody =
      'Le Facteur vient de déposer une enveloppe dans ta boîte mail. '
      'Ouvre-la pour finaliser : ça prend une minute.';
  static const linkSentSpamHint = 'Rien reçu ? Jette un œil à tes indésirables.';
  static const linkSentBack = 'Retour à ma lecture';
  static const linkSentResend = 'Renvoyer le lien';
  static const linkSentResendSuccess = 'Lien renvoyé !';
  static const linkSentRateLimited =
      'Patiente une minute avant de renvoyer.';
  static const sendLinkError =
      "Impossible d'envoyer le lien. Réessaie dans un instant.";
}
