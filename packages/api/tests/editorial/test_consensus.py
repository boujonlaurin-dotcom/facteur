"""Post-traitement déterministe de l'analyse des angles 6C (Story 35.1).

Ce qui est testé ici est exactement ce que le LLM n'a **pas** le droit de
décider : le compteur d'appui, la longueur des constats, l'appartenance des
domaines au corpus et le qualificatif.
"""

from types import SimpleNamespace

from app.services.editorial.consensus import (
    CONSENSUS_CTA_MAX_CHARS,
    CONSENSUS_STATEMENT_MAX_CHARS,
    ConsensusStatement,
    build_corpus_index,
    compute_angle_qualifier,
    compute_display_gates,
    empty_consensus_block,
    normalize_consensus,
    pick_display_domains,
    serve_consensus_block,
    truncate_to_sentence,
)

CORPUS = ["lemonde.fr", "lefigaro.fr", "mediapart.fr", "lesechos.fr", "liberation.fr"]

BIAS = {
    "lemonde.fr": "center-left",
    "liberation.fr": "left",
    "mediapart.fr": "left",
    "lefigaro.fr": "right",
    "lesechos.fr": "center-right",
}


def _statement(text: str, domains: list[str]) -> dict:
    return {"text": text, "source_domains": domains}


class TestSupportCount:
    def test_support_count_is_recomputed_from_the_corpus(self):
        """Le « +N » compte les domaines réellement présents, pas ce que dit le LLM."""
        raw = {
            "agreements": [
                {
                    "text": "Le budget prévoit 12 milliards d'économies.",
                    "source_domains": ["lemonde.fr", "lefigaro.fr"],
                    "support_count": 10,  # le modèle gonfle : ignoré
                }
            ]
        }

        payload = normalize_consensus(raw, CORPUS)

        assert payload.agreements[0].support_count == 2

    def test_hallucinated_domains_are_dropped(self):
        raw = {
            "agreements": [
                _statement(
                    "Le texte arrive à l'Assemblée en novembre.",
                    ["lemonde.fr", "journal-invente.fr"],
                )
            ]
        }

        payload = normalize_consensus(raw, CORPUS)

        assert payload.agreements[0].source_domains == ["lemonde.fr"]
        assert payload.agreements[0].support_count == 1

    def test_statement_with_no_corpus_domain_is_rejected(self):
        """Un constat que personne du corpus ne porte n'est pas attribuable."""
        raw = {
            "agreements": [
                _statement("Un constat sans appui.", ["inconnu.fr", "autre.fr"])
            ]
        }

        payload = normalize_consensus(raw, CORPUS)

        assert payload.agreements == []
        assert payload.state == "unavailable"

    def test_domains_are_canonicalized_before_matching(self):
        """URL complète, majuscules, `www.` : même clé que le corpus."""
        raw = {
            "agreements": [
                _statement(
                    "Les rédactions donnent les mêmes montants.",
                    ["https://www.LeMonde.fr/politique", "WWW.LEFIGARO.FR"],
                )
            ]
        }

        payload = normalize_consensus(raw, CORPUS)

        assert payload.agreements[0].source_domains == ["lemonde.fr", "lefigaro.fr"]

    def test_duplicate_domains_count_once(self):
        raw = {
            "agreements": [
                _statement(
                    "Les rédactions donnent les mêmes montants.",
                    ["lemonde.fr", "www.lemonde.fr", "lefigaro.fr"],
                )
            ]
        }

        assert normalize_consensus(raw, CORPUS).agreements[0].support_count == 2


class TestTruncation:
    def test_short_text_is_untouched(self):
        text = "Le budget prévoit 12 milliards d'économies."
        assert truncate_to_sentence(text, 130) == text

    def test_truncation_keeps_whole_sentences(self):
        text = (
            "Le budget prévoit 12 milliards d'économies. "
            "Le texte arrive à l'Assemblée en novembre, sans majorité acquise, "
            "après un passage en commission des finances."
        )

        result = truncate_to_sentence(text, 60)

        assert result == "Le budget prévoit 12 milliards d'économies."

    def test_first_sentence_too_long_falls_back_to_word_boundary(self):
        text = (
            "Le budget 2026 prévoit douze milliards d'euros d'économies "
            "réparties sur l'assurance maladie et les collectivités locales."
        )

        result = truncate_to_sentence(text, 40)

        assert len(result) <= 40
        assert result.endswith("…")
        assert not result.rstrip("…").endswith(" ")
        # Coupe au mot : aucun mot n'est amputé.
        assert text.startswith(result.rstrip("…"))

    def test_statements_are_truncated_at_the_section_budget(self):
        long_text = "Ce constat est écrit beaucoup trop long pour deux lignes. " * 4
        payload = normalize_consensus(
            {"agreements": [_statement(long_text, ["lemonde.fr"])]}, CORPUS
        )

        assert len(payload.agreements[0].text) <= CONSENSUS_STATEMENT_MAX_CHARS


class TestCaps:
    def test_agreements_capped_at_three_disagreements_at_two(self):
        raw = {
            "agreements": [
                _statement(f"Accord numéro {i} sur le budget.", ["lemonde.fr"])
                for i in range(6)
            ],
            "disagreements": [
                _statement(f"Désaccord numéro {i} : oui ou non.", ["lemonde.fr"])
                for i in range(5)
            ],
        }

        payload = normalize_consensus(raw, CORPUS)

        assert len(payload.agreements) == 3
        assert len(payload.disagreements) == 2

    def test_most_supported_statements_survive_the_cap(self):
        raw = {
            "agreements": [
                _statement("Accord faiblement porté.", ["lemonde.fr"]),
                _statement("Accord largement porté.", CORPUS),
                _statement("Accord moyennement porté.", ["lemonde.fr", "lefigaro.fr"]),
                _statement("Accord anecdotique.", ["mediapart.fr"]),
            ]
        }

        payload = normalize_consensus(raw, CORPUS)

        assert [s.support_count for s in payload.agreements] == [5, 2, 1]
        assert payload.agreements[0].text == "Accord largement porté."

    def test_duplicate_statements_are_deduplicated(self):
        raw = {
            "agreements": [
                _statement("Le budget prévoit 12 milliards.", ["lemonde.fr"]),
                _statement("Le budget prévoit 12 milliards", ["lefigaro.fr"]),
            ]
        }

        assert len(normalize_consensus(raw, CORPUS).agreements) == 1


class TestCta:
    def test_cta_uses_the_short_variant_and_the_full_attribution(self):
        """Le CTA dit le même constat en plus court : même « +N »."""
        raw = {
            "agreements": [
                _statement(
                    "Le budget 2026 prévoit 12 milliards d'économies, dont 4 sur "
                    "l'assurance maladie.",
                    ["lemonde.fr", "lefigaro.fr", "lesechos.fr"],
                )
            ],
            "cta_agreement": {"text": "12 milliards d'économies, dont 4 sur la santé."},
        }

        payload = normalize_consensus(raw, CORPUS)

        assert payload.cta.agreement.text.startswith("12 milliards")
        assert payload.cta.agreement.support_count == 3
        assert payload.cta.agreement.source_domains == [
            "lemonde.fr",
            "lefigaro.fr",
            "lesechos.fr",
        ]

    def test_cta_falls_back_to_the_first_statement(self):
        raw = {
            "agreements": [
                _statement(
                    "Le budget 2026 prévoit douze milliards d'euros d'économies "
                    "réparties sur plusieurs ministères.",
                    ["lemonde.fr", "lefigaro.fr"],
                )
            ]
        }

        payload = normalize_consensus(raw, CORPUS)

        assert payload.cta.agreement is not None
        assert len(payload.cta.agreement.text) <= CONSENSUS_CTA_MAX_CHARS

    def test_cta_is_none_without_statement(self):
        payload = normalize_consensus({"agreements": []}, CORPUS)

        assert payload.cta.agreement is None
        assert payload.cta.disagreement is None

    def test_cta_variant_is_truncated_to_the_cta_budget(self):
        raw = {
            "disagreements": [
                _statement(
                    "Sa portée : recomposition durable ou retour de l'UMP.",
                    ["lemonde.fr"],
                )
            ],
            "cta_disagreement": {
                "text": "Sa portée exacte pour les prochaines échéances "
                "électorales et pour la recomposition du paysage politique."
            },
        }

        payload = normalize_consensus(raw, CORPUS)

        assert len(payload.cta.disagreement.text) <= CONSENSUS_CTA_MAX_CHARS


class TestQualifier:
    def _disagreement(self, domains: list[str]) -> ConsensusStatement:
        return ConsensusStatement(
            text="Un axe de désaccord.",
            source_domains=domains,
            support_count=len(domains),
        )

    def test_no_disagreement_is_convergent(self):
        assert compute_angle_qualifier([], BIAS) == "convergent"

    def test_two_disagreements_across_the_spectrum_is_polarized(self):
        disagreements = [
            self._disagreement(["mediapart.fr", "lefigaro.fr"]),
            self._disagreement(["lemonde.fr"]),
        ]

        assert compute_angle_qualifier(disagreements, BIAS) == "polarized"

    def test_single_disagreement_is_varied_even_across_the_spectrum(self):
        disagreements = [self._disagreement(["mediapart.fr", "lefigaro.fr"])]

        assert compute_angle_qualifier(disagreements, BIAS) == "varied"

    def test_close_biases_are_varied_not_polarized(self):
        disagreements = [
            self._disagreement(["mediapart.fr", "liberation.fr"]),
            self._disagreement(["lemonde.fr", "liberation.fr"]),
        ]

        assert compute_angle_qualifier(disagreements, BIAS) == "varied"

    def test_no_qualifier_outside_available_state(self):
        """« On ne qualifie pas un débat qu'on n'a pas lu. »"""
        disagreements = [
            self._disagreement(["mediapart.fr", "lefigaro.fr"]),
            self._disagreement(["lemonde.fr"]),
        ]

        assert compute_angle_qualifier(disagreements, BIAS, state="pending") is None
        assert compute_angle_qualifier(disagreements, BIAS, state="unavailable") is None

    def test_unknown_bias_never_polarizes(self):
        disagreements = [
            self._disagreement(["lemonde.fr", "inconnu.fr"]),
            self._disagreement(["inconnu.fr"]),
        ]

        assert compute_angle_qualifier(disagreements, {}) == "varied"


class TestPayloadState:
    def test_state_available_when_something_survives(self):
        raw = {
            "agreements": [_statement("Le budget prévoit 12 milliards.", CORPUS)],
            "disagreements": [
                _statement(
                    "L'origine du déficit : dépenses ou recettes.",
                    ["mediapart.fr", "lefigaro.fr"],
                ),
                _statement("Son ampleur : coupe forte ou quasi-stabilité.", CORPUS),
            ],
        }

        payload = normalize_consensus(raw, CORPUS, BIAS)

        assert payload.state == "available"
        assert payload.qualifier == "polarized"

    def test_state_unavailable_when_nothing_survives(self):
        payload = normalize_consensus({"agreements": []}, CORPUS, BIAS)

        assert payload.state == "unavailable"
        assert payload.qualifier is None

    def test_garbage_llm_output_does_not_raise(self):
        for raw in (None, "not a dict", {"agreements": "nope"}, {"agreements": [None]}):
            payload = normalize_consensus(raw, CORPUS, BIAS)
            assert payload.state == "unavailable"

    def test_markdown_emphasis_is_stripped_from_statements(self):
        raw = {
            "agreements": [
                _statement("**Le budget** prévoit _12 milliards_.", ["lemonde.fr"])
            ]
        }

        assert (
            normalize_consensus(raw, CORPUS).agreements[0].text
            == "Le budget prévoit 12 milliards."
        )

    def test_empty_corpus_rejects_everything(self):
        raw = {"agreements": [_statement("Un constat.", ["lemonde.fr"])]}

        assert normalize_consensus(raw, []).state == "unavailable"


class TestBudgets:
    """Le plafond appliqué doit rester au-dessus du budget annoncé au modèle.

    Inversé, il tronquerait *tous* les constats avec une ellipse — une
    régression invisible aux tests de contrat, et visible seulement au dry-run.
    """

    def test_statement_cap_leaves_room_above_the_prompt_budget(self):
        from app.services.perspective_service import CONSENSUS_STATEMENT_PROMPT_CHARS

        assert CONSENSUS_STATEMENT_MAX_CHARS > CONSENSUS_STATEMENT_PROMPT_CHARS

    def test_cta_cap_leaves_room_above_the_prompt_budget(self):
        from app.services.perspective_service import CONSENSUS_CTA_PROMPT_CHARS

        assert CONSENSUS_CTA_MAX_CHARS > CONSENSUS_CTA_PROMPT_CHARS


class TestCorpusIndex:
    """Même règle d'attribution pour le pipeline (objets) et le dry-run (dicts)."""

    def _rows(self):
        return [
            {"source_domain": "WWW.LeMonde.fr", "bias_stance": "center-left"},
            {"source_domain": "lefigaro.fr", "bias_stance": "right"},
            # Doublon : la première occurrence gagne, comme en couverture.
            {"source_domain": "lemonde.fr", "bias_stance": "left"},
            {"source_domain": None, "bias_stance": "left"},
        ]

    def test_mapping_and_object_give_the_same_index(self):
        rows = self._rows()
        objects = [SimpleNamespace(**row) for row in rows]

        assert build_corpus_index(rows) == build_corpus_index(objects)

    def test_domains_are_canonical_deduplicated_and_ordered(self):
        domains, bias = build_corpus_index(self._rows())

        assert domains == ["lemonde.fr", "lefigaro.fr"]
        assert bias == {"lemonde.fr": "center-left", "lefigaro.fr": "right"}

    def test_missing_stance_falls_back_to_unknown(self):
        _, bias = build_corpus_index([{"source_domain": "lemonde.fr"}])

        assert bias == {"lemonde.fr": "unknown"}


# --- Service au Reader (Story 35.2) ----------------------------------------


class TestDisplayGates:
    """Seuils du hand-off : 1 → rien ; 2 → CTA + carrousel sans carte IA ;
    3+ → rendu complet. Dérivés du `coverage_count` servi, jamais du front."""

    def test_solo_hides_everything(self):
        gates = compute_display_gates(1)
        assert gates == {
            "is_solo": True,
            "has_cta": False,
            "has_cards": False,
            "has_ai_card": False,
            "has_bar": False,
        }

    def test_two_media_show_cta_and_cards_without_ai(self):
        gates = compute_display_gates(2)
        assert gates["is_solo"] is False
        assert gates["has_cta"] is True
        assert gates["has_cards"] is True
        assert gates["has_ai_card"] is False
        assert gates["has_bar"] is False

    def test_three_media_render_everything(self):
        gates = compute_display_gates(3)
        assert all(gates[k] for k in ("has_cta", "has_cards", "has_ai_card", "has_bar"))
        assert gates["is_solo"] is False

    def test_nominal_six_media(self):
        assert compute_display_gates(6) == compute_display_gates(3)

    def test_zero_and_none_are_solo(self):
        assert compute_display_gates(0)["is_solo"] is True
        assert compute_display_gates(None)["is_solo"] is True


NOTORIETY = {
    "lemonde.fr": (120, True),
    "lefigaro.fr": (80, True),
    "mediapart.fr": (40, True),
    "lesechos.fr": (40, False),
    "liberation.fr": (10, True),
}


class TestPickDisplayDomains:
    def test_followed_sources_come_first(self):
        """Une source suivie peu notoire passe devant la plus notoire (D3)."""
        picked = pick_display_domains(
            ["lemonde.fr", "lefigaro.fr", "liberation.fr"],
            followed={"liberation.fr"},
            notoriety=NOTORIETY,
        )
        assert picked == ["liberation.fr", "lemonde.fr"]

    def test_notoriety_fallback_orders_by_followers_then_curated(self):
        picked = pick_display_domains(
            ["lesechos.fr", "mediapart.fr", "lemonde.fr"],
            followed=frozenset(),
            notoriety=NOTORIETY,
        )
        # 120 > 40=40, et à followers égaux le curé passe devant.
        assert picked == ["lemonde.fr", "mediapart.fr"]

    def test_unknown_domain_ranks_last_but_keeps_corpus_order(self):
        picked = pick_display_domains(
            ["inconnu.fr", "autre-inconnu.fr", "lemonde.fr"],
            notoriety=NOTORIETY,
        )
        assert picked == ["lemonde.fr", "inconnu.fr"]

    def test_disagreement_forces_one_domain_per_side(self):
        """Deux médias du même bord raconteraient une fausse symétrie."""
        picked = pick_display_domains(
            ["lemonde.fr", "liberation.fr", "lefigaro.fr"],
            followed={"lemonde.fr", "liberation.fr"},
            notoriety=NOTORIETY,
            bias_by_domain=BIAS,
            opposing=True,
        )
        assert picked == ["lemonde.fr", "lefigaro.fr"]

    def test_disagreement_without_both_sides_keeps_ranking(self):
        picked = pick_display_domains(
            ["lemonde.fr", "liberation.fr", "mediapart.fr"],
            notoriety=NOTORIETY,
            bias_by_domain=BIAS,
            opposing=True,
        )
        assert picked == ["lemonde.fr", "mediapart.fr"]

    def test_two_or_fewer_candidates_are_returned_ranked(self):
        assert pick_display_domains(
            ["lesechos.fr", "lemonde.fr"], notoriety=NOTORIETY
        ) == ["lemonde.fr", "lesechos.fr"]
        assert pick_display_domains([], notoriety=NOTORIETY) == []


class TestServeConsensusBlock:
    STORED = {
        "state": "available",
        "qualifier": "polarized",
        "agreements": [
            {
                "text": "Le fait établi par tous les médias du corpus.",
                "source_domains": [
                    "lemonde.fr",
                    "lefigaro.fr",
                    "mediapart.fr",
                    "lesechos.fr",
                ],
                "support_count": 4,
            }
        ],
        "disagreements": [
            {
                "text": "Sa portée : recomposition durable ou parenthèse.",
                "source_domains": ["liberation.fr", "lefigaro.fr"],
                "support_count": 2,
            }
        ],
        "cta": {
            "agreement": {
                "text": "Fait établi, version courte.",
                "source_domains": [
                    "lemonde.fr",
                    "lefigaro.fr",
                    "mediapart.fr",
                    "lesechos.fr",
                ],
                "support_count": 4,
            },
            "disagreement": None,
        },
    }

    def test_statements_carry_display_domains_and_plus_count(self):
        block = serve_consensus_block(
            self.STORED, generated_at="2026-08-21T07:30:00+00:00", notoriety=NOTORIETY
        )
        agreement = block["agreements"][0]
        assert agreement["display_domains"] == ["lemonde.fr", "lefigaro.fr"]
        assert agreement["support_count"] == 4
        assert agreement["plus_count"] == 2
        assert block["state"] == "available"
        assert block["qualifier"] == "polarized"
        assert block["generated_at"] == "2026-08-21T07:30:00+00:00"

    def test_plus_count_absent_at_two_sources(self):
        """« +N » seulement au-delà de 2 sources (hand-off)."""
        block = serve_consensus_block(self.STORED, generated_at=None)
        assert block["disagreements"][0]["plus_count"] == 0

    def test_cta_agreement_served_and_missing_disagreement_stays_none(self):
        block = serve_consensus_block(self.STORED, generated_at=None)
        assert block["cta"]["agreement"]["text"] == "Fait établi, version courte."
        assert block["cta"]["agreement"]["plus_count"] == 2
        assert block["cta"]["disagreement"] is None

    def test_support_count_is_clamped_to_the_stored_domains(self):
        """Une ligne corrompue ne peut pas afficher un « +N » supérieur à
        l'attribution qu'elle porte réellement."""
        stored = {
            "agreements": [
                {
                    "text": "Constat avec un compteur gonflé par corruption.",
                    "source_domains": ["lemonde.fr"],
                    "support_count": 9,
                }
            ]
        }
        block = serve_consensus_block(stored, generated_at=None)
        assert block["agreements"][0]["support_count"] == 1
        assert block["agreements"][0]["plus_count"] == 0

    def test_caps_are_applied_when_serving(self):
        stored = {
            "agreements": [
                {"text": f"Accord numéro {i} assez long.", "source_domains": ["a.fr"]}
                for i in range(5)
            ],
            "disagreements": [
                {"text": f"Désaccord numéro {i} en axe.", "source_domains": ["a.fr"]}
                for i in range(4)
            ],
        }
        block = serve_consensus_block(stored, generated_at=None)
        assert len(block["agreements"]) == 3
        assert len(block["disagreements"]) == 2

    def test_empty_block_shape_matches_the_nominal_contract(self):
        """Le front ne doit jamais distinguer « clé absente » de « liste vide »."""
        block = empty_consensus_block("pending")
        assert block == {
            "state": "pending",
            "qualifier": None,
            "agreements": [],
            "disagreements": [],
            "cta": {"agreement": None, "disagreement": None},
            "generated_at": None,
        }
