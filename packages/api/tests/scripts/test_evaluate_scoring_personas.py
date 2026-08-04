"""Tests hermétiques pour `scripts/evaluate_scoring_personas.py`.

Ni DB ni réseau : deux fixtures jouets (`toy_scoring_personas.json`,
`toy_scoring_corpus.json`) suffisent, puisque le harnais réhydrate des objets
ORM transitoires et n'ouvre jamais de session.

Couvre :
- **l'anti-drift d'identité** : le harnais appelle le moteur de prod, pas une
  copie (l'équivalent de `assert ev._score_block is feed_filter._score_block`
  côté veille) ;
- les deux métriques publiées côte à côte (τ-b sur ensemble fixe, churn top-5),
  y compris leurs cas dégénérés ;
- le détecteur de forme de courbe, qui est le garde-fou anti-calibration sur du
  bruit ;
- le refus de `--compare` sur deux corpus différents ;
- le **piège `PILLAR_WEIGHTS`** : un moteur construit hors du `with` ne verrait
  pas l'override (`scoring_engine.py:207`) ;
- la garde de périmètre : `recency_base` est en minuscules et pilote tout le
  pilier Fraîcheur — un scan qui la raterait la déclarerait « hors-périmètre ».

Limite assumée : la validation « le sweep reproduit l'inertie déjà établie »
tourne sur le **vrai** corpus et vit dans le runbook, pas ici — elle prend
plusieurs minutes.
"""

import datetime as dt
import json
from pathlib import Path

import pytest

from app.services.recommendation import scoring_engine
from app.services.recommendation.scoring_config import ScoringWeights
from scripts import evaluate_scoring_personas as ev
from scripts._scoring_overrides import weights_override

FIXTURES = Path(__file__).parent / "fixtures"
TOY_PERSONAS = FIXTURES / "toy_scoring_personas.json"
TOY_CORPUS = FIXTURES / "toy_scoring_corpus.json"
TOY_GOLD = FIXTURES / "toy_scoring_gold.json"

MUTED_SOURCE_ID = "22222222-2222-4222-8222-00000000000c"


@pytest.fixture
def corpus() -> ev.Corpus:
    return ev.load_corpus(TOY_CORPUS)


@pytest.fixture
def personas() -> list[ev.Persona]:
    return ev.load_personas(TOY_PERSONAS)


def _persona(personas: list[ev.Persona], persona_id: str) -> ev.Persona:
    return next(p for p in personas if p.persona_id == persona_id)


# ---------------------------------------------------------------------------
# Anti-drift : le harnais rejoue la porte de prod
# ---------------------------------------------------------------------------


def test_harness_uses_the_production_engine():
    """Si le harnais forke le moteur, il cesse de mesurer la prod — et rien ne
    le dirait. C'est le seul test qui garde cette propriété."""
    assert ev.PillarScoringEngine is scoring_engine.PillarScoringEngine
    assert ev.ScoringContext is scoring_engine.ScoringContext


def test_sport_penalty_is_replayed_from_the_production_constant():
    """`DIGEST_SPORT_PENALTY` vit **hors** du moteur de piliers (appliqué par
    `digest_selector` après combinaison). Le harnais la rejoue, mais depuis la
    constante de prod — pas une copie locale."""
    source = Path(ev.__file__).read_text(encoding="utf-8")
    assert "ScoringWeights.DIGEST_SPORT_PENALTY" in source
    assert "is_sport_content" in source


# ---------------------------------------------------------------------------
# Réhydratation
# ---------------------------------------------------------------------------


def test_now_is_frozen_to_the_corpus_generated_at(corpus):
    """Sans NOW figé, le pilier Fraîcheur dérive et deux runs sur le même corpus
    ne sont plus comparables."""
    assert corpus.now == dt.datetime(2026, 8, 1, 12, 0, tzinfo=dt.UTC)


def test_corpus_rehydrates_sources_shared_by_identity(corpus):
    """Deux articles d'une même source partagent l'instance `Source` : le
    pilier lit `content.source` sans jamais déclencher de lazy-load."""
    by_source: dict[str, set[int]] = {}
    for content in corpus.contents:
        by_source.setdefault(str(content.source_id), set()).add(id(content.source))
    assert all(len(instances) == 1 for instances in by_source.values())
    assert len(by_source) == 3


def test_cluster_source_counts_are_recomputed_from_the_corpus(corpus):
    """Le cluster partagé A2+A9 réunit 2 sources distinctes ; les articles sans
    cluster n'entrent pas dans la table."""
    assert list(corpus.cluster_source_counts.values()) == [2]


def test_load_corpus_rejects_a_foreign_dataset(tmp_path):
    path = tmp_path / "wrong.json"
    path.write_text(json.dumps({"dataset_kind": "veille_curation"}), encoding="utf-8")
    with pytest.raises(ValueError, match="scoring_corpus"):
        ev.load_corpus(path)


def test_load_personas_rejects_a_foreign_dataset(tmp_path):
    path = tmp_path / "wrong.json"
    path.write_text(json.dumps({"dataset_kind": "scoring_corpus"}), encoding="utf-8")
    with pytest.raises(ValueError, match="scoring_personas"):
        ev.load_personas(path)


def test_persona_mutes_are_parsed_as_uuids(personas):
    muted = _persona(personas, "toy_persona_02").muted_sources
    assert {str(sid) for sid in muted} == {MUTED_SOURCE_ID}


# ---------------------------------------------------------------------------
# Métriques — τ-b sur ensemble fixe
# ---------------------------------------------------------------------------


def test_tau_is_one_when_nothing_moved():
    assert ev.kendall_tau_b([3.0, 2.0, 1.0], [3.0, 2.0, 1.0]) == 1.0
    # Une transformation affine croissante ne change aucun ordre.
    assert ev.kendall_tau_b([3.0, 2.0, 1.0], [30.0, 20.0, 10.0]) == 1.0


def test_tau_is_minus_one_when_the_order_is_reversed():
    assert ev.kendall_tau_b([3.0, 2.0, 1.0], [1.0, 2.0, 3.0]) == -1.0


def test_tau_handles_ties_without_dividing_by_zero():
    """Cas qu'un τ « sur le top-5 » ne saurait pas traiter : des ex æquo des
    deux côtés. La variante -b corrige le dénominateur, elle ne plante pas."""
    assert ev.kendall_tau_b([1.0, 1.0, 2.0], [1.0, 1.0, 2.0]) == 1.0
    # Tout ex æquo d'un côté : plus aucune paire départageable → « rien n'a
    # bougé d'observable », donc 1.0 et surtout pas une division par zéro.
    assert ev.kendall_tau_b([1.0, 1.0, 1.0], [3.0, 2.0, 1.0]) == 1.0


def test_tau_on_a_degenerate_set_is_one():
    assert ev.kendall_tau_b([], []) == 1.0
    assert ev.kendall_tau_b([1.0], [9.0]) == 1.0


def test_tau_rejects_mismatched_vectors():
    with pytest.raises(ValueError):
        ev.kendall_tau_b([1.0, 2.0], [1.0])


# ---------------------------------------------------------------------------
# Métriques — churn du top-5
# ---------------------------------------------------------------------------


def test_churn_is_zero_when_the_top5_is_untouched():
    order = ["a", "b", "c", "d", "e", "f"]
    assert ev.top_k_churn(order, order) == 0.0
    # Permuter à l'intérieur du top-5 ne change pas *l'ensemble* vu.
    assert ev.top_k_churn(order, ["e", "d", "c", "b", "a", "f"]) == 0.0


def test_churn_counts_the_replaced_share():
    before = ["a", "b", "c", "d", "e"]
    assert ev.top_k_churn(before, ["a", "b", "c", "d", "z"]) == pytest.approx(0.2)
    assert ev.top_k_churn(before, ["v", "w", "x", "y", "z"]) == 1.0


def test_precision_at_k_counts_only_the_top():
    order = ["a", "b", "c", "d", "e", "f"]
    assert ev.precision_at_k(order, {"a", "b"}) == pytest.approx(0.4)
    # Un pertinent hors du top-5 ne compte pas.
    assert ev.precision_at_k(order, {"f"}) == 0.0


# ---------------------------------------------------------------------------
# Classement déterministe
# ---------------------------------------------------------------------------


def test_ranking_breaks_ties_by_id():
    """Sans tie-break, deux runs identiques permuteraient des ex æquo et le
    churn mesurerait l'ordre d'itération d'un dict, pas un effet de scoring."""
    scores = {"b": 10.0, "a": 10.0, "c": 20.0}
    assert ev.ranking(scores) == ["c", "a", "b"]


def test_scoring_the_same_corpus_twice_is_stable(corpus, personas):
    persona = _persona(personas, "toy_persona_01")
    first = ev.ranking(ev.score_corpus(corpus, persona))
    second = ev.ranking(ev.score_corpus(corpus, persona))
    assert first == second


# ---------------------------------------------------------------------------
# Piège PILLAR_WEIGHTS
# ---------------------------------------------------------------------------


def test_engine_built_inside_the_override_sees_the_new_pillar_weights(corpus, personas):
    """`PillarScoringEngine.__init__` copie `ScoringWeights.PILLAR_WEIGHTS`
    (`scoring_engine.py:207`). Le harnais construit donc un moteur **par
    configuration**, dans le `with` — sinon le sweep serait un no-op silencieux.
    """
    persona = _persona(personas, "toy_persona_01")
    baseline = ev.score_corpus(corpus, persona)

    all_on_pertinence = dict.fromkeys(ScoringWeights.PILLAR_WEIGHTS, 0.0)
    all_on_pertinence["pertinence"] = 1.0

    with weights_override(PILLAR_WEIGHTS=all_on_pertinence):
        shifted = ev.score_corpus(corpus, persona)

    assert shifted != baseline, (
        "un moteur construit hors du `with` aurait garde l'ancien dict de poids"
    )
    # Et la restauration a bien eu lieu.
    assert ev.score_corpus(corpus, persona) == baseline


def test_a_stale_engine_would_miss_the_override(corpus, personas):
    """Contre-épreuve du piège : le moteur instancié **avant** le `with` garde
    l'ancien dict. C'est la raison d'être de la règle « un moteur neuf par
    configuration » — ce test la rend visible plutôt que folklorique."""
    persona = _persona(personas, "toy_persona_01")
    stale = ev.PillarScoringEngine()
    context = ev.build_context(persona, corpus, personalized_theme_mode=False)
    content = corpus.contents[0]

    before = stale.compute_score(content, context).final_score
    all_on_pertinence = dict.fromkeys(ScoringWeights.PILLAR_WEIGHTS, 0.0)
    all_on_pertinence["pertinence"] = 1.0
    with weights_override(PILLAR_WEIGHTS=all_on_pertinence):
        during = stale.compute_score(content, context).final_score
        fresh = ev.PillarScoringEngine().compute_score(content, context).final_score

    assert during == before  # le moteur périmé n'a rien vu
    assert fresh != before  # le moteur neuf, si


# ---------------------------------------------------------------------------
# Périmètre des constantes
# ---------------------------------------------------------------------------


def test_non_patchable_constants_are_excluded_from_the_grid():
    """`weights_override` lève sur `SUBTOPIC_DECAY` (patch inerte). Les balayer
    ferait planter le run au lieu de produire un rapport."""
    assert "SUBTOPIC_DECAY" not in ev.numeric_constants()


def test_engine_scope_includes_the_lowercase_recency_base():
    """Garde de régression : `recency_base` est la seule constante en minuscules
    et elle pilote tout le pilier Fraîcheur. Un scan `[A-Z]` la raterait et la
    classerait « hors-périmètre » — l'inverse de la vérité."""
    scope = ev.constants_in_engine_scope()
    assert "recency_base" in scope
    for name in ("THEME_MATCH", "TRUSTED_SOURCE", "CURATED_SOURCE"):
        assert name in scope, f"{name} devrait être dans le périmètre du moteur"


def test_out_of_scope_constants_are_not_labelled_inert():
    """« hors-périmètre » et « inerte » sont deux verdicts opposés : le premier
    dit que ce harnais ne mesure rien, le second qu'il a mesuré zéro effet."""
    scope = ev.constants_in_engine_scope()
    assert "TOURNEE_SUGGEST_SUBCAP" not in scope
    assert ev._sensitivity_verdict(0.0, 1.0, False) == "hors-périmètre"
    assert ev._sensitivity_verdict(0.4, 0.9, True) == "actif"
    assert ev._sensitivity_verdict(0.0, 1.0, True) == "inerte"


def test_a_constant_that_reorders_without_moving_the_top5_is_weak_not_inert():
    """Le churn seul déclarerait « inerte » une constante qui réordonne tout le
    top-20 sans changer l'ensemble des 5 premiers — et on la retirerait à tort
    du champ du tuning."""
    assert ev._sensitivity_verdict(0.0, 0.93, True) == "faible"


def test_the_scope_excludes_modules_the_engine_never_runs():
    """`tournee_suggester`, `carousel_*` et les `layers/` legacy vivent dans le
    même paquet mais ne passent jamais par `compute_score`. Les inclure ferait
    passer un cap d'arrangement de la Tournée pour une constante de scoring."""
    scope = ev.constants_in_engine_scope()
    for name in ("TOURNEE_TARGET_SECTIONS", "VEILLE_RELEVANCE_THRESHOLD"):
        assert name not in scope


def test_no_perturbation_makes_a_pillar_collapse(corpus, personas):
    """Garde contre un **faux « actif »**.

    `PillarScoringEngine.compute_score` avale les exceptions de pilier
    (`except Exception → pillar_scores[name] = 0.0`) et structlog écrit sur
    stderr, hors du `logging` stdlib : une constante entière perturbée en float
    qui casserait un `range()` ou une tranche produirait un pilier à 0, donc un
    churn maximal, donc un verdict « actif » entièrement faux — et rien ne le
    signalerait.

    On balaie toute la grille sur le corpus jouet et on vérifie qu'aucun pilier
    ne s'effondre à 0 alors qu'il ne l'est pas en baseline.
    """
    persona = _persona(personas, "toy_persona_01")
    context = ev.build_context(persona, corpus, personalized_theme_mode=True)
    content = corpus.contents[0]

    baseline = ev.PillarScoringEngine().compute_score(content, context).pillar_scores
    alive = {name for name, score in baseline.items() if score != 0.0}
    assert alive, "le corpus jouet doit activer au moins un pilier en baseline"

    for name in sorted(ev.constants_in_engine_scope()):
        for label, value in ev.perturbations(name):
            with weights_override(**{name: value}):
                scores = (
                    ev.PillarScoringEngine().compute_score(content, context)
                ).pillar_scores
            collapsed = [p for p in alive if scores.get(p, 0.0) == 0.0]
            assert not collapsed, (
                f"{name}={value} ({label}) fait tomber {collapsed} à 0 — "
                "probable exception avalée par le moteur, pas un vrai effet"
            )


def test_perturbations_are_multiplicative_and_fall_back_to_additive():
    values = [value for _, value in ev.perturbations("THEME_MATCH")]
    base = float(ScoringWeights.THEME_MATCH)
    assert values == [base * f for f in ev.SENSITIVITY_FACTORS]

    # Une constante nulle : la multiplier serait un no-op déguisé en mesure.
    with weights_override(THEME_MATCH=0.0):
        labels = [label for label, _ in ev.perturbations("THEME_MATCH")]
        assert labels == ["-1", "+1"]


# ---------------------------------------------------------------------------
# Sensibilité
# ---------------------------------------------------------------------------


def test_sensitivity_ranks_active_constants_first(corpus, personas):
    metrics = ev.run_sensitivity(corpus, personas, only_prefix="THEME_")
    churns = [row["max_churn"] for row in metrics["rows"]]
    assert churns == sorted(churns, reverse=True)
    assert metrics["rows"], "le préfixe THEME_ doit matcher au moins une constante"


def test_sensitivity_does_not_measure_out_of_scope_constants(corpus, personas):
    metrics = ev.run_sensitivity(corpus, personas, only_prefix="TOURNEE_")
    assert metrics["rows"]
    for row in metrics["rows"]:
        assert row["measured"] is False
        assert row["verdict"] == "hors-périmètre"


def test_theme_match_has_a_measurable_effect(corpus, personas):
    """Contrôle de vraisemblance : si le levier thématique principal ressortait
    sans **aucun** effet, c'est le harnais qui serait faux, pas le scoring.

    Sur 12 articles jouets il ne déplace pas l'*ensemble* du top-5 (le corpus
    est trop petit pour ça) mais il réordonne — d'où « faible » ici et non
    « actif ». Le verdict sur données réelles vit dans le runbook.
    """
    metrics = ev.run_sensitivity(corpus, personas, only_prefix="THEME_MATCH")
    row = next(r for r in metrics["rows"] if r["constant"] == "THEME_MATCH")
    assert row["measured"] is True
    assert row["verdict"] in {"actif", "faible"}
    assert row["min_tau"] < 1.0


def test_the_grid_reaches_every_pillar(corpus, personas):
    """Au moins une constante de chaque pilier doit bouger quelque chose : un
    pilier entièrement muet signalerait une réhydratation incomplète (un champ
    du corpus jamais peuplé, par exemple)."""
    metrics = ev.run_sensitivity(corpus, personas)
    moved = {
        row["constant"]
        for row in metrics["rows"]
        if row["measured"] and row["verdict"] in {"actif", "faible"}
    }
    for pillar_constant in (
        "THEME_MATCH",  # Pertinence
        "TRUSTED_SOURCE",  # Source
        "recency_base",  # Fraîcheur
        "CONTENT_QUALITY_FULL_BOOST",  # Qualité
    ):
        assert pillar_constant in moved, f"{pillar_constant} n'a aucun effet"


# ---------------------------------------------------------------------------
# Invariants
# ---------------------------------------------------------------------------


def test_muted_source_invariant_fails_when_the_article_gets_through(corpus, personas):
    """`toy_persona_02` mute la source qui publie sa thématique suivie : sur ce
    corpus de 12 articles, la fenêtre de contrôle couvre tout, donc l'invariant
    doit **échouer**. Un invariant qui ne peut pas échouer ne teste rien."""
    persona = _persona(personas, "toy_persona_02")
    order = ev.ranking(ev.score_corpus(corpus, persona))
    checks = {c["name"]: c for c in ev.check_invariants(corpus, persona, order)}
    assert checks["muted_source_never_surfaces"]["status"] == "fail"


def test_invariants_report_na_rather_than_a_vacuous_pass(corpus, personas):
    """`toy_persona_01` n'a aucune source mutée : le verdict doit être `n/a`,
    pas un `pass` qui gonflerait le compteur sans rien avoir vérifié."""
    persona = _persona(personas, "toy_persona_01")
    order = ev.ranking(ev.score_corpus(corpus, persona))
    checks = {c["name"]: c for c in ev.check_invariants(corpus, persona, order)}
    assert checks["muted_source_never_surfaces"]["status"] == "n/a"


def test_invariant_totals_split_pass_fail_and_na(corpus, personas):
    metrics = ev.run_invariants(corpus, personas)
    totals = metrics["totals"]
    assert totals["pass"] + totals["fail"] + totals["n/a"] == 2 * 4
    assert totals["fail"] >= 1  # toy_persona_02 doit tomber


# ---------------------------------------------------------------------------
# Gold
# ---------------------------------------------------------------------------


def test_gold_excludes_heldout_personas_by_default(corpus, personas):
    gold = ev.load_gold(TOY_GOLD)
    metrics = ev.run_gold(corpus, personas, gold)
    assert [row["persona_id"] for row in metrics["rows"]] == ["toy_persona_01"]

    opened = ev.run_gold(corpus, personas, gold, include_heldout=True)
    assert {row["persona_id"] for row in opened["rows"]} == {
        "toy_persona_01",
        "toy_persona_02",
    }


def test_gold_loader_keeps_only_relevant_labels():
    gold = ev.load_gold(TOY_GOLD)
    assert gold["toy_persona_01"] == {
        "11111111-1111-4111-8111-000000000001",
        "11111111-1111-4111-8111-000000000011",
        "11111111-1111-4111-8111-000000000002",
    }


def test_an_empty_gold_reports_no_measure_not_a_score_of_zero(corpus, personas):
    """Un « macro precision@5 : 0.000 » sur un gold vide se lirait comme une
    catastrophe alors qu'il ne s'est rien passé — c'est le faux négatif
    silencieux que la jauge sœur a déjà payé une fois."""
    metrics = ev.run_gold(corpus, personas, {})
    assert metrics["rows"] == []
    assert metrics["macro_precision_at_5"] is None

    report = ev.render_gold(metrics)
    assert "squelette vide" in report
    assert "0.000" not in report


def test_the_shipped_gold_is_an_empty_skeleton():
    """PR-3 livre le chargeur et le schéma, **pas** des labels : 240 labels
    fabriqués pour 113 constantes seraient de l'overfit déguisé en gold."""
    payload = json.loads(ev.DEFAULT_GOLD.read_text(encoding="utf-8"))
    assert payload["dataset_kind"] == "scoring_gold_labels"
    assert payload["personas"] == []


# ---------------------------------------------------------------------------
# Forme de courbe
# ---------------------------------------------------------------------------


def test_curve_shapes():
    assert ev.classify_curve([0.0, 0.1, 0.2, 0.3]) == "MONOTONE"
    assert ev.classify_curve([0.3, 0.2, 0.1, 0.0]) == "MONOTONE"
    assert ev.classify_curve([0.0, 0.4, 0.2, 0.1]) == "UNIMODALE"
    assert ev.classify_curve([0.5, 0.5, 0.5]).startswith("PLATE")
    assert ev.classify_curve([0.1, 0.4, 0.1, 0.4, 0.1]).startswith("NON MONOTONE")
    assert ev.classify_curve([0.2]) == "TROP COURTE"


def test_sweep_publishes_the_whole_curve_never_the_argmax(corpus, personas):
    metrics = ev.run_sweep(
        corpus, personas, "ENTITY_AFFINITY_BASE", [8.0, 16.0, 32.0, 64.0]
    )
    assert [row["value"] for row in metrics["rows"]] == [8.0, 16.0, 32.0, 64.0]
    assert "argmax" not in json.dumps(metrics)
    # Sur le corpus jouet, ce levier ne doit pas produire de dents de scie :
    # une courbe bruitée ici signalerait un harnais non déterministe.
    assert not metrics["shape_churn"].startswith("NON MONOTONE")


def test_sweep_restores_the_constant_afterwards(corpus, personas):
    before = ScoringWeights.ENTITY_AFFINITY_BASE
    ev.run_sweep(corpus, personas, "ENTITY_AFFINITY_BASE", [8.0, 64.0])
    assert before == ScoringWeights.ENTITY_AFFINITY_BASE


def test_sweep_rejects_a_malformed_spec():
    with pytest.raises(SystemExit):
        ev._parse_sweep("ENTITY_AFFINITY_BASE")
    with pytest.raises(SystemExit):
        ev._parse_sweep("ENTITY_AFFINITY_BASE=8")  # une seule valeur = pas de courbe
    assert ev._parse_sweep("X=1,2,3") == ("X", [1.0, 2.0, 3.0])


# ---------------------------------------------------------------------------
# --compare
# ---------------------------------------------------------------------------


def test_compare_refuses_two_different_corpora():
    """La règle qui rend la campagne falsifiable : deux mesures prises sur deux
    jeux de candidats ne se comparent pas, et rien dans les chiffres ne le
    dirait."""
    baseline = {"tag": "a", "corpus_file": "scoring_corpus_2026-08-03.json"}
    after = {"tag": "b", "corpus_file": "scoring_corpus_2026-08-10.json"}
    with pytest.raises(ValueError, match="pas comparables"):
        ev.render_compare(baseline, after)


def test_compare_refuses_two_different_samples_of_the_same_corpus():
    """Même fichier ne suffit pas : `--corpus-sample` change le jeu de candidats
    sans changer le nom du corpus. Deux top-5 tirés d'univers différents ne se
    comparent pas, et aucun chiffre du rapport ne le dirait."""
    common = "scoring_corpus_2026-08-03.json"
    baseline = {"tag": "a", "corpus_file": common, "corpus_articles": 200}
    after = {"tag": "b", "corpus_file": common, "corpus_articles": 30}
    with pytest.raises(ValueError, match="articles retenus"):
        ev.render_compare(baseline, after)


def test_compare_reports_the_gold_delta_on_a_common_corpus():
    common = "scoring_corpus_2026-08-03.json"
    baseline = {
        "tag": "before",
        "corpus_file": common,
        "gold": {"macro_precision_at_5": 0.40},
        "invariants": {"totals": {"pass": 5, "fail": 2, "n/a": 1}},
    }
    after = {
        "tag": "after",
        "corpus_file": common,
        "gold": {"macro_precision_at_5": 0.60},
        "invariants": {"totals": {"pass": 6, "fail": 1, "n/a": 1}},
    }
    report = ev.render_compare(baseline, after)
    assert "+20.0 pp" in report
    assert "invariants fail : 2 → 1" in report


# ---------------------------------------------------------------------------
# Rendu
# ---------------------------------------------------------------------------


def test_render_sensitivity_separates_inert_from_out_of_scope(corpus, personas):
    metrics = ev.run_sensitivity(corpus, personas, only_prefix="TOURNEE_")
    report = ev.render_sensitivity(metrics)
    assert "hors-périmètre" in report
    assert "ne dit **rien** de son effet en prod" in report


def test_render_invariants_and_gold_produce_markdown(corpus, personas):
    invariants = ev.render_invariants(ev.run_invariants(corpus, personas))
    assert "| persona | invariant | statut | détail |" in invariants

    gold = ev.load_gold(TOY_GOLD)
    report = ev.render_gold(ev.run_gold(corpus, personas, gold))
    assert "macro precision@5" in report
    assert "portail" in report


def test_render_sweep_states_the_shape(corpus, personas):
    metrics = ev.run_sweep(corpus, personas, "ENTITY_AFFINITY_BASE", [8.0, 64.0])
    report = ev.render_sweep(metrics)
    assert "jamais l'argmax" in report
    assert metrics["shape_churn"] in report
