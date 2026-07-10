typedef SourceThemeFilter = ({String? key, String label});

const sourceThemeFilters = <SourceThemeFilter>[
  (key: null, label: 'Toutes'),
  (key: 'tech', label: 'Tech'),
  (key: 'society', label: 'Société'),
  (key: 'environment', label: 'Environnement'),
  (key: 'economy', label: 'Économie'),
  (key: 'politics', label: 'Politique'),
  (key: 'culture', label: 'Culture'),
  (key: 'science', label: 'Sciences'),
  (key: 'international', label: 'International'),
];

/// `true` si [slug] correspond à un macro-thème connu du catalogue de sources
/// (clé de [sourceThemeFilters]) → on peut pré-filtrer le catalogue. Un slug
/// custom (sujet hors macro-thème) ouvrira le catalogue non filtré.
bool isCatalogTheme(String? slug) =>
    slug != null && sourceThemeFilters.any((f) => f.key == slug);
