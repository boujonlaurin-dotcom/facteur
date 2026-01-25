# User Stories - Facteur

## 📁 Structure des dossiers

```
docs/stories/
├── core/           # Stories de base (features initiales)
├── evolutions/     # Stories qui étendent/modifient une feature existante
└── README.md       # Ce fichier
```

## 🏷️ Conventions de nommage

### Stories Core
Format : `{epic}.{story}.{nom-court}.md`

Exemples :
- `1.1.setup-flutter.md`
- `4.1.feed-algorithme.md`

### Évolutions
Format : `{epic}.{story}{suffixe}.{nom-court}.md`

Suffixes : `b`, `c`, `d`, `e` (ordre chronologique d'évolution)

Exemples :
- `1.3b.auth-email-confirmation.story.md` (évolution de 1.3)
- `4.1c.taxonomie-50-topics.story.md` (évolution de 4.1)

## 🔗 Liaisons entre stories

Chaque évolution DOIT inclure un header de liaison :

```markdown
# Story X.Yb: Titre de l'évolution

> **Parent Story**: [[../core/X.Y.nom-parent.md]]  
> **Type**: Evolution
```

## 📋 Autres types de documentation

| Type | Dossier | Description |
|------|---------|-------------|
| **Bugfix** | `docs/bugs/` | Corrections de comportements cassés |
| **Maintenance** | `docs/maintenance/` | Nettoyage, optimisation technique, data cleaning |
| **Handoff** | `docs/handoffs/` | Documentation de passage de relais entre agents |

## ⚠️ Règle importante

**Ne jamais créer de User Story pour :**
- Des bugfixes → utiliser `docs/bugs/`
- Du nettoyage/maintenance → utiliser `docs/maintenance/`
- Du refactoring technique sans impact fonctionnel

Les User Stories sont réservées à la **valeur produit**.
